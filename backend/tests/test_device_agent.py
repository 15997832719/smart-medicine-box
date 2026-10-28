import asyncio
import io
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from fastapi import HTTPException, UploadFile
from sqlalchemy.pool import StaticPool
from sqlmodel import SQLModel, Session, create_engine

from app.device_agent import (
    AgentCommandResult,
    CameraAssetReview,
    DeviceCommandCreate,
    DeviceFaceIdentityUpdate,
    HardwareDeviceCreate,
    agent_command_result,
    agent_next_command,
    create_device_command,
    create_hardware_device,
    agent_upload_camera_asset,
    list_camera_assets,
    list_device_faces,
    list_hardware_devices,
    update_device_face_identity,
    review_camera_asset,
)
from app.models import FamilyLink, User, UserRole


class DeviceAgentFlowTests(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine(
            'sqlite://',
            connect_args={'check_same_thread': False},
            poolclass=StaticPool,
        )
        SQLModel.metadata.create_all(self.engine)
        self.session = Session(self.engine)
        self.child = User(id=1, phone='13800000101', password_hash='x', role=UserRole.child, nickname='child')
        self.elder = User(id=2, phone='13800000102', password_hash='x', role=UserRole.elder, nickname='elder')
        self.session.add(self.child)
        self.session.add(self.elder)
        self.session.commit()
        self.session.add(FamilyLink(elder_id=2, child_id=1))
        self.session.commit()
        self.temp_dir = tempfile.TemporaryDirectory()

    def tearDown(self) -> None:
        self.session.close()
        self.temp_dir.cleanup()

    def _settings(self):
        return SimpleNamespace(
            device_camera_dir=self.temp_dir.name,
            device_camera_max_upload_mb=10,
            api_prefix="/api/v1",
        )

    def _jpeg(self, name="snapshot.jpg") -> UploadFile:
        return UploadFile(filename=name, file=io.BytesIO(b"\xff\xd8\xff\xe0smart-medicine-box-test"))

    def _mp4(self, name="intake.mp4") -> UploadFile:
        return UploadFile(filename=name, file=io.BytesIO(b"\x00\x00\x00\x18ftypmp42smart-medicine-box-test"))

    def test_face_enroll_command_round_trip(self) -> None:
        device = create_hardware_device(
            HardwareDeviceCreate(device_uid='orangepi-test', name='test box', owner_id=2),
            self.child,
            self.session,
        )
        command = create_device_command(
            device['id'],
            DeviceCommandCreate(command_type='face_enroll', payload={'user_id': 2, 'samples': 5}),
            self.child,
            self.session,
        )
        claimed = agent_next_command('orangepi-test', None, self.session)
        self.assertIsNotNone(claimed['command'])
        self.assertEqual(claimed['command']['id'], command['id'])
        self.assertEqual(claimed['command']['payload']['face_key'], 'smb-user-2')

        result = agent_command_result(
            command['id'],
            AgentCommandResult(
                device_uid='orangepi-test',
                success=True,
                result={'sample_count': 5, 'identity': 'smb-user-2'},
            ),
            None,
            self.session,
        )
        self.assertEqual(result['status'], 'completed')
        faces = list_device_faces(device['id'], self.child, self.session)
        self.assertEqual(len(faces), 1)
        self.assertEqual(faces[0]['user_id'], 2)
        self.assertEqual(faces[0]['sample_count'], 5)
        devices = list_hardware_devices(self.child, self.session)
        self.assertEqual(len(devices), 1)
        self.assertEqual(len(devices[0]['faces']), 1)

    def test_child_cannot_register_unrelated_user(self) -> None:
        outsider = User(id=9, phone='13800000109', password_hash='x', role=UserRole.elder, nickname='outsider')
        self.session.add(outsider)
        self.session.commit()
        device = create_hardware_device(
            HardwareDeviceCreate(device_uid='orangepi-test-2', name='test box', owner_id=2),
            self.child,
            self.session,
        )
        with self.assertRaises(Exception):
            create_device_command(
                device['id'],
                DeviceCommandCreate(command_type='face_enroll', payload={'user_id': 9}),
                self.child,
                self.session,
            )

    def test_camera_snapshot_upload_and_family_access(self) -> None:
        device = create_hardware_device(
            HardwareDeviceCreate(device_uid='orangepi-camera', name='camera box', owner_id=2),
            self.child,
            self.session,
        )
        command = create_device_command(
            device['id'],
            DeviceCommandCreate(command_type='camera_snapshot'),
            self.child,
            self.session,
        )
        with patch('app.device_agent.get_settings', self._settings):
            asset = asyncio.run(agent_upload_camera_asset(
                device_uid='orangepi-camera',
                kind='camera_snapshot',
                command_id=command['id'],
                user_id=2,
                captured_at=None,
                duration_seconds=None,
                metadata_json='{"source":"app"}',
                file=self._jpeg(),
                thumbnail=None,
                _=None,
                session=self.session,
            ))
            self.assertEqual(asset['kind'], 'camera_snapshot')
            self.assertEqual(asset['status'], 'snapshot')
            self.assertTrue(any(Path(self.temp_dir.name).iterdir()))
            assets = list_camera_assets(device['id'], 'camera_snapshot', 50, self.child, self.session)
            self.assertEqual(len(assets), 1)
            self.assertEqual(assets[0]['metadata']['source'], 'app')

    def test_intake_video_upload_list_and_review(self) -> None:
        device = create_hardware_device(
            HardwareDeviceCreate(device_uid='orangepi-video', name='video box', owner_id=2),
            self.child,
            self.session,
        )
        command = create_device_command(
            device['id'],
            DeviceCommandCreate(command_type='intake_record', payload={'user_id': 2, 'duration': 20}),
            self.child,
            self.session,
        )
        with patch('app.device_agent.get_settings', self._settings):
            asset = asyncio.run(agent_upload_camera_asset(
                device_uid='orangepi-video',
                kind='intake_video',
                command_id=command['id'],
                user_id=2,
                captured_at='2026-10-27T12:00:00Z',
                duration_seconds=19.8,
                metadata_json=None,
                file=self._mp4(),
                thumbnail=self._jpeg('thumb.jpg'),
                _=None,
                session=self.session,
            ))
            self.assertEqual(asset['status'], 'possible_taken')
            self.assertIsNotNone(asset['thumbnail_url'])
            reviewed = review_camera_asset(
                device['id'],
                asset['id'],
                CameraAssetReview(status='confirmed_taken', note='家属确认'),
                self.child,
                self.session,
            )
            self.assertEqual(reviewed['status'], 'confirmed_taken')
            self.assertEqual(reviewed['review_note'], '家属确认')

    def test_camera_upload_rejects_wrong_type(self) -> None:
        device = create_hardware_device(
            HardwareDeviceCreate(device_uid='orangepi-bad-camera', name='bad camera', owner_id=2),
            self.child,
            self.session,
        )
        with patch('app.device_agent.get_settings', self._settings):
            with self.assertRaises(HTTPException) as raised:
                asyncio.run(agent_upload_camera_asset(
                    device_uid='orangepi-bad-camera',
                    kind='intake_video',
                    command_id=None,
                    user_id=2,
                    captured_at=None,
                    duration_seconds=None,
                    metadata_json=None,
                    file=self._jpeg(),
                    thumbnail=None,
                    _=None,
                    session=self.session,
                ))
            self.assertEqual(raised.exception.status_code, 400)


    def test_face_identity_can_be_set_to_child_or_stranger(self) -> None:
        device = create_hardware_device(
            HardwareDeviceCreate(device_uid='orangepi-identity', name='identity box', owner_id=2),
            self.child,
            self.session,
        )
        create_device_command(
            device['id'],
            DeviceCommandCreate(command_type='face_enroll', payload={'user_id': 2, 'samples': 5}),
            self.child,
            self.session,
        )
        claimed = agent_next_command('orangepi-identity', None, self.session)
        agent_command_result(
            claimed['command']['id'],
            AgentCommandResult(
                device_uid='orangepi-identity',
                success=True,
                result={'sample_count': 5},
            ),
            None,
            self.session,
        )
        face = list_device_faces(device['id'], self.child, self.session)[0]
        child_face = update_device_face_identity(
            device['id'],
            face['id'],
            DeviceFaceIdentityUpdate(role='child', announce_user_id=1),
            self.child,
            self.session,
        )
        self.assertEqual(child_face['role'], 'child')
        self.assertEqual(child_face['announce_user_id'], 1)
        stranger_face = update_device_face_identity(
            device['id'],
            face['id'],
            DeviceFaceIdentityUpdate(role='stranger'),
            self.child,
            self.session,
        )
        self.assertEqual(stranger_face['role'], 'stranger')
        self.assertIsNone(stranger_face['announce_user_id'])


if __name__ == '__main__':
    unittest.main()
