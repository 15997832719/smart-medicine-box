#!/usr/bin/env python3
"""Enroll a person locally using YuNet face detection and SFace embeddings."""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from datetime import datetime
from pathlib import Path

import cv2
import numpy as np

DEFAULT_MODEL_DIR = Path('/home/orangepi/models')
DEFAULT_DATA_FILE = Path('/home/orangepi/faces/embeddings.json')
DEFAULT_THUMB_DIR = Path('/home/orangepi/faces/thumbnails')


def rotate_frame(frame: np.ndarray, degrees: int) -> np.ndarray:
    if degrees == 180:
        return cv2.rotate(frame, cv2.ROTATE_180)
    if degrees == 90:
        return cv2.rotate(frame, cv2.ROTATE_90_CLOCKWISE)
    if degrees == 270:
        return cv2.rotate(frame, cv2.ROTATE_90_COUNTERCLOCKWISE)
    return frame


def pick_largest_face(faces: np.ndarray | None, min_score: float) -> np.ndarray | None:
    if faces is None or len(faces) == 0:
        return None
    eligible = [face for face in faces if float(face[-1]) >= min_score]
    if not eligible:
        return None
    return max(eligible, key=lambda face: float(face[2]) * float(face[3]))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--name', required=True, help='Identity name, e.g. elder or child')
    parser.add_argument('--samples', type=int, default=5)
    parser.add_argument('--device', default='/dev/video1')
    parser.add_argument('--rotate', type=int, default=0, choices=[0, 90, 180, 270])
    parser.add_argument('--model-dir', default=str(DEFAULT_MODEL_DIR))
    parser.add_argument('--data-file', default=str(DEFAULT_DATA_FILE))
    parser.add_argument('--countdown', type=int, default=3)
    parser.add_argument('--min-score', type=float, default=0.70)
    args = parser.parse_args()

    name = args.name.strip()
    if not name:
        print(json.dumps({'ok': False, 'error': 'empty_name'}), flush=True)
        return 2
    if args.samples < 1 or args.samples > 20:
        print(json.dumps({'ok': False, 'error': 'samples_out_of_range'}), flush=True)
        return 2

    model_dir = Path(args.model_dir)
    detector_model = model_dir / 'face_detection_yunet_2023mar.onnx'
    recognizer_model = model_dir / 'face_recognition_sface_2021dec.onnx'
    for model in (detector_model, recognizer_model):
        if not model.exists():
            print(json.dumps({'ok': False, 'error': 'model_missing', 'path': str(model)}), flush=True)
            return 2

    cap = cv2.VideoCapture(args.device, cv2.CAP_V4L2)
    if not cap.isOpened():
        print(json.dumps({'ok': False, 'error': 'camera_open_failed'}), flush=True)
        return 2
    cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*'MJPG'))
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
    cap.set(cv2.CAP_PROP_FPS, 30)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

    detector = cv2.FaceDetectorYN.create(
        str(detector_model), '', (1280, 720), 0.65, 0.3, 5000
    )
    recognizer = cv2.FaceRecognizerSF.create(str(recognizer_model), '')

    print(json.dumps({'status': 'get_ready', 'countdown': args.countdown}), flush=True)
    for remaining in range(args.countdown, 0, -1):
        print(json.dumps({'countdown': remaining}), flush=True)
        time.sleep(1)

    embeddings: list[list[float]] = []
    thumbnail_frame = None
    started = time.time()
    next_capture = started
    while len(embeddings) < args.samples and time.time() - started < 30:
        ok, frame = cap.read()
        if not ok:
            continue
        frame = rotate_frame(frame, args.rotate)
        h, w = frame.shape[:2]
        detector.setInputSize((w, h))
        _, faces = detector.detect(frame)
        face = pick_largest_face(faces, args.min_score)
        if face is None or time.time() < next_capture:
            time.sleep(0.03)
            continue
        try:
            aligned = recognizer.alignCrop(frame, face)
            feature = recognizer.feature(aligned).reshape(-1).astype(float)
        except Exception as exc:
            print(json.dumps({'warning': 'feature_failed', 'detail': str(exc)}), flush=True)
            next_capture = time.time() + 0.8
            continue
        if feature.size == 0:
            next_capture = time.time() + 0.8
            continue
        embeddings.append(feature.tolist())
        if thumbnail_frame is None:
            thumbnail_frame = aligned.copy()
        print(json.dumps({
            'status': 'sample_captured',
            'sample': len(embeddings),
            'total': args.samples,
            'score': round(float(face[-1]), 4),
        }), flush=True)
        next_capture = time.time() + 1.0

    cap.release()
    if len(embeddings) < args.samples:
        print(json.dumps({
            'ok': False,
            'error': 'not_enough_samples',
            'captured': len(embeddings),
            'required': args.samples,
        }), flush=True)
        return 3

    data_file = Path(args.data_file)
    data_file.parent.mkdir(parents=True, exist_ok=True)
    thumb_dir = DEFAULT_THUMB_DIR
    thumb_dir.mkdir(parents=True, exist_ok=True)
    if data_file.exists():
        try:
            data = json.loads(data_file.read_text(encoding='utf-8'))
        except Exception:
            data = {'people': {}}
    else:
        data = {'people': {}}
    people = data.setdefault('people', {})
    now = datetime.now().astimezone().isoformat(timespec='seconds')
    safe_name = re.sub(r'[^0-9A-Za-z_\-\u4e00-\u9fff]+', '_', name)
    thumb_path = thumb_dir / f'{safe_name}.jpg'
    if thumbnail_frame is not None:
        cv2.imwrite(str(thumb_path), thumbnail_frame)
    people[name] = {
        'name': name,
        'samples': embeddings,
        'sample_count': len(embeddings),
        'thumbnail': str(thumb_path),
        'updated_at': now,
    }
    data['updated_at'] = now
    data_file.write_text(json.dumps(data, ensure_ascii=False), encoding='utf-8')
    print(json.dumps({
        'ok': True,
        'name': name,
        'sample_count': len(embeddings),
        'data_file': str(data_file),
        'thumbnail': str(thumb_path),
    }, ensure_ascii=False), flush=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())