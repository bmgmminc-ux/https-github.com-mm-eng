-- ════════════════════════════════════════════════════════════════
-- other_income_items (기타수익) 테이블 생성 — cost_items 패턴 동일
-- Supabase 대시보드 → SQL Editor 에 붙여넣고 RUN. 재실행해도 안전.
-- 코드(disassemble/assemble + bint)는 이미 배포됨 → 이 테이블만 생기면 동기화 작동.
-- ════════════════════════════════════════════════════════════════

create table if not exists public.other_income_items (
  id              uuid primary key default gen_random_uuid(),
  project_id      text not null references public.projects(id) on delete cascade,
  vendor          text,                                       -- 거래처/항목
  desc_text       text,                                       -- 내용
  supply_amt      bigint not null default 0,                  -- 공급가
  tax             bigint not null default 0,                  -- 세액
  total           bigint not null default 0,                  -- 합계
  received        bigint not null default 0,                  -- 수금액
  received_date   date,                                       -- 수금일
  memo            text,
  created_at      timestamptz default now()
);
create index if not exists idx_other_income_project on public.other_income_items(project_id);

alter table public.other_income_items enable row level security;

-- 프로젝트 owner면 접근 (cost_items / billing_items 동일 패턴)
drop policy if exists "other_income_via_project" on public.other_income_items;
create policy "other_income_via_project" on public.other_income_items for all
  using (exists (select 1 from public.projects p where p.id = project_id and p.owner_id = auth.uid()));

-- realtime 구독 (선택)
do $$ begin
  begin
    alter publication supabase_realtime add table public.other_income_items;
  exception when others then null;
  end;
end $$;
