-- R2 검증 · 역할별로 서버가 무엇을 주는가 — SQL Editor 에서 RUN(한 묶음 = 하나의 암묵적 트랜잭션: 중간에 실패하면 전부 되돌아간다).
-- 대표 프로필 역할을 잠시 'user' 로 바꿔 집계한 뒤 마지막에 'ceo' 로 되돌린다. 계정 생성 없이 직원 시각을 재현한다.
create temp table _r(who text, projects int, cost_items int, finance int, billing int, other_income int, thresholds int, upsert_fin text) on commit drop;
alter table _r enable row level security;   -- 대시보드 경고(RLS 없는 표 생성) 회피용 — 임시표, 커밋 시 삭제
create policy _r_all on _r for all using (true) with check (true);
grant all on _r to authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', (select id from public.user_profiles where lower(email) = 'bmgmminc@gmail.com'), 'role', 'authenticated')::text, true);

-- ① 대표(ceo) 시각
set local role authenticated;
insert into _r select 'ceo',
  (select count(*) from public.projects), (select count(*) from public.cost_items), (select count(*) from public.project_finance),
  (select count(*) from public.billing_items), (select count(*) from public.other_income_items), (select count(*) from public.thresholds), null;
reset role;

-- ② 직원(user) 시각 — 역할을 잠시 바꾼다
update public.user_profiles set role = 'user' where lower(email) = 'bmgmminc@gmail.com';
set local role authenticated;
insert into _r select 'user',
  (select count(*) from public.projects), (select count(*) from public.cost_items), (select count(*) from public.project_finance),
  (select count(*) from public.billing_items), (select count(*) from public.other_income_items), (select count(*) from public.thresholds), null;
do $$ begin
  begin
    perform public.mm_upsert_project_finance('[{"project_id":"명문-9101","contract_orig":1,"contract_add":0,"budget_items":[]}]'::jsonb);
    update _r set upsert_fin = 'ALLOWED(!)' where who = 'user';
  exception when others then
    update _r set upsert_fin = 'REFUSED: ' || left(sqlerrm, 70) where who = 'user';
  end;
end $$;
reset role;

-- ③ 되돌리기 + 결과
update public.user_profiles set role = 'ceo' where lower(email) = 'bmgmminc@gmail.com';
select *, (select role from public.user_profiles where lower(email) = 'bmgmminc@gmail.com') as 복원된_역할 from _r order by who desc;
