# ㈜명문이엔지 회계앱 — 운영 RUNBOOK

> 단일 HTML 무빌드 앱. 라이브 https://myungmoon.netlify.app · 소스 `index.html`(이 리포 루트) · 백엔드 Supabase(ref `mauqgsoxbncnwumhysvf`) + Netlify Functions.
> 이 문서는 운영 임계지식의 단일 출처다. 기존엔 AI 세션 메모리에만 있어 리포 클론·신규 인원이 볼 수 없었음.

---

## 0. 절대 규율 (먼저 읽기)

1. **편집은 이 리포(`C:\deploy\publish`)의 `index.html`에서만.** `C:\deploy\mm-eng`는 동결 아카이브 — 편집·복사 금지(역방향 회귀 위험). 프리뷰도 publish를 서빙한다.
2. **라이브 배포는 대표 '배포' 동의 후에만.** AI는 commit까지, push는 대표 승인 후.
3. **DB 스키마 변경(.sql)은 대표가 SQL Editor에서 직접 RUN.** AI는 .sql 파일 작성만(라이브 DB 직접쓰기 불가).
4. **API 키·시크릿은 채팅 금지.** Edge Function 시크릿 / Netlify env 에만. (예: OCR용 `ANTHROPIC_API_KEY`)
5. **데모/시드/샘플 데이터 생성 금지.** 실데이터 운영 중. 빈 화면은 0/정직 빈상태.
6. **프리뷰(localhost)는 라이브 DB에 연결 안 됨**(getSupabaseClient localhost 가드). 쓰기경로 테스트는 가짜 Supabase 클라이언트 주입으로.

---

## 1. 배포 (라이브 반영)

1. `index.html` 편집(publish에서 직접).
2. 검증 체크리스트(§5) 통과.
3. `publish\_commitmsg.txt` 에 커밋 메시지 작성(멀티라인 가능).
4. **대표 '배포' 동의** 후 PowerShell:
   ```
   C:\deploy\deploy.ps1                      # 태그 없이
   C:\deploy\deploy.ps1 -Tag v2026-MMDD-요약  # 릴리스 태그까지
   ```
   동작: `pull --ff-only → add index.html → commit -F → (태그) → push → push --tags`. node/CLI 불필요(git만). Netlify CI가 main push 감지해 자동 빌드(~1분).
5. 빌드 후 라이브 마커 확인(§5-④).

> functions/netlify.toml 등 index.html 외 파일을 바꿨으면 deploy.ps1 대신 수동으로 `git add <파일>` 후 커밋.

---

## 2. 롤백

- **코드 되돌리기**: `git -C C:\deploy\publish checkout <tag>` (안정 태그 목록 `git tag -l`). 첫 안정 태그 = `v2026-0618`.
- **라이브 즉시 되돌리기**: Netlify 대시보드 → Deploys → 직전 정상 deploy → **Publish deploy** (빌드·node 불필요, 1클릭). *주의: Netlify deploy 보존은 약 30일 — 그보다 오래된 좌표는 git tag로.*
- **위험 배포 직전**: Netlify 'Lock auto-publish'로 잠그고 검증 후 발행.

---

## 3. DB 스키마 변경 (마이그레이션)

- 마이그레이션 .sql = `supabase/migrations/` (파일명순 = 적용순서). **단일 소스 — base 스키마까지 포함**:
  - `00000000_schema_migrations.sql` : 적용추적 테이블(최초 1회 RUN).
  - `00001_base_schema.sql` / `00002_base_phase1.sql` : 기반 스키마(원본 supabase-schema*.sql 편입). **00001은 신규/빈 DB 전용**(정책 drop-가드 없음 → 기존 DB 재실행 시 정책 중복 오류, 라이브엔 이미 적용됨). 00002·증분은 멱등.
  - `20260609_*` ~ `20260614_*` : 증분(컬럼/테이블 추가, 전부 `if not exists` 멱등).
- **신규 변경 절차**: ① `supabase/migrations/YYYYMMDD_name.sql` 작성(AI) ② 파일 끝에 자기기록 1줄 추가:
  ```
  insert into public.schema_migrations(filename) values('YYYYMMDD_name.sql') on conflict (filename) do nothing;
  ```
  ③ **대표가 SQL Editor에서 RUN** ④ commit.
- **적용현황 확인(메모)**: `select * from public.schema_migrations order by filename;`
- **무결성 점검(실제)**: `99_verify_schema.sql` RUN — 핵심 테이블/컬럼이 라이브 DB에 진짜 있는지(present=true). 기록과 실제를 대조.
- **신규 환경 재구축**: migrations 를 **파일명순**으로 RUN(00001 base → 00002 → 증분). 빈 DB라 00001 정책도 정상 생성. 끝에 `99_verify_schema.sql`로 확인.

---

## 4. 백업 / 복구

