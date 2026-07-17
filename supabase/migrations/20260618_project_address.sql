-- ════════════════════════════════════════════════════════════════
-- 20260618_project_address — 현장(projects) 주소·좌표 [영업 지도 ①]
-- Supabase 대시보드 → SQL Editor 에 붙여넣고 RUN. 재실행해도 안전(idempotent).
--
-- 목적: 영업 지도(카카오)에 현장을 마커로 찍으려면 현장마다 주소와 좌표가 필요.
--       address = 카카오 주소검색으로 선택한 도로명/지번 주소
--       lat/lng  = 주소를 카카오 지오코더로 변환한 위경도 (지도 마커 좌표)
-- 코드: 컬럼이 없어도 앱은 정상 동작(push 시 해당 필드 자동 제외 폴백) —
--       이 SQL을 RUN해야 주소·좌표가 클라우드에 동기화되고 멀티기기에서 보임.
-- ════════════════════════════════════════════════════════════════

alter table public.projects add column if not exists address text;
alter table public.projects add column if not exists lat double precision;
alter table public.projects add column if not exists lng double precision;

-- 지도 조회용 (좌표 있는 현장만 빠르게)
create index if not exists idx_projects_latlng on public.projects(lat, lng);

-- 자기기록 (적용 추적)
insert into public.schema_migrations(filename) values('20260618_project_address.sql')
  on conflict (filename) do nothing;

-- 검증: 3행(address, lat, lng) 나오면 정상
select column_name, data_type from information_schema.columns
where table_schema='public' and table_name='projects'
  and column_name in ('address','lat','lng')
order by column_name;
