"""
FAM 소비기한 추정 — 프롬프트 엔지니어링 기법 정량 평가 스크립트.

세 가지 프롬프트 조건(baseline / cot / few_shot_cot)에 대해
40개 식품 표본의 소비기한 추정값을 받아 CSV로 저장한다.

일관성 측정을 위해 같은 조건에서 N_RUNS_PER_SAMPLE 회 반복 호출한다.
(Self-Consistency를 production에는 적용하지 않지만, 평가 단계에서
 표준편차를 측정해 발표 자료에 보고하기 위함)

사용법:
    cd evaluation/
    pip install -r requirements.txt
    export GEMINI_API_KEY=your_key   # Windows: set GEMINI_API_KEY=...
    python run_evaluation.py

출력:
    results.csv (각 표본 × 조건 × 반복의 결과)
"""

import os
import json
import csv
import time
import re
from pathlib import Path
from datetime import date

import google.generativeai as genai


# ─── 설정 ──────────────────────────────────────────────
N_RUNS_PER_SAMPLE = 3     # 일관성 측정용 반복 횟수 (Self-Consistency 아님, std 측정만)
MODEL_NAME = "gemini-2.5-flash"
TEMPERATURE = 0.7         # 일관성 차이를 보려면 temperature 0이 아닌 게 낫다
DELAY_BETWEEN_CALLS = 0.5 # API 레이트리밋 회피 (초)
TODAY_STR = date.today().isoformat()

PROMPT_CONDITIONS = ["baseline", "cot", "few_shot_cot"]
SCRIPT_DIR = Path(__file__).parent
SAMPLES_PATH = SCRIPT_DIR / "samples.json"
PROMPTS_DIR = SCRIPT_DIR / "prompts"
OUTPUT_PATH = SCRIPT_DIR / "results.csv"


# ─── API 키 ────────────────────────────────────────────
api_key = os.getenv("GEMINI_API_KEY")
if not api_key:
    raise SystemExit("GEMINI_API_KEY 환경변수가 설정되지 않았습니다.")
genai.configure(api_key=api_key)


# ─── 프롬프트 로드 ──────────────────────────────────────
def load_prompt(condition: str) -> str:
    """프롬프트 템플릿 파일을 읽어 문자열로 반환."""
    path = PROMPTS_DIR / f"{condition}.txt"
    return path.read_text(encoding="utf-8")


def fill_prompt(template: str, food_name: str) -> str:
    """플레이스홀더 치환. {FOOD_NAME}, {TODAY}를 실제 값으로 교체."""
    return template.replace("{FOOD_NAME}", food_name).replace("{TODAY}", TODAY_STR)


# ─── 응답 파싱 ──────────────────────────────────────────
def parse_response(text: str) -> int:
    """
    응답 문자열에서 estimated_days 값을 추출.
    실패 시 -1 반환 (분석 단계에서 outlier로 처리).

    Gemini가 ```json ... ``` 마크다운 펜스로 감쌀 수 있으므로 정규식으로 JSON 블록 추출.
    """
    # 마크다운 코드 펜스 제거
    cleaned = re.sub(r"```(?:json)?\s*|\s*```", "", text).strip()
    try:
        data = json.loads(cleaned)
        days = data.get("estimated_days", -1)
        if isinstance(days, (int, float)):
            return int(days)
        return -1
    except (json.JSONDecodeError, AttributeError):
        # JSON 파싱 실패 — 본문에서 숫자만 추출 시도
        match = re.search(r"estimated_days[\"\s:]+(-?\d+)", text)
        if match:
            return int(match.group(1))
        return -1


# ─── 단일 호출 ──────────────────────────────────────────
def estimate_once(model, prompt_template: str, food_name: str) -> tuple[int, str]:
    """한 번의 API 호출. (estimated_days, raw_response_text) 반환."""
    prompt = fill_prompt(prompt_template, food_name)
    try:
        response = model.generate_content(
            prompt,
            generation_config={
                "temperature": TEMPERATURE,
                # Gemini 2.5 Flash는 thinking 토큰을 max_output_tokens에서 차감함.
                # 응답이 잘리는 현상 방지를 위해 충분히 크게 설정.
                "max_output_tokens": 4096,
            },
        )
        # response.text가 None일 수 있음 (안전 필터 등에 의해)
        text = response.text if hasattr(response, "text") and response.text else ""
        # 추가 디버깅: candidate finish_reason도 같이 기록
        if not text and hasattr(response, "candidates") and response.candidates:
            cand = response.candidates[0]
            finish_reason = getattr(cand, "finish_reason", "UNKNOWN")
            text = f"EMPTY_RESPONSE(finish_reason={finish_reason})"
        return parse_response(text), text
    except Exception as e:
        # API 오류 — -1로 마킹하고 계속 진행
        return -1, f"ERROR: {type(e).__name__}: {e}"


# ─── 메인 루프 ──────────────────────────────────────────
def main():
    samples = json.loads(SAMPLES_PATH.read_text(encoding="utf-8"))["samples"]
    prompts = {cond: load_prompt(cond) for cond in PROMPT_CONDITIONS}

    model = genai.GenerativeModel(MODEL_NAME)

    total_calls = len(samples) * len(PROMPT_CONDITIONS) * N_RUNS_PER_SAMPLE
    print(f"총 {total_calls}회 호출 시작 "
          f"(샘플 {len(samples)} × 조건 {len(PROMPT_CONDITIONS)} × 반복 {N_RUNS_PER_SAMPLE})")

    with OUTPUT_PATH.open("w", newline="", encoding="utf-8-sig") as f:
        # utf-8-sig: 엑셀에서 한글 깨짐 방지 (BOM 포함)
        writer = csv.writer(f)
        writer.writerow([
            "sample_id", "food_name", "category",
            "gt_min", "gt_max",
            "condition", "run_id",
            "predicted_days",
            "in_range", "abs_error",
            "raw_response_excerpt",
        ])

        call_count = 0
        for sample in samples:
            sid = sample["id"]
            name = sample["name"]
            cat = sample["category"]
            gt_min = sample["gt_min"]
            gt_max = sample["gt_max"]

            for cond in PROMPT_CONDITIONS:
                for run in range(N_RUNS_PER_SAMPLE):
                    call_count += 1
                    days, raw = estimate_once(model, prompts[cond], name)

                    # in_range: GT [min, max] 범위 안이면 1, 아니면 0
                    # ±20% 여유를 줄지 여부는 분석 스크립트에서 결정 (여기선 정확한 in_range만)
                    in_range = 1 if (days >= 0 and gt_min <= days <= gt_max) else 0
                    # abs_error: 범위 밖이면 가장 가까운 경계까지 거리
                    if days < 0:
                        abs_err = -1
                    elif days < gt_min:
                        abs_err = gt_min - days
                    elif days > gt_max:
                        abs_err = days - gt_max
                    else:
                        abs_err = 0

                    # 로그 (raw는 너무 길면 잘라서 저장)
                    raw_excerpt = raw.replace("\n", " ")[:200]
                    writer.writerow([
                        sid, name, cat,
                        gt_min, gt_max,
                        cond, run,
                        days,
                        in_range, abs_err,
                        raw_excerpt,
                    ])
                    f.flush()  # 중간에 끊겨도 데이터 보존

                    print(f"[{call_count}/{total_calls}] {sid:>4} | {cond:>14} | run={run} | "
                          f"pred={days:>4}d | gt=[{gt_min},{gt_max}] | in_range={in_range}")

                    time.sleep(DELAY_BETWEEN_CALLS)

    print(f"\n완료: {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
