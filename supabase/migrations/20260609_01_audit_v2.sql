-- ════════════════════════════════════════════════════════════════
-- 명문이엔지 v23 — 데이터 무결성 감사 후속 스키마 (재감사 반영본)
-- Supabase 대시보드 → SQL Editor 에 붙여넣고 RUN
-- 모두 "add column if not exists" 라 재실행해도 안전
-- ════════════════════════════════════════════════════════════════

-- [cost_items] 매입 항목 누락 컬럼
--   worker_name : 일용직 이름(거래처 대신 사람명으로 기록한 노무 매입)   [감사 #4]
--   contract_amt: 직접도급 계약금액                                       [감사 #7]
--   deduction   : 직불 공제액                                             [감사 #7]
--   created_at  : 등록일 (doc_date 단일컬럼 합치기 폐기, 분리 보존)       [재감사 rank6]
--   paid_date   : 지급일 (지급일 날조 방지)                               [재감사 rank6]
alter table public.cost_items
  add column if not exists worker_name  text,
  add column if not exists contract_amt bigint default 0,
  add column if not exists deduction    bigint default 0,
  add column if not exists created_at   timestamptz,
  add column if not exists paid_date    date;

-- [projects] 계약/원가 분산 항목(budgetItems) 동기화용 jsonb 1컬럼      [감사 #3]
--   (created_at 은 이미 default now() 로 존재 — 재사용)                  [재감사 rank7]
alter table public.projects
  add column if not exists budget_items jsonb default '[]'::jsonb;

-- [other_income_items] 등록일 (선택, low) — 테이블 미존재(42P01)로 보류.
--   기타수익 동기화 자체가 안 되고 있을 수 있음(별도 이슈 — 테이블 생성으로 후속 처리).
-- alter table public.other_income_items
--   add column if not exists created_at timestamptz;

-- 확인용(선택)
-- select table_name, column_name from information_schema.columns
--  where table_schema='public'
--    and ((table_name='cost_items'        and column_name in ('worker_name','contract_amt','deduction','created_at','paid_date'))
--      or (table_name='projects'          and column_name in ('budget_items'))
--      or (table_name='other_income_items' and column_name in ('created_at')))
--  order by table_name, column_name;
