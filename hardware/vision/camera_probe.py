# -*- coding: utf-8 -*-
"""香橙派摄像头自检脚本。

在香橙派上运行：
    python3 camera_probe.py

它会：
  1. 打开 /dev/video0
  2. 打印分辨率、帧率、编码格式
  3. 保存一张 snapshot.jpg
  4. 录 5 秒 test.mp4

如果打不开，先运行：  ls -l /dev/video*
"""
import sys
import time

import cv2


def main(device="/dev/video0"):
    cap = cv2.VideoCapture(device, cv2.CAP_V4L2)
    if not cap.isOpened():
        print(f"[FAIL] 打不开 {device}")
        print("检查：ls -l /dev/video*；是否插在 USB-A 口；v4l2-ctl --list-devices")
        return 1

    # 优先设 MJPG + 1080P，失败就退回默认
    cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
    cap.set(cv2.CAP_PROP_FPS, 30)

    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps = cap.get(cv2.CAP_PROP_FPS)
    fourcc_num = int(cap.get(cv2.CAP_PROP_FOURCC))
    fourcc = "".join(chr((fourcc_num >> 8 * i) & 0xFF) for i in range(4))
    print(f"[OK] {device}  {width}x{height}  {fps:.1f}fps  {fourcc}")

    ok, frame = cap.read()
    if not ok:
        print("[FAIL] 能打开但读不到画面")
        cap.release()
        return 1
    cv2.imwrite("snapshot.jpg", frame)
    print("[OK] 已保存 snapshot.jpg，打开看看人脸和桌面是否都清楚")

    writer = cv2.VideoWriter(
        "test.mp4",
        cv2.VideoWriter_fourcc(*"mp4v"),
        20.0,
        (width, height),
    )
    start = time.time()
    frames = 0
    while time.time() - start < 5:
        ok, frame = cap.read()
        if not ok:
            print("[WARN] 录制中掉帧")
            break
        writer.write(frame)
        frames += 1
    writer.release()
    cap.release()
    print(f"[OK] 录制 5 秒，共 {frames} 帧 -> test.mp4（约 {frames/5:.1f}fps）")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "/dev/video0"))
