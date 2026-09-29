-- ════════════════════════════════════════════════════════════════════════
-- 가상 현장 9개 삭제 — 2026-09-13 실증 테스트용으로 앱 올리기 경로로 넣은 가상 데이터 정리(대표 지시 2026-09-28)
-- 대상: 명문-9101~9103(2024) · 9201~9203(2025) · 9301~9303(2026) 중 이름이 '가상'으로 시작하는 행만(오삭제 방지).
-- 사전 확인(2026-09-28, 읽기 전용): 전체 현장 9곳 = 전부 대상 · 매입 129 · 기성 22 · 원가 분류 81 · 재무 9 · 기타수익 0 · 출역 0 · 첨부 0
--   · 거래처·일용직 마스터에 '가상' 이름 0건.
-- 하위 표도 같은 조건으로 먼저 지우고 현장을 지운다(외래키 cascade 에 기대지 않음). 한 번 실행 = 한 트랜잭션(중간 실패 시 전부 되돌아감).
-- 되돌릴 수 없다. SQL Editor 에서 대표가 실행(Ctrl+Enter → '쿼리 실행').
-- ════════════════════════════════════════════════════════════════════════

delete from public.cost_items         where project_id in (select id from public.projects where id in ('명문-9101','명문-9102','명문-9103','명문-9201','명문-9202','명문-9203','명문-9301','명문-9302','명문-9303') and name like '가상%');
delete from public.billing_items      where project_id in (select id from public.projects where id in ('명문-9101','명문-9102','명문-9103','명문-9201','명문-9202','명문-9203','명문-9301','명문-9302','명문-9303') and name like '가상%');
delete from public.other_income_items where project_id in (select id from public.projects where id in ('명문-9101','명문-9102','명문-9103','명문-9201','명문-9202','명문-9203','명문-9301','명문-9302','명문-9303') and name like '가상%');
delete from public.project_costs      where project_id in (select id from public.projects where id in ('명문-9101','명문-9102','명문-9103','명문-9201','명문-9202','명문-9203','명문-9301','명문-9302','명문-9303') and name like '가상%');
delete from public.project_finance    where project_id in (select id from public.projects where id in ('명문-9101','명문-9102','명문-9103','명문-9201','명문-9202','명문-9203','명문-9301','명문-9302','명문-9303') and name like '가상%');
delete from public.attachments        where project_id in (select id from public.projects where id in ('명문-9101','명문-9102','명문-9103','명문-9201','명문-9202','명문-9203','명문-9301','명문-9302','명문-9303') and name like '가상%');
delete from public.projects           where id in ('명문-9101','명문-9102','명문-9103','명문-9201','명문-9202','명문-9203','명문-9301','명문-9302','명문-9303') and name like '가상%';

insert into public.schema_migrations(filename) values('20260928_delete_virtual_sites.sql') on conflict do nothing;

select 1 as n, '남은 현장' as k, (select count(*) from public.projects)::text as v
union all select 2, '남은 매입', (select count(*) from public.cost_items)::text
union all select 3, '남은 기성', (select count(*) from public.billing_items)::text
union all select 4, '남은 원가 분류', (select count(*) from public.project_costs)::text
union all select 5, '남은 재무', (select count(*) from public.project_finance)::text
order by 1;
