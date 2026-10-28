import unittest
from datetime import time

from sqlalchemy.pool import StaticPool
from sqlmodel import SQLModel, Session, create_engine, select

from app import device_agent, device_events  # noqa: F401
from app.auth import delete_account, login, sheng_cheng_mi_ma_zhai_yao
from app.models import AuditLog, AuthDevice, DeviceToken, FamilyLink, IntakeLog, Medicine, Reminder, SpeakerBinding, User, UserRole
from app.schemas import AccountDeleteRequest, LoginRequest


class AccountSecurityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine('sqlite://', connect_args={'check_same_thread': False}, poolclass=StaticPool)
        SQLModel.metadata.create_all(self.engine)
        self.session = Session(self.engine)
        self.user = User(phone='13800000100', password_hash=sheng_cheng_mi_ma_zhai_yao('123456'), role=UserRole.elder, nickname='elder')
        self.session.add(self.user)
        self.session.commit()
        self.session.refresh(self.user)

    def tearDown(self) -> None:
        self.session.close()

    def test_login_writes_audit(self) -> None:
        response = login(LoginRequest(phone=self.user.phone, password='123456'), self.session)
        self.assertTrue(response.access_token)
        record = self.session.exec(select(AuditLog).where(AuditLog.action == 'login')).first()
        self.assertIsNotNone(record)
        self.assertEqual(record.user_id, self.user.id)

    def test_delete_account_cleans_dependent_records(self) -> None:
        medicine = Medicine(name='medicine', owner_id=self.user.id, stock_count=1)
        self.session.add(medicine)
        self.session.commit()
        self.session.refresh(medicine)
        self.session.add(Reminder(medicine_id=medicine.id or 0, title='medicine', remind_time=time(8, 0), owner_id=self.user.id))
        self.session.add(IntakeLog(medicine_id=medicine.id or 0, owner_id=self.user.id))
        self.session.add(AuthDevice(user_id=self.user.id or 0, device_id='device-1', refresh_token_hash='hash'))
        self.session.add(DeviceToken(user_id=self.user.id or 0, registration_id='registration-1'))
        self.session.add(SpeakerBinding(speaker_id='speaker-1', user_id=self.user.id or 0))
        other = User(phone='13800000101', password_hash='test', role=UserRole.child)
        self.session.add(other)
        self.session.commit()
        self.session.refresh(other)
        self.session.add(FamilyLink(elder_id=self.user.id or 0, child_id=other.id or 0))
        self.session.commit()
        user_id = self.user.id

        result = delete_account(AccountDeleteRequest(password='123456'), self.user, self.session)

        self.assertTrue(result['success'])
        self.assertIsNone(self.session.get(User, user_id))
        self.assertIsNone(self.session.exec(select(Medicine).where(Medicine.owner_id == user_id)).first())
        self.assertIsNone(self.session.exec(select(AuthDevice).where(AuthDevice.user_id == user_id)).first())
        self.assertIsNone(self.session.exec(select(SpeakerBinding).where(SpeakerBinding.user_id == user_id)).first())
        self.assertIsNotNone(self.session.exec(select(AuditLog).where(AuditLog.action == 'delete_account')).first())


if __name__ == '__main__':
    unittest.main()
