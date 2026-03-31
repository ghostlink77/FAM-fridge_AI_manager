"""
FAM Voice API Server - 메인 서버 파일
음성 파일을 받아서 STT + 음식/수량 추출 결과를 JSON으로 반환

실행 방법:
    uvicorn main:app --host 0.0.0.0 --port 8000 --reload
"""

from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import tempfile
import os

from stt_model import transcribe_audio
from ner_model import extract_food_items

app = FastAPI(
    title="FAM Voice API",
    description="음성 → 텍스트 → 음식/수량 추출 API",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class FoodItem(BaseModel):
    name: str
    quantity: float
    unit: str
    category: str
    consumeByDate: str | None = None


class STTResponse(BaseModel):
    success: bool
    text: str
    items: list[FoodItem]
    error: str | None = None


@app.post("/api/stt", response_model=STTResponse)
async def process_voice(audio_file: UploadFile = File(...)):
    try:
        suffix = os.path.splitext(audio_file.filename or ".wav")[1]
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
            content = await audio_file.read()
            tmp.write(content)
            tmp_path = tmp.name
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

    try:
        text = transcribe_audio(tmp_path)
        items = extract_food_items(text)
        return STTResponse(success=True, text=text, items=[FoodItem(**item) for item in items])
    except Exception as e:
        return STTResponse(success=False, text="", items=[], error=str(e))
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)


@app.get("/health")
async def health_check():
    return {"status": "ok", "message": "FAM Voice API is running"}


# 텍스트만 보내서 NER 테스트 (Whisper 없이도 테스트 가능)
class NERRequest(BaseModel):
    text: str

@app.post("/api/ner", response_model=STTResponse)
async def process_text(req: NERRequest):
    """텍스트를 직접 보내서 NER만 테스트 (STT 건너뜀)"""
    try:
        items = extract_food_items(req.text)
        return STTResponse(
            success=True, text=req.text,
            items=[FoodItem(**item) for item in items],
        )
    except Exception as e:
        return STTResponse(success=False, text=req.text, items=[], error=str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
