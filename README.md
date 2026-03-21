# FAM - Fridge AI Manager

냉장고 식료품 관리 앱 — Flutter + Firebase 기반 졸업설계 프로젝트

## 프로젝트 개요

냉장고 속 식재료를 관리하고, AI 기반 맞춤 레시피를 추천받을 수 있는 모바일 앱입니다.

### 핵심 기능

- **식료품 등록/관리** — 직접 입력, 영수증 OCR(Gemini API), 음성 입력(Whisper STT + KoELECTRA NER)
- **유통기한 관리** — 캘린더 뷰, 유통기한 자동 인식(서버 연동), 만료 임박 알림
- **AI 레시피 추천 챗봇** — 냉장고 재고 기반 맞춤 추천, 카드형 UI, 재고 차감 연동
- **냉장고 상태 분석** — 유통기한 분류(지남/임박/여유), AI 분석 코멘트, 폐기 처리

## 기술 스택

| 구분 | 기술 |
|------|------|
| Frontend | Flutter (Dart) |
| Backend | Firebase Auth, Cloud Firestore |
| AI/ML | Gemini API (OCR, 챗봇), Whisper (STT), KoELECTRA (NER) |
| NER 서버 | Python, FastAPI, uvicorn |

## 프로젝트 구조

```
flutter_application_test_1/
├── lib/
│   ├── main.dart                  # 앱 진입점
│   ├── firebase_options.dart      # Firebase 설정
│   ├── screens/
│   │   ├── splash_page.dart       # 스플래시 화면
│   │   ├── login_page.dart        # 로그인
│   │   ├── sign_up_page.dart      # 회원가입
│   │   ├── login_success_page.dart
│   │   ├── calendar_page.dart     # 유통기한 캘린더
│   │   ├── inventory_list_page.dart        # 재고 목록
│   │   ├── inventory_add_selection_page.dart # 등록 방법 선택
│   │   ├── inventory_add_input_page.dart   # 직접 입력 등록
│   │   ├── inventory_add_ocr_page.dart     # 영수증 OCR 등록
│   │   ├── inventory_add_voice_page.dart   # 음성 등록
│   │   └── chatbot_page.dart      # AI 레시피 챗봇
│   ├── services/
│   │   └── voice_api_service.dart # NER 서버 통신
│   └── widgets/
│       └── main_bottom_nav.dart   # 공통 하단 네비게이션
├── assets/
│   └── chatbot_prompt.txt         # 챗봇 시스템 프롬프트
├── server/                        # NER 서버 (Python)
│   ├── main.py
│   ├── stt_model.py
│   ├── ner_model.py
│   ├── requirements.txt
│   └── models/                    # NER 모델 파일 (Git 미포함)
├── .env                           # API 키 (Git 미포함)
├── .env.example                   # API 키 형식 안내
└── pubspec.yaml
```

## 초기 설정 가이드

### 1. 프로젝트 클론

```bash
git clone https://github.com/ghostlink77/FAM-fridge_AI_manager.git
cd FAM-fridge_AI_manager
```

### 2. .env 파일 설정 (필수)

프로젝트 루트에 `.env` 파일을 생성하고 API 키를 입력합니다.  
`.env.example` 파일을 참고하세요.

```bash
cp .env.example .env
```

`.env` 파일 내용:
```
GEMINI_API_KEY=본인의_Gemini_API_키
EXPIRY_SERVER_URL=유통기한_인식_서버_주소
```

- **Gemini API 키**: [Google AI Studio](https://aistudio.google.com/app/apikey)에서 무료 발급
- **유통기한 서버 URL**: 유통기한 이미지 인식 서버 주소 (서버 담당자에게 확인)

> ⚠️ `.env` 파일은 `.gitignore`에 포함되어 있으므로 Git에 올라가지 않습니다. 절대로 API 키를 코드에 직접 넣지 마세요.

### 3. Flutter 패키지 설치

```bash
flutter pub get
```

### 4. 앱 실행

```bash
# Chrome 웹으로 실행
flutter run -d chrome

# Android 에뮬레이터로 실행
flutter run
```

## NER 서버 설정 (음성 등록 기능 사용 시)

음성 등록 기능을 사용하려면 별도의 Python NER 서버가 필요합니다.

### 사전 요구사항

- Python 3.10+
- ffmpeg (시스템 설치 필요)

### 서버 실행

```bash
cd server

# 가상환경 생성 및 활성화
python -m venv venv
venv\Scripts\activate        # Windows

# 패키지 설치
pip install -r requirements.txt

# ffmpeg 설치 (Windows)
winget install ffmpeg

# 서버 실행
$env:PYTHONIOENCODING="utf-8"   # Windows PowerShell
python -m uvicorn main:app --host 0.0.0.0 --port 8000
```

### NER 모델 파일

`server/models/` 폴더에 아래 파일이 필요합니다 (용량 문제로 Git 미포함):

- `model.safetensors` (~54MB)
- `tokenizer.json`
- `tokenizer_config.json`
- `config.json`

> 모델 파일은 팀원에게 직접 전달받으세요.

## Firestore 데이터 구조

```
users/{userId}/
├── inventory/{docId}           # 현재 재고
│   ├── name: String
│   ├── quantity: num
│   ├── unit: String
│   ├── expiryDate: String (YYYY-MM-DD)
│   ├── registrationDate: String (YYYY-MM-DD)
│   └── createdAt: Timestamp
└── chat_messages/{docId}       # 챗봇 대화 기록
    ├── role: String (user/assistant)
    ├── text: String
    └── createdAt: Timestamp
```
