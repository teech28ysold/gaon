import unittest
from datetime import datetime

try:
    from .ai_service import GaonAiService
except ImportError:
    from ai_service import GaonAiService


class _Response:
    def __init__(self, text):
        self.text = text


class _Models:
    def __init__(self, responses):
        self._responses = iter(responses)

    def generate_content(self, **_kwargs):
        return _Response(next(self._responses))


class _Client:
    def __init__(self, responses):
        self.models = _Models(responses)


class GaonAiServiceTest(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 7, 13, 9, 30)
        self.service = GaonAiService(api_key=None, model_name="test-model")

    def test_schedule_requires_complete_valid_data(self):
        self.service.client = _Client([
            '{"is_schedule": true, "task_content": "약 먹기"}',
            '{"is_schedule": true, "task_content": "약 먹기", "task_time": "잘못된 시간"}',
        ])

        self.assertEqual(
            self.service.extract_schedule("내일 약 알려줘", self.now),
            {"is_schedule": False},
        )
        self.assertEqual(
            self.service.extract_schedule("내일 약 알려줘", self.now),
            {"is_schedule": False},
        )

    def test_schedule_accepts_valid_timestamp(self):
        expected = {
            "is_schedule": True,
            "task_content": "약 먹기",
            "task_time": "2026-07-14 09:00:00",
        }
        self.service.client = _Client([
            '{"is_schedule": true, "task_content": "약 먹기", '
            '"task_time": "2026-07-14 09:00:00"}'
        ])

        self.assertEqual(
            self.service.extract_schedule("내일 9시에 약 알려줘", self.now),
            expected,
        )

    def test_empty_chat_response_is_rejected(self):
        self.service.client = _Client(["  "])

        with self.assertRaises(ValueError):
            self.service.generate_chat_reply(
                user_message="오늘 날짜 알려줘",
                now=self.now,
                schedules_text="오늘 등록된 일정이 없습니다.",
                history=[],
            )

    def test_document_analysis_does_not_supply_sample_content(self):
        self.service.client = _Client(["사진이 흐려 내용을 확인하기 어렵습니다."])

        reply = self.service.analyze_document(b"image", "image/jpeg")

        self.assertEqual(reply, "사진이 흐려 내용을 확인하기 어렵습니다.")


if __name__ == "__main__":
    unittest.main()
