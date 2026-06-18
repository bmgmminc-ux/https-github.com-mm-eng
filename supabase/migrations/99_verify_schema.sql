-- ════════════════════════════════════════════════════════════════
-- 99_verify_schema — 스키마 무결성 점검 (마이그레이션 ≠ 적용, 둘 분리 확인)
-- Supabase 대시보드 → SQL Editor 에 붙여넣고 RUN. 읽기 전용(변경 없음), 언제든 안전.
--
-- 용도: 마이그레이션이 만들었어야 할 핵심 테이블/컬럼이 라이브 DB에 '실제' 존재하는지.
--       모든 행 present=true 면 정상. false 가 있으면 해당 마이그레이션을 RUN.
--       (00000000_schema_migrations 의 기록은 '돌렸다는 메모', 이 쿼리는 '진짜 있나' 확인 — 둘 대조)
-- 주의: base 테이블 목록은 핵심 위주(전수 아님). 컬럼 체크는 증분 마이그레이션 산출물.
-- ════════════════════════════════════════════════════════════════

with expected(label, kind, t, c) as (
  values
    -- base / phase1 핵심 테이블
    ('projects (base)',           'table',  'projects',           null),
    ('project_costs (base)',      'table',  'project_costs',      null),
    ('cost_items (base)',         'table',  'cost_items',         null),
    ('billing_items (base)',      'table',  'billing_items',      null),
    ('vendors (base)',            'table',  'vendors',            null),
    ('workers (base)',            'table',  'workers',            null),
    ('attendance (base)',         'table',  'attendance',         null),
    ('alert_recipients',          'table',  'alert_recipients',   null),
    ('thresholds',                'table',  'thresholds',         null),
    -- 증분 마이그레이션 산출 테이블
    ('other_income_items',        'table',  'other_income_items', null),
    ('app_settings',              'table',  'app_settings',       null),
    ('attachments',               'table',  'attachments',        null),
    ('dunning_queue',             'table',  'dunning_queue',      null),
    ('schema_migrations',         'table',  'schema_migrations',  null),
    -- 증분 마이그레이션 산출 컬럼
    ('cost_items.attrib_cat',     'column', 'cost_items',  'attrib_cat'),
    ('cost_items.worker_name',    'column', 'cost_items',  'worker_name'),
    ('cost_items.contract_amt',   'column', 'cost_items',  'contract_amt'),
    ('cost_items.deduction',      'column', 'cost_items',  'deduction'),
    ('cost_items.paid_date',      'column', 'cost_items',  'paid_date'),
    ('projects.budget_items',     'column', 'projects',    'budget_items'),
    ('attachments.cost_item_id',  'column', 'attachments', 'cost_item_id')
)
select
  e.label,
  e.kind,
  case when e.kind = 'table'
       then exists(select 1 from information_schema.tables  where table_schema='public' and table_name=e.t)
       else exists(select 1 from information_schema.columns where table_schema='public' and table_name=e.t and column_name=e.c)
  end as present
from expected e
order by present asc, e.kind, e.label;   -- 누락(false)이 맨 위로

-- (참고용 — 위 결과 확인 후 개별로 실행)
-- 적용 기록:   select * from public.schema_migrations order by filename;
-- 정책 수:     select tablename, count(*) from pg_policies where schemaname='public' group by tablename order by tablename;
