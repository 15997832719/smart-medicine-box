#!/usr/bin/env python3
"""Report Xiaozhi idle/listening/speaking state to the Smart Medicine Box backend."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from device_agent_client import load_config, request_json


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('state', choices=['idle', 'listening', 'speaking'])
    parser.add_argument('--config', default='/home/orangepi/device-agent.json')
    parser.add_argument('--event-id', default=None)
    args = parser.parse_args()
    config = load_config(Path(args.config))
    result = request_json(
        config,
        'POST',
        '/api/v1/device-agent/xiaozhi/state',
        {
            'device_uid': config['device_uid'],
            'state': args.state,
            'event_id': args.event_id,
        },
        timeout=8,
    )
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())