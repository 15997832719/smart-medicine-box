#!/usr/bin/env python3
"""Record a video-only medication-taking clip from the Orange Pi camera."""
from __future__ import annotations

import argparse
import json
import sys
import time
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
    parser.add_argument('--duration', type=float, default=20.0)
    parser.add_argument('--fps', type=float, default=10.0)
    parser.add_argument('--output-dir', default='/home/orangepi/intake_videos')
    parser.add_argument('--prefix', default='intake')
    parser.add_argument('--thumbnail', action='store_true')
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

    for _ in range(10):
        cap.read()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().astimezone().strftime('%Y%m%d_%H%M%S')
    output_path = output_dir / f'{args.prefix}_{stamp}.mp4'
    writer = cv2.VideoWriter(
        str(output_path),
        cv2.VideoWriter_fourcc(*'mp4v'),
        args.fps,
        (1280, 720),
    )
    if not writer.isOpened():
        cap.release()
        print(json.dumps({'ok': False, 'error': 'video_writer_failed'}), flush=True)
        return 3

    started = time.time()
    frames = 0
    thumbnail_path = output_path.with_suffix('.jpg') if args.thumbnail else None
    thumbnail_saved = False
    try:
        while time.time() - started < args.duration:
            ok, frame = cap.read()
            if not ok:
                continue
            if frame.shape[1] != 1280 or frame.shape[0] != 720:
                frame = cv2.resize(frame, (1280, 720))
            frame = rotate_frame(frame, args.rotate)
            writer.write(frame)
            if thumbnail_path is not None and not thumbnail_saved:
                thumbnail_saved = bool(cv2.imwrite(
                    str(thumbnail_path),
                    frame,
                    [int(cv2.IMWRITE_JPEG_QUALITY), 88],
                ))
            frames += 1
    finally:
        writer.release()
        cap.release()

    elapsed = max(time.time() - started, 0.001)
    size = output_path.stat().st_size if output_path.exists() else 0
    result = {
        'ok': frames > 0 and size > 0,
        'path': str(output_path),
        'frames': frames,
        'elapsed_seconds': round(elapsed, 2),
        'actual_fps': round(frames / elapsed, 2),
        'size_bytes': size,
        'thumbnail_path': str(thumbnail_path) if thumbnail_saved and thumbnail_path else None,
    }
    print(json.dumps(result, ensure_ascii=False), flush=True)
    return 0 if result['ok'] else 4


if __name__ == '__main__':
    sys.exit(main())