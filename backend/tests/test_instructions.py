import asyncio
import io
import unittest
from unittest.mock import AsyncMock, patch

from sqlalchemy.pool import StaticPool
from sqlmodel import SQLModel, Session, create_engine, select

from import_drug_instructions import import_records
from app.instructions import find_approved_instruction, search_instructions
from app.routers import recognize_medicine
from app.schemas import MedicineCreate, RecognizeResult
from fastapi import UploadFile
from app.models import DrugInstruction, InstructionReviewStatus, Medicine, User, UserRole


class InstructionLibraryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine(
            'sqlite://',
            connect_args={'check_same_thread': False},
            poolclass=StaticPool,
        )
        SQLModel.metadata.create_all(self.engine)
        self.session = Session(self.engine)
        self.user = User(
            id=1,
            phone='13800000001',
            password_hash='test',
            role=UserRole.child,
            nickname='reviewer',
        )
        self.session.add(self.user)
        self.approved = DrugInstruction(
            name='Aspirin',
            aliases='aspirin tablet',
            dosage='one tablet daily',
            source_url='https://example.com/aspirin',
            file_hash='approved-hash',
            review_status=InstructionReviewStatus.approved,
        )
        self.pending = DrugInstruction(
            name='Ibuprofen',
            source_url='https://example.com/ibuprofen',
            file_hash='pending-hash',
            review_status=InstructionReviewStatus.pending,
        )
        self.session.add(self.approved)
        self.session.add(self.pending)
        self.session.commit()

    def tearDown(self) -> None:
        self.session.close()

    def test_search_returns_only_approved_matches(self) -> None:
        approved = search_instructions('aspirin', 20, self.user, self.session)
        pending = search_instructions('ibuprofen', 20, self.user, self.session)
        self.assertEqual([item.name for item in approved], ['Aspirin'])
        self.assertEqual(pending, [])

    def test_medicine_alias_finds_approved_instruction(self) -> None:
        medicine = Medicine(
            name='Acetylsalicylic acid',
            alias='Aspirin,aspirin tablet',
            owner_id=1,
            stock_count=1,
        )
        result = find_approved_instruction(self.session, medicine=medicine)
        self.assertIsNotNone(result)
        self.assertEqual(result.name, 'Aspirin')

    def test_photo_recognition_enriches_from_reviewed_instruction(self) -> None:
        recognized = RecognizeResult(
            medicine=MedicineCreate(name='Aspirin', stock_count=0),
            confidence=0.91,
            source='vision',
        )
        upload = UploadFile(filename='medicine.jpg', file=io.BytesIO(b'fake-image'))
        with patch('app.routers.recognize_medicine_image', new=AsyncMock(return_value=recognized)):
            result = asyncio.run(recognize_medicine(image=upload, user=self.user, session=self.session))
        self.assertEqual(result.source, 'reviewed_instruction')
        self.assertEqual(result.medicine.dosage, 'one tablet daily')
        self.assertEqual(result.medicine.information_source, 'https://example.com/aspirin')

    def test_import_is_idempotent_and_approval_supersedes_old_version(self) -> None:
        record = {
            'name': 'Aspirin',
            'approval_number': 'H-001',
            'dosage': 'two tablets daily',
            'source_url': 'https://example.com/aspirin-v2',
            'version': '2',
        }
        first = import_records(self.session, [record], approve=True, reviewed_by=1)
        second = import_records(self.session, [record], approve=True, reviewed_by=1)
        self.assertEqual(first['inserted'], 1)
        self.assertEqual(second['skipped'], 1)
        approved = self.session.exec(
            select(DrugInstruction).where(
                DrugInstruction.name == 'Aspirin',
                DrugInstruction.version == '2',
            )
        ).first()
        self.assertIsNotNone(approved)
        self.assertEqual(approved.review_status, InstructionReviewStatus.approved)
        self.assertEqual(approved.reviewed_by, 1)


if __name__ == '__main__':
    unittest.main()
