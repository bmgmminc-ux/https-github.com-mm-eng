// ㈜명문이엔지 v3 — 알리고 SMS 발송 서버 프록시 (Netlify Function)
// 보안: 알리고 키/계정/발신번호는 Netlify 환경변수에만 존재. 브라우저로 절대 전송되지 않음.
// 브라우저(mmSendSms) → 이 함수 → 알리고 순으로 호출 (CORS 우회 + 키 비노출)
exports.handler = async (event) => {
  const headers = { 'Content-Type': 'application/json' };

  if (event.httpMethod === 'OPTIONS') return { statusCode: 204, headers, body: '' };
  if (event.httpMethod !== 'POST') {
    return { statusCode: 405, headers, body: JSON.stringify({ error: 'Method not allowed' }) };
  }

  const key = process.env.ALIGO_API_KEY;
  const userId = process.env.ALIGO_USER_ID;
  const sender = process.env.ALIGO_SENDER;
  if (!key || !userId || !sender) {
    return { statusCode: 500, headers, body: JSON.stringify({ error: 'ALIGO_API_KEY / ALIGO_USER_ID / ALIGO_SENDER 환경변수 미설정' }) };
  }

  let body;
  try { body = JSON.parse(event.body || '{}'); }
  catch (e) { return { statusCode: 400, headers, body: JSON.stringify({ error: 'Invalid JSON' }) }; }

  const to = body.to;
  const message = body.message || '';
  if (!to || !message) {
    return { statusCode: 400, headers, body: JSON.stringify({ error: 'to/message 필수' }) };
  }

  const form = new URLSearchParams();
  form.append('key', key);
  form.append('user_id', userId);
  form.append('sender', sender);
  form.append('receiver', to);
  form.append('msg', message);
  form.append('msg_type', message.length > 90 ? 'LMS' : 'SMS');

  try {
    const r = await fetch('https://apis.aligo.in/send/', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: form.toString()
    });
    const data = await r.json().catch(() => ({}));
    return { statusCode: r.status, headers, body: JSON.stringify(data) };
  } catch (e) {
    return { statusCode: 502, headers, body: JSON.stringify({ error: '알리고 호출 실패: ' + e.message }) };
  }
};
