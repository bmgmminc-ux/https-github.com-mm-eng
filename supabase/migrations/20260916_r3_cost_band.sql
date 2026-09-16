-- ════════════════════════════════════════════════════════════════════════
-- R3 · 원가율 구간 — 직원에게는 숫자 대신 구간(양호·주의·초과)만. 서버가 계산하고 구간 이름만 내보낸다.
-- 2026-09-16. Supabase → SQL Editor 에서 RUN. 여러 번 실행해도 안전. R2 뒤에 실행.
--
-- [왜] 원가율 = 원가 ÷ 매출(계약 + 기타수익). 직원은 계약을 받지 못하므로 화면에서 계산할 수 없다.
--      security definer 함수가 정책 밖에서 계약·임계값을 읽어 구간 한 단어만 돌려준다 — 계약금액은 함수 밖으로 나가지 않는다.
-- [산식] 앱과 동일: 원가 = project_costs.actual 9분류 합 · 매출 = contract_orig + contract_add + 기타수익 공급가 합
--        구간: 매출 0 → 'none' · 원가/매출 ≥ 100% → 'crit' · ≥ 임계값(thresholds.cost_max, 기본 85) → 'warn' · 그 외 'good'
-- [범위] 호출자 회사의 현장만(my_company()). 로그인 사용자만 실행.
-- ════════════════════════════════════════════════════════════════════════

create or replace function public.mm_cost_bands()
returns table(project_id text, band text)
language sql stable security definer set search_path = public as $$
  with th as (
    select coalesce((select t.cost_max from public.thresholds t order by t.id limit 1), 85)::numeric as cost_max
  ),
  fin as (
    select p.id, (coalesce(f.contract_orig, 0) + coalesce(f.contract_add, 0))::numeric as contract
      from public.projects p
      left join public.project_finance f on f.project_id = p.id
     where p.company_id = public.my_company()
  ),
  oi as (
    select o.project_id, sum(coalesce(o.supply_amt, 0))::numeric as oi
      from public.other_income_items o group by o.project_id
  ),
  cost as (
    select c.project_id, sum(coalesce(c.actual, 0))::numeric as cost
      from public.project_costs c group by c.project_id
  )
  select fin.id as project_id,
         case
           when (fin.contract + coalesce(oi.oi, 0)) <= 0 then 'none'
           when coalesce(cost.cost, 0) / (fin.contract + coalesce(oi.oi, 0)) >= 1 then 'crit'
           when coalesce(cost.cost, 0) / (fin.contract + coalesce(oi.oi, 0)) * 100 >= (select cost_max from th) then 'warn'
           else 'good'
         end as band
    from fin
    left join oi   on oi.project_id = fin.id
    left join cost on cost.project_id = fin.id
$$;
revoke all on function public.mm_cost_bands() from public;
grant execute on function public.mm_cost_bands() to authenticated;

insert into public.schema_migrations(filename) values('20260916_r3_cost_band.sql') on conflict do nothing;

-- ── 확인: 대표 계정 시각으로 실행(계약금액 없이 구간만 나오는지) ──
select set_config('request.jwt.claims',
  json_build_object('sub', (select id from public.user_profiles where lower(email) = 'bmgmminc@gmail.com'), 'role', 'authenticated')::text, true);
set local role authenticated;
select b.band, count(*) as 현장수, string_agg(b.project_id, ', ' order by b.project_id) as 현장
  from public.mm_cost_bands() b group by b.band order by b.band;