- **1차(자동·상시)**: 앱의 push/pull 동기화가 localStorage ↔ Supabase 미러. 정상 동작이 곧 1차 백업.
- **2차(오프사이트·수동)**: **주 1회** 앱에서 `mmBackup`(설정/도구 화면의 백업 버튼)으로 JSON 받아 **외부 드라이브(C:\deploy 밖)** 로 반출. Supabase 무료플랜은 자동백업 0이므로 이 습관이 마지막 방어선.
  - 백업 키엔 회사정보·사업자등록증/도장 이미지·이름→uuid 매핑(`mm-cloud-id-map`) 포함(2026-06-18 보강, `e78e26a`).
- **첨부 원본**(`mm-attachments` 버킷): 증빙 누적되면 Supabase 대시보드에서 주기적 버킷 백업 착수(현재 소량이면 후순위).
- **복구**: 앱 `mmRestore`로 백업 JSON 적용(localStorage 덮어쓰기 + reload).

---

## 5. 배포 전 검증 체크리스트

1. **파스검사** — 편집 후 프리뷰 로드 시 콘솔 에러 0 (문법 깨짐은 로드시점 발생).
2. **프리뷰 E2E** — 로컬(8778, publish 서빙)에서 동작 확인. 실 클라우드 쓰기는 localhost 가드로 차단됨 — 쓰기경로는 가짜 클라이언트 주입으로 검증.
3. **diff 확인** — `git -C C:\deploy\publish diff` 로 의도한 변경만인지 육안 확인(단일 거대파일이라 diff가 묻히므로 변경 영역 명시).
4. **라이브 마커** — push·빌드 후 라이브 HTML에 변경 마커(고유 문자열) 존재 확인.
5. **태그** — 의미있는 릴리스면 `-Tag`로 롤백 좌표 남김.

---

## 6. 멀티 머신 규율 (분기 방지)

- 'MYUNGMOON본체' 등 다른 PC에도 **이 리포(publish) 클론**만 사용. mm-eng 식 편집본을 머신별로 두지 말 것.
- **작업 시작 전 `git pull`, 끝나면 `git push`.** `origin/main`이 유일 진실원.
- 1.1MB 단일 파일은 줄단위 자동 머지 불가 → **동시 두 머신 편집 금지**. 시작 전 `git fetch` 로 ahead/behind 확인.

---

## 7. 안전한 점진 개발 (쓰며 축적)

- 새 기능은 정적 플래그로 감싸 문제 시 즉시 폴백: `var FLAGS={ newX:false }; if(FLAGS.newX){…}`.
- 위험 경로는 `try/catch` + 구 로직 폴백. (스키마 깨짐 폴백 기구현: `attrib_cat`/`vendors.ceo` delete 후 재insert.)
- 커밋은 작게(기능/영역 단위) — 단일파일 diff 한계의 최선 완화.

---

## 8. 역할 / 승인 게이트

| 영역 | AI(Claude) | 대표(게이트키퍼) |
|---|---|---|
| 코드 편집 | 인플레이스 수정·diff 제시 | — |
| 라이브 push | commit까지 | **'배포' 동의 후** deploy.ps1 |
| DB SQL RUN | .sql 작성만 | **SQL Editor 직접 RUN** |
| API 키/시크릿 | — | 직접 등록(채팅 금지) |

인원 합류 시: AI/주니어 = PR 작성까지, 대표 = 머지·RUN·시크릿. 게이트 구조 그대로 확장.

---

## 9. 미래 인원 합류 전 필수 (선제 경고)

- **계정 추가 = RLS 사고 트리거.** 현재 한 DB에 owner-격리(`app_settings`·`attachments`)와 회사-공유(`dunning_queue`·`alert_recipients`·`thresholds`, `auth.role()='authenticated'`)가 **혼재**.
- 직원 계정 1개라도 추가하기 **전에** RLS 모델을 1종으로 통일(회사 테넌트 컬럼 또는 owner_id 일원화). 안 하면 회사-공유 테이블이 전 직원 상호 R/W/D 가능.

---

## 10. 결정 기록 (ADR — 큰 결정만 1줄씩 누적)

- **ADR-001** 단일 HTML 무빌드 유지 — 프레임워크 빌드 도입 안 함(운영 단순성).
- **ADR-002** v1 React 빌드 부분 추출 금지(불가침) — 인플레이스 수정만.
- **ADR-003 (2026-06-18)** 편집 일원화 — mm-eng↔publish 이원화 폐지, publish 직접 편집.
- **ADR-004 (2026-06-18)** 프리뷰 localhost는 라이브 Supabase 미연결(코드 가드).
- **ADR-005** 신규 도구(staging DB·supabase CLI·멀티계정) 미도입 — 1인+AI·node없음 환경상 부담 과다. 필요해질 때 재검토.
