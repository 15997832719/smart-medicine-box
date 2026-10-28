import asyncio
import base64
import tempfile
import unittest
from datetime import datetime, time, timedelta
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from fastapi import FastAPI, Request
from sqlalchemy.pool import StaticPool
from sqlmodel import SQLModel, Session, create_engine, select

from app import device_events
from app.device_agent import DeviceCommand, DeviceFaceProfile, HardwareDeviceCreate, MedicineBoxDevice, create_hardware_device
from app.device_events import (
    DeviceAnnouncement,
    DeviceRuntimeState,
    RadarEventCreate,
    RecognitionEventCreate,
    Syn6288StateCallback,
    XiaozhiStateCallback,
    _preview_status,
    _process_radar_event,
    _process_recognition_event,
    _process_syn_state,
    _process_xiaozhi_state,
    next_announcement,
    start_preview,
    upload_preview_frame,
)
from app.models import FamilyLink, Medicine, Reminder, User, UserRole


class DeviceEventFlowTests(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine(
            'sqlite://',
            connect_args={'check_same_thread': False},
            poolclass=StaticPool,
        )
        SQLModel.metadata.create_all(self.engine)
        self.session = Session(self.engine)
        self.child = User(id=1, phone='13800000301', password_hash='x', role=UserRole.child, nickname='child')
        self.elder = User(id=2, phone='13800000302', password_hash='x', role=UserRole.elder, nickname='elder')
        self.session.add(self.child)
        self.session.add(self.elder)
        self.session.commit()
        self.session.add(FamilyLink(elder_id=2, child_id=1))
        medicine = Medicine(id=1, name='降压药', owner_id=2, stock_count=10)
        self.session.add(medicine)
        self.session.commit()
        self.session.add(Reminder(id=1, medicine_id=1, title='降压药', remind_time=time(8, 0), owner_id=2))
        self.session.commit()
        self.session.add(Medicine(id=2, name='子女药', owner_id=1, stock_count=5))
        self.session.commit()
        self.session.add(Reminder(id=2, medicine_id=2, title='子女药', remind_time=time(9, 0), owner_id=1))
        self.session.commit()
        self.device = create_hardware_device(
            HardwareDeviceCreate(device_uid='orangepi-events', name='事件测试药箱', owner_id=2),
            self.child,
            self.session,
        )
        self.device_model = self.session.get(MedicineBoxDevice, self.device['id'])
        self.session.add(DeviceFaceProfile(
            device_id=self.device['id'],
            user_id=2,
            face_key='smb-user-2',
            display_name='老人',
            role='elder',
            announce_user_id=2,
            sample_count=5,
        ))
        self.session.add(DeviceFaceProfile(
            device_id=self.device['id'],
            user_id=1,
            announce_user_id=1,
            face_key='child-face',
            display_name='子女',
            role='child',
            sample_count=5,
        ))
        self.session.commit()
        self.session.commit()
        self.temp_dir = tempfile.TemporaryDirectory()

    def tearDown(self) -> None:
        self.session.close()
        self.temp_dir.cleanup()

    def _settings(self):
        return SimpleNamespace(
            device_camera_dir=self.temp_dir.name,
            device_agent_token='dev-device-agent-token',
            api_prefix='/api/v1',
        )

    def test_radar_and_recognition_queue_one_announcement(self) -> None:
        radar = _process_radar_event(
            self.session,
            self.device_model,
            RadarEventCreate(device_uid='orangepi-events', present=True, distance_cm=120),
        )
        self.assertEqual(radar['episode'], 1)
        self.assertIsNotNone(radar['recognition_command_id'])
        recognition_command = self.session.get(DeviceCommand, radar['recognition_command_id'])
        self.assertEqual(recognition_command.command_type, 'face_recognize')
        result = _process_recognition_event(
            self.session,
            self.device_model,
            RecognitionEventCreate(
                device_uid='orangepi-events',
                face_key='smb-user-2',
                event_type='recognized',
                score=0.73,
            ),
        )
        self.assertIsNotNone(result['announcement_id'])
        duplicate = _process_recognition_event(
            self.session,
            self.device_model,
            RecognitionEventCreate(
                device_uid='orangepi-events',
                face_key='smb-user-2',
                event_type='recognized',
                score=0.71,
            ),
        )
        self.assertEqual(duplicate['announcement_id'], result['announcement_id'])
        announcements = self.session.exec(select(DeviceAnnouncement)).all()
        self.assertEqual(len(announcements), 1)
        self.assertIn('降压药', announcements[0].text)

    def test_xiaozhi_busy_cancels_pending_and_requests_stop(self) -> None:
        _process_radar_event(
            self.session,
            self.device_model,
            RadarEventCreate(device_uid='orangepi-events', present=True, distance_cm=100),
        )
        result = _process_recognition_event(
            self.session,
            self.device_model,
            RecognitionEventCreate(device_uid='orangepi-events', face_key='smb-user-2', score=0.8),
        )
        busy = _process_xiaozhi_state(
            self.session,
            self.device_model,
            XiaozhiStateCallback(device_uid='orangepi-events', state='listening'),
        )
        self.assertTrue(busy['stop_tts'])
        self.assertGreaterEqual(busy['cancelled'], 1)
        announcement = self.session.get(DeviceAnnouncement, result['announcement_id'])
        self.assertEqual(announcement.status, 'cancelled')
        self.assertEqual(announcement.reason, 'xiaozhi_busy')
        runtime = self.session.exec(select(DeviceRuntimeState)).first()
        self.assertIsNotNone(runtime.stop_tts_requested_at)

    def test_idle_xiaozhi_after_settle_delivers_announcement(self) -> None:
        _process_radar_event(
            self.session,
            self.device_model,
            RadarEventCreate(device_uid='orangepi-events', present=True, distance_cm=90),
        )
        _process_recognition_event(
            self.session,
            self.device_model,
            RecognitionEventCreate(device_uid='orangepi-events', face_key='smb-user-2', score=0.8),
        )
        runtime = self.session.exec(select(DeviceRuntimeState)).first()
        runtime.xiaozhi_state = 'idle'
        runtime.last_xiaozhi_at = datetime.utcnow() - timedelta(seconds=2)
        self.session.add(runtime)
        self.session.commit()
        with patch('app.device_events._agent_token_ok', return_value=True):
            response = next_announcement('orangepi-events', self.session, 'token')
        self.assertIsNotNone(response['announcement'])
        self.assertIn('降压药', response['announcement']['text'])
        decoded = base64.b64decode(response['announcement']['text_gb2312_base64']).decode('gb2312')
        self.assertIn('降压药', decoded)
        _process_syn_state(
            self.session,
            self.device_model,
            Syn6288StateCallback(device_uid='orangepi-events', state='idle', announcement_id=response['announcement']['id']),
        )
        finished = self.session.get(DeviceAnnouncement, response['announcement']['id'])
        self.assertEqual(finished.status, 'finished')

    def test_preview_start_and_frame_upload(self) -> None:
        start_preview(self.device['id'], self.child, self.session)
        self.assertTrue(_preview_status(self.session, self.device['id'])['active'])

        async def receive():
            return {'type': 'http.request', 'body': b'\xff\xd8\xff\xe0preview', 'more_body': False}

        request = Request({'type': 'http', 'method': 'POST', 'path': '/', 'headers': []}, receive)
        with patch('app.device_events.get_settings', self._settings), patch('app.device_events._agent_token_ok', return_value=True):
            result = asyncio.run(upload_preview_frame(
                request,
                device_uid='orangepi-events',
                session=self.session,
                x_agent_token='token',
            ))
        self.assertTrue(result['ok'])
        frame_path = Path(self.temp_dir.name) / 'preview' / str(self.device['id']) / 'latest.jpg'
        self.assertTrue(frame_path.is_file())

    def test_device_websocket_route_is_registered(self) -> None:
        app = FastAPI()
        app.include_router(device_events.agent_router, prefix='/api/v1')
        self.assertIn('/api/v1/device-agent/ws', [route.path for route in app.routes])

    def test_child_face_uses_child_box_and_stranger_does_not_announce(self) -> None:
        _process_radar_event(
            self.session,
            self.device_model,
            RadarEventCreate(device_uid='orangepi-events', present=True, distance_cm=90),
        )
        child_result = _process_recognition_event(
            self.session,
            self.device_model,
            RecognitionEventCreate(device_uid='orangepi-events', face_key='child-face', score=0.81),
        )
        self.assertIsNotNone(child_result['announcement_id'])
        self.assertEqual(child_result['event']['user_id'], 1)
        self.assertEqual(child_result['event']['identity_role'], 'child')
        announcement = self.session.get(DeviceAnnouncement, child_result['announcement_id'])
        self.assertIn('子女药', announcement.text)

        profile = self.session.exec(select(DeviceFaceProfile).where(DeviceFaceProfile.face_key == 'child-face')).first()
        profile.role = 'stranger'
        profile.announce_user_id = None
        profile.display_name = '陌生人'
        self.session.add(profile)
        self.session.commit()
        _process_radar_event(
            self.session,
            self.device_model,
            RadarEventCreate(device_uid='orangepi-events', present=False),
        )
        _process_radar_event(
            self.session,
            self.device_model,
            RadarEventCreate(device_uid='orangepi-events', present=True, distance_cm=80),
        )
        stranger_result = _process_recognition_event(
            self.session,
            self.device_model,
            RecognitionEventCreate(device_uid='orangepi-events', face_key='child-face', score=0.82),
        )
        self.assertIsNone(stranger_result['announcement_id'])
        self.assertEqual(stranger_result['event']['event_type'], 'stranger')
        self.assertIsNone(stranger_result['event']['user_id'])


if __name__ == '__main__':
    unittest.main()
