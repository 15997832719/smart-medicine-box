import asyncio
import base64
import io
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from fastapi import HTTPException, UploadFile
from sqlalchemy.pool import StaticPool
from sqlmodel import SQLModel, Session, create_engine, select
from PIL import Image

from app import face_auth
from app.face_auth import FaceMatch
from app.models import AuditLog, FaceConsent, FaceLoginLock, FaceProfile, User, UserRole
from app.schemas import FaceConsentRequest


class FakeProvider:
    name = 'tenant'

    def __init__(self, expected_image: bytes) -> None:
        self.expected_image = expected_image

    def enroll(self, user_id: int, image: bytes):
        return f'smb-user-{user_id}', 'face-1'

    def search(self, image: bytes):
        if image != self.expected_image:
            return None
        return FaceMatch('smb-user-1', 95)

    def delete(self, person_id: str) -> None:
        return None


def settings_stub() -> SimpleNamespace:
    return SimpleNamespace(
        face_auth_enabled=True,
        face_provider='mock',
        face_encryption_key=base64.urlsafe_b64encode(b'1' * 32).decode(),
        face_max_failures=2,
        face_lock_minutes=15,
        face_search_threshold=80,
        sms_provider='debug',
        sms_code_ttl_minutes=5,
    )


class FaceAuthTests(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine('sqlite://', connect_args={'check_same_thread': False}, poolclass=StaticPool)
        SQLModel.metadata.create_all(self.engine)
        self.session = Session(self.engine)
        self.user = User(id=1, phone='13800000200', password_hash='test', role=UserRole.elder, nickname='elder')
        self.session.add(self.user)
        self.session.commit()
        red = io.BytesIO()
        Image.new('RGB', (32, 32), (220, 30, 30)).save(red, format='JPEG')
        self.provider = FakeProvider(face_auth.normalize_face_image(red.getvalue()))
        self.request = SimpleNamespace(client=SimpleNamespace(host='127.0.0.1'), headers={})

    def tearDown(self) -> None:
        self.session.close()

    def _upload(self, content: bytes) -> UploadFile:
        color = (30, 30, 220) if content == b'wrong-image' else (220, 30, 30)
        output = io.BytesIO()
        Image.new('RGB', (32, 32), color).save(output, format='JPEG')
        output.seek(0)
        return UploadFile(filename='face.jpg', file=output)

    def _patch(self):
        return patch.multiple(face_auth, get_settings=settings_stub, get_face_provider=lambda: self.provider)

    def test_enroll_login_and_delete(self) -> None:
        with self._patch():
            face_auth.record_face_consent(FaceConsentRequest(), self.request, self.user, self.session)
            enrolled = asyncio.run(face_auth.enroll_face(self._upload(b'face-image'), 'device-abcdef', self.user, self.session))
            self.assertTrue(enrolled['enrolled'])
            response = asyncio.run(face_auth.face_login(self.request, self._upload(b'face-image'), 'device-abcdef', self.session))
            self.assertTrue(response['access_token'])
            self.assertEqual(response['score'], 95)
            deleted = face_auth.delete_face(self.user, self.session)
            self.assertTrue(deleted['deleted'])
        self.assertIsNone(self.session.exec(select(FaceProfile).where(FaceProfile.user_id == 1)).first())
        self.assertIsNotNone(self.session.exec(select(FaceConsent).where(FaceConsent.user_id == 1)).first())

    def test_failures_lock_device(self) -> None:
        with self._patch():
            face_auth.record_face_consent(FaceConsentRequest(), self.request, self.user, self.session)
            asyncio.run(face_auth.enroll_face(self._upload(b'face-image'), 'device-abcdef', self.user, self.session))
            for _ in range(2):
                with self.assertRaises(HTTPException) as raised:
                    asyncio.run(face_auth.face_login(self.request, self._upload(b'wrong-image'), 'device-abcdef', self.session))
                self.assertEqual(raised.exception.status_code, 401)
            with self.assertRaises(HTTPException) as raised:
                asyncio.run(face_auth.face_login(self.request, self._upload(b'face-image'), 'device-abcdef', self.session))
            self.assertEqual(raised.exception.status_code, 423)
        lock = self.session.exec(select(FaceLoginLock).where(FaceLoginLock.device_key == 'device-abcdef')).first()
        self.assertIsNotNone(lock)


if __name__ == '__main__':
    unittest.main()
