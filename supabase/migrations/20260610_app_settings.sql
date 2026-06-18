-- ════════════════════════════════════════════════════════════════
-- app_settings — 회사정보·보험요율·임계값 등 키-값 설정 클라우드 동기화 [감사 4단계]
-- Supabase 대시보드 → SQL Editor 에 붙여넣고 RUN. 재실행해도 안전.
-- 코드(pushSettings/pullSettings)는 이미 배포됨 → 이 테이블만 생기면 동기화 작동.
-- 보험요율 소실 시 기본값 회귀 → 정산 오류를 막기 위한 백업.
-- ════════════════════════════════════════════════════════════════

create table if not exists public.app_settings (
  owner_id    uuid not null references auth.users(id) on delete cascade,
  key         text not null,                  -- 'mm-company' | 'mm-insurance-rates' | 'mm-alert-thresholds' ...
  value       jsonb,                          -- 해당 키의 localStorage 값(JSON)
  updated_at  timestamptz default now(),
  primary key (owner_id, key)
);

alter table public.app_settings enable row level security;

-- 본인(owner) 것만 R/W
drop policy if exists "settings_owner_all" on public.app_settings;
create policy "settings_owner_all" on public.app_settings for all
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- realtime (선택)
do $$ begin
  begin
    alter publication supabase_realtime add table public.app_settings;
  exception when others then null;
  end;
end $$;
