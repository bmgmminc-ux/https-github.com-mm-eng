-- ════════════════════════════════════════════════════════════════
-- 00001_base_schema — 기반 스키마(원본 supabase-schema.sql). migrations 단일소스 편입(2026-06-18).
-- ⚠️ 신규/빈 DB 재구축용. create table은 if-not-exists(멱등)이나, 정책(create policy)에
--    drop-if-exists 가드가 없어 '기존 DB 재실행 시 정책 중복 오류' 발생 → 라이브엔 이미 적용됨(재실행 불필요).
--    재구축은 이 파일 → 00002 → 날짜순 증분 순으로 RUN.
-- ════════════════════════════════════════════════════════════════
-- ?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧
-- MM E.N.G v3 ??Supabase ?ㅽ궎留?(?뺢퇋??6媛??뚯씠釉?+ RLS 湲곕낯)
-- ?ъ슜踰? Supabase Dashboard ??SQL Editor ??New Query ???꾩껜 遺숈뿬?ｊ린 ??Run
-- ?앹꽦?? 2026-05-19
-- ?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧

-- ??? 0. ?뺤옣 ???
create extension if not exists "pgcrypto";

-- ??? 1. ?ъ슜???꾨줈??(auth.users ?뺤옣) ???
create table if not exists public.user_profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text not null,
  name        text,
  role        text not null default 'user' check (role in ('ceo','admin','user','demo')),
  company_id  uuid,
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);

