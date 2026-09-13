-- ════════════════════════════════════════════════════════════════════════
-- R2 · 재무 분리 — 계약금액·추가계약·예산 항목을 project_finance 표로 떼어 관리자(ceo·admin)만 읽고 쓴다
-- 2026-09-13. Supabase → SQL Editor 에서 RUN. 여러 번 실행해도 안전. R1(20260913_r1_company_rls.sql) 뒤에 실행.
--
-- [왜] 직원과 함께 매입을 입력하되 이윤(= 계약 + 기타수익 − 원가)은 상위 관리자만 보려면,
--      화면 숨김이 아니라 서버가 계약·기성·기타수익·임계값을 직원에게 아예 보내지 않아야 한다.
-- [무엇]
--   1. project_finance(project_id PK, contract_orig, contract_add, budget_items) 신설 + projects 에서 이관
--   2. projects 의 옛 재무 컬럼은 0/[] 로 비우고, 트리거로 앞으로도 비워 둔다(옛 앱 탭이 올려도 새지 않는다)
--   3. project_finance · billing_items · other_income_items · thresholds 는 관리자만 select/write
--   4. mm_upsert_project_finance(rows) — 앱의 올리기 함수(security invoker → 위 정책이 그대로 적용)
-- [역할] ceo = 대표 · admin = 관리자(둘이 '관리자') · user = 직원 · demo = 읽기전용
-- ════════════════════════════════════════════════════════════════════════

-- ── 1. 표 ──────────────────────────────────────────────────────────────
create table if not exists public.project_finance (
  project_id    text primary key references public.projects(id) on delete cascade,
  contract_orig bigint not null default 0,
  contract_add  bigint not null default 0,
  budget_items  jsonb  not null default '[]'::jsonb,
  updated_at    timestamptz default now(),
  updated_by    uuid
);
alter table public.project_finance enable row level security;

-- 이관(처음 한 번만 — 이미 행이 있으면 건드리지 않는다)
insert into public.project_finance (project_id, contract_orig, contract_add, budget_items)
select p.id, coalesce(p.contract_orig, 0), coalesce(p.contract_add, 0), coalesce(p.budget_items, '[]'::jsonb)
  from public.projects p
on conflict (project_id) do nothing;

-- ── 2. projects 의 옛 재무 컬럼 비우기 + 앞으로도 비워 두는 트리거 ────────
create or replace function public.strip_project_finance()
returns trigger language plpgsql as $$
begin
  new.contract_orig := 0;
  new.contract_add  := 0;
  new.budget_items  := '[]'::jsonb;
  return new;
end $$;
drop trigger if exists trg_projects_strip_finance on public.projects;
create trigger trg_projects_strip_finance before insert or update on public.projects
  for each row execute procedure public.strip_project_finance();
update public.projects
   set contract_orig = 0, contract_add = 0, budget_items = '[]'::jsonb
 where contract_orig <> 0 or contract_add <> 0 or coalesce(budget_items, '[]'::jsonb) <> '[]'::jsonb;

-- ── 3. 헬퍼 + 정책 ──────────────────────────────────────────────────────
create or replace function public.is_manager() returns boolean
language sql stable security definer set search_path = public as $$
  select public.my_role() in ('ceo','admin')
$$;

-- 재무: 같은 회사 + 관리자
drop policy if exists "finance_manager_select" on public.project_finance;
drop policy if exists "finance_manager_write"  on public.project_finance;
create policy "finance_manager_select" on public.project_finance for select
  using (public.project_in_my_company(project_id) and public.is_manager());
create policy "finance_manager_write" on public.project_finance for all
  using (public.project_in_my_company(project_id) and public.is_manager())
  with check (public.project_in_my_company(project_id) and public.is_manager());

-- 기성·기타수익: R1 의 '같은 회사 + 쓰기 가능' 정책을 '같은 회사 + 관리자' 로 좁힌다(대표 결정 3 — 기성은 직원에게 숨김)
do $$
declare t text;
begin
  foreach t in array array['billing_items','other_income_items'] loop
    execute format('drop policy if exists "%s_company_select" on public.%I', t, t);
    execute format('drop policy if exists "%s_company_write"  on public.%I', t, t);
    execute format('drop policy if exists "%s_manager_select" on public.%I', t, t);
    execute format('drop policy if exists "%s_manager_write"  on public.%I', t, t);
    execute format('create policy "%s_manager_select" on public.%I for select using (public.project_in_my_company(project_id) and public.is_manager())', t, t);
    execute format('create policy "%s_manager_write"  on public.%I for all using (public.project_in_my_company(project_id) and public.is_manager()) with check (public.project_in_my_company(project_id) and public.is_manager())', t, t);
  end loop;
end $$;

-- 임계값(원가 한계·이익 목표): 읽기도 관리자만 — 직원 원가율은 R3 의 mm_cost_band 가 구간만 계산해 준다
drop policy if exists "thresholds_read"         on public.thresholds;
drop policy if exists "thresholds_manage_read"  on public.thresholds;
create policy "thresholds_manage_read" on public.thresholds for select using (public.is_manager());

-- ── 4. 앱의 올리기 함수 ─────────────────────────────────────────────────
-- security invoker: 호출자의 정책이 그대로 적용된다 → 직원이 부르면 정책 위반으로 거부된다.
create or replace function public.mm_upsert_project_finance(p_rows jsonb)
returns integer
language plpgsql security invoker set search_path = public as $$
declare n integer := 0;
begin
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then return 0; end if;
  insert into public.project_finance (project_id, contract_orig, contract_add, budget_items, updated_at, updated_by)
  select r.project_id, coalesce(r.contract_orig, 0), coalesce(r.contract_add, 0), coalesce(r.budget_items, '[]'::jsonb), now(), auth.uid()
    from jsonb_to_recordset(p_rows) as r(project_id text, contract_orig bigint, contract_add bigint, budget_items jsonb)
   where r.project_id is not null
  on conflict (project_id) do update
     set contract_orig = excluded.contract_orig,
         contract_add  = excluded.contract_add,
         budget_items  = excluded.budget_items,
         updated_at    = now(),
         updated_by    = auth.uid();
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.mm_upsert_project_finance(jsonb) from public;
grant execute on function public.mm_upsert_project_finance(jsonb) to authenticated;

-- 실시간 알림에 포함(관리자 기기끼리 계약 변경 반영)
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'project_finance') then
    alter publication supabase_realtime add table public.project_finance;
  end if;
exception when others then null; end $$;

-- ── 5. 기록 ────────────────────────────────────────────────────────────
insert into public.schema_migrations(filename) values('20260913_r2_project_finance.sql') on conflict do nothing;

-- ── 6. 확인 ────────────────────────────────────────────────────────────
select
  (select count(*) from public.project_finance)                                                          as 재무행,
  (select count(*) from public.projects)                                                                 as 현장,
  (select count(*) from public.projects where contract_orig <> 0 or contract_add <> 0)                   as 옛컬럼_잔존,
  (select coalesce(sum(contract_orig + contract_add), 0) from public.project_finance)                    as 계약합계,
  (select count(*) from pg_policies where schemaname = 'public' and policyname like '%manager%')         as 관리자정책_수,
  (select count(*) from pg_proc where proname = 'mm_upsert_project_finance')                             as 함수;
