#!/usr/bin/env python3
"""Recognize enrolled faces locally with YuNet + SFace and multi-frame voting."""
from __future__ import annotations

import argparse
import collections
import json
import sys
import time
from pathlib import Path

import cv2
import numpy as np

DEFAULT_MODEL_DIR = Path('/home/orangepi/models')
DEFAULT_DATA_FILE = Path('/home/orangepi/faces/embeddings.json')


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


def person_score(recognizer, feature: np.ndarray, samples: list[list[float]]) -> float:
    scores: list[float] = []
    for sample in samples:
        known = np.asarray(sample, dtype=np.float32).reshape(1, -1)
        try:
            score = float(recognizer.match(feature, known, cv2.FaceRecognizerSF_FR_COSINE))
        except Exception:
            continue
        scores.append(score)
    if not scores:
        return 0.0
    scores.sort(reverse=True)
    top = scores[:min(2, len(scores))]
    return float(sum(top) / len(top))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--device', default='/dev/video1')
    parser.add_argument('--rotate', type=int, default=0, choices=[0, 90, 180, 270])
    parser.add_argument('--model-dir', default=str(DEFAULT_MODEL_DIR))
    parser.add_argument('--data-file', default=str(DEFAULT_DATA_FILE))
    parser.add_argument('--timeout', type=float, default=10.0)
    parser.add_argument('--threshold', type=float, default=0.42)
    parser.add_argument('--min-votes', type=int, default=3)
    parser.add_argument('--output', default='face_recognition.jpg')
    args = parser.parse_args()

    model_dir = Path(args.model_dir)
    detector_model = model_dir / 'face_detection_yunet_2023mar.onnx'
    recognizer_model = model_dir / 'face_recognition_sface_2021dec.onnx'
    data_file = Path(args.data_file)
    if not data_file.exists():
        print(json.dumps({'ok': False, 'error': 'no_enrolled_faces'}), flush=True)
        return 2
    data = json.loads(data_file.read_text(encoding='utf-8'))
    people = data.get('people', {})
    if not people:
        print(json.dumps({'ok': False, 'error': 'no_enrolled_faces'}), flush=True)
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
    votes: collections.Counter[str] = collections.Counter()
    best_scores: dict[str, float] = {}
    last_frame = None
    last_face = None
    started = time.time()
    frames_seen = 0

    while time.time() - started < args.timeout:
        ok, frame = cap.read()
        if not ok:
            continue
        frame = rotate_frame(frame, args.rotate)
        last_frame = frame.copy()
        h, w = frame.shape[:2]
        detector.setInputSize((w, h))
        _, faces = detector.detect(frame)
        face = pick_largest_face(faces, 0.65)
        if face is None:
            time.sleep(0.02)
            continue
        try:
            aligned = recognizer.alignCrop(frame, face)
            feature = recognizer.feature(aligned).reshape(1, -1).astype(np.float32)
        except Exception:
            continue
        frames_seen += 1
        best_name = 'unknown'
        best_score = 0.0
        for name, person in people.items():
            score = person_score(recognizer, feature, person.get('samples', []))
            if score > best_score:
                best_name = name
                best_score = score
        if best_name != 'unknown' and best_score >= args.threshold:
            votes[best_name] += 1
            best_scores[best_name] = max(best_scores.get(best_name, 0.0), best_score)
            last_face = face.copy()
            if votes[best_name] >= args.min_votes:
                break
        time.sleep(0.05)

    cap.release()
    identity = 'unknown'
    score = 0.0
    if votes:
        identity, count = votes.most_common(1)[0]
        if count >= args.min_votes:
            score = best_scores.get(identity, 0.0)
        else:
            identity = 'unknown'

    if last_frame is not None and last_face is not None:
        annotated = last_frame.copy()
        if identity != 'unknown':
            x, y, w, h = last_face[:4].astype(int)
            cv2.rectangle(annotated, (x, y), (x + w, y + h), (0, 255, 0), 2)
            cv2.putText(
                annotated,
                f'{identity} {score:.2f}',
                (x, max(24, y - 8)),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.7,
                (0, 255, 0),
                2,
                cv2.LINE_AA,
            )
        cv2.imwrite(args.output, annotated)

    print(json.dumps({
        'ok': True,
        'identity': identity,
        'score': round(score, 4),
        'votes': dict(votes),
        'frames_seen': frames_seen,
        'output': str(Path(args.output).resolve()),
    }, ensure_ascii=False), flush=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())