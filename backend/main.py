import hashlib
import hmac
import json
import logging
import os
import sys
import sqlite3
import urllib.error
import urllib.request
import uuid
from datetime import datetime
from typing import Optional
from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from dotenv import load_dotenv
try:
    from .ai_service import GaonAiService
except ImportError:
    from ai_service import GaonAiService

logger = logging.getLogger(__name__)

# stdout, stderr 인코딩 오류 방지 (Windows 콘솔 환경에서 이모지 출력 시 크래시 방지)
try:
    sys.stdout.reconfigure(errors='replace')
    sys.stderr.reconfigure(errors='replace')
except Exception:
    pass

# .env 파일에서 환경변수 로드 (기존 환경변수가 설정되어 있을 경우 덮어쓰도록 override=True 설정)
env_path = os.path.join(os.path.dirname(__file__), ".env")
load_dotenv(dotenv_path=env_path, override=True)

app = FastAPI(title="Gaon AI Assistant Backend")

# CORS 설정 (Flutter 앱 연동을 위해 허용)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

DB_PATH = os.path.join(os.path.dirname(__file__), "chat.db")

# Gemini API 설정
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-2.5-pro")
ai_service = GaonAiService(GEMINI_API_KEY, GEMINI_MODEL)
if ai_service.is_ready:
    print(f"Gemini API client configured with model {GEMINI_MODEL}.")

# 데이터베이스 및 테이블 초기화
def init_db():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS ChatHistory (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sender TEXT NOT NULL,
            message TEXT NOT NULL,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
            msg_type TEXT DEFAULT 'text'
        );
    """)
    try:
        cursor.execute("ALTER TABLE ChatHistory ADD COLUMN msg_type TEXT DEFAULT 'text'")
    except Exception:
        pass  # 이미 컬럼이 존재함
        
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS Schedules (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task_content TEXT NOT NULL,
            task_time TEXT NOT NULL,
            is_done INTEGER DEFAULT 0
        );
    """)
    conn.commit()
    conn.close()

init_db()

class ChatRequest(BaseModel):
    message: str
    latitude: Optional[float] = None
    longitude: Optional[float] = None

class SmsRequest(BaseModel):
    receivers: list[str]
    message: str

def get_db_connection():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def normalize_phone_number(phone: str) -> str:
    return "".join(ch for ch in phone if ch.isdigit())

