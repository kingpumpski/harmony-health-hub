-- Localized diagnosis architecture: keep each clinical standard independent and connect them through mappings.
CREATE TABLE IF NOT EXISTS public.diagnosis_standards (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), code text NOT NULL UNIQUE, name text NOT NULL, jurisdiction text NOT NULL,
 version text, publisher text, source_uri text, effective_from date, effective_to date,
 is_default boolean NOT NULL DEFAULT false, is_active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.stg_diagnoses (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), standard_id uuid NOT NULL REFERENCES public.diagnosis_standards(id) ON DELETE CASCADE,
 code text NOT NULL, display_name text NOT NULL, description text, category text, synonyms text[] NOT NULL DEFAULT '{}',
 icd10_code_id uuid REFERENCES public.icd_codes(id) ON DELETE SET NULL, source_reference text,
 is_active boolean NOT NULL DEFAULT true, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(standard_id,code)
);
CREATE TABLE IF NOT EXISTS public.diagnosis_standard_mappings (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), stg_diagnosis_id uuid NOT NULL REFERENCES public.stg_diagnoses(id) ON DELETE CASCADE,
 icd10_code_id uuid NOT NULL REFERENCES public.icd_codes(id) ON DELETE CASCADE,
 mapping_type text NOT NULL DEFAULT 'exact' CHECK (mapping_type IN ('exact','broader','narrower','related','approximate')),
 confidence numeric(5,4) CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1), source_reference text,
 reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL, reviewed_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(stg_diagnosis_id,icd10_code_id)
);
CREATE TABLE IF NOT EXISTS public.facility_diagnosis_standards (
 facility_id uuid NOT NULL REFERENCES public.healthcare_facilities(id) ON DELETE CASCADE,
 standard_id uuid NOT NULL REFERENCES public.diagnosis_standards(id) ON DELETE CASCADE,
 priority integer NOT NULL DEFAULT 100 CHECK (priority >= 0), is_active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(facility_id,standard_id)
);
INSERT INTO public.diagnosis_standards(code,name,jurisdiction,version,publisher,source_uri,is_default)
VALUES('GH-STG','Ghana Standard Treatment Guidelines','Ghana','7th Edition (2017)','Ghana National Drugs Programme / Ministry of Health','https://www.moh.gov.gh/wp-content/uploads/2020/07/GHANA-STG-2017-1.pdf',true)
ON CONFLICT(code) DO UPDATE SET name=EXCLUDED.name,jurisdiction=EXCLUDED.jurisdiction,version=EXCLUDED.version,publisher=EXCLUDED.publisher,source_uri=EXCLUDED.source_uri,is_default=true,is_active=true,updated_at=now();
CREATE INDEX IF NOT EXISTS idx_stg_diagnoses_standard_code ON public.stg_diagnoses(standard_id,code);
CREATE INDEX IF NOT EXISTS idx_stg_diagnoses_name ON public.stg_diagnoses USING gin(to_tsvector('simple',display_name));
CREATE INDEX IF NOT EXISTS idx_diagnosis_standard_mappings_stg ON public.diagnosis_standard_mappings(stg_diagnosis_id);
CREATE INDEX IF NOT EXISTS idx_diagnosis_standard_mappings_icd ON public.diagnosis_standard_mappings(icd10_code_id);
CREATE INDEX IF NOT EXISTS idx_facility_diagnosis_standards_priority ON public.facility_diagnosis_standards(facility_id,priority);
ALTER TABLE public.diagnosis_standards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stg_diagnoses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.diagnosis_standard_mappings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.facility_diagnosis_standards ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS diagnosis_standards_authenticated_read ON public.diagnosis_standards;
CREATE POLICY diagnosis_standards_authenticated_read ON public.diagnosis_standards FOR SELECT TO authenticated USING(is_active=true);
DROP POLICY IF EXISTS stg_diagnoses_authenticated_read ON public.stg_diagnoses;
CREATE POLICY stg_diagnoses_authenticated_read ON public.stg_diagnoses FOR SELECT TO authenticated USING(is_active=true);
DROP POLICY IF EXISTS diagnosis_standard_mappings_authenticated_read ON public.diagnosis_standard_mappings;
CREATE POLICY diagnosis_standard_mappings_authenticated_read ON public.diagnosis_standard_mappings FOR SELECT TO authenticated USING(true);
DROP POLICY IF EXISTS facility_diagnosis_standards_authenticated_read ON public.facility_diagnosis_standards;
CREATE POLICY facility_diagnosis_standards_authenticated_read ON public.facility_diagnosis_standards FOR SELECT TO authenticated USING(is_active=true);
CREATE OR REPLACE FUNCTION public.search_clinical_diagnoses(_query text,_facility_id uuid DEFAULT NULL,_limit integer DEFAULT 20)
RETURNS TABLE(source text,diagnosis_id uuid,code text,display_name text,icd10_code text,standard_code text,standard_name text,match_rank integer)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public AS $$
WITH q AS(SELECT lower(trim(coalesce(_query,''))) term), stg AS(
 SELECT 'stg'::text source,s.id diagnosis_id,s.code,s.display_name,icd.code icd10_code,ds.code standard_code,ds.name standard_name,
 CASE WHEN lower(s.code)=q.term OR lower(s.display_name)=q.term THEN 100 WHEN lower(s.code) LIKE q.term||'%' OR lower(s.display_name) LIKE q.term||'%' THEN 90 WHEN lower(s.display_name) LIKE '%'||q.term||'%' THEN 70 ELSE 50 END match_rank
 FROM public.stg_diagnoses s JOIN public.diagnosis_standards ds ON ds.id=s.standard_id LEFT JOIN public.icd_codes icd ON icd.id=s.icd10_code_id CROSS JOIN q
 WHERE s.is_active AND ds.is_active AND q.term<>'' AND(lower(s.code) LIKE '%'||q.term||'%' OR lower(s.display_name) LIKE '%'||q.term||'%' OR EXISTS(SELECT 1 FROM unnest(s.synonyms) x WHERE lower(x) LIKE '%'||q.term||'%'))
 AND(_facility_id IS NULL OR EXISTS(SELECT 1 FROM public.facility_diagnosis_standards fds WHERE fds.facility_id=_facility_id AND fds.standard_id=s.standard_id AND fds.is_active))
), icd AS(
 SELECT 'icd10'::text source,i.id diagnosis_id,i.code,i.description display_name,i.code icd10_code,'ICD10' standard_code,'WHO ICD-10' standard_name,
 CASE WHEN lower(i.code)=q.term THEN 80 WHEN lower(i.code) LIKE q.term||'%' OR lower(i.description) LIKE q.term||'%' THEN 60 ELSE 40 END match_rank
 FROM public.icd_codes i CROSS JOIN q WHERE q.term<>'' AND(lower(i.code) LIKE '%'||q.term||'%' OR lower(i.description) LIKE '%'||q.term||'%')
 AND NOT EXISTS(SELECT 1 FROM stg s WHERE s.icd10_code=i.code)
)
SELECT * FROM(SELECT * FROM stg UNION ALL SELECT * FROM icd)x ORDER BY match_rank DESC,(source='stg') DESC,display_name LIMIT greatest(1,least(coalesce(_limit,20),100));
$$;
REVOKE ALL ON FUNCTION public.search_clinical_diagnoses(text,uuid,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.search_clinical_diagnoses(text,uuid,integer) TO authenticated;
NOTIFY pgrst,'reload schema';
