import unittest

from sqlalchemy.pool import StaticPool
from sqlmodel import SQLModel, Session, create_engine

from app.dueros import (
    FALLBACK_REPROMPT,
    FALLBACK_TEXT,
    dueros_skill,
    platform_intent_name,
    request_identifier,
    skill_response,
)
from app.models import SpeakerBinding, User, UserRole


class DuerOSResponseContractTests(unittest.TestCase):
    def test_continuing_response_contains_reprompt(self) -> None:
        response = skill_response("today medicine")
        body = response["response"]
        self.assertFalse(body["shouldEndSession"])
        self.assertEqual(body["reprompt"]["outputSpeech"]["text"], FALLBACK_REPROMPT)

    def test_ending_response_does_not_continue(self) -> None:
        response = skill_response("goodbye", end_session=True)
        self.assertTrue(response["response"]["shouldEndSession"])
        self.assertNotIn("reprompt", response["response"])

    def test_request_metadata_is_extracted(self) -> None:
        payload = {
            "request": {
                "requestId": "req-123",
                "intent": {"name": "SystemChitchatIntent"},
            },
            "session": {"sessionId": "session-456"},
        }
        self.assertEqual(request_identifier(payload), "req-123")
        self.assertEqual(platform_intent_name(payload), "SystemChitchatIntent")


class DuerOSSkillRoutingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        SQLModel.metadata.create_all(self.engine)
        self.session = Session(self.engine)
        user = User(
            id=1,
            phone="13800000011",
            password_hash="test",
            role=UserRole.elder,
            nickname="speaker test",
        )
        self.session.add(user)
        self.session.add(SpeakerBinding(speaker_id="speaker-1", user_id=1))
        self.session.commit()

    def tearDown(self) -> None:
        self.session.close()

    def _payload(self, text: str, request_id: str = "req-1") -> dict:
        return {
            "request": {
                "type": "IntentRequest",
                "requestId": request_id,
                "query": text,
                "intent": {"name": "SystemChitchatIntent"},
            },
            "session": {"sessionId": "session-1"},
            "context": {"device": {"deviceId": "speaker-1"}},
        }

    def test_unknown_text_never_falls_through_to_chitchat(self) -> None:
        with self.assertLogs("app.dueros", level="INFO") as logs:
            response = dueros_skill(self._payload("steamed lamb"), self.session)
        body = response["response"]
        self.assertFalse(body["shouldEndSession"])
        self.assertEqual(body["outputSpeech"]["text"], FALLBACK_TEXT)
        self.assertIn("reprompt", body)
        record = logs.records[0]
        self.assertEqual(record.final_intent, "FallbackIntent")
        self.assertEqual(record.raw_text, "steamed lamb")
        self.assertEqual(record.request_id, "req-1")
        self.assertGreaterEqual(record.elapsed_ms, 0)

    def test_twenty_unknown_queries_stay_on_safe_route(self) -> None:
        for index in range(20):
            response = dueros_skill(
                self._payload("weather today", request_id=f"req-{index}"),
                self.session,
            )
            self.assertEqual(response["response"]["outputSpeech"]["text"], FALLBACK_TEXT)
            self.assertFalse(response["response"]["shouldEndSession"])


if __name__ == "__main__":
    unittest.main()
