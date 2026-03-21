const {onCall} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const fetch = require("node-fetch");

// ⚠️ 보안 주의: API 키를 코드에 직접 넣지 마세요. 깃허브에 올리면 노출됩니다!
// 실제 프로덕션에서는 Secret Manager 사용 권장
const OPENAI_API_KEY = "YOUR_OPENAI_API_KEY";

exports.parseReceipt = onCall(async (request) => {
  const text = request.data.text;

  if (!text || text.trim() === "") {
    throw new Error("text is required");
  }

  logger.info("Parsing receipt text", {length: text.length});

  const prompt = `다음 영수증 텍스트에서 품목명과 수량을 JSON 배열로 추출해줘.
형식: [{"name":"사과","quantity":2}]
규칙:
- 품목명과 수량만 추출
- 가격, 총액, 쿠폰, 날짜, 매장명은 무시
- 수량이 명시되지 않으면 1로 설정
- JSON 배열만 반환 (다른 설명 없이)

텍스트:
${text}`;

  try {
    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${OPENAI_API_KEY}`,
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: [{role: "user", content: prompt}],
        temperature: 0,
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      logger.error("OpenAI API error", {status: response.status, error: errorText});
      throw new Error(`OpenAI API error: ${response.status}`);
    }

    const data = await response.json();
    const content = data.choices && data.choices[0] && data.choices[0].message && data.choices[0].message.content || "[]";

    logger.info("OpenAI response", {content});

    let items = [];
    try {
      items = JSON.parse(content);
    } catch (parseError) {
      logger.error("Failed to parse GPT response", {content, error: parseError.message});
      // GPT가 배열 외에 다른 텍스트도 반환했을 수 있음
      // 배열 부분만 추출 시도
      const jsonMatch = content.match(/\[[\s\S]*\]/);
      if (jsonMatch) {
        items = JSON.parse(jsonMatch[0]);
      } else {
        items = [];
      }
    }

    logger.info("Parsed items", {count: items.length});

    return {items};
  } catch (error) {
    logger.error("Error parsing receipt", {error: error.message});
    throw new Error(`Failed to parse receipt: ${error.message}`);
  }
});
