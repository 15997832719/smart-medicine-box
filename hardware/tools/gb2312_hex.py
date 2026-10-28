# -*- coding: utf-8 -*-
"""把一句中文转成 SYN6288 需要的 GB2312 十六进制数组。

用法：
    python gb2312_hex.py "该吃九九九感冒灵，一次一袋。"
输出可直接粘进 .ino 的 PHRASE[]。
"""
import sys

text = sys.argv[1] if len(sys.argv) > 1 else "检测到有人，请按时服药。"
data = text.encode("gb2312")
print(f"// {text}  ({len(data)} bytes)")
print("static const uint8_t PHRASE[] = {")
for i in range(0, len(data), 12):
    print("  " + ",".join(f"0x{b:02X}" for b in data[i:i+12]) + ",")
print("};")
