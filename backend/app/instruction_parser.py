from __future__ import annotations

import re
from pathlib import Path


SECTION_PATTERNS = {
    'name': ('药品名称', '通用名称', '通用名'),
    'aliases': ('商品名称', '商品名', '别名'),
    'specification': ('规格',),
    'manufacturer': ('生产企业', '上市许可持有人', '药品上市许可持有人'),
    'approval_number': ('批准文号', '药品批准文号', '国药准字'),
    'dosage': ('用法用量', '用法与用量', '用法'),
    'contraindications': ('禁忌', '禁忌症'),
    'precautions': ('注意事项', '警告', '警示语'),
    'adverse_reactions': ('不良反应',),
    'interactions': ('药物相互作用', '相互作用'),
}


def normalize_instruction_text(text: str) -> str:
    value = (text or '').replace('\r\n', '\n').replace('\r', '\n')
    value = re.sub(r'(?m)^\s*第?\s*\d+\s*页\s*$', '', value)
    value = re.sub(r'(?m)^\s*[-—]+\s*\d+\s*[-—]+\s*$', '', value)
    value = re.sub(r'[ \t]+', ' ', value)
    value = re.sub(r'\n{3,}', '\n\n', value)
    return value.strip()


def _heading_pattern(labels: tuple[str, ...]) -> re.Pattern[str]:
    joined = '|'.join(re.escape(label) for label in labels)
    return re.compile(rf'[【\[]?\s*(?:{joined})\s*[】\]]?\s*[：:]?')


def parse_instruction_text(text: str) -> dict[str, str]:
    normalized = normalize_instruction_text(text)
    if not normalized:
        raise ValueError('instruction text is empty')

    matches: list[tuple[int, int, str]] = []
    for key, labels in SECTION_PATTERNS.items():
        for match in _heading_pattern(labels).finditer(normalized):
            matches.append((match.start(), match.end(), key))
    matches.sort(key=lambda item: item[0])

    result: dict[str, str] = {}
    for index, (_, content_start, key) in enumerate(matches):
        content_end = matches[index + 1][0] if index + 1 < len(matches) else len(normalized)
        value = normalized[content_start:content_end].strip(' \n：:')
        if value and key not in result:
            result[key] = value

    if 'name' not in result and normalized:
        first_line = normalized.splitlines()[0].strip()
        if first_line and len(first_line) <= 120:
            result['name'] = first_line
    result['raw_excerpt'] = normalized[:6000]
    return result


def extract_pdf_text(path: Path) -> str:
    try:
        from pypdf import PdfReader
    except ImportError as exc:
        raise RuntimeError('PDF extraction requires pypdf; convert the official PDF to text first or install pypdf') from exc
    reader = PdfReader(str(path))
    return '\n'.join(page.extract_text() or '' for page in reader.pages)


def parse_instruction_file(path: Path) -> dict[str, str]:
    if not path.exists() or not path.is_file():
        raise FileNotFoundError(path)
    suffix = path.suffix.lower()
    if suffix == '.pdf':
        text = extract_pdf_text(path)
    elif suffix in {'.txt', '.md'}:
        text = path.read_text(encoding='utf-8-sig')
    else:
        raise ValueError('instruction file must be .txt, .md, or .pdf')
    result = parse_instruction_text(text)
    result['source_file_path'] = str(path)
    return result
