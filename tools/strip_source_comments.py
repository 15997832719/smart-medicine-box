from __future__ import annotations

import io
import tokenize
from pathlib import Path

BASE = Path(r'D:\smart-medicine-box')
TARGET_ROOTS = [
    BASE / 'backend/app',
    BASE / 'backend/tests',
    BASE / 'frontend/lib',
    BASE / 'frontend/test',
    BASE / 'frontend/ohos/entry/src/main/ets',
    BASE / 'frontend/android/app/src/main/kotlin',
]
SUFFIXES = {'.py', '.dart', '.ets', '.ts', '.kt', '.java'}


def strip_python_comments(source: str) -> str:
    lines = source.splitlines()
    masks: list[list[tuple[int, int]]] = [[] for _ in lines]
    previous_type = tokenize.ENCODING
    for token in tokenize.generate_tokens(io.StringIO(source).readline):
        if token.type == tokenize.COMMENT:
            row = token.start[0] - 1
            if 0 <= row < len(masks):
                masks[row].append((token.start[1], token.end[1]))
        elif token.type == tokenize.STRING and token.string.strip().startswith(('"""', "'''")):
            if previous_type in {tokenize.ENCODING, tokenize.NEWLINE, tokenize.INDENT, tokenize.DEDENT}:
                for row in range(token.start[0] - 1, min(token.end[0], len(lines))):
                    start_col = token.start[1] if row == token.start[0] - 1 else 0
                    end_col = token.end[1] if row == token.end[0] - 1 else len(lines[row])
                    masks[row].append((start_col, end_col))
        if token.type not in {tokenize.NL, tokenize.COMMENT, tokenize.ENCODING}:
            previous_type = token.type
    result: list[str] = []
    for line, ranges in zip(lines, masks):
        chars = list(line)
        for start_col, end_col in ranges:
            for index in range(max(0, start_col), min(len(chars), end_col)):
                chars[index] = ' '
        result.append(''.join(chars).rstrip())
    return '\n'.join(result) + ('\n' if source.endswith('\n') else '')


def strip_c_like_comments(source: str) -> str:
    out: list[str] = []
    index = 0
    length = len(source)
    quote = ''
    triple = False

    while index < length:
        char = source[index]
        next_char = source[index + 1] if index + 1 < length else ''

        if quote:
            if triple:
                if source.startswith(quote * 3, index):
                    out.append(quote * 3)
                    index += 3
                    quote = ''
                    triple = False
                    continue
                out.append(char)
                index += 1
                continue
            out.append(char)
            if char == '\\' and index + 1 < length:
                out.append(next_char)
                index += 2
                continue
            if char == quote:
                quote = ''
            index += 1
            continue

        if char == '/' and next_char == '/':
            index += 2
            while index < length and source[index] not in '\r\n':
                index += 1
            continue

        if char == '/' and next_char == '*':
            index += 2
            while index < length and not source.startswith('*/', index):
                if source[index] in '\r\n':
                    out.append(source[index])
                index += 1
            index += 2
            continue

        if char in {'\'', '"'}:
            if source.startswith(char * 3, index):
                out.append(char * 3)
                index += 3
                quote = char
                triple = True
                continue
            quote = char
            out.append(char)
            index += 1
            continue

        if char == '`':
            quote = char
            out.append(char)
            index += 1
            continue

        out.append(char)
        index += 1

    return ''.join(out)


files = [
    path
    for root in TARGET_ROOTS
    if root.exists()
    for path in root.rglob('*')
    if path.is_file() and path.suffix in SUFFIXES
]
changed = 0
for path in files:
    source = path.read_text(encoding='utf-8')
    stripped = strip_python_comments(source) if path.suffix == '.py' else strip_c_like_comments(source)
    if stripped != source:
        path.write_text(stripped, encoding='utf-8')
        changed += 1
print(f'comment cleanup changed {changed} files')
