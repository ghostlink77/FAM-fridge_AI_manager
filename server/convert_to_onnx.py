"""
SafeTensors → 자체 포함 ONNX 변환 스크립트

사용법:
    python convert_to_onnx.py

결과:
    models/food_ner_model_standalone.onnx  (단일 파일, 외부 데이터 불필요)

변환 후:
    ner_model.py에서 USE_ONNX = True 로 변경하면 ONNX 모드로 전환됨
"""

import os
import torch
from transformers import AutoModelForTokenClassification, AutoTokenizer

MODEL_DIR = os.path.join(os.path.dirname(__file__), "models")
OUTPUT_PATH = os.path.join(MODEL_DIR, "food_ner_model_standalone.onnx")

print("1. 모델 로드 중...")
model = AutoModelForTokenClassification.from_pretrained(MODEL_DIR)
tokenizer = AutoTokenizer.from_pretrained(MODEL_DIR)
model.eval()

print("2. 더미 입력 생성...")
dummy_text = "사과 세 개랑 우유 두 팩"
inputs = tokenizer(dummy_text, return_tensors="pt", max_length=128, truncation=True)

print("3. ONNX 변환 중...")
torch.onnx.export(
    model,
    (inputs["input_ids"], inputs["attention_mask"]),
    OUTPUT_PATH,
    input_names=["input_ids", "attention_mask"],
    output_names=["logits"],
    dynamic_axes={
        "input_ids": {0: "batch", 1: "sequence"},
        "attention_mask": {0: "batch", 1: "sequence"},
        "logits": {0: "batch", 1: "sequence"},
    },
    opset_version=14,
)

file_size = os.path.getsize(OUTPUT_PATH) / 1024 / 1024
print(f"\n변환 완료!")
print(f"  파일: {OUTPUT_PATH}")
print(f"  크기: {file_size:.1f} MB")
print(f"\n다음 단계: ner_model.py에서 USE_ONNX = True 로 변경하세요.")
