-- ════════════════════════════════════════════════════════════════════════
-- 2단계-2 · 행 단위 동기화 — "전부 지우고 다시 넣기" 를 "바뀐 행만 덮어쓰기 + 사라진 행만 지우기" 로
-- 2026-09-13. Supabase → SQL Editor 에서 RUN. 여러 번 실행해도 안전.
--
-- [왜] 지금까지는 저장할 때마다 그 현장의 매입 전체를 갈아끼웠다. 두 사람이 같은 현장을 쓰면
--      나중에 저장한 사람의 사본이 먼저 저장한 사람의 새 행을 통째로 밀어냈다(소실).
--      앱은 이제 '마지막 동기화 시점 사본'과 비교해 바뀐 행과 사라진 행만 보낸다. 이 함수는
--      그 두 목록을 한 트랜잭션으로 처리한다. 남이 넣은 행은 건드리지 않는다.
-- [전제] cost_items.client_id + unique(project_id, client_id) (20260913_client_id.sql)
-- ════════════════════════════════════════════════════════════════════════

create or replace function public.mm_upsert_cost_items(
  p_project_id text,
  p_rows       jsonb,
  p_delete_ids text[]
) returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_up  integer := 0;
  v_del integer := 0;
  v_legacy integer := 0;
begin
  if p_project_id is null or length(p_project_id) = 0 then
    raise exception 'project_id 가 비어 있습니다';
  end if;

  perform pg_advisory_xact_lock(hashtext('mm_cost_items'), hashtext(p_project_id));

  -- 앱이 명시적으로 지운 행
  if p_delete_ids is not null and array_length(p_delete_ids, 1) > 0 then
    delete from public.cost_items
     where project_id = p_project_id and client_id = any(p_delete_ids);
    get diagnostics v_del = row_count;
  end if;

  -- 번호 없는 옛 행은 앱이 추적할 수 없다 — 내려받은 뒤 번호를 받아 다시 올라오므로 여기서 정리
  delete from public.cost_items where project_id = p_project_id and client_id is null;
  get diagnostics v_legacy = row_count;

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
    where x.type is not null
    on conflict (project_id, client_id) where client_id is not null do update set
      type = excluded.type, vendor = excluded.vendor, worker_name = excluded.worker_name,
      desc_text = excluded.desc_text, supply_amt = excluded.supply_amt, tax = excluded.tax,
      total = excluded.total, paid_amount = excluded.paid_amount, contract_amt = excluded.contract_amt,
      deduction = excluded.deduction, attrib_cat = excluded.attrib_cat, doc_date = excluded.doc_date,
      paid_date = excluded.paid_date, memo = excluded.memo;
    get diagnostics v_up = row_count;
  end if;

  return jsonb_build_object('upserted', v_up, 'deleted', v_del, 'legacy_removed', v_legacy);
end;
$$;

-- 기성 청구는 회차 번호가 위치(순서)라서 행 단위 병합이 성립하지 않는다 → 현장 단위 원자적 치환으로 통일
create or replace function public.mm_replace_billing_items(
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

  perform pg_advisory_xact_lock(hashtext('mm_billing_items'), hashtext(p_project_id));

  delete from public.billing_items where project_id = p_project_id;

  if p_rows is not null and jsonb_typeof(p_rows) = 'array' and jsonb_array_length(p_rows) > 0 then
    insert into public.billing_items (
      project_id, round_no, apply_date, apply_supply, apply_tax, apply_total,
      receive_date, billing_amount, advance_amount, memo
    )
    select
      p_project_id, x.round_no, x.apply_date,
      coalesce(x.apply_supply, 0), coalesce(x.apply_tax, 0), coalesce(x.apply_total, 0),
      x.receive_date, coalesce(x.billing_amount, 0), coalesce(x.advance_amount, 0), x.memo
    from jsonb_populate_recordset(null::public.billing_items, p_rows) x
    where x.round_no is not null;
    get diagnostics v_inserted = row_count;
  end if;

  return v_inserted;
end;
$$;

revoke execute on function public.mm_upsert_cost_items(text, jsonb, text[]) from public, anon;
revoke execute on function public.mm_replace_billing_items(text, jsonb)      from public, anon;
grant  execute on function public.mm_upsert_cost_items(text, jsonb, text[]) to authenticated;
grant  execute on function public.mm_replace_billing_items(text, jsonb)      to authenticated;

insert into public.schema_migrations(filename) values('20260913_row_sync.sql')
  on conflict do nothing;

-- 확인: 함수 3개(upsert_cost / replace_billing / replace_other_income / replace_cost 포함 4행) 나오면 정상
select p.proname as fn, pg_get_function_identity_arguments(p.oid) as args
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname like 'mm_%'
 order by 1;
