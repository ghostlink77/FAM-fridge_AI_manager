"""
NER 모델 래퍼 (텍스트에서 음식명·수량 추출)

현재: model.safetensors + tokenizer 파일로 동작
ONNX 변환 후: USE_ONNX = True 로 전환 가능
"""

import os
import re
import json
import numpy as np

# ──────────────────────────────────────────
# 설정
# ──────────────────────────────────────────
MODEL_DIR = os.path.join(os.path.dirname(__file__), "models")
USE_ONNX = False  # True = ONNX 모드 (convert_to_onnx.py 실행 후)

# 모델 출력 5개 클래스 (학습 시 라벨 순서에 맞게 수정)
ID2LABEL = {0: "O", 1: "B-FOOD", 2: "I-FOOD", 3: "B-QTY", 4: "I-QTY"}

# ──────────────────────────────────────────
# 모델 로드 (서버 시작 시 한 번만)
# ──────────────────────────────────────────
print("[NER] 모델 로딩 중...")

if USE_ONNX:
    import onnxruntime as ort
    from transformers import AutoTokenizer
    onnx_path = os.path.join(MODEL_DIR, "food_ner_model_standalone.onnx")
    session = ort.InferenceSession(onnx_path)
    tokenizer = AutoTokenizer.from_pretrained(MODEL_DIR)
    print(f"[NER] ONNX 모델 로드 완료")
else:
    from transformers import AutoTokenizer, AutoModelForTokenClassification
    import torch
    # config.json 없으면 KoELECTRA-small 기본 설정으로 자동 생성
    config_path = os.path.join(MODEL_DIR, "config.json")
    if not os.path.exists(config_path):
        print("[NER] config.json 없음 — 기본 설정 생성 중...")
        config = {
            "architectures": ["ElectraForTokenClassification"],
            "model_type": "electra",
            "num_labels": 5,
            "id2label": {str(k): v for k, v in ID2LABEL.items()},
            "label2id": {v: k for k, v in ID2LABEL.items()},
            "attention_probs_dropout_prob": 0.1,
            "embedding_size": 128, "hidden_act": "gelu",
            "hidden_dropout_prob": 0.1, "hidden_size": 256,
            "initializer_range": 0.02, "intermediate_size": 1024,
            "max_position_embeddings": 512, "num_attention_heads": 4,
            "num_hidden_layers": 12, "type_vocab_size": 2, "vocab_size": 35000,
        }
        with open(config_path, "w", encoding="utf-8") as f:
            json.dump(config, f, indent=2, ensure_ascii=False)
    model = AutoModelForTokenClassification.from_pretrained(MODEL_DIR)
    tokenizer = AutoTokenizer.from_pretrained(MODEL_DIR)
    model.eval()
    print("[NER] SafeTensors 모델 로드 완료")

# ──────────────────────────────────────────
# 유틸리티
# ──────────────────────────────────────────
CATEGORY_MAP = {
    "사과": "과일", "바나나": "과일", "딸기": "과일", "오렌지": "과일",
    "포도": "과일", "수박": "과일", "참외": "과일", "복숭아": "과일",
    "우유": "유제품", "치즈": "유제품", "요거트": "유제품", "버터": "유제품",
    "돼지고기": "육류", "소고기": "육류", "닭고기": "육류", "삼겹살": "육류",
    "양파": "채소", "당근": "채소", "감자": "채소", "배추": "채소",
    "시금치": "채소", "파": "채소", "마늘": "채소", "고추": "채소",
    "계란": "달걀/두부", "달걀": "달걀/두부", "두부": "달걀/두부",
    "라면": "가공식품", "햄": "가공식품", "소시지": "가공식품", "스팸": "가공식품",
    "새우": "해산물", "고등어": "해산물", "연어": "해산물", "오징어": "해산물",
    "쌀": "곡류", "밀가루": "곡류", "국수": "곡류",
}
KOREAN_NUMBERS = {
    "한": 1, "두": 2, "세": 3, "네": 4, "다섯": 5,
    "여섯": 6, "일곱": 7, "여덟": 8, "아홉": 9, "열": 10,
}

def get_category(name: str) -> str:
    for key, cat in CATEGORY_MAP.items():
        if key in name:
            return cat
    return "기타"

def parse_quantity(qty_text: str) -> tuple[float, str]:
    qty_text = qty_text.strip()
    for kr, num in KOREAN_NUMBERS.items():
        if kr in qty_text:
            unit = qty_text.replace(kr, "").strip()
            return float(num), unit if unit else "개"
    match = re.match(r"(\d+\.?\d*)\s*(.*)", qty_text)
    if match:
        return float(match.group(1)), match.group(2).strip() or "개"
    return 1.0, "개"

# ──────────────────────────────────────────
# 추론 + 엔티티 추출
# ──────────────────────────────────────────
def run_inference(text: str) -> list[dict]:
    encoding = tokenizer(
        text, return_tensors="np" if USE_ONNX else "pt",
        truncation=True, max_length=128, return_offsets_mapping=True,
    )
    offset_mapping = encoding.pop("offset_mapping")[0]

    if USE_ONNX:
        inputs = {
            "input_ids": encoding["input_ids"].astype(np.int64),
            "attention_mask": encoding["attention_mask"].astype(np.int64),
        }
        logits = session.run(None, inputs)[0]
        predictions = np.argmax(logits[0], axis=-1)
    else:
        import torch
        with torch.no_grad():
            outputs = model(**{k: v for k, v in encoding.items()})
            predictions = torch.argmax(outputs.logits[0], dim=-1).numpy()

    # BIO 태그 → 엔티티 리스트
    entities, current = [], None
    for pred_id, offsets in zip(predictions, offset_mapping):
        s, e = int(offsets[0]), int(offsets[1])
        if s == 0 and e == 0:
            if current: entities.append(current); current = None
            continue
        label = ID2LABEL.get(int(pred_id), "O")
        if label.startswith("B-"):
            if current: entities.append(current)
            current = {"label": label[2:], "start": s, "end": e, "text": text[s:e]}
        elif label.startswith("I-") and current and current["label"] == label[2:]:
            current["end"] = e
            current["text"] = text[current["start"]:e]
        else:
            if current: entities.append(current); current = None
    if current: entities.append(current)
    return entities


def extract_food_items(text: str) -> list[dict]:
    """main.py에서 호출되는 메인 함수"""
    entities = run_inference(text)
    foods = [e for e in entities if e["label"] == "FOOD"]
    qtys = [e for e in entities if e["label"] == "QTY"]
    items = []
    for food in foods:
        name = food["text"].strip()
        best_qty, best_dist = None, float("inf")
        for qty in qtys:
            d = abs(qty["start"] - food["end"])
            if d < best_dist: best_dist, best_qty = d, qty
        if best_qty and best_dist < 20:
            quantity, unit = parse_quantity(best_qty["text"])
            qtys.remove(best_qty)
        else:
            quantity, unit = 1.0, "개"
        items.append({"name": name, "quantity": quantity, "unit": unit, "category": get_category(name)})
    return items
