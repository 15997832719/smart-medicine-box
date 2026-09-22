import unittest

from app.config import get_settings
from app.dueros import request_text, skill_response
from app.main import app
from app.services import _jie_xi_mo_xing_ri_qi


class BackendSmokeTests(unittest.TestCase):
    def test_settings_load_with_optional_dueros_id_empty(self) -> None:
        settings = get_settings()
        self.assertIn("glm", settings.zhipu_vision_model)

    def test_dueros_request_text_reads_nested_query(self) -> None:
        payload = {
            "request": {
                "query": "今天我要吃什么药",
                "intent": {"slots": {"medicine": {"value": "布洛芬"}}},
            }
        }
        text = request_text(payload)
        self.assertIn("今天我要吃什么药", text)
        self.assertIn("布洛芬", text)

    def test_dueros_response_contains_speech(self) -> None:
        response = skill_response("测试回复")
        self.assertEqual(response["version"], "2.0")
        self.assertEqual(response["response"]["outputSpeech"]["text"], "测试回复")

    def test_required_routes_are_registered(self) -> None:
        paths = {route.path for route in app.routes}
        self.assertIn("/api/v1/health", paths)
        self.assertIn("/api/v1/voice/transcribe", paths)
        self.assertIn("/api/v1/logs/voice-intent", paths)
        self.assertIn("/api/v1/dueros/skill", paths)

    def test_vision_expiry_date_is_parsed(self) -> None:
        self.assertEqual(str(_jie_xi_mo_xing_ri_qi("2027-03-15")), "2027-03-15")
        self.assertIsNone(_jie_xi_mo_xing_ri_qi("not-a-date"))


if __name__ == "__main__":
    unittest.main()
