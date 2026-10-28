import asyncio
import unittest

from fastapi import HTTPException
from sqlalchemy.pool import StaticPool
from sqlmodel import SQLModel, Session, create_engine, select

from app.auth import accessible_owner_ids, require_owner_access
from app.models import AuditLog, FamilyLink, Medicine, User, UserRole
from app.routers import _voice_intent, create_medicine, list_medicines
from app.schemas import MedicineCreate, VoiceIntentRequest


class OwnerIsolationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine(
            'sqlite://',
            connect_args={'check_same_thread': False},
            poolclass=StaticPool,
        )
        SQLModel.metadata.create_all(self.engine)
        self.session = Session(self.engine)
        self.child = User(
            id=10,
            phone='13800000010',
            password_hash='test',
            role=UserRole.child,
            nickname='child',
        )
        self.linked_elder = User(
            id=20,
            phone='13800000020',
            password_hash='test',
            role=UserRole.elder,
            nickname='linked elder',
        )
        self.other_elder = User(
            id=30,
            phone='13800000030',
            password_hash='test',
            role=UserRole.elder,
            nickname='other elder',
        )
        self.session.add(self.child)
        self.session.add(self.linked_elder)
        self.session.add(self.other_elder)
        self.session.add(FamilyLink(elder_id=20, child_id=10))
        self.session.add(Medicine(name='own medicine', owner_id=10, stock_count=4))
        self.session.add(Medicine(name='elder medicine', owner_id=20, stock_count=9))
        self.session.add(Medicine(name='other medicine', owner_id=30, stock_count=7))
        self.session.commit()

    def tearDown(self) -> None:
        self.session.close()

    def test_child_accessible_boxes_include_self_and_linked_elder(self) -> None:
        self.assertEqual(accessible_owner_ids(self.session, self.child), [10, 20])

    def test_default_owner_is_child_not_elder(self) -> None:
        self.assertEqual(require_owner_access(self.session, self.child), 10)
        self.assertEqual(require_owner_access(self.session, self.child, 20), 20)
        with self.assertRaises(HTTPException) as raised:
            require_owner_access(self.session, self.child, 30)
        self.assertEqual(raised.exception.status_code, 403)

    def test_medicine_list_defaults_to_child_box(self) -> None:
        own = list_medicines(owner_id=None, elder_id=None, user=self.child, session=self.session)
        elder = list_medicines(owner_id=20, elder_id=None, user=self.child, session=self.session)
        self.assertEqual([item.name for item in own], ['own medicine'])
        self.assertEqual([item.name for item in elder], ['elder medicine'])

    def test_voice_intent_uses_explicit_owner_box(self) -> None:
        own = asyncio.run(_voice_intent(
            VoiceIntentRequest(text='\u5e93\u5b58\u8fd8\u5269\u591a\u5c11', owner_id=10, session_id='own-box'),
            self.child,
            self.session,
        ))
        elder = asyncio.run(_voice_intent(
            VoiceIntentRequest(text='\u5e93\u5b58\u8fd8\u5269\u591a\u5c11', owner_id=20, session_id='elder-box'),
            self.child,
            self.session,
        ))
        self.assertIn('own medicine', own['reply'])
        self.assertNotIn('elder medicine', own['reply'])
        self.assertIn('elder medicine', elder['reply'])
        self.assertNotIn('own medicine', elder['reply'])

    def test_voice_intent_rejects_unlinked_box(self) -> None:
        with self.assertRaises(HTTPException) as raised:
            asyncio.run(_voice_intent(
                VoiceIntentRequest(text='\u5e93\u5b58\u8fd8\u5269\u591a\u5c11', owner_id=30),
                self.child,
                self.session,
            ))
        self.assertEqual(raised.exception.status_code, 403)

    def test_create_medicine_records_owner_and_actor(self) -> None:
        result = create_medicine(
            MedicineCreate(name='new elder medicine'),
            owner_id=20,
            elder_id=None,
            user=self.child,
            session=self.session,
        )
        self.assertEqual(result.owner_id, 20)
        audit = self.session.exec(
            select(AuditLog).where(
                AuditLog.action == 'create',
                AuditLog.resource_type == 'medicine',
                AuditLog.resource_id == result.id,
            )
        ).first()
        self.assertIsNotNone(audit)
        self.assertEqual(audit.user_id, 10)
        self.assertIn('owner_id=20', audit.detail or '')
        self.assertIn('actor_user_id=10', audit.detail or '')


if __name__ == '__main__':
    unittest.main()
