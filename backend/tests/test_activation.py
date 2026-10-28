import unittest

from fastapi import HTTPException
from sqlalchemy.pool import StaticPool
from sqlmodel import SQLModel, Session, create_engine

from app.auth import (
    claim_activation,
    exchange_activation,
    enable_device_credential,
    list_devices,
    login_with_device,
    revoke_all_devices,
    revoke_device,
    start_activation,
)
from app.models import User, UserRole
from app.schemas import ActivationClaimRequest, ActivationExchangeRequest, DeviceCredentialRequest, DeviceLoginRequest


class ActivationFlowTests(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine(
            'sqlite://',
            connect_args={'check_same_thread': False},
            poolclass=StaticPool,
        )
        SQLModel.metadata.create_all(self.engine)
        self.session = Session(self.engine)
        self.child = User(
            id=1,
            phone='13800000001',
            password_hash='test',
            role=UserRole.child,
            nickname='child',
        )
        self.session.add(self.child)
        self.session.commit()

    def tearDown(self) -> None:
        self.session.close()

    def test_family_activation_and_device_login(self) -> None:
        started = start_activation(self.session)
        claimed = claim_activation(
            ActivationClaimRequest(
                activation_id=started.activation_id,
                activation_code=started.activation_code,
                nickname='elder',
            ),
            self.child,
            self.session,
        )
        self.assertTrue(claimed['success'])
        response = exchange_activation(
            ActivationExchangeRequest(
                activation_id=started.activation_id,
                device_secret=started.device_secret,
                platform='ohos',
            ),
            self.session,
        )
        self.assertEqual(response.user.nickname, 'elder')
        self.assertEqual(response.user.role, 'elder')
        self.assertTrue(response.access_token)
        elder_user = self.session.get(User, response.user.id)
        self.assertIsNotNone(elder_user)
        devices = list_devices(elder_user, self.session)
        self.assertEqual(len(devices), 1)
        self.assertEqual(devices[0].platform, 'ohos')

    def test_revoke_all_devices(self) -> None:
        started = start_activation(self.session)
        claim_activation(
            ActivationClaimRequest(
                activation_id=started.activation_id,
                activation_code=started.activation_code,
                nickname='elder',
            ),
            self.child,
            self.session,
        )
        response = exchange_activation(
            ActivationExchangeRequest(
                activation_id=started.activation_id,
                device_secret=started.device_secret,
            ),
            self.session,
        )
        elder = self.session.get(User, response.user.id)
        self.assertIsNotNone(elder)
        result = revoke_all_devices(elder, self.session)
        self.assertEqual(result['revoked'], 1)
        devices = list_devices(elder, self.session)
        self.assertIsNotNone(devices[0].revoked_at)

    def test_login_can_enable_and_use_device_credential(self) -> None:
        credential = enable_device_credential(
            DeviceCredentialRequest(platform='ohos'),
            self.child,
            self.session,
        )
        self.assertTrue(credential.device_id)
        self.assertTrue(credential.device_secret)
        response = login_with_device(
            DeviceLoginRequest(
                device_id=credential.device_id,
                device_secret=credential.device_secret,
                platform='ohos',
            ),
            self.session,
        )
        self.assertEqual(response.user.id, self.child.id)
        self.assertTrue(response.access_token)

    def test_wrong_activation_code_is_rejected(self) -> None:
        started = start_activation(self.session)
        with self.assertRaises(HTTPException) as raised:
            claim_activation(
                ActivationClaimRequest(
                    activation_id=started.activation_id,
                    activation_code='000000',
                    nickname='elder',
                ),
                self.child,
                self.session,
            )
        self.assertEqual(raised.exception.status_code, 400)

    def test_revoked_device_cannot_exchange_again(self) -> None:
        started = start_activation(self.session)
        claim_activation(
            ActivationClaimRequest(
                activation_id=started.activation_id,
                activation_code=started.activation_code,
                nickname='elder',
            ),
            self.child,
            self.session,
        )
        response = exchange_activation(
            ActivationExchangeRequest(
                activation_id=started.activation_id,
                device_secret=started.device_secret,
            ),
            self.session,
        )
        elder = self.session.get(User, response.user.id)
        device = list_devices(elder, self.session)[0]
        revoke_device(device.id, elder, self.session)
        with self.assertRaises(HTTPException) as raised:
            exchange_activation(
                ActivationExchangeRequest(
                    activation_id=started.activation_id,
                    device_secret=started.device_secret,
                ),
                self.session,
            )
        self.assertEqual(raised.exception.status_code, 401)


if __name__ == '__main__':
    unittest.main()
