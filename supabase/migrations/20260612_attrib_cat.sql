-- ════════════════════════════════════════════════════════════════
-- cost_items.attrib_cat — 직불 행의 '귀속 공종' 클라우드 동기화
-- Supabase 대시보드 → SQL Editor 에 붙여넣고 RUN. 재실행해도 안전.
--
-- 용도: 직불금·인건비직불금 매입 행이 어느 공종(외주비/인건비 등)의
--       원가인지 기록 → 예산 분석에서 해당 공종 원가로 합산.
-- 코드는 이미 배포됨 — 컬럼이 없어도 자동 폴백(로컬 보존, 동기화만 생략).
-- 이 컬럼이 생기면 기기 간에도 귀속 공종이 동기화됩니다.
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.cost_items ADD COLUMN IF NOT EXISTS attrib_cat text;

-- 검증: 1행 나오면 정상
SELECT column_name, data_type FROM information_schema.columns
WHERE table_schema='public' AND table_name='cost_items' AND column_name='attrib_cat';