def send_solapi_sms(receivers: list[str], message: str) -> dict:
    api_key = os.getenv("SOLAPI_API_KEY")
    api_secret = os.getenv("SOLAPI_API_SECRET")
    from_number = normalize_phone_number(os.getenv("SOLAPI_FROM_NUMBER", ""))

    if not api_key or not api_secret or not from_number:
        return {"sent": False, "reason": "SOLAPI 환경변수가 설정되지 않았습니다."}

    date = datetime.utcnow().isoformat(timespec="milliseconds") + "Z"
    salt = uuid.uuid4().hex
    signature = hmac.new(
        api_secret.encode("utf-8"),
        f"{date}{salt}".encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()

    payload = {
        "messages": [
            {
                "to": normalize_phone_number(receiver),
                "from": from_number,
                "text": message,
            }
            for receiver in receivers
        ]
    }

    request = urllib.request.Request(
        "https://api.solapi.com/messages/v4/send-many",
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={
            "Authorization": (
                f"HMAC-SHA256 apiKey={api_key}, date={date}, salt={salt}, signature={signature}"
            ),
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            body = response.read().decode("utf-8")
            return {
                "sent": True,
                "provider": "solapi",
                "response": json.loads(body) if body else {},
            }
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")
        raise HTTPException(status_code=502, detail=f"Solapi 문자 발송 실패: {detail}")
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Solapi 문자 발송 오류: {str(e)}")

@app.get("/")
def read_root():
    return {"message": "가온 AI 비서 백엔드 서버가 작동 중입니다."}

@app.get("/api/status")
def get_api_status():
    return {
        "status": "ok",
        "gemini_key_present": bool(GEMINI_API_KEY),
        "gemini_client_configured": ai_service.is_ready,
        "gemini_model": GEMINI_MODEL,
        "ai_ready": ai_service.is_ready,
        "render_git_commit": os.getenv("RENDER_GIT_COMMIT", ""),
        "service": os.getenv("RENDER_SERVICE_NAME", ""),
    }

# 1. 대화 내역 전체 조회 API
@app.get("/api/history")
def get_chat_history():
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT id, sender, message, timestamp, msg_type FROM ChatHistory ORDER BY id ASC")
        rows = cursor.fetchall()
        conn.close()
        
        history = []
        for row in rows:
            history.append({
                "id": row["id"],
                "sender": row["sender"],
                "message": row["message"],
                "timestamp": row["timestamp"],
                "msg_type": row["msg_type"] if "msg_type" in row.keys() else "text"
            })
        return history
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"데이터베이스 조회 오류: {str(e)}")

# 2. 일정 파싱 및 추출 헬퍼 함수
def get_today_schedules_text(cursor, now: datetime) -> str:
    cursor.execute(
        "SELECT task_content, task_time, is_done FROM Schedules WHERE task_time LIKE ?",
        (f"{now.strftime('%Y-%m-%d')}%",),
    )
    summaries = []
    for schedule in cursor.fetchall():
        status = "완료" if schedule["is_done"] == 1 else "예정"
        summaries.append(
            f"- {schedule['task_content']} ({schedule['task_time'][11:16]}, {status})"
        )
    return "\n".join(summaries) if summaries else "오늘 등록된 일정이 없습니다."


def save_schedule(cursor, schedule_info: dict) -> Optional[dict]:
    if not schedule_info.get("is_schedule"):
        return None
    cursor.execute(
        "INSERT INTO Schedules (task_content, task_time, is_done) VALUES (?, ?, ?)",
        (schedule_info["task_content"], schedule_info["task_time"], 0),
    )
    return {
        "id": cursor.lastrowid,
        "task_content": schedule_info["task_content"],
        "task_time": schedule_info["task_time"],
    }


def ai_unavailable_message() -> str:
    return "지금은 가온이 답변을 가져오지 못했어요. 잠시 후 같은 질문을 다시 해 주세요."

# 3. 메시지 전송 및 가온 AI 응답 생성 API
@app.post("/api/chat")
def post_chat_message(request: ChatRequest):
    user_msg = request.message.strip()
    latitude = request.latitude
    longitude = request.longitude
    if not user_msg:
        raise HTTPException(status_code=400, detail="메시지 내용이 비어있습니다.")
        
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # 1) 사용자 메시지 DB 저장 (msg_type: 'text')
        cursor.execute(
            "INSERT INTO ChatHistory (sender, message, timestamp, msg_type) VALUES (?, ?, ?, ?)",
            ("user", user_msg, datetime.now().strftime("%Y-%m-%d %H:%M:%S"), "text")
        )
        user_msg_id = cursor.lastrowid
        
        # 2) 일정 정보 추출 및 저장
        now = datetime.now()
        schedule_data = save_schedule(
            cursor,
            ai_service.extract_schedule(user_msg, now),
        )

        # 3) 최근 대화와 오늘 일정을 참고해 답변 생성
        msg_type = "text"
        cursor.execute(
            "SELECT sender, message FROM ChatHistory WHERE id < ? AND msg_type = 'text' ORDER BY id DESC LIMIT 10",
            (user_msg_id,),
        )
        recent_history = cursor.fetchall()
        recent_history.reverse()

        try:
            ai_reply = ai_service.generate_chat_reply(
                user_message=user_msg,
                now=now,
                schedules_text=get_today_schedules_text(cursor, now),
                history=recent_history,
                latitude=latitude,
                longitude=longitude,
                saved_schedule=schedule_data,
            )
        except Exception:
            logger.exception("Gemini chat generation failed")
            ai_reply = ai_unavailable_message()
        
        # 6) AI 답변 DB 저장 (msg_type 추가)
        cursor.execute(
            "INSERT INTO ChatHistory (sender, message, timestamp, msg_type) VALUES (?, ?, ?, ?)",
            ("ai", ai_reply, datetime.now().strftime("%Y-%m-%d %H:%M:%S"), msg_type)
        )
        ai_msg_id = cursor.lastrowid
        
        conn.commit()
        
        # 저장된 내역 다시 읽기
        cursor.execute("SELECT timestamp FROM ChatHistory WHERE id = ?", (user_msg_id,))
        user_time = cursor.fetchone()["timestamp"]
        
        cursor.execute("SELECT timestamp FROM ChatHistory WHERE id = ?", (ai_msg_id,))
        ai_time = cursor.fetchone()["timestamp"]
        
        conn.close()
        
        return {
            "status": "success",
            "user_message": {
                "id": user_msg_id,
                "sender": "user",
                "message": user_msg,
                "timestamp": user_time,
                "msg_type": "text"
            },
            "ai_message": {
                "id": ai_msg_id,
                "sender": "ai",
                "message": ai_reply,
                "timestamp": ai_time,
                "msg_type": msg_type
            },
            "schedule": schedule_data
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"메시지 처리 오류: {str(e)}")

# 4. 이미지 업로드 및 문서 분석 API
@app.post("/api/chat/image")
async def post_chat_image(file: UploadFile = File(...)):
    # 파일 확장자 검사
    if not (file.content_type or "").startswith("image/"):
        ext = file.filename.split('.')[-1].lower() if file.filename else ""
        if ext in ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'gif']:
            file.content_type = f"image/{'jpeg' if ext in ['jpg', 'jpeg'] else ext}"
        elif file.content_type == "application/octet-stream":
            file.content_type = "image/jpeg"
        else:
            raise HTTPException(status_code=400, detail="이미지 파일 형식만 업로드 가능합니다.")
        
    try:
        # 이미지 바이트 로드
        image_bytes = await file.read()
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # 1) 사용자 이미지 메시지 DB 저장
        user_msg = "📷 [사진] 문서 해독을 요청하셨습니다."
        cursor.execute(
            "INSERT INTO ChatHistory (sender, message, timestamp) VALUES (?, ?, ?)",
            ("user", user_msg, datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
        )
        user_msg_id = cursor.lastrowid
        
        # 2) 실제 사진 내용만 분석하며, 실패 시 임의의 문서 내용을 만들지 않음
        try:
            ai_reply = ai_service.analyze_document(
                image_bytes=image_bytes,
                mime_type=file.content_type,
            )
        except Exception:
            logger.exception("Gemini document analysis failed")
            ai_reply = (
                "지금은 사진 속 글자를 읽지 못했어요. 사진을 밝은 곳에서 문서 전체가 "
                "보이도록 다시 찍어 주세요. 그래도 안 되면 잠시 후 다시 시도해 주세요."
            )
            
        # 3) AI 답변 DB 저장
        cursor.execute(
            "INSERT INTO ChatHistory (sender, message, timestamp) VALUES (?, ?, ?)",
            ("ai", ai_reply, datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
        )
        ai_msg_id = cursor.lastrowid
        
        conn.commit()
        
        # 저장된 타임스탬프 로드
        cursor.execute("SELECT timestamp FROM ChatHistory WHERE id = ?", (user_msg_id,))
        user_time = cursor.fetchone()["timestamp"]
        
        cursor.execute("SELECT timestamp FROM ChatHistory WHERE id = ?", (ai_msg_id,))
        ai_time = cursor.fetchone()["timestamp"]
        
        conn.close()
        
        return {
            "status": "success",
            "user_message": {
                "id": user_msg_id,
                "sender": "user",
                "message": user_msg,
                "timestamp": user_time
            },
            "ai_message": {
                "id": ai_msg_id,
                "sender": "ai",
                "message": ai_reply,
                "timestamp": ai_time
            }
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"이미지 처리 오류: {str(e)}")

# 4. 대화 내역 초기화 API
@app.post("/api/chat/clear")
def clear_chat_history():
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("DELETE FROM ChatHistory")
        conn.commit()
        conn.close()
        return {"status": "success", "message": "모든 대화 내역이 성공적으로 초기화되었습니다."}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"데이터 초기화 오류: {str(e)}")

# 5. 보호자 SMS 발송 API (Solapi 설정 시 실제 발송, 미설정 시 테스트 모드)
@app.post("/api/send-sms")
def send_virtual_sms(request: SmsRequest):
    receivers = [normalize_phone_number(receiver) for receiver in request.receivers]
    receivers = [receiver for receiver in receivers if receiver]
    message = request.message
    
    if not receivers:
        raise HTTPException(status_code=400, detail="수신자 번호가 존재하지 않습니다.")
    if not message:
        raise HTTPException(status_code=400, detail="메시지 내용이 비어있습니다.")
        
    solapi_result = send_solapi_sms(receivers, message)
    if solapi_result.get("sent"):
        return {
            "status": "success",
            "mode": "live",
            "provider": solapi_result.get("provider"),
            "message": "안심 문자가 실제로 발송 요청되었습니다.",
            "receivers": receivers,
            "content": message,
            "provider_response": solapi_result.get("response"),
        }

    print("\n" + "=" * 50)
    print("[SMS 테스트 모드]")
    print(f"시간: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"수신처: {', '.join(receivers)}")
    print(f"내용:\n{message}")
    print(f"사유: {solapi_result.get('reason')}")
    print("=" * 50 + "\n")
    
    return {
        "status": "success",
        "mode": "mock",
        "message": "안심 문자가 테스트 모드로 기록되었습니다. 실제 발송은 Solapi 설정 후 가능합니다.",
        "receivers": receivers,
        "content": message
    }
