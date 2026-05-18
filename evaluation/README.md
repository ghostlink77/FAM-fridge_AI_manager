# FAM 소비기한 추정 평가

졸업 프로젝트 FAM의 영수증 OCR 소비기한 추정 기능에 대해
세 가지 프롬프트 엔지니어링 조건(baseline, CoT, Few-shot CoT)을
정량적으로 비교 평가하는 스크립트.

## 실행 절차

```bash
# 1. 의존성 설치
cd evaluation/
pip install -r requirements.txt

# 2. API 키 설정
# Windows (PowerShell)
$env:GEMINI_API_KEY="your_key_here"
# Windows (CMD)
set GEMINI_API_KEY=your_key_here
# macOS / Linux
export GEMINI_API_KEY=your_key_here

# 3. 평가 실행 (대략 10~15분 소요, 40 × 3조건 × 3회 = 360회 API 호출)
python run_evaluation.py

# 4. 결과 분석 + 그래프 생성
python analyze_results.py
```

## 산출물

| 파일 | 내용 |
|---|---|
| `results.csv` | 모든 호출의 원본 결과 (sample_id × condition × run_id) |
| `summary_by_condition.csv` | 조건별 정확도/오차/일관성 표 |
| `summary_by_category.csv` | 카테고리 × 조건별 정확도 매트릭스 |
| `accuracy_chart.png` | 조건별 in-range accuracy 막대그래프 (발표용) |
| `consistency_chart.png` | 조건별 일관성(std) 막대그래프 (발표용) |
| `error_distribution.png` | 조건별 절대오차 boxplot (발표용) |

## 평가 설계

- **표본**: 40개 식품 (5카테고리: 과일/채소/유제품/육류/가공식품)
- **표기 변형 포함**: "삼겹살 200g" vs "삼겹살 한근" vs "삼겹살 600g" 등
- **Ground Truth**: [min, max] 일수 범위 (단일값 아님). 범위 안이면 "in_range = 1"
- **반복 호출**: 각 표본 × 조건당 3회 호출 (일관성 측정, std 계산용)
- **temperature**: 0.7 (deterministic 아닌 일반적 사용 환경 시뮬레이션)

## 주의사항

- API 호출 비용 발생 (Gemini Flash, 360회 약 < $0.10 추정)
- samples.json의 ground truth는 추정값. 식약처/농촌진흥청 자료로 검토 권장.
- 결과는 매 실행마다 미세하게 다를 수 있음 (temperature > 0)

## 참고 논문 (발표 자료용)

- Wei et al. (2022). Chain-of-Thought Prompting. NeurIPS. arXiv:2201.11903.
- Brown et al. (2020). Language Models are Few-Shot Learners. NeurIPS. arXiv:2005.14165.
- Wang et al. (2023). Self-Consistency Improves CoT. ICLR. arXiv:2203.11171.
  (평가 단계에서 std 측정에만 사용. Production에는 latency 이유로 미적용.)
