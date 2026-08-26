-- ════════════════════════════════════════════════════════════════════
-- 지혈 패치 — 2026-08-26
-- Supabase 대시보드 > SQL Editor 에서 통째로 실행하세요.
-- 전부 멱등(여러 번 실행해도 안전)이며 기존 데이터를 지우지 않습니다.
-- ════════════════════════════════════════════════════════════════════


-- ── 1. 매입 증빙 첨부가 재로그인으로 끊기는 문제 ────────────────────
-- 매입 건에 붙인 파일은 브라우저가 만든 ci_… 식별자로 연결되는데,
-- 이 값이 클라우드로 올라가지도 내려오지도 않아 로그인 한 번에 링크가 끊겼습니다.
-- 그 식별자를 담을 자리를 만듭니다. (앱은 이 컬럼이 없어도 동작하도록 폴백이 들어가 있습니다)

alter table public.cost_items
  add column if not exists client_id text;

create index if not exists cost_items_client_id_idx
  on public.cost_items (client_id)
  where client_id is not null;

comment on column public.cost_items.client_id is
  '브라우저가 부여한 매입 건 식별자. attachments.cost_item_id 가 이 값을 가리킨다.';


-- ── 2. 첨부 파일 저장소가 로그인만 하면 전부 열리는 문제 ──────────────
-- 기존 정책은 조건이 "로그인했는가" 하나뿐이라, 계정이 있으면 남의 첨부도
-- 목록 조회·내려받기·삭제가 가능했습니다. 파일 경로의 첫 폴더를 소유자 id 로 보고
-- 본인 것만 다루도록 좁힙니다.
--
-- ⚠️ 먼저 확인하세요 — 기존 파일이 "<사용자id>/파일명" 형태로 저장돼 있어야 합니다.
--    아래 조회로 확인한 뒤 진행하십시오.
--
--    select name, (storage.foldername(name))[1] as first_folder, owner
--    from storage.objects where bucket_id = 'mm-attachments' limit 20;
--
--    first_folder 가 사용자 uuid 가 아니라면 이 블록은 건너뛰고 알려주세요.
--    (경로 규칙에 맞춘 다른 조건으로 다시 만들어 드리겠습니다)

drop policy if exists att_storage_insert on storage.objects;
drop policy if exists att_storage_select on storage.objects;
drop policy if exists att_storage_delete on storage.objects;

create policy att_storage_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'mm-attachments'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy att_storage_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'mm-attachments'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy att_storage_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'mm-attachments'
    and (storage.foldername(name))[1] = auth.uid()::text
  );


-- ── 3. 주민등록번호 ─────────────────────────────────────────────────
-- 앱은 이제 주민번호를 클라우드로 보내지 않습니다(로컬 보관만).
-- 이미 올라가 있는 값을 지웁니다. 컬럼 이름이 jumin_masked 인데
-- 실제로는 마스킹되지 않은 원문이 들어 있었습니다.
--
-- ⚠️ 지우기 전에 남아 있는 건수를 먼저 확인하십시오.
--    select count(*) from public.workers where jumin_masked is not null;
--
-- 확인 후 아래 주석을 풀고 실행하세요.

-- update public.workers set jumin_masked = null where jumin_masked is not null;

comment on column public.workers.jumin_masked is
  '사용 중단. 암호화 도입 전까지 주민번호는 클라우드에 저장하지 않는다.';


-- ── 4. 확인용 ───────────────────────────────────────────────────────
-- 실행 후 아래를 돌려 결과를 알려주시면 반영 여부를 확인하겠습니다.

select
  (select count(*) from information_schema.columns
     where table_name = 'cost_items' and column_name = 'client_id')            as client_id_컬럼,
  (select count(*) from pg_policies
     where tablename = 'objects' and policyname like 'att_storage_%')          as 첨부정책_개수,
  (select count(*) from public.workers where jumin_masked is not null)         as 주민번호_잔존건수;
