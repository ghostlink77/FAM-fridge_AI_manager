"""
results.csv를 읽어 발표용 표/그래프를 생성하는 분석 스크립트.

산출물:
  1) summary_by_condition.csv  — 조건별 종합 지표 표
  2) summary_by_category.csv   — 카테고리별 × 조건별 in-range accuracy
  3) accuracy_chart.png         — 조건별 in-range accuracy 막대그래프
  4) consistency_chart.png      — 조건별 std deviation (일관성)
  5) error_distribution.png     — 조건별 absolute error 분포 (boxplot)
  6) (콘솔 출력) Wilcoxon signed-rank test 결과

사용법:
    python analyze_results.py
"""

from pathlib import Path
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib
from scipy import stats

# 한글 폰트 (Windows 환경 가정 — 다른 OS면 적절히 변경)
matplotlib.rcParams["font.family"] = "Malgun Gothic"
matplotlib.rcParams["axes.unicode_minus"] = False

SCRIPT_DIR = Path(__file__).parent
INPUT = SCRIPT_DIR / "results.csv"
CONDITIONS = ["baseline", "cot", "few_shot_cot"]
COND_LABEL = {
    "baseline": "Baseline",
    "cot": "+ CoT",
    "few_shot_cot": "+ Few-shot CoT",
}


def main():
    df = pd.read_csv(INPUT)

    # -1은 API 오류 또는 파싱 실패 → 분석에서 제외
    df_valid = df[df["predicted_days"] >= 0].copy()
    n_failed = len(df) - len(df_valid)
    if n_failed > 0:
        print(f"⚠ API 오류/파싱 실패 {n_failed}건 제외하고 분석")

    # ─── 1. 조건별 종합 지표 ──────────────────────────────
    summary = (
        df_valid.groupby("condition")
        .agg(
            n=("predicted_days", "count"),
            in_range_rate=("in_range", "mean"),
            mean_abs_error=("abs_error", "mean"),
            median_abs_error=("abs_error", "median"),
        )
        .reindex(CONDITIONS)
    )
    summary["in_range_rate_pct"] = (summary["in_range_rate"] * 100).round(1)

    # 같은 식품 × 같은 조건의 N=3 호출의 std (일관성)
    consistency = (
        df_valid.groupby(["condition", "sample_id"])["predicted_days"]
        .std(ddof=1)
        .reset_index(name="std_per_sample")
    )
    consistency_mean = consistency.groupby("condition")["std_per_sample"].mean().reindex(CONDITIONS)
    summary["mean_std_across_runs"] = consistency_mean.round(2)

    print("\n=== 조건별 종합 지표 ===")
    print(summary.to_string())
    summary.to_csv(SCRIPT_DIR / "summary_by_condition.csv", encoding="utf-8-sig")

    # ─── 2. 카테고리 × 조건별 in-range accuracy ──────────
    # 어떤 조건에 데이터가 0건이면 unstack 결과에 컬럼이 없을 수 있음 → reindex로 안전 처리
    cat_summary = (
        df_valid.groupby(["category", "condition"])["in_range"]
        .mean()
        .unstack()
        .reindex(columns=CONDITIONS)
        * 100
    ).round(1)
    print("\n=== 카테고리 × 조건별 in-range accuracy (%) ===")
    print(cat_summary.to_string())
    cat_summary.to_csv(SCRIPT_DIR / "summary_by_category.csv", encoding="utf-8-sig")

    # ─── 3. 조건별 accuracy 막대그래프 ────────────────────
    fig, ax = plt.subplots(figsize=(7, 4.5))
    x_labels = [COND_LABEL[c] for c in CONDITIONS]
    rates = [summary.loc[c, "in_range_rate_pct"] for c in CONDITIONS]
    bars = ax.bar(x_labels, rates, color=["#9E9E9E", "#FFA726", "#43A047"])
    for bar, rate in zip(bars, rates):
        ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 1,
                f"{rate}%", ha="center", fontsize=11, fontweight="bold")
    ax.set_ylabel("In-range Accuracy (%)")
    ax.set_title("프롬프트 조건별 소비기한 추정 정확도")
    ax.set_ylim(0, 105)
    ax.grid(axis="y", alpha=0.3)
    plt.tight_layout()
    plt.savefig(SCRIPT_DIR / "accuracy_chart.png", dpi=150, bbox_inches="tight")
    print(f"\n✓ accuracy_chart.png 저장")

    # ─── 4. 조건별 std 막대그래프 (일관성) ─────────────────
    fig, ax = plt.subplots(figsize=(7, 4.5))
    stds = [summary.loc[c, "mean_std_across_runs"] for c in CONDITIONS]
    bars = ax.bar(x_labels, stds, color=["#9E9E9E", "#FFA726", "#43A047"])
    for bar, std in zip(bars, stds):
        ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 0.5,
                f"{std:.1f}d", ha="center", fontsize=11, fontweight="bold")
    ax.set_ylabel("Mean Std. Deviation (days)\n(낮을수록 일관성 높음)")
    ax.set_title("프롬프트 조건별 응답 일관성")
    ax.grid(axis="y", alpha=0.3)
    plt.tight_layout()
    plt.savefig(SCRIPT_DIR / "consistency_chart.png", dpi=150, bbox_inches="tight")
    print("✓ consistency_chart.png 저장")

    # ─── 5. Absolute error boxplot ────────────────────────
    fig, ax = plt.subplots(figsize=(7, 4.5))
    data = [df_valid[df_valid["condition"] == c]["abs_error"].values for c in CONDITIONS]
    bp = ax.boxplot(data, labels=x_labels, patch_artist=True)
    colors = ["#9E9E9E", "#FFA726", "#43A047"]
    for patch, color in zip(bp["boxes"], colors):
        patch.set_facecolor(color)
        patch.set_alpha(0.6)
    ax.set_ylabel("Absolute Error (days)")
    ax.set_title("프롬프트 조건별 절대 오차 분포")
    ax.grid(axis="y", alpha=0.3)
    plt.tight_layout()
    plt.savefig(SCRIPT_DIR / "error_distribution.png", dpi=150, bbox_inches="tight")
    print("✓ error_distribution.png 저장")

    # ─── 6. Wilcoxon signed-rank test ─────────────────────
    # 표본당 평균 abs_error로 paired 비교
    print("\n=== Wilcoxon signed-rank test (paired) ===")
    print("귀무가설: 두 조건의 abs_error 분포가 동일")
    pivot = (
        df_valid.groupby(["sample_id", "condition"])["abs_error"]
        .mean()
        .unstack()[CONDITIONS]
        .dropna()
    )
    pairs = [
        ("baseline", "cot"),
        ("baseline", "few_shot_cot"),
        ("cot", "few_shot_cot"),
    ]
    for a, b in pairs:
        # zero_method='wilcox': 동률 쌍 제외 (기본)
        try:
            stat, p = stats.wilcoxon(pivot[a], pivot[b])
            sig = "***" if p < 0.001 else "**" if p < 0.01 else "*" if p < 0.05 else "n.s."
            print(f"  {a:>14} vs {b:<14}  W={stat:>6.1f}  p={p:.4f}  {sig}")
        except ValueError as e:
            print(f"  {a:>14} vs {b:<14}  검정 실패: {e}")


if __name__ == "__main__":
    main()