-- ??? 2. ?꾨줈?앺듃 (硫붿씤) ???
create table if not exists public.projects (
  id              text primary key,                           -- ?? MM-2025-001
  owner_id        uuid not null references auth.users(id),
  name            text not null,
  type            text,                                       -- 嫄댁텞 ?좎텞 / 由щえ?몃쭅 / MEP ??  client          text,                                       -- 諛쒖＜泥?  start_date      date,
  end_date        date,
  contract_orig   bigint not null default 0,                  -- ??怨꾩빟湲?(??
  contract_add    bigint not null default 0,                  -- 異붽? 怨꾩빟
  memo            text,
  meta            jsonb default '{}'::jsonb,                  -- ?뺤옣??  created_at      timestamptz default now(),
  updated_at      timestamptz default now()
);
create index if not exists idx_projects_owner on public.projects(owner_id);
create index if not exists idx_projects_dates on public.projects(start_date, end_date);

-- ??? 3. 9遺꾨쪟 ?뚭퀎 (project_costs) ???
-- ???꾨줈?앺듃??9??(outsource/material/product/indirect/cashexp/labor/safety/direct/labordirect)
create table if not exists public.project_costs (
  id              uuid primary key default gen_random_uuid(),
  project_id      text not null references public.projects(id) on delete cascade,
  category        text not null check (category in
                    ('outsource','material','product','indirect','cashexp',
                     'labor','safety','direct','labordirect')),
  contract        bigint not null default 0,
  actual          bigint not null default 0,
  seed_actual     bigint default 0,                           -- ?쒕뱶 baseline 蹂댁〈
  updated_at      timestamptz default now(),
  unique (project_id, category)
);
create index if not exists idx_pcosts_project on public.project_costs(project_id);

-- ??? 4. 留ㅼ엯 ?몃? ??ぉ (cost_items) ???
create table if not exists public.cost_items (
  id              uuid primary key default gen_random_uuid(),
  project_id      text not null references public.projects(id) on delete cascade,
  type            text not null check (type in
                    ('outsource','material','product','indirect','cashexp',
                     'labor','safety','direct','labordirect')),
  vendor          text,
  desc_text       text,
  supply_amt      bigint not null default 0,                  -- 怨듦툒媛
  tax             bigint not null default 0,                  -- ?몄븸
  total           bigint not null default 0,                  -- ?⑷퀎
  paid_amount     bigint not null default 0,
  doc_date        date,
  memo            text,
  created_by      uuid references auth.users(id),
  created_at      timestamptz default now()
);
create index if not exists idx_costitems_project on public.cost_items(project_id);
create index if not exists idx_costitems_type on public.cost_items(type);
create index if not exists idx_costitems_date on public.cost_items(doc_date);

-- ??? 5. 湲곗꽦 ?뚯감 (billing_items) ???
create table if not exists public.billing_items (
  id              uuid primary key default gen_random_uuid(),
  project_id      text not null references public.projects(id) on delete cascade,
  round_no        int not null,                               -- ?뚯감 踰덊샇 (1,2,3...)
  apply_date      date,                                       -- ?좎껌??  apply_supply    bigint not null default 0,                  -- 怨듦툒媛
  apply_tax       bigint not null default 0,                  -- ?몄븸
  apply_total     bigint not null default 0,                  -- ?⑷퀎
  receive_date    date,                                       -- ?섍툑??  billing_amount  bigint not null default 0,                  -- ?ㅼ닔湲?  memo            text,
  created_at      timestamptz default now(),
  unique (project_id, round_no)
);
create index if not exists idx_billing_project on public.billing_items(project_id);
create index if not exists idx_billing_apply on public.billing_items(apply_date);

-- ??? 6. 嫄곕옒泥?留덉뒪?????
create table if not exists public.vendors (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null references auth.users(id),
  name            text not null,
  business_no     text,                                       -- ?ъ뾽?먮쾲??  category        text,                                       -- ?몄＜/?먯옱/?곹뭹/...
  phone           text,
  email           text,
  address         text,
  memo            text,
  created_at      timestamptz default now(),
  updated_at      timestamptz default now()
);
create index if not exists idx_vendors_owner on public.vendors(owner_id);

-- ??? 7. ?쇱슜吏?留덉뒪??(?ㅺ린??吏?? ???
create table if not exists public.workers (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null references auth.users(id),
  name            text not null,
  jumin_masked    text,                                       -- 二쇰?踰덊샇 留덉뒪??  phone           text,
  address         text,
  primary_job     text,                                       -- 二?吏곸쥌
  primary_wage    bigint default 0,
  alt_jobs        jsonb default '[]'::jsonb,                  -- [{type, wage}, ...] 蹂댁“ 吏곸쥌
  insurance_ok    boolean default false,                      -- 4?蹂댄뿕 媛???щ?
  created_at      timestamptz default now(),
  updated_at      timestamptz default now()
);
create index if not exists idx_workers_owner on public.workers(owner_id);

-- ??? 8. 異쒖뿭 湲곕줉 ???
create table if not exists public.attendance (
  id              uuid primary key default gen_random_uuid(),
  worker_id       uuid not null references public.workers(id) on delete cascade,
  project_id      text references public.projects(id) on delete set null,
  work_date       date not null,
  job_type        text,                                       -- 洹몃궇 ?쇳븳 吏곸쥌
  wage            bigint not null default 0,                  -- 洹몃궇 ?쇰떦
  memo            text,
  created_at      timestamptz default now(),
  unique (worker_id, work_date, project_id)
);
create index if not exists idx_attend_worker on public.attendance(worker_id);
create index if not exists idx_attend_date on public.attendance(work_date);

-- ??? 9. 媛먯궗 濡쒓렇 ???
create table if not exists public.audit_log (
  id              bigserial primary key,
  user_id         uuid references auth.users(id),
  action          text not null,                              -- INSERT/UPDATE/DELETE
  table_name      text not null,
  record_id       text,
  before_data     jsonb,
  after_data      jsonb,
  created_at      timestamptz default now()
);
create index if not exists idx_audit_user on public.audit_log(user_id);
create index if not exists idx_audit_table on public.audit_log(table_name, created_at desc);

-- ?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧
-- RLS ?뺤콉 (湲곕낯 ??owner留??먯떊???곗씠???묎렐)
-- ?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧
alter table public.user_profiles enable row level security;
alter table public.projects      enable row level security;
alter table public.project_costs enable row level security;
alter table public.cost_items    enable row level security;
alter table public.billing_items enable row level security;
alter table public.vendors       enable row level security;
alter table public.workers       enable row level security;
alter table public.attendance    enable row level security;
alter table public.audit_log     enable row level security;

-- ?먯떊 ?꾨줈???쎄린쨌?곌린
create policy "profiles_self_read" on public.user_profiles for select using (auth.uid() = id);
create policy "profiles_self_update" on public.user_profiles for update using (auth.uid() = id);

-- ?꾨줈?앺듃 ??owner留?? 沅뚰븳
create policy "projects_owner_all" on public.projects for all
  using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

-- ?먯떇 ?뚯씠釉????꾨줈?앺듃 owner硫??묎렐 媛??create policy "costs_via_project" on public.project_costs for all
  using (exists (select 1 from public.projects p where p.id = project_id and p.owner_id = auth.uid()));
create policy "costitems_via_project" on public.cost_items for all
  using (exists (select 1 from public.projects p where p.id = project_id and p.owner_id = auth.uid()));
create policy "billing_via_project" on public.billing_items for all
  using (exists (select 1 from public.projects p where p.id = project_id and p.owner_id = auth.uid()));

-- 嫄곕옒泥??쇱슜吏?異쒖뿭 ??owner留?create policy "vendors_owner_all" on public.vendors for all
  using (auth.uid() = owner_id) with check (auth.uid() = owner_id);
create policy "workers_owner_all" on public.workers for all
  using (auth.uid() = owner_id) with check (auth.uid() = owner_id);
create policy "attend_via_worker" on public.attendance for all
  using (exists (select 1 from public.workers w where w.id = worker_id and w.owner_id = auth.uid()));

-- 媛먯궗 濡쒓렇 ??蹂몄씤 濡쒓렇留??쎄린 (?곌린??trigger濡?
create policy "audit_self_read" on public.audit_log for select using (auth.uid() = user_id);

-- ?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧
-- updated_at ?먮룞 媛깆떊 ?몃━嫄?-- ?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

drop trigger if exists trg_projects_touch on public.projects;
create trigger trg_projects_touch before update on public.projects
  for each row execute procedure public.touch_updated_at();

drop trigger if exists trg_pcosts_touch on public.project_costs;
create trigger trg_pcosts_touch before update on public.project_costs
  for each row execute procedure public.touch_updated_at();

drop trigger if exists trg_vendors_touch on public.vendors;
create trigger trg_vendors_touch before update on public.vendors
  for each row execute procedure public.touch_updated_at();

drop trigger if exists trg_workers_touch on public.workers;
create trigger trg_workers_touch before update on public.workers
  for each row execute procedure public.touch_updated_at();

-- ?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧
-- 泥??뚯썝媛????user_profile ?먮룞 ?앹꽦 ?몃━嫄?-- ?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.user_profiles(id, email, name, role)
  values (new.id, new.email, split_part(new.email,'@',1), 'user');
  return new;
end $$;

drop trigger if exists trg_auth_user_created on auth.users;
create trigger trg_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧
-- ??븷 湲곕컲 RLS 蹂닿컯 [#123] ??CEO/admin/user/demo
-- ?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧

-- ?꾩옱 ?ъ슜????븷 議고쉶 ?ы띁
create or replace function public.my_role()
returns text language sql stable security definer as $$
  select coalesce((select role from public.user_profiles where id = auth.uid()), 'demo');
$$;

-- CEO???뚯궗 ?꾩껜 ?꾨줈?앺듃 ?쎄린 (owner 臾닿?)
create policy "projects_ceo_read_all" on public.projects for select
  using (public.my_role() = 'ceo');

-- admin? ?뚯궗 ?꾩껜 ?꾨줈?앺듃 ?쎄린 (?섏젙? owner留?????projects_owner_all ?뺤콉 ?좎?)
create policy "projects_admin_read_all" on public.projects for select
  using (public.my_role() = 'admin');

-- demo ??븷? 紐⑤뱺 ?곌린 李⑤떒 (?쎄린留? ??蹂꾨룄 紐낆떆
-- (projects_owner_all ??with check 媛 owner ?쇱튂瑜??붽뎄?섎?濡?--  demo 怨꾩젙?쇰줈 留뚮뱺 ?곗씠?곌? ?놁쑝硫??먯뿰???곌린 遺덇?)

-- CEO留?user_profiles ???ㅻⅨ ?ъ슜????븷 蹂寃?媛??create policy "profiles_ceo_manage" on public.user_profiles for update
  using (public.my_role() = 'ceo');

-- 媛먯궗 濡쒓렇 ??CEO???꾩껜 議고쉶
create policy "audit_ceo_read_all" on public.audit_log for select
  using (public.my_role() = 'ceo');

-- ????????????????????????????????????????????????????????????????
-- ??븷 遺??諛⑸쾿 (Supabase Dashboard SQL Editor?먯꽌 ?섎룞 ?ㅽ뻾):
--   update public.user_profiles set role = 'ceo'   where email = 'ceo@?뚯궗.com';
--   update public.user_profiles set role = 'admin' where email = 'manager@?뚯궗.com';
-- ?먮뒗 auth.users ??app_metadata 濡?愿由ы븯?ㅻ㈃ Dashboard ??Authentication ??Users
-- ????????????????????????????????????????????????????????????????

-- ?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧
-- 泥⑤? ?뚯씪 [#126] ??attachments ?뚯씠釉?+ Storage 踰꾪궥
-- ?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧
create table if not exists public.attachments (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null references auth.users(id),
  project_id   text references public.projects(id) on delete cascade,
  category     text default '湲고?',                  -- ?곸닔利??멸툑怨꾩궛??怨꾩빟???ъ쭊/湲고?
  file_name    text not null,
  file_path    text not null,                        -- storage ??寃쎈줈
  file_size    bigint default 0,
  mime_type    text,
  uploaded_at  timestamptz default now()
);
create index if not exists idx_attach_project on public.attachments(project_id);

alter table public.attachments enable row level security;
create policy "attach_via_project" on public.attachments for all
  using (exists (select 1 from public.projects p where p.id = project_id and p.owner_id = auth.uid()))
  with check (auth.uid() = owner_id);

-- Storage 踰꾪궥 ?앹꽦 (鍮꾧났媛?
insert into storage.buckets (id, name, public)
  values ('mm-attachments', 'mm-attachments', false)
  on conflict (id) do nothing;

-- Storage RLS ??濡쒓렇???ъ슜?먮쭔 ?낅줈??議고쉶/??젣
do $$
begin
  begin
    create policy "att_storage_insert" on storage.objects for insert
      with check (bucket_id = 'mm-attachments' and auth.uid() is not null);
  exception when others then null; end;
  begin
    create policy "att_storage_select" on storage.objects for select
      using (bucket_id = 'mm-attachments' and auth.uid() is not null);
  exception when others then null; end;
  begin
    create policy "att_storage_delete" on storage.objects for delete
      using (bucket_id = 'mm-attachments' and auth.uid() is not null);
  exception when others then null; end;
end $$;

-- ?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧
-- 媛먯궗 濡쒓렇 ?먮룞 湲곕줉 ?몃━嫄?[#125]
-- INSERT/UPDATE/DELETE 諛쒖깮 ??audit_log???먮룞 湲곕줉
-- ?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧
create or replace function public.fn_audit()
returns trigger language plpgsql security definer as $$
declare
  rec_id text;
begin
  rec_id := coalesce((case when tg_op='DELETE' then old.id else new.id end)::text, '');
  insert into public.audit_log(user_id, action, table_name, record_id, before_data, after_data)
  values (
    auth.uid(),
    tg_op,
    tg_table_name,
    rec_id,
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end
  );
  return coalesce(new, old);
end $$;

drop trigger if exists trg_audit_projects on public.projects;
create trigger trg_audit_projects after insert or update or delete on public.projects
  for each row execute procedure public.fn_audit();

drop trigger if exists trg_audit_costitems on public.cost_items;
create trigger trg_audit_costitems after insert or update or delete on public.cost_items
  for each row execute procedure public.fn_audit();

drop trigger if exists trg_audit_billing on public.billing_items;
create trigger trg_audit_billing after insert or update or delete on public.billing_items
  for each row execute procedure public.fn_audit();

drop trigger if exists trg_audit_vendors on public.vendors;
create trigger trg_audit_vendors after insert or update or delete on public.vendors
  for each row execute procedure public.fn_audit();

-- ?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧
-- Realtime 諛쒗뻾 ?쒖꽦??[#124] ???ㅻⅨ ?ъ슜??蹂寃??ㅼ떆媛??섏떊
-- ?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧
-- (?대? 異붽???寃쎌슦 ?먮윭 臾댁떆 ??do block?쇰줈 ?덉쟾 泥섎━)
do $$
begin
  begin alter publication supabase_realtime add table public.projects;       exception when others then null; end;
  begin alter publication supabase_realtime add table public.project_costs;  exception when others then null; end;
  begin alter publication supabase_realtime add table public.cost_items;     exception when others then null; end;
  begin alter publication supabase_realtime add table public.billing_items;  exception when others then null; end;
end $$;

-- ?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧
-- ?꾨즺. Supabase Dashboard?먯꽌:
--   1. Authentication ??Providers ??Email ?쒖꽦??--   2. Database ??Replication ??supabase_realtime ??4媛??뚯씠釉??ы븿 ?뺤씤
--   3. 沅뚰븳 遺?? update public.user_profiles set role='ceo' where email='...'
-- ?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧

