from __future__ import annotations

import argparse
import hashlib
import json
from datetime import date, datetime
from pathlib import Path
from typing import Any

from sqlmodel import Session, select

from app.database import engine, init_db
from app.instruction_parser import parse_instruction_file
from app.models import DrugInstruction, InstructionReviewStatus


def canonical_record_hash(record: dict[str, Any], source_path: Path | None = None) -> str:
    if source_path is not None and source_path.exists() and source_path.is_file():
        digest = hashlib.sha256()
        with source_path.open('rb') as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b''):
                digest.update(chunk)
        return digest.hexdigest()
    payload = json.dumps(record, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode('utf-8')
    return hashlib.sha256(payload).hexdigest()


def normalize_record(record: dict[str, Any]) -> dict[str, Any]:
    allowed = {
        'name',
        'aliases',
        'specification',
        'manufacturer',
        'approval_number',
        'dosage',
        'contraindications',
        'precautions',
        'adverse_reactions',
        'interactions',
        'source_url',
        'source_type',
        'source_file_path',
        'document_date',
        'version',
        'raw_excerpt',
    }
    data = {key: value for key, value in record.items() if key in allowed}
    if not str(data.get('name') or '').strip():
        raise ValueError('name is required')
    if not str(data.get('source_url') or '').strip():
        raise ValueError('source_url is required')
    for key in ('document_date',):
        value = data.get(key)
        if isinstance(value, str) and value:
            data[key] = date.fromisoformat(value)
    return data


def load_records(path: Path) -> list[dict[str, Any]]:
    data = json.loads(path.read_text(encoding='utf-8'))
    if isinstance(data, list):
        return [item for item in data if isinstance(item, dict)]
    if isinstance(data, dict) and isinstance(data.get('items'), list):
        return [item for item in data['items'] if isinstance(item, dict)]
    if isinstance(data, dict):
        return [data]
    raise ValueError('instruction file must contain a JSON object, array, or items array')


def import_records(
    session: Session,
    records: list[dict[str, Any]],
    *,
    approve: bool = False,
    reviewed_by: int | None = None,
) -> dict[str, int]:
    result = {'inserted': 0, 'skipped': 0, 'superseded': 0}
    for raw in records:
        record = normalize_record(raw)
        source_path = Path(record['source_file_path']) if record.get('source_file_path') else None
        file_hash = canonical_record_hash(record, source_path)
        existing = session.exec(
            select(DrugInstruction).where(DrugInstruction.file_hash == file_hash)
        ).first()
        if existing:
            result['skipped'] += 1
            continue

        previous = None
        if approve:
            query = select(DrugInstruction).where(
                DrugInstruction.review_status == InstructionReviewStatus.approved,
                DrugInstruction.name == record['name'],
            )
            if record.get('approval_number'):
                query = query.where(DrugInstruction.approval_number == record['approval_number'])
            previous = session.exec(query.order_by(DrugInstruction.updated_at.desc())).first()

        instruction = DrugInstruction(
            **record,
            file_hash=file_hash,
            review_status=(
                InstructionReviewStatus.approved
                if approve
                else InstructionReviewStatus.pending
            ),
            reviewed_by=reviewed_by if approve else None,
            reviewed_at=datetime.utcnow() if approve else None,
            supersedes_id=previous.id if previous else None,
        )
        session.add(instruction)
        session.flush()
        if previous is not None:
            previous.review_status = InstructionReviewStatus.superseded
            previous.effective_until = date.today()
            previous.updated_at = datetime.utcnow()
            session.add(previous)
            result['superseded'] += 1
        result['inserted'] += 1
    session.commit()
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description='Import reviewed drug instruction records.')
    parser.add_argument('file', type=Path, help='JSON/JSONL-like JSON file containing instruction records')
    parser.add_argument('--approve', action='store_true', help='mark imported records approved after manual review')
    parser.add_argument('--reviewed-by', type=int, default=None, help='reviewer user id')
    parser.add_argument('--source-url', default=None, help='official source URL when importing txt/md/pdf')
    parser.add_argument('--source-type', default='nmpa', help='source type when importing txt/md/pdf')
    args = parser.parse_args()

    init_db()
    if args.file.suffix.lower() in {'.txt', '.md', '.pdf'}:
        if not args.source_url:
            parser.error('--source-url is required when importing txt/md/pdf')
        record = parse_instruction_file(args.file)
        record['source_url'] = args.source_url
        record['source_type'] = args.source_type
        records = [record]
    else:
        records = load_records(args.file)
    with Session(engine) as session:
        result = import_records(
            session,
            records,
            approve=args.approve,
            reviewed_by=args.reviewed_by,
        )
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
