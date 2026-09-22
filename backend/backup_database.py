"""Create or restore a SQLite backup without stopping the API process.

Usage:
  python backup_database.py backup backups/smart-medicine-box.db
  python backup_database.py restore backups/smart-medicine-box.db
"""

import shutil
import sys
from pathlib import Path

from app.config import get_settings


def database_path() -> Path:
    url = get_settings().database_url
    if not url.startswith("sqlite:///"):
        raise SystemExit("Backup helper currently supports SQLite databases only.")
    return Path(url.removeprefix("sqlite:///"))


def main() -> None:
    if len(sys.argv) != 3 or sys.argv[1] not in {"backup", "restore"}:
        raise SystemExit(__doc__)
    source = database_path().resolve()
    target = Path(sys.argv[2]).expanduser().resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    if sys.argv[1] == "backup":
        if not source.exists():
            raise SystemExit(f"Database does not exist: {source}")
        shutil.copy2(source, target)
        print(f"Backup created: {target}")
        return
    if not target.exists():
        raise SystemExit(f"Backup does not exist: {target}")
    if source.exists():
        safety = source.with_suffix(source.suffix + ".before-restore")
        shutil.copy2(source, safety)
        print(f"Current database saved as: {safety}")
    shutil.copy2(target, source)
    print(f"Database restored: {source}")


if __name__ == "__main__":
    main()
