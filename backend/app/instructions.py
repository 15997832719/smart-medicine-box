from __future__ import annotations

import re

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlmodel import Session, select

from app.auth import get_current_user
from app.database import get_session
from app.models import DrugInstruction, InstructionReviewStatus, Medicine
from app.schemas import DrugInstructionRead

router = APIRouter(prefix="/instructions", tags=["instructions"])


def normalize_instruction_text(value: str | None) -> str:
    return re.sub(r"[\s,???;?:?/\-]+", "", (value or "").strip().lower())


def split_aliases(value: str | None) -> list[str]:
    return [part.strip() for part in re.split(r"[,??/\n]+", value or "") if part.strip()]


def instruction_to_read(instruction: DrugInstruction) -> DrugInstructionRead:
    data = instruction.model_dump()
    data["review_status"] = instruction.review_status.value
    return DrugInstructionRead(**data)


def instruction_match_score(instruction: DrugInstruction, query: str) -> int:
    normalized = normalize_instruction_text(query)
    if not normalized:
        return 0
    names = [instruction.name, *split_aliases(instruction.aliases)]
    normalized_names = [normalize_instruction_text(name) for name in names if name]
    if normalized in normalized_names:
        return 100
    if instruction.approval_number and normalized == normalize_instruction_text(instruction.approval_number):
        return 100
    if any(normalized in name or name in normalized for name in normalized_names):
        return 70
    return 0


def find_approved_instruction(
    session: Session,
    *,
    query: str | None = None,
    medicine: Medicine | None = None,
) -> DrugInstruction | None:
    values = [value for value in (query,) if value]
    if medicine is not None:
        values.extend([medicine.name, medicine.alias or ""])
    search_values = [value for value in values if value and value.strip()]
    if not search_values:
        return None
    instructions = session.exec(
        select(DrugInstruction)
        .where(DrugInstruction.review_status == InstructionReviewStatus.approved)
        .order_by(DrugInstruction.updated_at.desc())
    ).all()
    best: tuple[int, DrugInstruction] | None = None
    for instruction in instructions:
        score = max(instruction_match_score(instruction, value) for value in search_values)
        if score and (best is None or score > best[0]):
            best = (score, instruction)
    return best[1] if best else None


@router.get("/search", response_model=list[DrugInstructionRead])
def search_instructions(
    q: str = Query(min_length=1, max_length=160),
    limit: int = Query(default=20, ge=1, le=100),
    user=Depends(get_current_user),
    session: Session = Depends(get_session),
) -> list[DrugInstructionRead]:
    del user
    instructions = session.exec(
        select(DrugInstruction)
        .where(DrugInstruction.review_status == InstructionReviewStatus.approved)
        .order_by(DrugInstruction.updated_at.desc())
    ).all()
    ranked = sorted(
        (
            (instruction_match_score(instruction, q), instruction)
            for instruction in instructions
        ),
        key=lambda item: (item[0], item[1].updated_at),
        reverse=True,
    )
    return [
        instruction_to_read(instruction)
        for score, instruction in ranked
        if score > 0
    ][:limit]


@router.get("/status")
def instruction_status(
    user=Depends(get_current_user),
    session: Session = Depends(get_session),
) -> dict[str, int]:
    del user
    instructions = session.exec(select(DrugInstruction)).all()
    return {
        status.value: sum(1 for item in instructions if item.review_status == status)
        for status in InstructionReviewStatus
    }


@router.get("/{instruction_id}", response_model=DrugInstructionRead)
def get_instruction(
    instruction_id: int,
    user=Depends(get_current_user),
    session: Session = Depends(get_session),
) -> DrugInstructionRead:
    del user
    instruction = session.get(DrugInstruction, instruction_id)
    if not instruction or instruction.review_status != InstructionReviewStatus.approved:
        raise HTTPException(status_code=404, detail="Instruction not found")
    return instruction_to_read(instruction)
