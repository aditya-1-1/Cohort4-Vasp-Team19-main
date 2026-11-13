-- Migration: 005_add_ai_evaluation_metadata.sql
-- Description: Adds production AI evaluation provider, execution mode, schema version, and detailed evaluation payload.

ALTER TABLE public.rehearsals
ADD COLUMN IF NOT EXISTS evaluation_provider text DEFAULT 'google_gemini',
ADD COLUMN IF NOT EXISTS model_id text DEFAULT 'gemini-3.5-flash-lite',
ADD COLUMN IF NOT EXISTS execution_mode text DEFAULT 'online',
ADD COLUMN IF NOT EXISTS evaluation_schema_version text DEFAULT '1.0',
ADD COLUMN IF NOT EXISTS evaluation_result jsonb;

CREATE INDEX IF NOT EXISTS rehearsals_evaluation_provider ON public.rehearsals (evaluation_provider);
CREATE INDEX IF NOT EXISTS rehearsals_execution_mode ON public.rehearsals (execution_mode);

