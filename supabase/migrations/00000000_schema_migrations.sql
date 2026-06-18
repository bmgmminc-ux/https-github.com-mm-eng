-- ════════════════════════════════════════════════════════════════
-- 00000000_schema_migrations — 마이그레이션 적용 추적 테이블 [지속개발 토대]
-- Supabase 대시보드 → SQL Editor 에 붙여넣고 RUN. 재실행 안전(idempotent).
--
-- 목적: "어느 .sql 이 라이브 DB에 적용됐나"를 기억(MEMORY.md)이 아니라
--       DB에서 SELECT 로 확인. 신규 환경 부트스트랩·사고 후 재구축 시 누락 방지.
-- 사용: ① 이 파일을 가장 먼저 RUN(테이블 생성 + 기존 6건 백필)
--       ② 앞으로 새 마이그레이션 .sql 은 파일 '맨 끝'에 아래 1줄을 넣어 자기기록:
--          insert into public.schema_migrations(filename) values('YYYYMMDD_name.sql')
--            on conflict (filename) do nothing;
-- 보안: RLS on + 정책 없음 → anon/앱에서 안 보이고, 대표 SQL Editor(service)만 조회.
-- ════════════════════════════════════════════════════════════════

create table if not exists public.schema_migrations (
  filename    text primary key,
  applied_at  timestamptz not null default now()
);
alter table public.schema_migrations enable row level security;  -- 정책 없음 = 앱(anon) 비노출, SQL Editor만

-- 기존 적용분 백필 (실행 순서대로). 실제 미적용분이 있으면 해당 .sql 을 먼저 RUN 후 표시.
insert into public.schema_migrations(filename) values
  ('00001_base_schema.sql'),
  ('00002_base_phase1.sql'),
  ('20260609_01_audit_v2.sql'),
  ('20260609_02_other_income.sql'),
  ('20260610_app_settings.sql'),
  ('20260611_dunning_queue.sql'),
  ('20260612_attrib_cat.sql'),
  ('20260614_attachments_rls.sql')
on conflict (filename) do nothing;

-- 검증: 적용 목록 확인
select filename, applied_at from public.schema_migrations order by filename;
