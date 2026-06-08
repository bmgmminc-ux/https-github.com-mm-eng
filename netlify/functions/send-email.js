// ㈜명문이엔지 v3 — Resend 이메일 발송 서버 프록시 (Netlify Function)
// 보안: RESEND_API_KEY 는 Netlify 환경변수에만 존재. 브라우저로 절대 전송되지 않음.
// 브라우저(mmSendEmail) → 이 함수 → Resend 순으로 호출 (CORS 우회 + 키 비노출)
exports.handler = async (event) => {
  const headers = { 'Content-Type': 'application/json' };

  if (event.httpMethod === 'OPTIONS') return { statusCode: 204, headers, body: '' };
  if (event.httpMethod !== 'POST') {
    return { statusCode: 405, headers, body: JSON.stringify({ error: 'Method not allowed' }) };
  }

  const key = process.env.RESEND_API_KEY;
  if (!key) {
    return { statusCode: 500, headers, body: JSON.stringify({ error: 'RESEND_API_KEY 미설정 (Netlify 환경변수에 등록 필요)' }) };
  }

  let body;
  try { body = JSON.parse(event.body || '{}'); }
  catch (e) { return { statusCode: 400, headers, body: JSON.stringify({ error: 'Invalid JSON' }) }; }

  const to = body.to;
  const subject = body.subject;
  const html = body.html || '';
  if (!to || !subject) {
    return { statusCode: 400, headers, body: JSON.stringify({ error: 'to/subject 필수' }) };
  }

  // 도메인 인증 전: onboarding@resend.dev (계정 소유 메일로만 발송 가능)
  // 도메인 인증 후: Netlify 환경변수 RESEND_FROM 에 'noreply@회사도메인' 설정
  const from = process.env.RESEND_FROM || 'onboarding@resend.dev';

  try {
    const r = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { 'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from, to: Array.isArray(to) ? to : [to], subject, html })
    });
    const data = await r.json().catch(() => ({}));
    return { statusCode: r.status, headers, body: JSON.stringify(data) };
  } catch (e) {
    return { statusCode: 502, headers, body: JSON.stringify({ error: 'Resend 호출 실패: ' + e.message }) };
  }
};
