import json
import logging
from datetime import datetime
from typing import Optional, Sequence

from google import genai
from google.genai import types


logger = logging.getLogger(__name__)

WEEKDAYS_KO = ["월요일", "화요일", "수요일", "목요일", "금요일", "토요일", "일요일"]


class GaonAiService:
    def __init__(self, api_key: Optional[str], model_name: str):
        self.model_name = model_name
        self.client = genai.Client(api_key=api_key) if api_key else None

    @property
    def is_ready(self) -> bool:
        return self.client is not None

    def extract_schedule(self, user_message: str, now: datetime) -> dict:
        if not self.client:
            return {"is_schedule": False}

        current_time = self._format_current_time(now)
        prompt = f"""사용자 메시지에 미래 일정이나 알림 등록 요청이 있는지 판단하세요.
현재 기준 일시: {current_time}
사용자 메시지: {user_message}

일정 등록 의도가 있고 날짜와 시간을 구체적으로 정할 수 있을 때만 아래 JSON을 반환하세요.
{{"is_schedule": true, "task_content": "할 일", "task_time": "YYYY-MM-DD HH:MM:SS"}}
그 외에는 {{"is_schedule": false}}를 반환하세요. JSON 이외의 내용은 출력하지 마세요."""

        try:
            response = self.client.models.generate_content(
                model=self.model_name,
                contents=prompt,
                config=types.GenerateContentConfig(response_mime_type="application/json"),
            )
            result = json.loads(response.text.strip())
            if not result.get("is_schedule"):
                return {"is_schedule": False}
            if not result.get("task_content") or not result.get("task_time"):
                return {"is_schedule": False}
            datetime.strptime(result["task_time"], "%Y-%m-%d %H:%M:%S")
            return result
        except (AttributeError, TypeError, ValueError, json.JSONDecodeError) as exc:
            logger.warning("Gemini schedule response was invalid: %s", exc)
            return {"is_schedule": False}
        except Exception:
            logger.exception("Gemini schedule extraction failed")
            return {"is_schedule": False}

    def generate_chat_reply(
        self,
        user_message: str,
        now: datetime,
        schedules_text: str,
        history: Sequence,
        latitude: Optional[float] = None,
        longitude: Optional[float] = None,
        saved_schedule: Optional[dict] = None,
    ) -> str:
        if not self.client:
            raise RuntimeError("Gemini client is not configured")

        contents = []
        for row in history:
            role = "user" if row["sender"] == "user" else "model"
            contents.append(
                types.Content(
                    role=role,
                    parts=[types.Part.from_text(text=row["message"])],
                )
            )
        contents.append(
            types.Content(
                role="user",
                parts=[types.Part.from_text(text=user_message)],
            )
        )

        response = self.client.models.generate_content(
            model=self.model_name,
            contents=contents,
            config=types.GenerateContentConfig(
                system_instruction=self._build_system_instruction(
                    now=now,
                    schedules_text=schedules_text,
                    latitude=latitude,
                    longitude=longitude,
                    saved_schedule=saved_schedule,
                ),
                tools=[types.Tool(google_search=types.GoogleSearch())],
            ),
        )
        reply = (response.text or "").strip()
        if not reply:
            raise ValueError("Gemini returned an empty chat response")
        return reply

    def analyze_document(self, image_bytes: bytes, mime_type: str) -> str:
        if not self.client:
            raise RuntimeError("Gemini client is not configured")

        prompt = (
            "사진 속 문서에 실제로 보이는 내용만 읽어 주세요. 문서 종류와 핵심 내용을 "
            "어르신이 이해하기 쉬운 한국어로 짧게 설명하고, 해야 할 일이 있다면 순서대로 알려 주세요. "
            "글자가 흐리거나 확인되지 않는 부분은 추측하지 말고 확인하기 어렵다고 명확히 말하세요."
        )
        response = self.client.models.generate_content(
            model=self.model_name,
            contents=[
                types.Part.from_bytes(data=image_bytes, mime_type=mime_type),
                prompt,
            ],
        )
        reply = (response.text or "").strip()
        if not reply:
            raise ValueError("Gemini returned an empty document response")
        return reply

    def _build_system_instruction(
        self,
        now: datetime,
        schedules_text: str,
        latitude: Optional[float],
        longitude: Optional[float],
        saved_schedule: Optional[dict],
    ) -> str:
        instruction = f"""당신은 어르신을 돕는 친절하고 신뢰할 수 있는 AI 비서 '가온'입니다.
현재 기준 일시는 {self._format_current_time(now)}입니다.

[오늘 일정]
{schedules_text}

답변 원칙:
- 결론부터 쉬운 한국어로 답하고, 보통 2~4개의 짧은 문장으로 설명하세요.
- 전문용어는 풀어서 말하고, 한 문장에 한 가지 내용만 담으세요.
- 확실하지 않은 내용은 추측하지 말고 확인이 필요하다고 말하세요.
- 의료, 금융, 법률처럼 중요한 결정은 전문가나 보호자에게 확인하도록 안내하세요.
- 최신 정보가 필요한 질문은 Google 검색 결과를 확인한 뒤 답하세요.
- 사용자를 아버님, 어머님으로 단정하지 말고 존중하는 높임말을 사용하세요.
- 이모지는 꼭 필요할 때만 하나 이하로 사용하세요."""

        if latitude is not None and longitude is not None:
            instruction += f"""

[현재 위치]
위도 {latitude}, 경도 {longitude}
위치 질문에는 검색으로 실제 장소를 확인하고, 장소 이름과 위치 판단에 필요한 정보를 간단히 알려 주세요."""

        if saved_schedule:
            instruction += f"""

[방금 저장한 일정]
할 일: {saved_schedule['task_content']}
시간: {saved_schedule['task_time']}
일정이 저장됐음을 먼저 명확히 알려 주세요."""
        return instruction

    @staticmethod
    def _format_current_time(now: datetime) -> str:
        weekday = WEEKDAYS_KO[now.weekday()]
        return now.strftime(f"%Y년 %m월 %d일 {weekday} %H시 %M분")
