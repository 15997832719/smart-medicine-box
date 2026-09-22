from __future__ import annotations

import io
import re
import shutil
import tokenize
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "软著材料" / "source-clean"


def clean_python(path: Path) -> str:
    source = path.read_text(encoding="utf-8")
    tokens = list(tokenize.generate_tokens(io.StringIO(source).readline))
    kept = []
    for token in tokens:
        if token.type in {tokenize.COMMENT, tokenize.ENCODING, tokenize.ENDMARKER}:
            continue
        kept.append(token)
    return tokenize.untokenize(kept).strip() + "\n"


def clean_dart(path: Path) -> str:
    source = path.read_text(encoding="utf-8")
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    source = re.sub(r"^[ \t]*//.*(?:\r?\n|$)", "", source, flags=re.M)
    source = re.sub(r"[ \t]+//[^\r\n]*", "", source)
    return source.strip() + "\n"


def main() -> None:
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    files = sorted(list((ROOT / "backend" / "app").glob("*.py")) + list((ROOT / "frontend" / "lib").rglob("*.dart")))
    output = []
    for path in files:
        relative = path.relative_to(ROOT).as_posix()
        output.append(f"FILE: {relative}\n")
        output.append(clean_python(path) if path.suffix == ".py" else clean_dart(path))
    (OUT / "source.txt").write_text("\n".join(output), encoding="utf-8")
    (OUT / "文件清单.txt").write_text("\n".join(p.relative_to(ROOT).as_posix() for p in files) + "\n", encoding="utf-8")
    print(f"generated {len(files)} files at {OUT}")


if __name__ == "__main__":
    main()
