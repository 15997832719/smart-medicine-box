from pathlib import Path
p = Path(r'D:\smart-medicine-box\tools\build_copyright_materials.py')
s = p.read_text(encoding='utf-8')
if 'import unicodedata' not in s:
    s = s.replace('import tokenize\n', 'import tokenize\nimport unicodedata\n', 1)
old = "def sanitize_line(line: str) -> str:\n    replacements = {\n"
new = "EMOJI_RE = re.compile('[\U0001F000-\U0001FAFF\u2600-\u27BF\u2B00-\u2BFF\uFE0F\u200D]')\nKAOMOJI_RE = re.compile(r'(?<![A-Za-z0-9_])(?:\^_?\^|>_<|T_T|Q_Q|Orz|orz|:\)|:\(|:D|;P|=\)|=\()(?![A-Za-z0-9_])')\n\n\ndef sanitize_line(line: str) -> str:\n    line = EMOJI_RE.sub('', line)\n    line = ''.join(ch for ch in line if unicodedata.category(ch) not in {'So', 'Sk', 'Cf'})\n    line = KAOMOJI_RE.sub('', line)\n    replacements = {\n"
if s.count(old) != 1:
    raise SystemExit(f'patch marker count={s.count(old)}')
s = s.replace(old, new, 1)
p.write_text(s, encoding='utf-8')
print('sanitizer patch applied')
