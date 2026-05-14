/// 식재료 영양정보 참조 테이블 (100g 기준).
///
/// 한국 식약처 식품영양성분 DB의 일반 통용 수치를 참고하여 정리한 값.
/// 챗봇이 레시피 추천 시 영양가를 추정할 때 이 테이블을 컨텍스트로 제공함으로써,
/// 자유 추정(hallucination)을 줄이고 검증된 데이터 기반의 grounding을 시도한다.
///
/// 사용처: chatbot_page.dart의 시스템 프롬프트 생성 시 {NUTRITION_DB} placeholder에 주입.
///
/// 향후 작업:
/// - 식약처 OpenAPI 직접 연동으로 4만+ 항목 커버
/// - 항목별 출처/검증일 메타데이터 추가
class NutritionInfo {
  final int kcal;          // 칼로리 (kcal)
  final double protein;    // 단백질 (g)
  final double carbs;      // 탄수화물 (g)
  final double fat;        // 지방 (g)

  const NutritionInfo({
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
  });
}

/// 식재료 영양정보 (100g 기준).
const Map<String, NutritionInfo> nutritionDb = {
  // ─── 곡물/면류/빵 (10) ──────────────────────────
  '백미밥':       NutritionInfo(kcal: 130, protein: 2.7,  carbs: 28.1, fat: 0.3),
  '현미밥':       NutritionInfo(kcal: 112, protein: 2.6,  carbs: 23.5, fat: 0.9),
  '잡곡밥':       NutritionInfo(kcal: 145, protein: 3.5,  carbs: 30.0, fat: 1.0),
  '식빵':         NutritionInfo(kcal: 265, protein: 9.0,  carbs: 49.0, fat: 3.2),
  '소면':         NutritionInfo(kcal: 365, protein: 12.0, carbs: 75.0, fat: 1.5),
  '라면사리':     NutritionInfo(kcal: 440, protein: 9.0,  carbs: 65.0, fat: 17.0),
  '당면':         NutritionInfo(kcal: 350, protein: 0.5,  carbs: 86.0, fat: 0.1),
  '떡':           NutritionInfo(kcal: 220, protein: 4.0,  carbs: 50.0, fat: 0.5),
  '밀가루':       NutritionInfo(kcal: 364, protein: 10.3, carbs: 76.3, fat: 1.0),
  '오트밀':       NutritionInfo(kcal: 389, protein: 16.9, carbs: 66.3, fat: 6.9),

  // ─── 육류 (12) ──────────────────────────────────
  '닭가슴살':     NutritionInfo(kcal: 165, protein: 31.0, carbs: 0.0,  fat: 3.6),
  '닭다리살':     NutritionInfo(kcal: 187, protein: 24.0, carbs: 0.0,  fat: 9.3),
  '돼지고기 삼겹살': NutritionInfo(kcal: 331, protein: 17.0, carbs: 0.0,  fat: 28.4),
  '돼지고기 목살':   NutritionInfo(kcal: 240, protein: 19.0, carbs: 0.0,  fat: 18.0),
  '돼지고기 안심':   NutritionInfo(kcal: 143, protein: 22.0, carbs: 0.0,  fat: 5.5),
  '소고기 등심':     NutritionInfo(kcal: 273, protein: 20.0, carbs: 0.0,  fat: 21.0),
  '소고기 안심':     NutritionInfo(kcal: 158, protein: 22.0, carbs: 0.0,  fat: 7.0),
  '소고기 양지':     NutritionInfo(kcal: 250, protein: 18.0, carbs: 0.0,  fat: 19.0),
  '햄':           NutritionInfo(kcal: 145, protein: 17.0, carbs: 1.5,  fat: 8.0),
  '소시지':       NutritionInfo(kcal: 280, protein: 12.0, carbs: 3.0,  fat: 25.0),
  '베이컨':       NutritionInfo(kcal: 417, protein: 13.0, carbs: 1.4,  fat: 41.0),
  '스팸':         NutritionInfo(kcal: 315, protein: 13.0, carbs: 1.0,  fat: 28.0),

  // ─── 어패류 (10) ───────────────────────────────
  '고등어':       NutritionInfo(kcal: 205, protein: 19.0, carbs: 0.0,  fat: 14.0),
  '연어':         NutritionInfo(kcal: 208, protein: 20.0, carbs: 0.0,  fat: 13.0),
  '참치 통조림':  NutritionInfo(kcal: 132, protein: 28.0, carbs: 0.0,  fat: 1.0),
  '오징어':       NutritionInfo(kcal: 92,  protein: 18.0, carbs: 3.1,  fat: 1.4),
  '새우':         NutritionInfo(kcal: 99,  protein: 24.0, carbs: 0.2,  fat: 0.3),
  '게맛살':       NutritionInfo(kcal: 95,  protein: 8.0,  carbs: 14.0, fat: 0.5),
  '명태':         NutritionInfo(kcal: 81,  protein: 17.5, carbs: 0.0,  fat: 0.7),
  '갈치':         NutritionInfo(kcal: 144, protein: 18.5, carbs: 0.0,  fat: 7.5),
  '어묵':         NutritionInfo(kcal: 113, protein: 11.0, carbs: 14.0, fat: 1.5),
  '멸치':         NutritionInfo(kcal: 158, protein: 25.0, carbs: 1.5,  fat: 4.8),

  // ─── 채소 (25) ──────────────────────────────────
  '양배추':       NutritionInfo(kcal: 25,  protein: 1.3,  carbs: 5.8,  fat: 0.1),
  '양파':         NutritionInfo(kcal: 40,  protein: 1.1,  carbs: 9.3,  fat: 0.1),
  '대파':         NutritionInfo(kcal: 32,  protein: 1.8,  carbs: 7.0,  fat: 0.2),
  '쪽파':         NutritionInfo(kcal: 27,  protein: 1.8,  carbs: 5.0,  fat: 0.2),
  '마늘':         NutritionInfo(kcal: 149, protein: 6.4,  carbs: 33.0, fat: 0.5),
  '당근':         NutritionInfo(kcal: 41,  protein: 0.9,  carbs: 9.6,  fat: 0.2),
  '감자':         NutritionInfo(kcal: 77,  protein: 2.0,  carbs: 17.5, fat: 0.1),
  '고구마':       NutritionInfo(kcal: 86,  protein: 1.6,  carbs: 20.1, fat: 0.1),
  '시금치':       NutritionInfo(kcal: 23,  protein: 2.9,  carbs: 3.6,  fat: 0.4),
  '청경채':       NutritionInfo(kcal: 13,  protein: 1.5,  carbs: 2.2,  fat: 0.2),
  '브로콜리':     NutritionInfo(kcal: 34,  protein: 2.8,  carbs: 6.6,  fat: 0.4),
  '피망':         NutritionInfo(kcal: 22,  protein: 0.9,  carbs: 4.6,  fat: 0.2),
  '파프리카':     NutritionInfo(kcal: 31,  protein: 1.0,  carbs: 6.0,  fat: 0.3),
  '오이':         NutritionInfo(kcal: 15,  protein: 0.7,  carbs: 3.6,  fat: 0.1),
  '가지':         NutritionInfo(kcal: 25,  protein: 1.0,  carbs: 5.9,  fat: 0.2),
  '호박':         NutritionInfo(kcal: 26,  protein: 1.0,  carbs: 6.5,  fat: 0.1),
  '애호박':       NutritionInfo(kcal: 17,  protein: 1.2,  carbs: 3.1,  fat: 0.3),
  '무':           NutritionInfo(kcal: 18,  protein: 0.6,  carbs: 4.1,  fat: 0.1),
  '배추':         NutritionInfo(kcal: 13,  protein: 1.5,  carbs: 2.2,  fat: 0.2),
  '상추':         NutritionInfo(kcal: 15,  protein: 1.4,  carbs: 2.9,  fat: 0.2),
  '버섯 새송이':  NutritionInfo(kcal: 35,  protein: 2.5,  carbs: 7.0,  fat: 0.3),
  '버섯 표고':    NutritionInfo(kcal: 34,  protein: 2.2,  carbs: 6.8,  fat: 0.5),
  '버섯 팽이':    NutritionInfo(kcal: 37,  protein: 2.7,  carbs: 7.8,  fat: 0.3),
  '깻잎':         NutritionInfo(kcal: 41,  protein: 3.9,  carbs: 7.3,  fat: 0.4),
  '콩나물':       NutritionInfo(kcal: 31,  protein: 4.0,  carbs: 3.0,  fat: 1.4),

  // ─── 과일 (10) ──────────────────────────────────
  '사과':         NutritionInfo(kcal: 52,  protein: 0.3,  carbs: 13.8, fat: 0.2),
  '바나나':       NutritionInfo(kcal: 89,  protein: 1.1,  carbs: 22.8, fat: 0.3),
  '딸기':         NutritionInfo(kcal: 32,  protein: 0.7,  carbs: 7.7,  fat: 0.3),
  '오렌지':       NutritionInfo(kcal: 47,  protein: 0.9,  carbs: 11.8, fat: 0.1),
  '귤':           NutritionInfo(kcal: 39,  protein: 0.7,  carbs: 10.0, fat: 0.2),
  '포도':         NutritionInfo(kcal: 67,  protein: 0.6,  carbs: 17.0, fat: 0.4),
  '토마토':       NutritionInfo(kcal: 18,  protein: 0.9,  carbs: 3.9,  fat: 0.2),
  '방울토마토':   NutritionInfo(kcal: 20,  protein: 1.0,  carbs: 4.0,  fat: 0.2),
  '키위':         NutritionInfo(kcal: 61,  protein: 1.1,  carbs: 14.7, fat: 0.5),
  '레몬':         NutritionInfo(kcal: 29,  protein: 1.1,  carbs: 9.3,  fat: 0.3),

  // ─── 유제품/달걀 (8) ──────────────────────────
  '우유':         NutritionInfo(kcal: 60,  protein: 3.2,  carbs: 4.8,  fat: 3.2),
  '치즈 슬라이스': NutritionInfo(kcal: 280, protein: 18.0, carbs: 3.0,  fat: 22.0),
  '체다치즈':     NutritionInfo(kcal: 402, protein: 25.0, carbs: 1.3,  fat: 33.0),
  '요거트 플레인': NutritionInfo(kcal: 61,  protein: 3.5,  carbs: 4.7,  fat: 3.3),
  '버터':         NutritionInfo(kcal: 717, protein: 0.9,  carbs: 0.1,  fat: 81.0),
  '계란':         NutritionInfo(kcal: 155, protein: 13.0, carbs: 1.1,  fat: 11.0),
  '메추리알':     NutritionInfo(kcal: 158, protein: 13.0, carbs: 0.4,  fat: 11.1),
  '두유':         NutritionInfo(kcal: 54,  protein: 3.3,  carbs: 6.3,  fat: 1.8),

  // ─── 콩/두부/견과 (8) ─────────────────────────
  '두부':         NutritionInfo(kcal: 76,  protein: 8.0,  carbs: 1.9,  fat: 4.8),
  '순두부':       NutritionInfo(kcal: 47,  protein: 5.0,  carbs: 1.5,  fat: 2.5),
  '유부':         NutritionInfo(kcal: 388, protein: 18.6, carbs: 6.0,  fat: 31.0),
  '검은콩':       NutritionInfo(kcal: 341, protein: 35.0, carbs: 32.0, fat: 16.0),
  '땅콩':         NutritionInfo(kcal: 567, protein: 26.0, carbs: 16.0, fat: 49.0),
  '호두':         NutritionInfo(kcal: 654, protein: 15.0, carbs: 14.0, fat: 65.0),
  '아몬드':       NutritionInfo(kcal: 579, protein: 21.0, carbs: 22.0, fat: 50.0),
  '잣':           NutritionInfo(kcal: 673, protein: 14.0, carbs: 13.0, fat: 68.0),

  // ─── 양념/조미 (10) ───────────────────────────
  '간장':         NutritionInfo(kcal: 60,  protein: 8.0,  carbs: 6.0,  fat: 0.1),
  '된장':         NutritionInfo(kcal: 198, protein: 12.0, carbs: 25.0, fat: 6.0),
  '고추장':       NutritionInfo(kcal: 230, protein: 5.5,  carbs: 50.0, fat: 1.5),
  '쌈장':         NutritionInfo(kcal: 200, protein: 8.0,  carbs: 28.0, fat: 6.0),
  '식용유':       NutritionInfo(kcal: 884, protein: 0.0,  carbs: 0.0,  fat: 100.0),
  '참기름':       NutritionInfo(kcal: 884, protein: 0.0,  carbs: 0.0,  fat: 100.0),
  '들기름':       NutritionInfo(kcal: 884, protein: 0.0,  carbs: 0.0,  fat: 100.0),
  '설탕':         NutritionInfo(kcal: 387, protein: 0.0,  carbs: 99.8, fat: 0.0),
  '소금':         NutritionInfo(kcal: 0,   protein: 0.0,  carbs: 0.0,  fat: 0.0),
  '식초':         NutritionInfo(kcal: 18,  protein: 0.0,  carbs: 0.9,  fat: 0.0),

  // ─── 김치/가공식품/기타 (7) ────────────────────
  '김치 배추김치': NutritionInfo(kcal: 32,  protein: 1.7,  carbs: 6.0,  fat: 0.5),
  '깍두기':       NutritionInfo(kcal: 33,  protein: 1.5,  carbs: 6.5,  fat: 0.3),
  '단무지':       NutritionInfo(kcal: 18,  protein: 0.6,  carbs: 4.0,  fat: 0.1),
  '김':           NutritionInfo(kcal: 35,  protein: 5.8,  carbs: 5.0,  fat: 0.3),
  '미역':         NutritionInfo(kcal: 45,  protein: 6.5,  carbs: 9.0,  fat: 0.6),
  '다시마':       NutritionInfo(kcal: 43,  protein: 1.7,  carbs: 9.6,  fat: 0.6),
  '꿀':           NutritionInfo(kcal: 304, protein: 0.3,  carbs: 82.4, fat: 0.0),
};

/// 영양 DB를 LLM 프롬프트용 텍스트로 변환.
/// 형식: "백미밥(100g): 130kcal, 단백질 2.7g, 탄수화물 28.1g, 지방 0.3g"
String buildNutritionDbContext() {
  final buffer = StringBuffer();
  buffer.writeln('[식재료 영양정보 참조표 (100g 기준)]');
  nutritionDb.forEach((name, info) {
    buffer.writeln(
      '- $name: ${info.kcal}kcal, '
      '단백질 ${info.protein}g, '
      '탄수화물 ${info.carbs}g, '
      '지방 ${info.fat}g',
    );
  });
  return buffer.toString();
}
