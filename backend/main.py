import os
import sys
import sqlite3
from datetime import datetime
from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from google import genai
from google.genai import types
from dotenv import load_dotenv

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
client = None
if GEMINI_API_KEY:
    print("LOADED API KEY FOR CLIENT:", GEMINI_API_KEY[:10] + "..." if GEMINI_API_KEY else "None")
    client = genai.Client(api_key=GEMINI_API_KEY)

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
    latitude: float = None
    longitude: float = None

class SmsRequest(BaseModel):
    receivers: list[str]
    message: str

def get_db_connection():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

@app.get("/")
def read_root():
    return {"message": "가온 AI 비서 백엔드 서버가 작동 중입니다."}

@app.get("/api/debug-key")
def get_debug_key():
    key = os.getenv("GEMINI_API_KEY")
    return {
        "key_prefix": key[:10] + "..." if key else "None",
        "key_length": len(key) if key else 0,
        "client_configured": client is not None
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
def extract_schedule_info(user_msg: str, current_time_str: str) -> dict:
    if not client:
        return {"is_schedule": False}
    try:
        prompt = (
            f"사용자 메시지를 분석하여 미래에 발생할 일정(알림/알람 설정)이 포함되어 있는지 확인하세요.\n"
            f"현재 기준 일시: {current_time_str}\n\n"
            f"사용자 메시지: \"{user_msg}\"\n\n"
            f"사용자가 미래의 특정 시점(예: '1분 뒤', '내일 오전 10시', '오후 3시', '5월 30일' 등)에 알림을 예약하거나 일정을 저장하고 싶어하는 경우, JSON 형식으로 추출하세요.\n"
            f"반드시 다음 JSON 스키마를 준수하여 결과를 반환하세요:\n"
            f"{{\n"
            f"  \"is_schedule\": true,\n"
            f"  \"task_content\": \"일정/할 일 내용 (예: 병원 가기, 물 마시기)\",\n"
            f"  \"task_time\": \"일정이 실행될 날짜와 시간 (형식: YYYY-MM-DD HH:MM:SS)\"\n"
            f"}}\n\n"
            f"만약 일정을 등록해 달라는 내용이 아니거나, 날짜/시간 정보가 구체적으로 유추되지 않는다면 다음 JSON을 반환하세요:\n"
            f"{{\n"
            f"  \"is_schedule\": false\n"
            f"}}\n"
            f"주의: JSON 이외의 텍스트는 절대 출력하지 마세요."
        )
        response = client.models.generate_content(
            model="gemini-2.5-pro",
            contents=prompt,
            config=types.GenerateContentConfig(
                response_mime_type="application/json"
            )
        )
        import json
        result = json.loads(response.text.strip())
        return result
    except Exception as e:
        print(f"일정 추출 오류: {e}")
        return {"is_schedule": False}

# 3. 유튜브 관련 헬퍼 함수들
def extract_youtube_video_id(message: str) -> str:
    import re
    patterns = [
        r"(?:https?:\/\/)?(?:www\.)?youtube\.com\/watch\?v=([^&\s\?]+)",
        r"(?:https?:\/\/)?(?:www\.)?youtu\.be\/([^&\s\?]+)",
        r"(?:https?:\/\/)?(?:www\.)?youtube\.com\/shorts\/([^&\s\?]+)",
        r"(?:https?:\/\/)?m\.youtube\.com\/watch\?v=([^&\s\?]+)"
    ]
    for pattern in patterns:
        match = re.search(pattern, message, re.IGNORECASE)
        if match:
            return match.group(1)
    return ""

def get_youtube_transcript(video_id: str) -> str:
    from youtube_transcript_api import YouTubeTranscriptApi
    try:
        api = YouTubeTranscriptApi()
        try:
            transcript_list = api.fetch(video_id, languages=['ko', 'en'])
        except Exception:
            transcript_list_info = api.list(video_id)
            transcript = None
            try:
                transcript = transcript_list_info.find_transcript(['ko', 'en'])
            except Exception:
                pass
            if not transcript:
                for t in transcript_list_info:
                    transcript = t
                    break
            if not transcript:
                return ""
            transcript_list = transcript.fetch()
        
        transcript_text = " ".join([item.text for item in transcript_list])
        return transcript_text
    except Exception as e:
        print(f"자막 추출 에러: {e}")
        return ""

def fact_check_youtube_transcript(transcript: str) -> dict:
    if not client:
        return {"category": "기타", "status": "safe", "summary": "Gemini API 비활성화 상태입니다.", "details": "서버 설정을 확인해 주세요."}
    try:
        if len(transcript) > 15000:
            transcript = transcript[:15000] + " (이하 생략)"
            
        prompt = (
            f"다음 유튜브 영상의 자막 내용을 꼼꼼하게 분석하여 팩트 체크 및 분석을 수행하세요.\n\n"
            f"[자막 내용]\n"
            f"{transcript}\n\n"
            f"1. 이 영상이 담고 있는 주요 정보의 주제(카테고리)를 다음 중 하나로 분류하세요: [건강, 금융, 기타]\n"
            f"2. 이 영상의 정보가 과대광고, 근거 없는 허위 정보, 낚시성 정보, 사기성 정보 등 위험 요소를 담고 있는지 분석하세요.\n"
            f"3. 분석 결과에 따라 상태(status)를 'warning'(위험/경고) 또는 'safe'(유용/안전) 중 하나로 판정하세요.\n"
            f"4. 40~50대 시니어가 이해하기 쉽고 명확하게 설명해 주세요.\n"
            f"   - 유용하거나 안전한 영상인 경우, 영상 내용의 핵심 요점 3줄 요약(summary)을 제공하세요.\n"
            f"   - 위험하거나 과대광고인 경우, 왜 위험한지 그 요점(경고 정보)을 3줄 요약(summary)으로 제공하세요.\n"
            f"5. 구체적인 분석 및 설명은 세부내용(details)에 작성하세요.\n\n"
            f"반드시 다음 JSON 스키마 형식으로만 답변을 작성하고 다른 설명은 하지 마세요:\n"
            f"{{\n"
            f"  \"category\": \"건강/금융/기타 중 하나\",\n"
            f"  \"status\": \"warning/safe 중 하나\",\n"
            f"  \"summary\": \"3줄 요약 및 경고 요점 (예: 1. ...\\n2. ...\\n3. ...)\",\n"
            f"  \"details\": \"구체적인 팩트 체크 근거 및 세부 분석 설명\"\n"
            f"}}"
        )
        response = client.models.generate_content(
            model="gemini-2.5-pro",
            contents=prompt,
            config=types.GenerateContentConfig(
                response_mime_type="application/json"
            )
        )
        import json
        result = json.loads(response.text.strip())
        return result
    except Exception as e:
        print(f"팩트 체크 분석 에러: {e}")
        return {
            "category": "기타",
            "status": "warning",
            "summary": "팩트 체크 분석 중 기술적인 오류가 발생했습니다.",
            "details": f"오류 원인: {str(e)}"
        }

# 4. 메시지 전송 및 가온 AI 응답 생성 API
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
        
        # 2) 일정 정보 추출 시도
        schedule_data = None
        now = datetime.now()
        weekday_kr = ["월요일", "화요일", "수요일", "목요일", "금요일", "토요일", "일요일"][now.weekday()]
        current_time_str = now.strftime(f"%Y-%m-%d %H:%M:%S ({weekday_kr})")
        
        # 3) 유튜브 링크 여부 및 분석 수행
        youtube_video_id = extract_youtube_video_id(user_msg)
        is_youtube = youtube_video_id != ""
        msg_type = "text"
        ai_reply = ""
        
        if is_youtube:
            # 유튜브 자막 로드
            transcript = get_youtube_transcript(youtube_video_id)
            if not transcript:
                # 자막이 없는 폴백 케이스
                ai_reply = "자막이 없는 영상이라 분석이 어렵습니다. 😢\n다른 자막이 있는 유익한 건강/금융 영상을 공유해 주시면 꼼꼼하게 검증해 드릴게요! 😊"
                msg_type = "text"
            else:
                # 자막 팩트 체크 분석 수행
                fact_check_result = fact_check_youtube_transcript(transcript)
                import json
                ai_reply = json.dumps(fact_check_result, ensure_ascii=False)
                msg_type = "fact_check"
        else:
            # 4) 일반 메시지의 경우 일정 및 대화 분석 진행
            if client:
                schedule_info = extract_schedule_info(user_msg, current_time_str)
                if schedule_info.get("is_schedule"):
                    try:
                        cursor.execute(
                            "INSERT INTO Schedules (task_content, task_time, is_done) VALUES (?, ?, ?)",
                            (schedule_info["task_content"], schedule_info["task_time"], 0)
                        )
                        schedule_id = cursor.lastrowid
                        schedule_data = {
                            "id": schedule_id,
                            "task_content": schedule_info["task_content"],
                            "task_time": schedule_info["task_time"]
                        }
                    except Exception as db_err:
                        print(f"일정 DB 저장 오류: {db_err}")

            # 5) Gemini 2.5 Pro를 사용한 시니어 맞춤 답변 생성
            if client:
                try:
                    # 오늘 등록된 일정 목록 조회해서 Gemini에 참고 정보로 전달
                    today_str = now.strftime("%Y-%m-%d")
                    cursor.execute("SELECT task_content, task_time, is_done FROM Schedules WHERE task_time LIKE ?", (f"{today_str}%",))
                    today_schedules = cursor.fetchall()
                    schedules_summary = []
                    for s in today_schedules:
                        status_str = "완료" if s["is_done"] == 1 else "예약됨(미완료)"
                        schedules_summary.append(f"- {s['task_content']} ({s['task_time'][11:16]}, 상태: {status_str})")
                    schedules_text = "\n".join(schedules_summary) if schedules_summary else "오늘 등록된 일정이 없습니다."

                    system_time_str = now.strftime(f"%Y년 %m월 %d일 {weekday_kr} %H시 %M분")
                    system_instruction = (
                        "당신은 40~50대 시니어를 위한 다정하고 꼼꼼한 AI 비서 '가온'입니다.\n"
                        f"현재 기준 일시는 {system_time_str} 입니다. 오늘 날짜, 시간, 요일 등에 대한 질문에는 반드시 이 정보를 기준으로 정확하게 대답해 주세요.\n"
                        f"\n[오늘 부모님의 일정/약 복용 기록]\n{schedules_text}\n"
                        "아버님, 어머님과 대화하듯이 항상 따뜻하고 친근하며 다정한 말투로 답변해 주세요.\n"
                        "설명은 너무 장황하지 않게 핵심만 짚어서 2~3줄로 이해하기 쉽게 설명해 주세요.\n"
                        "답변 중간에 어울리는 이모티콘(😊, 🌸, 📝 등)을 적절히 섞어주세요.\n"
                        "정치적인 질문이나 경제 정보(예: 현재 대한민국 대통령 이름, 실시간 주식 가격, 뉴스 등)에 대해서는 절대 답변을 회피하거나 거절하지 말고, 반드시 구글 검색 도구(Google Search)를 연동하여 확인한 정확한 검색 결과를 바탕으로 팩트에 맞게 사실대로 친절하게 답변하세요."
                    )
                    
                    # 위치 정보(GPS) 제공 시 지침 가이드라인 추가
                    if latitude is not None and longitude is not None:
                        system_instruction += (
                            f"\n\n[사용자 현재 위치 정보]\n"
                            f"- 위도(Latitude): {latitude}\n"
                            f"- 경도(Longitude): {longitude}\n"
                            f"사용자가 위치 기반 질문(예: '주변 병원 알려줘', '근처 약국 추천해줘' 등)을 한 경우, 위 위도와 경도 좌표를 기반으로 구글 검색을 통해 사용자 주변에 실제로 존재하는 병원, 의원, 약국 등의 시설 정보를 이름, 거리/위치와 함께 친절하고 정확하게 찾아서 가르쳐 주세요."
                        )
                    
                    # 일정 등록 시 지침 가이드라인 추가
                    if schedule_data:
                        system_instruction += (
                            f"\n\n[알림 설정 정보]\n"
                            f"- 할 일: {schedule_data['task_content']}\n"
                            f"- 예약 시간: {schedule_data['task_time']}\n"
                            f"방금 이 할 일과 예약 시간에 알람(알림)이 등록되었습니다. 사용자에게 다정하고 명확하게 알람 등록이 완료되었음을 알려주세요."
                        )
                    
                    # 이전 대화 내역 조회 (가장 최근 10개)
                    cursor.execute(
                        "SELECT sender, message FROM ChatHistory WHERE id < ? AND msg_type = 'text' ORDER BY id DESC LIMIT 10",
                        (user_msg_id,)
                    )
                    recent_history = cursor.fetchall()
                    recent_history.reverse()
                    
                    contents = []
                    for row in recent_history:
                        role = "user" if row["sender"] == "user" else "model"
                        contents.append(
                            types.Content(
                                role=role,
                                parts=[types.Part.from_text(text=row["message"])]
                            )
                        )
                    # 현재 사용자 메시지 추가
                    contents.append(
                        types.Content(
                            role="user",
                            parts=[types.Part.from_text(text=user_msg)]
                        )
                    )

                    config = types.GenerateContentConfig(
                        system_instruction=system_instruction,
                        tools=[types.Tool(google_search=types.GoogleSearch())]
                    )
                    response = client.models.generate_content(
                        model="gemini-2.5-pro",
                        contents=contents,
                        config=config
                    )
                    ai_reply = response.text.strip()
                except Exception as e:
                    ai_reply = f"아버님 어머님, 말씀하신 '{user_msg}' 내용을 잘 받아적어 두었어요! 😊 지금 서버 통신이 원활하지 않아 간략하게만 보관할게요. 궁금한 점이 있으시면 잠시 후 편하게 다시 여쭤봐 주세요! (오류: {str(e)})"
            else:
                ai_reply = f"아버님 어머님, '{user_msg}'라고 말씀하셨군요! 😊 제가 잘 기억해 두었다가 다음에도 꼼꼼히 챙겨드릴게요. 더 필요하신 심부름이나 궁금한 점이 있으시면 편하게 말씀해 주세요!"
        
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

# 3. 이미지 업로드 및 Gemini 1.5 Pro 분석 API
@app.post("/api/chat/image")
async def post_chat_image(file: UploadFile = File(...)):
    # 파일 확장자 검사
    if not file.content_type.startswith("image/"):
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
        
        # 2) Gemini 1.5 Pro 이미지 분석
        prompt = (
            "이 문서의 핵심 내용을 40~50대가 이해하기 쉬운 다정한 말투로 3줄 요약하고, "
            "당장 해야 할 행동(Action Item)을 알려줘."
        )
        
        ai_reply = ""
        if client:
            try:
                # Gemini 2.5 Pro 호출
                response = client.models.generate_content(
                    model="gemini-2.5-pro",
                    contents=[
                        types.Part.from_bytes(
                            data=image_bytes,
                            mime_type=file.content_type
                        ),
                        prompt
                    ]
                )
                ai_reply = response.text.strip()
            except Exception as e:
                # API 호출 오류 시 senior-friendly fallback 제공
                ai_reply = (
                    "아버님 어머님, 사진 속 글씨를 읽는 중에 기술적인 문제가 잠시 생겼어요. 😢\n"
                    "하지만 실망하지 마세요! 가온이가 예시 건강검진 안내장 문서의 해독 결과를 대신 보여드릴게요. 😊\n\n"
                    "1. 이 문서는 **'국민건강보험공단 무료 건강검진 안내장'**입니다.\n"
                    "2. 올해 12월 31일까지 가까운 공단 지정 병원에서 기본 검진을 받으실 수 있어요.\n"
                    "3. 전날 밤 9시부터는 꼭 금식(물 포함)하셔야 올바른 검사가 진행됩니다.\n\n"
                    "🙋 당장 해야 할 행동: **달력에 비어있는 날짜를 정하시고, 안내문 밑에 적힌 지정 병원 번호로 검진을 미리 예약하세요!**\n\n"
                    f"*(※ 참고: API 호출 실패 에러 - {str(e)})*"
                )
        else:
            # API 키가 환경변수에 없는 경우에 대한 Fallback 모의 데이터
            ai_reply = (
                "아버님 어머님, 보내주신 사진(공공기관 안내장)을 분석해 드릴게요! 😊\n\n"
                "1. 이 문서는 **'국민건강보험공단 무료 건강검진 안내장'**입니다.\n"
                "2. 올해 12월 31일까지 가까운 공단 지정 병원에서 기본 검진을 받으실 수 있어요.\n"
                "3. 전날 밤 9시부터는 꼭 금식(물 포함)하셔야 올바른 검사가 진행됩니다.\n\n"
                "🙋 당장 해야 할 행동: **달력에 비어있는 날짜를 정하시고, 안내문 밑에 적힌 지정 병원 번호로 검진을 미리 예약하세요!**\n\n"
                "*(※ 현재 백엔드 서버에 GEMINI_API_KEY 환경변수가 설정되어 있지 않아 테스트용 샘플 결과를 표시했습니다.)*"
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

# 5. 가상 SMS 발송 API (실제 SMS API 연동을 위한 백본 마련)
@app.post("/api/send-sms")
def send_virtual_sms(request: SmsRequest):
    receivers = request.receivers
    message = request.message
    
    if not receivers:
        raise HTTPException(status_code=400, detail="수신자 번호가 존재하지 않습니다.")
    if not message:
        raise HTTPException(status_code=400, detail="메시지 내용이 비어있습니다.")
        
    print("\n" + "=" * 50)
    print("[SMS 발송 시뮬레이션]")
    print(f"시간: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"수신처: {', '.join(receivers)}")
    print(f"내용:\n{message}")
    print("=" * 50 + "\n")
    
    return {
        "status": "success",
        "message": "안심 문자가 성공적으로 발송되었습니다. (가상 발송 완료)",
        "receivers": receivers,
        "content": message
    }
