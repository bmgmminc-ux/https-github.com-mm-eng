-- ════════════════════════════════════════════════════════════════════════
-- 감사 로그(audit_log) 정리 — 작성 2026-09-24 · 실행 2026-09-28(대표 승인 "순서대로 다시 진행")
--
-- 점검(2026-09-28, 읽기 전용 진단): DB 967MB · audit_log 948MB · 1,429,456행 · 기록 기간 2026-06-09 ~ 2026-09-13 · 최근 7일 0행
--   cost_items INSERT 689,035 · cost_items DELETE 688,906 · cost_items UPDATE 132      ← 삭제
--   billing_items INSERT 11,385 · billing_items DELETE 11,363                            ← 삭제
--   projects UPDATE 11,644 / INSERT 14 / DELETE 5 · vendors UPDATE 8,286 / INSERT 4,531 / DELETE 4,155   ← 보존(28,635행)
--   앱 동작 기록(table_name='app') 0행
-- 원인: fn_audit 트리거가 행 변경마다 변경 전·후 행 전체(JSON)를 기록하는데, 2단계(행 단위 동기화, 2026-09-13) 이전의 동기화는
--       현장의 매입 전부를 지우고 다시 넣는 방식이라 동기화 한 번에 매입 행 수만큼 DELETE·INSERT 기록이 쌓였다.
-- 조치: ① 매입·원가 분류·기성·기타수익 표의 트리거 기록 삭제(현장·거래처 기록 보존)
--       ② 같은 네 표의 감사 트리거 제거(행 변경마다 전체 행 JSON 을 남길 필요가 없다 — 앱 동작 기록으로 충분)
-- 방식: 대량 delete 는 삭제 행마다 로그(WAL)를 남겨 디스크를 잠시 두 배로 쓰고 vacuum full 이 따로 필요하다.
--       보존할 행만 임시 표로 옮긴 뒤 truncate → 되돌려 넣기를 한 트랜잭션으로 한다(공간 즉시 반환 · 중간 실패 시 전부 되돌아감).
-- 삭제는 되돌릴 수 없다.
-- ════════════════════════════════════════════════════════════════════════

create temp table _keep on commit drop as
  select * from public.audit_log
   where not (table_name in ('cost_items','project_costs','billing_items','other_income_items')
              and action in ('INSERT','UPDATE','DELETE'));
alter table _keep enable row level security;   -- 대시보드의 'RLS 없는 표 생성' 경고 회피(임시 표, 커밋 시 삭제)
truncate table public.audit_log;
insert into public.audit_log select * from _keep;

do $$
declare r record;
begin
  for r in
    select t.tgname, t.tgrelid::regclass as tbl
      from pg_trigger t
     where not t.tgisinternal
       and t.tgfoid = 'public.fn_audit'::regproc
       and t.tgrelid in ('public.cost_items'::regclass, 'public.project_costs'::regclass,
                         'public.billing_items'::regclass, 'public.other_income_items'::regclass)
  loop
    execute format('drop trigger if exists %I on %s', r.tgname, r.tbl);
  end loop;
end $$;

insert into public.schema_migrations(filename) values('20260924_audit_purge.sql') on conflict do nothing;

-- 확인(같은 트랜잭션 안이라 DB 전체 크기는 커밋 뒤 따로 본다)
select 1 as n, '남은 감사 행' as k, (select count(*) from public.audit_log)::text as v
union all select 2, '감사 표 크기', pg_size_pretty(pg_total_relation_size('public.audit_log'))
union all select 3, '남은 감사 트리거', coalesce((select string_agg(t.tgrelid::regclass::text, ', ' order by t.tgrelid::regclass::text)
                                              from pg_trigger t where not t.tgisinternal and t.tgfoid = 'public.fn_audit'::regproc), '(없음)')
order by 1;

-- ════════════════════════════════════════════════════════════════════════
-- 커밋 뒤 확인(따로 RUN):
--   select pg_size_pretty(pg_database_size(current_database())) as db_전체, pg_size_pretty(pg_total_relation_size('public.audit_log')) as 감사_표;
-- ════════════════════════════════════════════════════════════════════════
