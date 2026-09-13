-- ════════════════════════════════════════════════════════════════════════
-- R1 · 회사 기준 접근 규칙 — '만든 사람' 기준 정책을 '같은 회사' 기준으로 전면 교체
-- 2026-09-13. Supabase → SQL Editor 에서 RUN. 여러 번 실행해도 안전.
--
-- [왜] 지금 정책은 현장은 대표가 전부 보되 그 현장의 매입·기성은 만든 사람만 보는 구조라
--      직원과 함께 입력하는 순간 서로의 자료가 안 보인다. 회사 하나를 단위로 모든 표를 통일한다.
-- [역할] 기존 값 그대로 — ceo = 대표 · admin = 관리자 · user = 직원 · demo = 읽기전용.
-- [단일 회사 전제] 회사 id 는 대표 프로필에 하나 발급하고, 회사가 없는 프로필·새 가입자는 그 회사로 배정한다.
-- [안전] postgres 권한으로 실행되므로 정책이 잘못돼도 SQL Editor 에서는 언제나 되돌릴 수 있다.
-- ════════════════════════════════════════════════════════════════════════

-- ── 0. 대표 계정 역할 보정(앱의 관리자 이메일과 일치시킨다) ─────────────
update public.user_profiles set role = 'ceo' where lower(email) = 'bmgmminc@gmail.com' and role <> 'ceo';

-- ── 1. 회사 식별자 ─────────────────────────────────────────────────────
alter table public.user_profiles add column if not exists company_id uuid;
alter table public.projects      add column if not exists company_id uuid;
create index if not exists projects_company_idx on public.projects(company_id);

update public.user_profiles
   set company_id = gen_random_uuid()
 where role = 'ceo' and company_id is null
   and not exists (select 1 from public.user_profiles where role = 'ceo' and company_id is not null);
update public.user_profiles u
   set company_id = (select company_id from public.user_profiles where role = 'ceo' and company_id is not null order by created_at limit 1)
 where u.company_id is null;
update public.projects p
   set company_id = u.company_id
  from public.user_profiles u
 where u.id = p.owner_id and p.company_id is null;

-- ── 2. 헬퍼 함수(security definer — RLS 안에서 프로필을 안전하게 본다) ─────
create or replace function public.my_company() returns uuid
language sql stable security definer set search_path = public as $$
  select company_id from public.user_profiles where id = auth.uid()
$$;
create or replace function public.my_role() returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select role from public.user_profiles where id = auth.uid()), 'demo')
$$;
create or replace function public.project_in_my_company(pid text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.projects p where p.id = pid and p.company_id = public.my_company())
$$;
create or replace function public.user_in_my_company(uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.user_profiles u where u.id = uid and u.company_id = public.my_company())
$$;
create or replace function public.can_write() returns boolean
language sql stable security definer set search_path = public as $$
  select public.my_role() in ('ceo','admin','user')
$$;

-- 새 가입자 → 직원(user) + 대표 회사 배정
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.user_profiles(id, email, name, role, company_id)
  values (new.id, new.email, split_part(new.email, '@', 1), 'user',
          (select company_id from public.user_profiles where role = 'ceo' and company_id is not null order by created_at limit 1))
  on conflict (id) do nothing;
  return new;
end $$;

-- 현장 insert 시 회사 자동 채움(앱은 company_id 를 보내지 않는다)
create or replace function public.set_project_company()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.company_id is null then new.company_id := public.my_company(); end if;
  return new;
end $$;
drop trigger if exists trg_projects_company on public.projects;
create trigger trg_projects_company before insert on public.projects
  for each row execute procedure public.set_project_company();

-- ── 3. 정책 교체 ────────────────────────────────────────────────────────
drop policy if exists "projects_owner_all"      on public.projects;
drop policy if exists "projects_ceo_read_all"   on public.projects;
drop policy if exists "projects_admin_read_all" on public.projects;
drop policy if exists "projects_company_select" on public.projects;
drop policy if exists "projects_company_insert" on public.projects;
drop policy if exists "projects_company_update" on public.projects;
drop policy if exists "projects_ceo_delete"     on public.projects;
create policy "projects_company_select" on public.projects for select using (company_id = public.my_company());
create policy "projects_company_insert" on public.projects for insert with check (company_id = public.my_company() and public.can_write());
create policy "projects_company_update" on public.projects for update using (company_id = public.my_company() and public.can_write()) with check (company_id = public.my_company());
create policy "projects_ceo_delete"     on public.projects for delete using (company_id = public.my_company() and public.my_role() = 'ceo');

-- 현장의 자식 표: 읽기 = 같은 회사, 쓰기 = 같은 회사 + 읽기전용 아님
do $$
declare t text;
begin
  foreach t in array array['project_costs','cost_items','billing_items','other_income_items'] loop
    execute format('drop policy if exists "costs_via_project" on public.%I', t);
    execute format('drop policy if exists "costitems_via_project" on public.%I', t);
    execute format('drop policy if exists "billing_via_project" on public.%I', t);
    execute format('drop policy if exists "other_income_via_project" on public.%I', t);
    execute format('drop policy if exists "%s_company_select" on public.%I', t, t);
    execute format('drop policy if exists "%s_company_write" on public.%I', t, t);
    execute format('create policy "%s_company_select" on public.%I for select using (public.project_in_my_company(project_id))', t, t);
    execute format('create policy "%s_company_write" on public.%I for all using (public.project_in_my_company(project_id) and public.can_write()) with check (public.project_in_my_company(project_id) and public.can_write())', t, t);
  end loop;
