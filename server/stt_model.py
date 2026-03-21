"""
STT 모델 래퍼 (음성 → 텍스트 변환)

OpenAI Whisper를 사용 — 무료, 로컬 실행, API 키 불필요, 한국어 지원

설치:
    pip install openai-whisper

모델 크기별 비교:
    tiny   → 39MB,  가장 빠름, 정확도 낮음
    base   → 74MB,  빠름, 적당한 정확도
    small  → 244MB, 보통, 좋은 정확도
    medium → 769MB, 느림, 높은 정확도
    large  → 1.5GB, 매우 느림, 최고 정확도

첫 실행 시 모델 파일을 자동으로 다운로드함 (한 번만)
"""

# Whisper 설치 여부에 따라 자동 선택
try:
    import whisper
    WHISPER_MODEL_SIZE = "base"
    print(f"[STT] Whisper '{WHISPER_MODEL_SIZE}' 모델 로딩 중...")
    stt_model = whisper.load_model(WHISPER_MODEL_SIZE)
    print(f"[STT] Whisper 모델 로드 완료!")
    USE_WHISPER = True
except ImportError:
    print("[STT] Whisper not installed - dummy mode (test with /api/ner endpoint)")
    stt_model = None
    USE_WHISPER = False


def transcribe_audio(audio_path: str) -> str:
    if USE_WHISPER:
        result = stt_model.transcribe(audio_path, language="ko", fp16=False)
        return result["text"].strip()
    else:
        return "[Dummy STT] Whisper not installed. Use /api/ner for text testing."
