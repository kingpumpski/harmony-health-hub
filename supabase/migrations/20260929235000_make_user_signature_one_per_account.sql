DROP INDEX IF EXISTS public.user_document_signatures_active_uq;
CREATE UNIQUE INDEX IF NOT EXISTS user_document_signatures_user_uq ON public.user_document_signatures(user_id);