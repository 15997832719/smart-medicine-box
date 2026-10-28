import unittest

from app.voice_assistant import reply_payload, sanitize_speak_text


class SpeakTextSanitizerTests(unittest.TestCase):
    def test_markdown_table_links_and_emoji_are_removed(self) -> None:
        source = '''## 回答\n\n| 药品 | 用法 |\n|---|---|\n| 阿司匹林 | 一次1片 |\n\n[详情](https://example.com) 😀'''
        speak = sanitize_speak_text(source)
        self.assertNotIn('#', speak)
        self.assertNotIn('|', speak)
        self.assertNotIn('http', speak)
        self.assertNotIn('\U0001F600', speak)
        self.assertIn('阿司匹林', speak)
        self.assertIn('一次1片', speak)
        self.assertTrue(speak.endswith(('\u3002', '\uff01', '\uff1f')))

    def test_reply_payload_separates_display_and_speak_text(self) -> None:
        result = reply_payload('medicine_info', '**阿司匹林** 一次1片')
        self.assertEqual(result['display_text'], '**阿司匹林** 一次1片')
        self.assertEqual(result['reply'], result['display_text'])
        self.assertNotIn('*', result['speak_text'])
        self.assertIn('阿司匹林', result['speak_text'])


if __name__ == '__main__':
    unittest.main()
