#!/usr/bin/env python3
"""FileFlows production worker: SDR AVC MKV -> verified HEVC, atomic replacement.

No shell interpolation; credentials come from Kubernetes Secret environment refs.
An interrupted commit leaves a journal and original hardlink, and blocks new jobs.
"""
import argparse
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import urllib.parse
import urllib.request
import uuid
import xml.etree.ElementTree as ET

ROOTS = {"sonarr": Path('/data/media/tv-4k'), "radarr": Path('/data/media/movies-4k')}
STATE = Path('/app/Data/Production')


def log(message):
    print(message, file=sys.stderr, flush=True)


def run(args, timeout=86400):
    result = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f'{args[0]} failed: {result.stderr[-2500:]}')
    return result.stdout


def probe(path):
    return json.loads(run(['ffprobe', '-v', 'error', '-show_format', '-show_streams',
                           '-show_chapters', '-of', 'json', str(path)]))


def identity(path):
    s = path.stat()
    return [s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns]


def request(url, headers, payload=None):
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(url, data=data, headers=headers | {'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=30) as response:
        return response.read()


def api(app, path, payload=None):
    return json.loads(request(f'http://{app}-4k/api/v3/{path}',
                             {'X-Api-Key': os.environ[app.upper() + '_API_KEY']}, payload))


def plex(path):
    return request('http://plex:32400' + path, {'X-Plex-Token': os.environ['PLEX_TOKEN']})


def not_playing(path):
    sessions = ET.fromstring(plex('/status/sessions'))
    if any(p.get('file') == str(path) for p in sessions.iter('Part')):
        raise RuntimeError('File is playing in Plex; defer this file.')


def managed_file(app, source):
    if app == 'radarr':
        for movie in api(app, 'movie'):
            if Path(movie['path']) in source.parents:
                f = api(app, f'moviefile/{movie["movieFileId"]}')
                if f.get('path') == str(source):
                    return movie['id'], f['id']
    else:
        for series in api(app, 'series'):
            if Path(series['path']) in source.parents:
                for f in api(app, 'episodefile?seriesId=' + str(series['id'])):
                    if f.get('path') == str(source):
                        return series['id'], f['id']
    raise RuntimeError('Source is not tracked by the active media manager.')


def command(app, body):
    c = api(app, 'command', body)
    for _ in range(150):
        c = api(app, 'command/' + str(c['id']))
        if c['status'] == 'completed':
            return
        if c['status'] in ('failed', 'aborted', 'cancelled'):
            raise RuntimeError(f'{app} {body["name"]} failed')
        time.sleep(2)
    raise RuntimeError(f'{app} {body["name"]} timed out')


def track_signature(s):
    return {k: s.get(k) for k in ('codec_type', 'codec_name', 'sample_rate', 'channels',
                                  'channel_layout', 'disposition')} | {
        k: s.get('tags', {}).get(k) for k in ('language', 'title')}


def metadata_checks(a, b):
    av = [s for s in a['streams'] if s['codec_type'] == 'video']
    bv = [s for s in b['streams'] if s['codec_type'] == 'video']
    if len(av) != 1 or len(bv) != 1:
        raise RuntimeError('Expected exactly one video stream')
    if bv[0]['codec_name'] != 'hevc' or bv[0]['pix_fmt'] != 'yuv420p10le':
        raise RuntimeError('Output is not HEVC 10-bit')
    for key in ('width', 'height', 'r_frame_rate', 'sample_aspect_ratio',
                'color_space', 'color_transfer', 'color_primaries'):
        if av[0].get(key) != bv[0].get(key):
            raise RuntimeError('Video property changed: ' + key)
    if abs(float(a['format']['duration']) - float(b['format']['duration'])) > 0.1:
        raise RuntimeError('Duration changed by more than 100 ms')
    def others(p):
        return [track_signature(s) for s in p['streams'] if s['codec_type'] != 'video']
    if others(a) != others(b):
        raise RuntimeError('Audio/subtitle/attachment metadata changed')
    def chapters(p):
        return [(round(float(c['start_time']), 3), round(float(c['end_time']), 3),
                 c.get('tags', {})) for c in p.get('chapters', [])]
    if chapters(a) != chapters(b):
        raise RuntimeError('Chapter metadata changed')


def validate(source, output, a):
    b = probe(output)
    metadata_checks(a, b)
    if output.stat().st_size >= source.stat().st_size * 0.95:
        raise RuntimeError('Output saves less than 5%; original retained')
    def hashes(path):
        return run(['ffmpeg', '-v', 'error', '-i', str(path), '-map', '0:a?',
                    '-map', '0:s?', '-map', '0:t?', '-c', 'copy', '-f', 'streamhash', '-'])
    if hashes(source) != hashes(output):
        raise RuntimeError('Non-video payload hashes differ')
    log('Full output video/audio decode validation')
    run(['ffmpeg', '-nostdin', '-v', 'error', '-xerror', '-threads', '2', '-i', str(output),
         '-map', '0:v:0', '-map', '0:a?', '-f', 'null', '-'])
    return b


def encode(source, output, metadata):
    args = ['ffmpeg', '-hide_banner', '-nostdin', '-v', 'warning', '-stats', '-stats_period', '60',
            '-n', '-i', str(source), '-map', '0', '-map_metadata', '0', '-map_chapters', '0',
            '-c', 'copy', '-c:v:0', 'libx265', '-preset', 'slow', '-crf', '21',
            '-pix_fmt:v:0', 'yuv420p10le', '-profile:v:0', 'main10',
            '-x265-params', 'pools=4:frame-threads=2']
    # Explicitly retain every disposition, including original-language + SDH.
    for s in metadata['streams']:
        flags = '+'.join(k for k, v in s.get('disposition', {}).items() if v)
        args += ['-disposition:' + str(s['index']), flags or '0']
    args += ['-f', 'matroska', str(output)]
    log('Encoding HEVC 10-bit, CRF 21, slow preset, four encoder threads')
    subprocess.run(args, check=True, stdout=sys.stderr, timeout=86400)


def write_json(path, data):
    tmp = path.with_suffix('.tmp')
    with tmp.open('w') as f:
        json.dump(data, f, indent=2)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def process(source, candidate=None, check_only=False):
    if source.is_symlink() or source.absolute() != source.resolve():
        raise RuntimeError('Symlinked input is excluded')
    source = source.resolve()
    app = next((key for key, root in ROOTS.items() if root in source.parents), None)
    if app is None:
        raise RuntimeError('Path is outside managed production media roots')
    if source.suffix.lower() != '.mkv':
        return {'status': 'skipped', 'reason': 'Initial production scope is MKV', 'path': str(source)}
    original = identity(source)
    a = probe(source)
    videos = [s for s in a['streams'] if s['codec_type'] == 'video']
    if len(videos) != 1 or videos[0]['codec_name'] != 'h264':
        return {'status': 'skipped', 'reason': 'Not single-video H.264', 'path': str(source)}
    video = videos[0]
    # Fail closed on unspecified transfer characteristics as well as HDR.
    if (video.get('color_transfer') not in ('bt709', 'smpte170m', 'bt470bg')
            or video.get('color_primaries') == 'bt2020'
            or any('dovi' in json.dumps(s).lower() or 'mastering display' in json.dumps(s).lower()
                   for s in video.get('side_data_list', []))):
        return {'status': 'skipped', 'reason': 'HDR or unconfirmed SDR', 'path': str(source)}
    if source.stat().st_nlink != 1:
        return {'status': 'skipped', 'reason': 'Hardlinked source', 'path': str(source)}
    if time.time() - source.stat().st_mtime < 7200:
        raise RuntimeError('Source modified within two hours; defer this file')
    not_playing(source)
    parent_id, file_id = managed_file(app, source)
    plex_sections = ET.fromstring(plex('/library/sections'))
    section_ids = [d.get('key') for d in plex_sections.findall('Directory')
                   if any(Path(loc.get('path', '/invalid')) in source.parents for loc in d.findall('Location'))]
    if not section_ids:
        raise RuntimeError('No Plex section maps to source')
    if check_only:
        return {'status': 'preflight_passed', 'app': app, 'parentId': parent_id, 'fileId': file_id,
                'plexSections': section_ids, 'path': str(source)}
    for j in STATE.glob('*.json'):
        if json.loads(j.read_text()).get('phase') in ('committing', 'replaced', 'refreshing'):
            raise RuntimeError('Unfinished replacement journal needs recovery: ' + str(j))
    key = uuid.uuid4().hex
    stage = source.parent / ('.fileflows-' + key + '.partial')
    rollback = source.parent / ('.fileflows-' + key + '.original')
    journal = STATE / (key + '.json')
    record = {'source': str(source), 'stage': str(stage), 'rollback': str(rollback),
              'original_identity': original, 'phase': 'encoding', 'app': app,
              'parentId': parent_id, 'fileId': file_id}
    write_json(journal, record)
    committed = False
    try:
        if shutil.disk_usage(source.parent).free < original[2] * 1.2 + 1024**3:
            raise RuntimeError('Insufficient staging space')
        if candidate:
            candidate = candidate.resolve()
            if Path('/review') not in candidate.parents:
                raise RuntimeError('Existing candidates must be under /review')
            shutil.copyfile(candidate, stage)
        else:
            encode(source, stage, a)
        b = validate(source, stage, a)
        if identity(source) != original or source.stat().st_nlink != 1:
            raise RuntimeError('Source changed during conversion')
        if managed_file(app, source) != (parent_id, file_id):
            raise RuntimeError('Media manager file changed during conversion')
        not_playing(source)
        # Same filesystem, fsync, then atomic replace; original inode retained
        # only until media-manager refresh/rename and Plex refresh succeed.
        os.chmod(stage, source.stat().st_mode & 0o777)
        with stage.open('rb') as f:
            os.fsync(f.fileno())
        record.update(phase='committing', output_bytes=stage.stat().st_size)
        write_json(journal, record)
        os.link(source, rollback)
        if identity(source) != original:
            raise RuntimeError('Source changed before commit')
        os.replace(stage, source)
        committed = True
        fd = os.open(source.parent, os.O_DIRECTORY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
        record['phase'] = 'replaced'
        write_json(journal, record)
        kind = 'Series' if app == 'sonarr' else 'Movie'
        parent_key = 'seriesId' if app == 'sonarr' else 'movieId'
        endpoint = 'episodefile' if app == 'sonarr' else 'moviefile'
        command(app, {'name': 'Refresh' + kind, parent_key: parent_id})
        f = api(app, f'{endpoint}/{file_id}')
        if f.get('size') != record['output_bytes']:
            raise RuntimeError('Manager did not update converted file size')
        record['phase'] = 'refreshing'
        write_json(journal, record)
        command(app, {'name': 'RenameFiles', parent_key: parent_id, 'files': [file_id]})
        final = Path(api(app, f'{endpoint}/{file_id}')['path'])
        if ROOTS[app] not in final.parents or final.stat().st_size != record['output_bytes']:
            raise RuntimeError('Renamed media file not verified')
        record['path'] = str(final)
        write_json(journal, record)
        for section in section_ids:
            plex('/library/sections/' + section + '/refresh?' + urllib.parse.urlencode({'path': str(final.parent)}))
        rollback.unlink()
        if candidate:
            candidate.unlink()
        record.update(phase='complete', saved_bytes=original[2]-final.stat().st_size,
                      saved_percent=round(100*(1-final.stat().st_size/original[2]), 2))
        write_json(journal, record)
        return {'status': 'replaced', 'path': str(final), 'saved_bytes': record['saved_bytes'],
                'saved_percent': record['saved_percent']}
    except Exception:
        if not committed:
            stage.unlink(missing_ok=True)
            rollback.unlink(missing_ok=True)
            record['phase'] = 'failed_before_replacement'
            write_json(journal, record)
        # After commit, retain rollback/journal and block subsequent jobs.
        raise


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('--candidate', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    STATE.mkdir(parents=True, exist_ok=True)
    with (STATE / 'worker.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        print(json.dumps(process(args.source, args.candidate, args.check)), flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        log(str(error))
        sys.exit(1)
