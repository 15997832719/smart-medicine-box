#!/usr/bin/env python3
"""Capture one frame from the USB camera and run OpenCV YuNet face detection."""
from __future__ import annotations

import argparse
import json
import os
import sys

import cv2


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", default="/dev/video1")
    parser.add_argument(
        "--model",
        default="/home/orangepi/models/face_detection_yunet_2023mar.onnx",
    )
    parser.add_argument("--output", default="face_detection.jpg")
    parser.add_argument("--no-rotate", action="store_true")
    args = parser.parse_args()

    if not os.path.exists(args.model):
        print(json.dumps({"ok": False, "error": "model_missing"}), flush=True)
        return 2

    cap = cv2.VideoCapture(args.device, cv2.CAP_V4L2)
    if not cap.isOpened():
        print(json.dumps({"ok": False, "error": "camera_open_failed"}), flush=True)
        return 2

    cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
    cap.set(cv2.CAP_PROP_FPS, 30)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

    detector = cv2.FaceDetectorYN.create(args.model, "", (1280, 720), 0.65, 0.3, 5000)
    best = None
    best_score = 0.0
    for _ in range(12):
        ok, frame = cap.read()
        if not ok:
            continue
        if not args.no_rotate:
            frame = cv2.rotate(frame, cv2.ROTATE_180)
        height, width = frame.shape[:2]
        detector.setInputSize((width, height))
        _, faces = detector.detect(frame)
        if faces is not None:
            score = max(float(face[-1]) for face in faces)
            if best is None or score > best_score:
                best = (frame.copy(), faces.copy())
                best_score = score
    cap.release()

    if best is None:
        print(json.dumps({"ok": True, "faces": 0, "best_score": 0.0}), flush=True)
        return 0

    frame, faces = best
    for face in faces:
        x, y, w, h = face[:4].astype(int)
        score = float(face[-1])
        cv2.rectangle(frame, (x, y), (x + w, y + h), (0, 255, 0), 2)
        cv2.putText(
            frame,
            f"face {score:.2f}",
            (x, max(24, y - 8)),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.7,
            (0, 255, 0),
            2,
            cv2.LINE_AA,
        )
    cv2.imwrite(args.output, frame)

    result = {
        "ok": True,
        "faces": int(len(faces)),
        "best_score": round(best_score, 4),
        "width": int(frame.shape[1]),
        "height": int(frame.shape[0]),
        "output": os.path.abspath(args.output),
    }
    print(json.dumps(result, ensure_ascii=False), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())