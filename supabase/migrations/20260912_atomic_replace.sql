-- ════════════════════════════════════════════════════════════════════════
-- 1단계 · 매입·기타수익 업로드 원자화 — 중복 폭주를 구조적으로 차단
-- 2026-09-12. Supabase → SQL Editor 에 붙여넣고 RUN. 여러 번 실행해도 안전.
--
-- [무엇이 문제였나]
--   앱은 저장할 때마다 그 현장의 매입을 "전부 지우기" 요청과 "전부 넣기" 요청,
--   두 번의 별개 통신으로 교체한다. 두 사람(또는 두 창)이 동시에 저장하면
--       A지우기 → B지우기 → A넣기 → B넣기
--   순서가 되어 A와 B의 자료가 두 벌로 남는다. 매입 표에는 이를 막을 제약이 없어
--   조용히 쌓이고, 다음 내려받기가 그 수를 로컬에 굳혀 되돌아오지 않는다.
--   기성 청구는 unique(project_id, round_no) 가, 원가 분류는 unique(project_id, category) 가
--   막아냈다. 매입과 기타수익만 무방비였다.
--
-- [이 함수가 하는 일]
--   지우기와 넣기를 하나의 트랜잭션으로 묶는다. 그리고 같은 현장에 대한 동시 호출을
--   줄 세운다. 창이 몇 개든, 기기가 몇 대든, 결과는 항상 "마지막에 저장한 쪽의 자료"
--   한 벌뿐이다. 두 벌이 남는 경우가 생길 수 없다.
--
--   줄 세우기(advisory lock)가 반드시 필요하다. 없으면 뒤에 들어온 트랜잭션의 DELETE 가
--   앞 트랜잭션이 방금 넣은 행을 보지 못해(READ COMMITTED 스냅샷) 그대로 두 벌이 남는다.
--
-- [권한] security invoker — 호출자의 RLS 정책이 그대로 적용된다. 권한이 넓어지지 않는다.
--
-- [실행 순서] 이 SQL 을 먼저 실행하고 그 다음에 앱을 배포한다.
--             구버전 앱은 예전 경로를 그대로 쓰므로 이 SQL 만 먼저 돌려도 아무 문제 없다.
-- ════════════════════════════════════════════════════════════════════════


-- ── 매입 ────────────────────────────────────────────────────────────────
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

  -- 같은 현장에 대한 동시 호출을 줄 세운다(트랜잭션 종료 시 자동 해제)
  perform pg_advisory_xact_lock(hashtext('mm_cost_items'), hashtext(p_project_id));

  delete from public.cost_items where project_id = p_project_id;

  if p_rows is not null and jsonb_typeof(p_rows) = 'array' and jsonb_array_length(p_rows) > 0 then
    insert into public.cost_items (
      project_id, type, vendor, worker_name, desc_text,
      supply_amt, tax, total, paid_amount, contract_amt, deduction,
      attrib_cat, doc_date, paid_date, created_at, memo
    )
    select
      p_project_id,                       -- 배열에 섞인 다른 현장 id 는 무시하고 인자로 고정
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


-- ── 기타수익 ────────────────────────────────────────────────────────────
-- 매입과 완전히 같은 모양이었고, 오히려 오류를 화면에 알리지도 않던 자리다.
create or replace function public.mm_replace_other_income_items(
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

  perform pg_advisory_xact_lock(hashtext('mm_other_income_items'), hashtext(p_project_id));

  delete from public.other_income_items where project_id = p_project_id;

  if p_rows is not null and jsonb_typeof(p_rows) = 'array' and jsonb_array_length(p_rows) > 0 then
    insert into public.other_income_items (
      project_id, vendor, desc_text, supply_amt, tax, total,
      received, received_date, memo
    )
    select
      p_project_id,
      x.vendor, x.desc_text,
      coalesce(x.supply_amt, 0), coalesce(x.tax, 0), coalesce(x.total, 0),
      coalesce(x.received, 0), x.received_date, x.memo
    from jsonb_populate_recordset(null::public.other_income_items, p_rows) x;
    get diagnostics v_inserted = row_count;
  end if;

  return v_inserted;
end;
$$;


-- ── 실행 권한 ───────────────────────────────────────────────────────────
-- Postgres 는 새 함수에 PUBLIC 실행 권한을 기본으로 준다. anon 만 빼면 PUBLIC 경로로 여전히 호출된다.
-- 그래서 PUBLIC 과 anon 을 먼저 거두고, 로그인한 사용자(authenticated)에게만 다시 준다.
revoke execute on function public.mm_replace_cost_items(text, jsonb)         from public, anon;
revoke execute on function public.mm_replace_other_income_items(text, jsonb) from public, anon;
grant  execute on function public.mm_replace_cost_items(text, jsonb)         to authenticated;
grant  execute on function public.mm_replace_other_income_items(text, jsonb) to authenticated;


-- ── 적용 기록 ───────────────────────────────────────────────────────────
insert into public.schema_migrations(filename) values('20260912_atomic_replace.sql')
  on conflict do nothing;


-- ── 확인 ────────────────────────────────────────────────────────────────
-- 아래가 2행 나오면 정상.
select p.proname as 함수, pg_get_function_identity_arguments(p.oid) as 인자
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname like 'mm_replace_%'
 order by 1;
