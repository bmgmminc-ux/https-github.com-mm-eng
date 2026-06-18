-- ════════════════════════════════════════════════════════════════
-- 첨부파일 등록 차단 해소 — attachments 테이블 RLS 정책 복구
-- Supabase 대시보드 → SQL Editor 에 붙여넣고 RUN. 재실행해도 안전(idempotent).
--
-- 증상: 첨부파일을 올리면 파일은 Storage(mm-attachments 버킷)에 업로드되나,
--       attachments 테이블 기록(INSERT)이 "new row violates row-level
--       security policy" 로 차단되어 목록에 등록되지 않음.
-- 원인: 테이블 + RLS(행 수준 보안)는 켜져 있으나 정책이 적용 안 됨
--       (supabase-schema.sql 의 attachments 정책 블록이 미실행).
-- 조치: 소유자(owner_id = 로그인 사용자) 기준 정책을 (재)생성.
-- ════════════════════════════════════════════════════════════════

-- 1) 테이블 보장 (이미 있으면 변경 없음)
create table if not exists public.attachments (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null references auth.users(id),
  project_id   text references public.projects(id) on delete cascade,
  category     text default '기타',
  file_name    text not null,
  file_path    text not null,
  file_size    bigint default 0,
  mime_type    text,
  uploaded_at  timestamptz default now()
);
create index if not exists idx_attach_project on public.attachments(project_id);

-- 2) RLS 켜고, 소유자 기준 정책 (재)생성
alter table public.attachments enable row level security;
drop policy if exists "attach_via_project" on public.attachments;
drop policy if exists "attach_owner_all"   on public.attachments;
create policy "attach_owner_all" on public.attachments for all
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

-- 3) Storage 버킷 + 정책 (이미 있으면 무해)
insert into storage.buckets (id, name, public)
  values ('mm-attachments', 'mm-attachments', false)
  on conflict (id) do nothing;

drop policy if exists "att_storage_insert" on storage.objects;
create policy "att_storage_insert" on storage.objects for insert
  with check (bucket_id = 'mm-attachments' and auth.uid() is not null);
drop policy if exists "att_storage_select" on storage.objects;
create policy "att_storage_select" on storage.objects for select
  using (bucket_id = 'mm-attachments' and auth.uid() is not null);
drop policy if exists "att_storage_delete" on storage.objects;
create policy "att_storage_delete" on storage.objects for delete
  using (bucket_id = 'mm-attachments' and auth.uid() is not null);

-- 4) [Piece B 준비] 매입 건별 증빙 — cost_item_id 컬럼 (한 번에 같이 적용)
--    매입 세부내역 '행'에 증빙 파일을 직접 묶기 위한 컬럼. 지금 추가해 둬도 무해(미사용 시 NULL).
--    이 컬럼이 있으면 다음 작업(행별 📎 첨부 활성화)이 SQL 재실행 없이 바로 연결됩니다.
alter table public.attachments add column if not exists cost_item_id text;
create index if not exists idx_attach_costitem on public.attachments(cost_item_id);

-- 5) 검증 (정책 3건 + att_* storage 정책 + cost_item_id 컬럼이 보이면 정상)
select schemaname, tablename, policyname from pg_policies
where tablename = 'attachments' or policyname like 'att_storage_%'
order by tablename, policyname;
select column_name from information_schema.columns
where table_schema='public' and table_name='attachments' and column_name='cost_item_id';
