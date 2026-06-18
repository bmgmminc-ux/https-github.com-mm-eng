-- ════════════════════════════════════════════════════════════════
-- dunning_queue — 미수금 독촉 큐 클라우드 동기화
-- Supabase 대시보드 → SQL Editor 에 붙여넣고 RUN. 재실행해도 안전.
-- 코드(mmSyncPushPhase1/PullPhase1 + 등록·발송 시 자동 push)는 이미 배포됨
-- → 이 테이블만 생기면 동기화 작동. 실행 전까지는 자동 no-op(로컬 전용, 에러 없음).
-- 골격은 alert_recipients와 동일 (RLS = 인증 사용자 회사공유).
-- ════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.dunning_queue (
  id          BIGSERIAL PRIMARY KEY,
  target      TEXT,                          -- 수신 대상 (발주처/현장)
  status      TEXT,                          -- '발송 대기 ...' | '발송 완료 <ISO>'
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.dunning_queue ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "auth all dunning" ON public.dunning_queue;
CREATE POLICY "auth all dunning" ON public.dunning_queue
  FOR ALL USING (auth.role() = 'authenticated') WITH CHECK (auth.role() = 'authenticated');

-- realtime (선택)
DO $$ BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.dunning_queue;
  EXCEPTION WHEN others THEN NULL;
  END;
END $$;

-- 검증: 1행 나오면 정상
SELECT tablename, rowsecurity AS rls_on FROM pg_tables
WHERE schemaname='public' AND tablename='dunning_queue';
