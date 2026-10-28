import unittest
from types import SimpleNamespace

from xiaozhi_tts_base_original import TTSProviderBase


class _TTS(TTSProviderBase):
    def __init__(self):
        super().__init__({"tts_timeout": 15}, True)
        self.conn = SimpleNamespace(sample_rate=24000, audio_format="pcm")
        self.calls = []

    async def text_to_speak(self, text, output_file):
        return b""

    def to_tts_stream(self, text, opus_handler=None):
        self.calls.append(text)


class ShortReplyMergeTests(unittest.TestCase):
    def test_short_complete_reply_is_synthesized_once(self) -> None:
        tts = _TTS()
        tts.tts_text_buff = ["我是智能药箱的语音助手。", "可以帮您查用药计划。"]
        tts.processed_chars = 0
        self.assertTrue(tts._process_short_reply_as_one_segment())
        self.assertEqual(len(tts.calls), 1)
        self.assertIn("可以帮您查用药计划", tts.calls[0])

    def test_long_reply_keeps_streaming(self) -> None:
        tts = _TTS()
        tts.tts_text_buff = ["这是一段很长的回复。" * 20]
        tts.processed_chars = 0
        self.assertFalse(tts._process_short_reply_as_one_segment())

    def test_incomplete_sentence_keeps_streaming(self) -> None:
        tts = _TTS()
        tts.tts_text_buff = ["可以帮您查用药计划"]
        tts.processed_chars = 0
        self.assertFalse(tts._process_short_reply_as_one_segment())


if __name__ == "__main__":
    unittest.main()
