#!/usr/bin/env python3
"""Simulate radar -> recognized face -> announcement without physical hardware."""
from __future__ import annotations

import argparse
import json
import time
import urllib.parse
import urllib.request


def post(base_url: str, token: str, path: str, payload: dict) -> dict:
    request = urllib.request.Request(
        base_url.rstrip('/') + path,
        data=json.dumps(payload, ensure_ascii=False).encode('utf-8'),
        method='POST',
    )
    request.add_header('Content-Type', 'application/json')
    request.add_header('X-Agent-Token', token)
    with urllib.request.urlopen(request, timeout=15) as response:
        return json.loads(response.read().decode('utf-8'))


def get(base_url: str, token: str, path: str, query: dict) -> dict:
    url = base_url.rstrip('/') + path + '?' + urllib.parse.urlencode(query)
    request = urllib.request.Request(url, method='GET')
    request.add_header('X-Agent-Token', token)
    with urllib.request.urlopen(request, timeout=15) as response:
        return json.loads(response.read().decode('utf-8'))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--base-url', default='http://127.0.0.1:8000')
    parser.add_argument('--device-uid', default='orangepi-001')
    parser.add_argument('--agent-token', default='dev-device-agent-token')
    parser.add_argument('--face-key', default='smb-user-2')
    args = parser.parse_args()
    base = args.base_url.rstrip('/')
    prefix = '/api/v1/device-agent'
    print(post(base, args.agent_token, f'{prefix}/radar/events', {
        'device_uid': args.device_uid,
        'present': True,
        'distance_cm': 100,
    }))
    print(post(base, args.agent_token, f'{prefix}/recognition-events', {
        'device_uid': args.device_uid,
        'face_key': args.face_key,
        'event_type': 'recognized',
        'score': 0.78,
        'metadata': {'source': 'computer_simulator'},
    }))
    time.sleep(2)
    print(get(base, args.agent_token, f'{prefix}/runtime', {'device_uid': args.device_uid}))
    print(get(base, args.agent_token, f'{prefix}/announcements/next', {'device_uid': args.device_uid}))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())