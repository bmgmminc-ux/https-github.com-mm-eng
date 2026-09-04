// ㈜명문이엔지 — Netlify Function 공용 인증 [rn3 C-1]
// (lib/ 하위에 두어 Netlify 가 별도 함수로 번들하지 않게 함)
// 브라우저가 보낸 Supabase 세션 토큰(Authorization: Bearer <access_token>)을 Supabase Auth 에 검증한다.
// anon key 는 RLS 보호 공개 클라이언트 키(index.html 에도 있음) — 서버 시크릿이 아니다.
const SUPABASE_URL = process.env.SUPABASE_URL || 'https://mauqgsoxbncnwumhysvf.supabase.co';
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY ||
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1hdXFnc294Ym5jbnd1bWh5c3ZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkyOTA5NTQsImV4cCI6MjA5NDg2Njk1NH0.xNPOrmfYLgIAI0R4yfGajWyQFJrFkY7LkWEcj-4WAkI';

// 성공 시 { id, email } · 토큰 없음/무효 시 null · 인증 서버 미응답 시 { unreachable: true }
async function requireUser(event) {
  const h = event.headers || {};
  const auth = h.authorization || h.Authorization || '';
  const m = /^Bearer\s+(.+)$/i.exec(auth);
  if (!m) return null;
  try {
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), 5000);
    const r = await fetch(SUPABASE_URL + '/auth/v1/user', {
      headers: { apikey: SUPABASE_ANON_KEY, Authorization: 'Bearer ' + m[1] },
      signal: ctl.signal
    });
    clearTimeout(timer);
    if (r.status === 401 || r.status === 403) return null;
    if (!r.ok) return { unreachable: true };
    const u = await r.json().catch(() => null);
    return u && u.id ? { id: u.id, email: u.email || '' } : null;
  } catch (e) {
    return { unreachable: true };
  }
}

// 401(로그인 필요) 또는 503(인증 서버 미응답) 응답. 통과면 null.
function gate(user, headers) {
  if (user && user.unreachable) {
    return { statusCode: 503, headers, body: JSON.stringify({ error: '인증 서버 미응답 — 잠시 후 다시 시도하세요' }) };
  }
  if (!user) {
    return { statusCode: 401, headers, body: JSON.stringify({ error: '로그인 필요 — 클라우드 계정으로 로그인한 뒤 사용하세요' }) };
  }
  return null;
}

module.exports = { requireUser, gate };
