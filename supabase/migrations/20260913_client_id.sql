-- ════════════════════════════════════════════════════════════════════════
-- 2단계-1 · 매입 행 고유 번호(client_id) — 행 단위 동기화의 전제
-- 2026-09-13. Supabase → SQL Editor 에서 RUN. 여러 번 실행해도 안전.
--
-- [왜] 앱은 매입 행마다 'ci_<uuid>' 를 부여해 보내지만, 라이브 DB 에는 받을 컬럼이 없어
--      매번 버려졌다(20260826_triage.sql 미실행). 고유 번호가 있어야 "지우고 다시 넣기" 를
--      "행 단위 덮어쓰기" 로 바꿀 수 있고, 첨부 파일과 매입 행의 연결도 재로그인 뒤에 살아남는다.
-- [주의] 20260826_triage.sql 의 첨부 저장소 정책(폴더 첫 칸 = 사용자 uid)은 여기 넣지 않는다.
--        앱의 첨부 경로가 '현장ID/…' 라서 그 정책을 켜면 첨부가 전부 막힌다 → 3단계에서 경로와 함께 설계.
-- ════════════════════════════════════════════════════════════════════════

alter table public.cost_items add column if not exists client_id text;
comment on column public.cost_items.client_id is '앱이 부여한 매입 행 식별자(ci_<uuid>). attachments.cost_item_id 가 이 값을 가리킨다.';

-- 같은 현장 안에서 같은 번호가 두 번 들어오면 조용히 쌓이지 않고 즉시 실패한다.
create unique index if not exists cost_items_project_client_uq
  on public.cost_items (project_id, client_id)
  where client_id is not null;

-- 원자적 치환 함수에 client_id 를 포함한다. 번호가 없는 행은 서버가 발급한다(빈 값 방지).
create or replace function public.mm_replace_cost_items(
  p_project_id text,
  p_rows       jsonb
) returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_inserted integer := 0;
begin
  if p_project_id is null or length(p_project_id) = 0 then
    raise exception 'project_id 가 비어 있습니다';
  end if;

  perform pg_advisory_xact_lock(hashtext('mm_cost_items'), hashtext(p_project_id));

  delete from public.cost_items where project_id = p_project_id;

  if p_rows is not null and jsonb_typeof(p_rows) = 'array' and jsonb_array_length(p_rows) > 0 then
    insert into public.cost_items (
      project_id, client_id, type, vendor, worker_name, desc_text,
      supply_amt, tax, total, paid_amount, contract_amt, deduction,
      attrib_cat, doc_date, paid_date, created_at, memo
    )
    select
      p_project_id,
      coalesce(nullif(x.client_id, ''), 'ci_' || gen_random_uuid()::text),
      x.type, x.vendor, x.worker_name, x.desc_text,
      coalesce(x.supply_amt, 0), coalesce(x.tax, 0), coalesce(x.total, 0),
      coalesce(x.paid_amount, 0), coalesce(x.contract_amt, 0), coalesce(x.deduction, 0),
      x.attrib_cat, x.doc_date, x.paid_date, coalesce(x.created_at, now()), x.memo
    from jsonb_populate_recordset(null::public.cost_items, p_rows) x
    where x.type is not null;
    get diagnostics v_inserted = row_count;
  end if;

  return v_inserted;
end;
$$;

revoke execute on function public.mm_replace_cost_items(text, jsonb) from public, anon;
grant  execute on function public.mm_replace_cost_items(text, jsonb) to authenticated;

insert into public.schema_migrations(filename) values('20260913_client_id.sql')
  on conflict do nothing;

-- 확인: client_id 컬럼 1, 고유 인덱스 1 이면 정상
select
  (select count(*) from information_schema.columns
     where table_schema='public' and table_name='cost_items' and column_name='client_id') as client_id_컬럼,
  (select count(*) from pg_indexes
     where schemaname='public' and indexname='cost_items_project_client_uq')               as 고유인덱스;
