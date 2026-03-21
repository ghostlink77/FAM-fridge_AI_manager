# FAM Voice API Server

음성 파일 -> 텍스트 변환(STT, Whisper) -> 음식명/수량 추출(NER, KoELECTRA) -> JSON 반환 API 서버

## 빠른 시작 (5단계)

### 1. Python 가상환경 만들기
```bash
cd server
python -m venv venv

# Windows:
venv\Scripts\activate
# Mac/Linux:
source venv/bin/activate
```

### 2. Python 패키지 설치
```bash
pip install -r requirements.txt
pip install openai-whisper
```

### 3. ffmpeg 설치 (Whisper가 내부적으로 사용)
```bash
# Windows:
winget install ffmpeg
# Mac:
brew install ffmpeg

# 설치 후 터미널을 껐다가 다시 열어야 PATH에 적용됨!
```

### 4. 서버 실행
```bash
# Windows에서는 인코딩 설정 필요
$env:PYTHONIOENCODING="utf-8"

# 서버 시작
python -m uvicorn main:app --host 0.0.0.0 --port 8000
```

### 5. 확인
- 브라우저: http://localhost:8000/docs  (Swagger UI - API 테스트 가능)
- 상태 확인: http://localhost:8000/health

---

## API 엔드포인트

### POST /api/stt (음성 파일 -> STT + NER)
음성 파일을 업로드하면 텍스트 변환 + 음식 정보 추출 결과를 반환합니다.

- Content-Type: `multipart/form-data`
- Body 필드명: `audio_file` (음성 파일 .m4a, .wav, .mp3 등)

### POST /api/ner (텍스트 직접 -> NER만)
텍스트를 직접 보내서 NER만 수행합니다. (STT 건너뜀, 테스트용)

- Content-Type: `application/json`
- Body: `{"text": "사과 세 개랑 우유 두 팩 사왔어"}`

### GET /health
서버 상태 확인용

### 공통 응답 형식
```json
{
  "success": true,
  "text": "사과 세 개랑 우유 두 팩 추가해줘",
  "items": [
    {"name": "사과", "quantity": 3, "unit": "개", "category": "과일"},
    {"name": "우유", "quantity": 2, "unit": "팩", "category": "유제품"}
  ],
  "error": null
}
```

---

## 프로젝트 구조

```
server/
├── main.py              # FastAPI 서버 본체 (/api/stt, /api/ner, /health)
├── stt_model.py         # Whisper STT (미설치 시 자동 더미 모드)
├── ner_model.py         # KoELECTRA NER (SafeTensors, ONNX 전환 가능)
├── convert_to_onnx.py   # (선택) SafeTensors -> ONNX 변환 스크립트
├── requirements.txt     # Python 패키지 목록
├── README.md            # 이 문서
└── models/              # 모델 파일 (큰 파일은 Google Drive 공유)
    ├── model.safetensors      # NER 모델 가중치 (필수)
    ├── tokenizer.json         # 토크나이저 (필수)
    ├── tokenizer_config.json  # 토크나이저 설정 (필수)
    └── config.json            # 모델 설정 (첫 실행 시 자동 생성)
```


---

## 주의사항

- **서버 종료**: 터미널에서 `Ctrl+C` (터미널 창을 닫으면 안 됨, 최소화만)
- **포트 충돌 (10048 에러)**: 이전 서버가 포트를 점유 중
  ```bash
  netstat -ano | findstr :8000    # PID 확인
  taskkill /PID 번호 /F           # 종료
  ```
- **Whisper 없이 테스트**: Whisper 미설치 시 자동으로 더미 모드로 전환됨. `/api/ner` 엔드포인트로 텍스트 직접 테스트 가능
- **GPU**: Whisper는 GPU 있으면 빠르지만 CPU에서도 동작 (base 모델 기준 5~10초)
- **모델 파일 크기**: model.safetensors가 약 50MB. Git LFS 또는 Google Drive 사용 권장

---

## Flutter 앱에서 서버 호출 (참고)

```dart
// lib/services/voice_api_service.dart
final request = http.MultipartRequest('POST', Uri.parse('http://localhost:8000/api/stt'));
request.files.add(http.MultipartFile.fromBytes('audio_file', audioBytes, filename: fileName));
final response = await request.send();
final json = jsonDecode(await response.stream.bytesToString());
```

서버 주소 변경: `voice_api_service.dart`의 `_baseUrl` 수정

---

## 배포 옵션

| 방법 | 난이도 | 비용 | 설명 |
|------|--------|------|------|
| 로컬 PC | 쉬움 | 무료 | 개발/테스트 시 PC에서 직접 실행 |
| 학교 서버 | 보통 | 무료 | 학교 제공 서버가 있다면 |
| Railway | 쉬움 | 무료~월$5 | Git push만 하면 자동 배포 |
| Google Cloud Run | 보통 | 무료 티어 | Docker 필요 |