end $$;

-- 첨부 메타(attachments): 현장 기준
drop policy if exists "attach_owner_all"           on public.attachments;
drop policy if exists "attachments_company_select" on public.attachments;
drop policy if exists "attachments_company_write"  on public.attachments;
create policy "attachments_company_select" on public.attachments for select using (public.project_in_my_company(project_id));
create policy "attachments_company_write"  on public.attachments for all using (public.project_in_my_company(project_id) and public.can_write()) with check (public.project_in_my_company(project_id) and public.can_write());

-- 마스터(거래처·일용직): 소유자가 같은 회사면 공유. 새 행의 owner 는 본인.
drop policy if exists "vendors_owner_all"      on public.vendors;
drop policy if exists "vendors_company_select" on public.vendors;
drop policy if exists "vendors_company_insert" on public.vendors;
drop policy if exists "vendors_company_modify" on public.vendors;
drop policy if exists "vendors_company_delete" on public.vendors;
create policy "vendors_company_select" on public.vendors for select using (public.user_in_my_company(owner_id));
create policy "vendors_company_insert" on public.vendors for insert with check (owner_id = auth.uid() and public.can_write());
create policy "vendors_company_modify" on public.vendors for update using (public.user_in_my_company(owner_id) and public.can_write()) with check (public.user_in_my_company(owner_id));
create policy "vendors_company_delete" on public.vendors for delete using (public.user_in_my_company(owner_id) and public.can_write());

drop policy if exists "workers_owner_all"      on public.workers;
drop policy if exists "workers_company_select" on public.workers;
drop policy if exists "workers_company_insert" on public.workers;
drop policy if exists "workers_company_modify" on public.workers;
drop policy if exists "workers_company_delete" on public.workers;
create policy "workers_company_select" on public.workers for select using (public.user_in_my_company(owner_id));
create policy "workers_company_insert" on public.workers for insert with check (owner_id = auth.uid() and public.can_write());
create policy "workers_company_modify" on public.workers for update using (public.user_in_my_company(owner_id) and public.can_write()) with check (public.user_in_my_company(owner_id));
create policy "workers_company_delete" on public.workers for delete using (public.user_in_my_company(owner_id) and public.can_write());

drop policy if exists "attend_via_worker"         on public.attendance;
drop policy if exists "attendance_company_select" on public.attendance;
drop policy if exists "attendance_company_write"  on public.attendance;
create policy "attendance_company_select" on public.attendance for select
  using (exists (select 1 from public.workers w where w.id = worker_id and public.user_in_my_company(w.owner_id)));
create policy "attendance_company_write" on public.attendance for all
  using (public.can_write() and exists (select 1 from public.workers w where w.id = worker_id and public.user_in_my_company(w.owner_id)))
  with check (public.can_write() and exists (select 1 from public.workers w where w.id = worker_id and public.user_in_my_company(w.owner_id)));

-- 임계값(회사 공용 1행): 읽기 = 로그인 사용자, 쓰기 = 대표·관리자  (R2 에서 직원 읽기 제한)
drop policy if exists "auth all thresholds"       on public.thresholds;
drop policy if exists "thresholds_read"           on public.thresholds;
drop policy if exists "thresholds_manage_write"   on public.thresholds;
create policy "thresholds_read"         on public.thresholds for select using (auth.role() = 'authenticated');
create policy "thresholds_manage_write" on public.thresholds for all using (public.my_role() in ('ceo','admin')) with check (public.my_role() in ('ceo','admin'));

-- 사용자 프로필: 본인 읽기·수정(기존) + 대표·관리자는 같은 회사 전체 읽기 + 대표만 같은 회사 역할 변경
drop policy if exists "profiles_ceo_manage"         on public.user_profiles;
drop policy if exists "profiles_company_read"       on public.user_profiles;
drop policy if exists "profiles_ceo_update_company" on public.user_profiles;
create policy "profiles_company_read" on public.user_profiles for select
  using (company_id = public.my_company() and public.my_role() in ('ceo','admin'));
create policy "profiles_ceo_update_company" on public.user_profiles for update
  using (company_id = public.my_company() and public.my_role() = 'ceo')
  with check (company_id = public.my_company());

-- ── 4. 기록 ────────────────────────────────────────────────────────────
insert into public.schema_migrations(filename) values('20260913_r1_company_rls.sql') on conflict do nothing;

-- ── 5. 확인 ────────────────────────────────────────────────────────────
select
  (select count(*) from public.user_profiles where company_id is not null)                          as 회사배정_사용자,
  (select count(*) from public.user_profiles where role = 'ceo')                                     as 대표_수,
  (select count(*) from public.projects where company_id is null)                                    as 회사없는_현장,
  (select count(*) from public.projects p join public.user_profiles u on u.company_id = p.company_id
     where u.role = 'ceo')                                                                            as 대표회사_현장,
  (select count(*) from pg_policies where schemaname = 'public' and policyname like '%company%')     as 회사정책_수;
