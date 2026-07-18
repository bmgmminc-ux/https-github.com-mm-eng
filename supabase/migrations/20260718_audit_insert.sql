-- ════════════════════════════════════════════════════════════════
-- 20260718_audit_insert — 감사로그 서버 기록 허용 [C3]
-- Supabase 대시보드 → SQL Editor 에 붙여넣고 RUN. 재실행 안전.
--
-- 배경: audit_log 테이블·RLS는 있으나 정책이 select(audit_self_read)뿐이라
--       클라이언트 insert가 차단 → 감사추적이 기기 로컬 200건에 갇힘(캐시 삭제 시 소멸).
-- 조치: 본인(user_id=로그인 사용자) 기록 insert 허용. update/delete는 계속 불허(감사로그 불변성).
-- ════════════════════════════════════════════════════════════════

drop policy if exists "audit_self_insert" on public.audit_log;
create policy "audit_self_insert" on public.audit_log for insert
  with check (auth.uid() = user_id);

insert into public.schema_migrations(filename) values('20260718_audit_insert.sql')
  on conflict (filename) do nothing;

-- 검증: audit_log 정책 2건(read+insert) 나오면 정상
select policyname, cmd from pg_policies where tablename='audit_log' order by policyname;
