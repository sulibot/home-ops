import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "repair", Path(__file__).parents[1] / "repair-ceph-orphan-clone-metadata.py")
repair = importlib.util.module_from_spec(spec)
spec.loader.exec_module(repair)

TRACK = "11111111-2222-3333-4444-555555555555"
OTHER = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
SNAP = "csi-snap-01234567-1234-1234-1234-123456789abc"
DATA = ("[GLOBAL]\nstate = complete\npath = /keep/data\n\n"
        "[USER_METADATA]\nowner = keep\n\n[clone snaps]\n"
        f"{TRACK} = {SNAP}\n{OTHER} = other-snapshot\n").encode()


class RepairTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.index = Path(self.temp.name)

    def test_removes_only_target_line(self):
        result, tracks = repair.repaired_bytes(DATA, SNAP, self.index)
        self.assertEqual(tracks, [TRACK])
        self.assertEqual(result, DATA.replace(f"{TRACK} = {SNAP}\n".encode(), b""))

    def test_live_index_refused(self):
        (self.index / TRACK).write_text("live")
        with self.assertRaises(ValueError):
            repair.repaired_bytes(DATA, SNAP, self.index)

    def test_dangling_symlink_refused(self):
        (self.index / TRACK).symlink_to(self.index / "missing")
        with self.assertRaises(ValueError):
            repair.repaired_bytes(DATA, SNAP, self.index)

    def test_incomplete_source_refused(self):
        with self.assertRaises(ValueError):
            repair.repaired_bytes(DATA.replace(b"complete", b"in-progress"), SNAP, self.index)

    def test_unmatched_snapshot_refused(self):
        with self.assertRaises(ValueError):
            repair.repaired_bytes(DATA, "unknown-snapshot", self.index)

    def test_invalid_tracking_path_refused(self):
        with self.assertRaises(ValueError):
            repair.repaired_bytes(DATA.replace(TRACK.encode(), b"../outside"), SNAP, self.index)


if __name__ == "__main__":
    unittest.main()
