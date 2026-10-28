#!/usr/bin/env python3
"""Capture one JPEG from the Orange Pi camera for remote preview."""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path

import cv2
import numpy as np


def rotate_frame(frame: np.ndarray, degrees: int) -> np.ndarray:
    if degrees == 180:
        return cv2.rotate(frame, cv2.ROTATE_180)
    if degrees == 90:
        return cv2.rotate(frame, cv2.ROTATE_90_CLOCKWISE)
    if degrees == 270:
        return cv2.rotate(frame, cv2.ROTATE_90_COUNTERCLOCKWISE)
    return frame


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--device', default='/dev/video1')
    parser.add_argument('--rotate', type=int, default=0, choices=[0, 90, 180, 270])
    parser.add_argument('--output-dir', default='/home/orangepi/camera_snapshots')
    parser.add_argument('--prefix', default='snapshot')
    parser.add_argument('--warmup', type=int, default=5)
    parser.add_argument('--quality', type=int, default=90)
    args = parser.parse_args()

    cap = cv2.VideoCapture(args.device, cv2.CAP_V4L2)
    if not cap.isOpened():
        print(json.dumps({'ok': False, 'error': 'camera_open_failed'}), flush=True)
        return 2
    cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*'MJPG'))
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
    cap.set(cv2.CAP_PROP_FPS, 30)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

    frame = None
    try:
        for _ in range(max(1, args.warmup)):
            ok, sample = cap.read()
            if ok:
                frame = sample
    finally:
        cap.release()

    if frame is None:
        print(json.dumps({'ok': False, 'error': 'camera_read_failed'}), flush=True)
        return 3
    if frame.shape[1] != 1280 or frame.shape[0] != 720:
        frame = cv2.resize(frame, (1280, 720))
    frame = rotate_frame(frame, args.rotate)

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().astimezone().strftime('%Y%m%d_%H%M%S_%f')
    output_path = output_dir / f'{args.prefix}_{stamp}.jpg'
    ok = cv2.imwrite(
        str(output_path),
        frame,
        [int(cv2.IMWRITE_JPEG_QUALITY), max(50, min(95, args.quality))],
    )
    size = output_path.stat().st_size if output_path.exists() else 0
    result = {
        'ok': bool(ok and size > 0),
        'path': str(output_path),
        'size_bytes': size,
        'width': int(frame.shape[1]),
        'height': int(frame.shape[0]),
    }
    print(json.dumps(result, ensure_ascii=False), flush=True)
    return 0 if result['ok'] else 4


if __name__ == '__main__':
    sys.exit(main())
