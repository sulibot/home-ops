#!/usr/bin/env python3
"""Read-only gateway checks; credentials stay in memory and are never printed.

Default: production-like HTTPS through Cilium. Before cutover, port-forward the
new Envoy Service and pass --url http://127.0.0.1:18000.
"""
import argparse
import base64
import http.client
import json
import secrets
import subprocess
import sys
from urllib.parse import urlsplit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', default='https://context-fabric-staging.sulibot.com')
    args = parser.parse_args()
    target = urlsplit(args.url)
    allowed = {'context-fabric-staging.sulibot.com', '127.0.0.1', 'localhost'}
    if target.hostname not in allowed or target.username or target.password:
        parser.error('Only the staging endpoint or a local port-forward is allowed')
    if target.scheme != 'https' and not (target.scheme == 'http' and target.hostname in {'localhost', '127.0.0.1'}):
        parser.error('Remote endpoints require verified HTTPS')
    raw = subprocess.check_output([
        'kubectl', '-n', 'engineering-staging', 'get', 'secret',
        'context-fabric-supabase', '-o', 'json',
    ])
    data = json.loads(raw)['data']
    decode = lambda name: base64.b64decode(data[name]).decode()
    anon = {'apikey': decode('anonKey')}
    admin = {'apikey': decode('serviceKey')}
    basic = base64.b64encode((decode('dashboardUsername') + ':' + decode('dashboardPassword')).encode()).decode()
    failures = []

    def check(label, path, expected, headers=None, method='GET', required_header=None):
        conn_class = http.client.HTTPSConnection if target.scheme == 'https' else http.client.HTTPConnection
        conn = conn_class(target.hostname, target.port, timeout=15)
        try:
            conn.request(method, path, headers=headers or {})
            response = conn.getresponse()
            passed = response.status in expected
            if required_header:
                passed = passed and response.getheader(required_header) is not None
            print(f'{"PASS" if passed else "FAIL"} {label}: HTTP {response.status}')
            if not passed:
                failures.append(label)
        except Exception as exc:
            # Do not echo URLs, headers, bodies, keys, or exception payloads.
            print(f'FAIL {label}: {type(exc).__name__}')
            failures.append(label)
        finally:
            conn.close()

    check('REST rejects missing key', '/rest/v1/', {401})
    check('REST rejects invalid key', '/rest/v1/', {401}, {'apikey': 'invalid-synthetic-key'})
    check('Bearer alone does not bypass API key', '/rest/v1/', {401}, {'Authorization': 'Bearer ' + decode('serviceKey')})
    check('REST schema rejects anon', '/rest/v1/', {403}, anon)
    check('REST schema accepts service key', '/rest/v1/', {200}, admin)
    check('Caller JWT is not overwritten', '/rest/v1/', {401}, {**admin, 'Authorization': 'Bearer invalid-synthetic-jwt'})
    check('Auth health', '/auth/v1/health', {200}, anon)
    check('Auth settings', '/auth/v1/settings', {200}, anon)
    check('Storage health', '/storage/v1/status', {200})
    check('Storage bucket listing', '/storage/v1/bucket', {200}, admin)
    check('Meta denies anon', '/pg/health', {403}, anon)
    check('Meta health', '/pg/health', {200}, admin)
    check('Studio requires login', '/', {401})
    check('Studio rejects incorrect login', '/', {401}, {'Authorization': 'Basic ' + base64.b64encode(b'synthetic:wrong').decode()})
    check('Studio accepts login', '/project/default', {200}, {'Authorization': 'Basic ' + basic})
    check('MCP remains blocked', '/mcp', {403}, admin)
    check('Studio MCP remains blocked', '/api/mcp', {403}, admin)
    check('Realtime tenant admin blocked', '/realtime/v1/api/tenants', {403}, admin)
    check('Realtime OpenAPI blocked', '/realtime/v1/api/openapi', {403}, admin)
    check('CORS preflight', '/rest/v1/', {200, 204}, {
        'Origin': 'https://context-fabric-staging.sulibot.com',
        'Access-Control-Request-Method': 'GET',
        'Access-Control-Request-Headers': 'apikey,authorization',
    }, 'OPTIONS', 'access-control-allow-origin')
    check('Realtime WebSocket upgrade', '/realtime/v1/websocket?vsn=1.0.0', {101}, {
        **anon, 'Connection': 'Upgrade', 'Upgrade': 'websocket',
        'Sec-WebSocket-Version': '13',
        'Sec-WebSocket-Key': base64.b64encode(secrets.token_bytes(16)).decode(),
    })
    check('Functions rejects missing JWT', '/functions/v1/synthetic-gateway-check', {401})
    check('Functions rejects invalid JWT', '/functions/v1/synthetic-gateway-check', {401}, {'Authorization': 'Bearer invalid-synthetic-jwt'})
    print(f'Gateway checks: {len(failures)} failed')
    return bool(failures)


if __name__ == '__main__':
    sys.exit(main())
