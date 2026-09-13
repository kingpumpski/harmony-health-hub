


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE TYPE "public"."app_role" AS ENUM (
    'admin',
    'practitioner',
    'nurse',
    'midwife',
    'lab_technician',
    'pharmacist',
    'accountant',
    'front_desk',
    'canteen',
    'patient',
    'specialist_nurse'
);


ALTER TYPE "public"."app_role" OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."diagnoses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "encounter_id" "uuid" NOT NULL,
    "diagnosis" "text" NOT NULL,
    "is_principal" boolean DEFAULT false,
    "icd_code" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."diagnoses" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."add_encounter_diagnosis"("_encounter_id" "uuid", "_diagnosis" "text") RETURNS "public"."diagnoses"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ DECLARE result public.diagnoses; BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; IF NOT (public.has_role(auth.uid(),'admin'::public.app_role) OR public.has_role(auth.uid(),'practitioner'::public.app_role) OR public.has_role(auth.uid(),'nurse'::public.app_role) OR public.has_role(auth.uid(),'midwife'::public.app_role)) THEN RAISE EXCEPTION 'Not authorized to add diagnoses'; END IF; IF NOT EXISTS (SELECT 1 FROM public.encounters WHERE id=_encounter_id) THEN RAISE EXCEPTION 'Encounter does not exist'; END IF; IF NULLIF(trim(_diagnosis),'') IS NULL THEN RAISE EXCEPTION 'Diagnosis is required'; END IF; INSERT INTO public.diagnoses(encounter_id,diagnosis,is_principal) VALUES(_encounter_id,trim(_diagnosis),false) RETURNING * INTO result; RETURN result; END; $$;


ALTER FUNCTION "public"."add_encounter_diagnosis"("_encounter_id" "uuid", "_diagnosis" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."audit_patient_change"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ DECLARE old_json JSONB; new_json JSONB; changed JSONB; BEGIN old_json := CASE WHEN TG_OP IN ('UPDATE','DELETE') THEN to_jsonb(OLD) ELSE NULL END; new_json := CASE WHEN TG_OP IN ('INSERT','UPDATE') THEN to_jsonb(NEW) ELSE NULL END; IF TG_OP = 'UPDATE' THEN SELECT COALESCE(jsonb_object_agg(COALESCE(o.key, n.key), jsonb_build_object('old', o.value, 'new', n.value)) FILTER (WHERE o.value IS DISTINCT FROM n.value), '{}'::jsonb) INTO changed FROM jsonb_each(old_json) o FULL JOIN jsonb_each(new_json) n ON n.key = o.key; ELSE changed := '{}'::jsonb; END IF; INSERT INTO public.patient_audit(patient_id,actor_user_id,operation,changed_fields,old_record,new_record) VALUES (COALESCE(NEW.id, OLD.id),auth.uid(),TG_OP,changed,old_json,new_json); RETURN COALESCE(NEW, OLD); END; $$;


ALTER FUNCTION "public"."audit_patient_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_triage_bmi"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$ BEGIN IF NEW.weight_kg IS NOT NULL AND NEW.height_m IS NOT NULL AND NEW.height_m > 0 THEN NEW.bmi := ROUND((NEW.weight_kg / (NEW.height_m * NEW.height_m))::numeric, 2); ELSE NEW.bmi := NULL; END IF; RETURN NEW; END; $$;


ALTER FUNCTION "public"."calculate_triage_bmi"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_edit_patient_record"("_user_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role IN ('admin','practitioner','nurse','midwife','front_desk')); $$;


ALTER FUNCTION "public"."can_edit_patient_record"("_user_id" "uuid") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."appointments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "practitioner_id" "uuid",
    "department" "text",
    "scheduled_at" timestamp with time zone NOT NULL,
    "duration_minutes" integer DEFAULT 30,
    "reason" "text",
    "status" "text" DEFAULT 'scheduled'::"text" NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "attending_officer_id" "uuid",
    "claimed_at" timestamp with time zone,
    "treatment_status" "text" DEFAULT 'scheduled'::"text" NOT NULL,
    "treatment_notes" "text",
    "started_at" timestamp with time zone,
    "completed_at" timestamp with time zone
);

ALTER TABLE ONLY "public"."appointments" REPLICA IDENTITY FULL;


ALTER TABLE "public"."appointments" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."claim_appointment"("_appointment_id" "uuid") RETURNS "public"."appointments"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE result public.appointments;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(auth.uid(),'admin'::public.app_role) OR public.has_role(auth.uid(),'practitioner'::public.app_role) OR public.has_role(auth.uid(),'nurse'::public.app_role) OR public.has_role(auth.uid(),'midwife'::public.app_role) OR public.has_role(auth.uid(),'specialist_nurse'::public.app_role)) THEN RAISE EXCEPTION 'Only attending clinical officers may claim appointments'; END IF;
 UPDATE public.appointments SET attending_officer_id=auth.uid(), claimed_at=COALESCE(claimed_at,now()), treatment_status=CASE WHEN treatment_status='scheduled' THEN 'claimed' ELSE treatment_status END, updated_at=now() WHERE id=_appointment_id AND (attending_officer_id IS NULL OR attending_officer_id=auth.uid()) RETURNING * INTO result;
 IF result.id IS NULL THEN RAISE EXCEPTION 'Appointment is already assigned to another officer or does not exist'; END IF;
 RETURN result;
END; $$;


ALTER FUNCTION "public"."claim_appointment"("_appointment_id" "uuid") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."encounters" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "appointment_id" "uuid",
    "practitioner_id" "uuid",
    "encounter_type" "text" DEFAULT 'consultation'::"text",
    "symptoms" "text",
    "clerking_notes" "text",
    "principal_diagnosis" "text",
    "treatment_plan" "text",
    "follow_up_date" "date",
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "completed_at" timestamp with time zone
);


ALTER TABLE "public"."encounters" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."complete_encounter_workflow"("_encounter_id" "uuid") RETURNS "public"."encounters"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ DECLARE result public.encounters; BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; IF NOT (public.has_role(auth.uid(),'admin'::public.app_role) OR public.has_role(auth.uid(),'practitioner'::public.app_role) OR public.has_role(auth.uid(),'nurse'::public.app_role) OR public.has_role(auth.uid(),'midwife'::public.app_role)) THEN RAISE EXCEPTION 'Not authorized to complete encounters'; END IF; SELECT * INTO result FROM public.encounters WHERE id=_encounter_id FOR UPDATE; IF result.id IS NULL THEN RAISE EXCEPTION 'Encounter does not exist'; END IF; IF result.status='completed' THEN RETURN result; END IF; IF result.principal_diagnosis IS NULL OR NULLIF(trim(result.principal_diagnosis),'') IS NULL THEN RAISE EXCEPTION 'Principal diagnosis required'; END IF; UPDATE public.encounters SET status='completed',completed_at=COALESCE(completed_at,now()),updated_at=COALESCE(updated_at,now()) WHERE id=_encounter_id RETURNING * INTO result; RETURN result; END; $$;


ALTER FUNCTION "public"."complete_encounter_workflow"("_encounter_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_appointment_workflow"("_patient_id" "uuid", "_scheduled_at" timestamp with time zone, "_department" "text", "_reason" "text" DEFAULT NULL::"text") RETURNS "public"."appointments"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE result public.appointments;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(auth.uid(),'admin'::public.app_role) OR public.has_role(auth.uid(),'practitioner'::public.app_role) OR public.has_role(auth.uid(),'nurse'::public.app_role) OR public.has_role(auth.uid(),'midwife'::public.app_role) OR public.has_role(auth.uid(),'specialist_nurse'::public.app_role) OR public.has_role(auth.uid(),'front_desk'::public.app_role)) THEN RAISE EXCEPTION 'Not authorized to schedule appointments'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient does not exist'; END IF;
 IF _scheduled_at IS NULL THEN RAISE EXCEPTION 'Scheduled time is required'; END IF;
 INSERT INTO public.appointments(patient_id, practitioner_id, department, scheduled_at, duration_minutes, reason, status, notes, created_at, updated_at, treatment_status)
 VALUES(_patient_id, CASE WHEN public.has_role(auth.uid(),'practitioner'::public.app_role) THEN auth.uid() ELSE NULL END, NULLIF(trim(_department),''), _scheduled_at, 30, NULLIF(trim(_reason),''), 'scheduled', NULL, now(), now(), 'scheduled')
 RETURNING * INTO result;
 RETURN result;
END; $$;


ALTER FUNCTION "public"."create_appointment_workflow"("_patient_id" "uuid", "_scheduled_at" timestamp with time zone, "_department" "text", "_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_dental_record"("_patient_id" "uuid", "_examination" "text", "_treatment_plan" "text", "_procedures_performed" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ DECLARE _id UUID; BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner')) THEN RAISE EXCEPTION 'Authorized clinical role required'; END IF; IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF; INSERT INTO public.dental_records(patient_id,examination,treatment_plan,procedures_performed,performed_by) VALUES (_patient_id,NULLIF(trim(_examination),''),NULLIF(trim(_treatment_plan),''),NULLIF(trim(_procedures_performed),''),auth.uid()) RETURNING id INTO _id; RETURN _id; END; $$;


ALTER FUNCTION "public"."create_dental_record"("_patient_id" "uuid", "_examination" "text", "_treatment_plan" "text", "_procedures_performed" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_emergency_case"("_patient_id" "uuid", "_chief_complaint" "text", "_acuity" "text" DEFAULT 'urgent'::"text", "_arrival_mode" "text" DEFAULT 'walk_in'::"text", "_assigned_officer" "uuid" DEFAULT NULL::"uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ DECLARE uid UUID:=auth.uid(); v_id UUID; v_assigned UUID; v_priority TEXT; BEGIN IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'front_desk')) THEN RAISE EXCEPTION 'Emergency operations role required'; END IF; IF _patient_id IS NULL OR NULLIF(trim(_chief_complaint),'') IS NULL THEN RAISE EXCEPTION 'Patient and chief complaint are required'; END IF; IF _acuity NOT IN ('resuscitation','emergency','urgent','less_urgent','non_urgent') THEN RAISE EXCEPTION 'Invalid emergency acuity'; END IF; IF _arrival_mode NOT IN ('walk_in','ambulance','referral','other') THEN RAISE EXCEPTION 'Invalid arrival mode'; END IF; IF _assigned_officer IS NOT NULL AND _assigned_officer<>uid AND NOT public.has_role(uid,'admin') THEN RAISE EXCEPTION 'Only an administrator may assign another officer during creation'; END IF; v_priority:=CASE _acuity WHEN 'resuscitation' THEN 'critical' WHEN 'emergency' THEN 'critical' WHEN 'urgent' THEN 'urgent' WHEN 'less_urgent' THEN 'moderate' ELSE 'routine' END; v_assigned:=COALESCE(_assigned_officer,uid); INSERT INTO public.emergency_cases(patient_id,arrival_mode,triage_priority,chief_complaint,assigned_officer,status) VALUES(_patient_id,_arrival_mode,v_priority,trim(_chief_complaint),v_assigned,'waiting') RETURNING id INTO v_id; RETURN v_id; END; $$;


ALTER FUNCTION "public"."create_emergency_case"("_patient_id" "uuid", "_chief_complaint" "text", "_acuity" "text", "_arrival_mode" "text", "_assigned_officer" "uuid") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."prescriptions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "encounter_id" "uuid",
    "patient_id" "uuid" NOT NULL,
    "prescribed_by" "uuid",
    "medication" "text" NOT NULL,
    "dosage" "text",
    "frequency" "text",
    "duration" "text",
    "instructions" "text",
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "dispensed_by" "uuid",
    "dispensed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE ONLY "public"."prescriptions" REPLICA IDENTITY FULL;


ALTER TABLE "public"."prescriptions" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_encounter_prescription"("_encounter_id" "uuid", "_medication" "text", "_dosage" "text" DEFAULT NULL::"text", "_frequency" "text" DEFAULT NULL::"text", "_duration" "text" DEFAULT NULL::"text") RETURNS "public"."prescriptions"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ DECLARE result public.prescriptions; patient_id_value UUID; BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; IF NOT (public.has_role(auth.uid(),'admin'::public.app_role) OR public.has_role(auth.uid(),'practitioner'::public.app_role) OR public.has_role(auth.uid(),'nurse'::public.app_role) OR public.has_role(auth.uid(),'midwife'::public.app_role)) THEN RAISE EXCEPTION 'Not authorized to prescribe'; END IF; SELECT patient_id INTO patient_id_value FROM public.encounters WHERE id=_encounter_id; IF patient_id_value IS NULL THEN RAISE EXCEPTION 'Encounter does not exist'; END IF; IF NULLIF(trim(_medication),'') IS NULL THEN RAISE EXCEPTION 'Medication is required'; END IF; INSERT INTO public.prescriptions(encounter_id,patient_id,prescribed_by,medication,dosage,frequency,duration) VALUES(_encounter_id,patient_id_value,auth.uid(),trim(_medication),NULLIF(trim(_dosage),''),NULLIF(trim(_frequency),''),NULLIF(trim(_duration),'')) RETURNING * INTO result; RETURN result; END; $$;


ALTER FUNCTION "public"."create_encounter_prescription"("_encounter_id" "uuid", "_medication" "text", "_dosage" "text", "_frequency" "text", "_duration" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_encounter_workflow"("_patient_id" "uuid", "_symptoms" "text" DEFAULT NULL::"text", "_clerking_notes" "text" DEFAULT NULL::"text") RETURNS "public"."encounters"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ DECLARE result public.encounters; BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; IF NOT (public.has_role(auth.uid(),'admin'::public.app_role) OR public.has_role(auth.uid(),'practitioner'::public.app_role) OR public.has_role(auth.uid(),'nurse'::public.app_role) OR public.has_role(auth.uid(),'midwife'::public.app_role)) THEN RAISE EXCEPTION 'Only authorized clinical staff may create encounters'; END IF; IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient does not exist'; END IF; INSERT INTO public.encounters(patient_id,symptoms,clerking_notes,practitioner_id,status) VALUES(_patient_id,NULLIF(trim(_symptoms),''),NULLIF(trim(_clerking_notes),''),auth.uid(),'draft') RETURNING * INTO result; RETURN result; END; $$;


ALTER FUNCTION "public"."create_encounter_workflow"("_patient_id" "uuid", "_symptoms" "text", "_clerking_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_imaging_order_with_payment_gate"("_patient_id" "uuid", "_encounter_id" "uuid" DEFAULT NULL::"uuid", "_modality" "text" DEFAULT 'X-Ray'::"text", "_study_name" "text" DEFAULT 'General study'::"text", "_body_site" "text" DEFAULT NULL::"text", "_priority" "text" DEFAULT 'routine'::"text", "_clinical_indication" "text" DEFAULT NULL::"text", "_amount" numeric DEFAULT 0) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ DECLARE v_uid UUID:=auth.uid();v_imaging_id UUID;v_service_id UUID;v_status TEXT; BEGIN IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; IF _patient_id IS NULL OR NULLIF(trim(_study_name),'') IS NULL THEN RAISE EXCEPTION 'Patient and study name are required'; END IF; IF COALESCE(_amount,0)<0 THEN RAISE EXCEPTION 'Amount cannot be negative'; END IF; IF NOT EXISTS(SELECT 1 FROM public.patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF; INSERT INTO public.imaging_orders(patient_id,encounter_id,modality,study_name,body_site,priority,clinical_indication,amount,status,requested_by) VALUES(_patient_id,_encounter_id,trim(_modality),trim(_study_name),NULLIF(trim(_body_site),''),COALESCE(NULLIF(trim(_priority),''),'routine'),NULLIF(trim(_clinical_indication),''),COALESCE(_amount,0),CASE WHEN COALESCE(_amount,0)>0 THEN 'pending_payment_approval' ELSE 'released' END,v_uid) RETURNING id,status INTO v_imaging_id,v_status; IF COALESCE(_amount,0)>0 THEN INSERT INTO public.service_orders(patient_id,encounter_id,department,service_name,amount,status,requested_by,related_entity_id,order_type,service_code,payment_required,created_by,notes) VALUES(_patient_id,_encounter_id,'imaging',trim(_study_name),COALESCE(_amount,0),'pending_payment_approval',v_uid,v_imaging_id,'imaging',upper(trim(_modality)),true,v_uid,NULLIF(trim(_clinical_indication),'')) RETURNING id INTO v_service_id; UPDATE public.imaging_orders SET service_order_id=v_service_id WHERE id=v_imaging_id; END IF; RETURN jsonb_build_object('imaging_order_id',v_imaging_id,'service_order_id',v_service_id,'status',v_status); END; $$;


ALTER FUNCTION "public"."create_imaging_order_with_payment_gate"("_patient_id" "uuid", "_encounter_id" "uuid", "_modality" "text", "_study_name" "text", "_body_site" "text", "_priority" "text", "_clinical_indication" "text", "_amount" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_lab_order_with_payment_gate"("_patient_id" "uuid", "_test_name" "text", "_test_category" "text" DEFAULT NULL::"text", "_priority" "text" DEFAULT 'routine'::"text", "_clinical_notes" "text" DEFAULT NULL::"text", "_amount" numeric DEFAULT 0) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ DECLARE v_lab_order_id UUID;v_service_order_id UUID; BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication is required'; END IF; IF _patient_id IS NULL OR NULLIF(btrim(_test_name),'') IS NULL THEN RAISE EXCEPTION 'Patient and test name are required'; END IF; IF COALESCE(_amount,0)<0 THEN RAISE EXCEPTION 'Amount cannot be negative'; END IF; IF NOT EXISTS(SELECT 1 FROM public.patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF; INSERT INTO public.lab_orders(patient_id,test_name,test_category,priority,status,clinical_notes,ordered_by) VALUES(_patient_id,btrim(_test_name),NULLIF(btrim(_test_category),''),COALESCE(NULLIF(btrim(_priority),''),'routine'),'ordered',NULLIF(btrim(_clinical_notes),''),auth.uid()) RETURNING id INTO v_lab_order_id; INSERT INTO public.service_orders(patient_id,department,service_name,amount,unit_price,payment_required,status,requested_by,created_by,related_entity_id,order_type,service_code,notes) VALUES(_patient_id,'laboratory',btrim(_test_name),COALESCE(_amount,0),COALESCE(_amount,0),COALESCE(_amount,0)>0,'pending_payment_approval',auth.uid(),auth.uid(),v_lab_order_id,'lab',NULLIF(btrim(_test_category),''),NULLIF(btrim(_clinical_notes),'')) RETURNING id INTO v_service_order_id; RETURN jsonb_build_object('lab_order_id',v_lab_order_id,'service_order_id',v_service_order_id,'status','pending_payment_approval'); END; $$;


ALTER FUNCTION "public"."create_lab_order_with_payment_gate"("_patient_id" "uuid", "_test_name" "text", "_test_category" "text", "_priority" "text", "_clinical_notes" "text", "_amount" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_ophthalmology_exam"("_patient_id" "uuid", "_visual_acuity" "text", "_refraction" "text", "_keratometry" "text", "_intraocular_pressure" numeric, "_color_vision" "text", "_fundus_notes" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ DECLARE v_id UUID; BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner')) THEN RAISE EXCEPTION 'Ophthalmology clinical role required'; END IF; IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF; IF _intraocular_pressure IS NOT NULL AND _intraocular_pressure < 0 THEN RAISE EXCEPTION 'Intraocular pressure cannot be negative'; END IF; INSERT INTO public.ophthalmology_exams(patient_id,visual_acuity,refraction,keratometry,intraocular_pressure,color_vision,fundus_notes,performed_by) VALUES (_patient_id,NULLIF(trim(_visual_acuity),''),NULLIF(trim(_refraction),''),NULLIF(trim(_keratometry),''),_intraocular_pressure,NULLIF(trim(_color_vision),''),NULLIF(trim(_fundus_notes),''),auth.uid()) RETURNING id INTO v_id; RETURN v_id; END; $$;


ALTER FUNCTION "public"."create_ophthalmology_exam"("_patient_id" "uuid", "_visual_acuity" "text", "_refraction" "text", "_keratometry" "text", "_intraocular_pressure" numeric, "_color_vision" "text", "_fundus_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_patient_appointment"("_patient_id" "uuid", "_scheduled_at" timestamp with time zone, "_department" "text" DEFAULT NULL::"text", "_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_appt public.appointments;
BEGIN
  v_appt := public.create_appointment_workflow(_patient_id, _scheduled_at, _department, _reason);
  RETURN jsonb_build_object('appointment_id', v_appt.id);
END;
$$;


ALTER FUNCTION "public"."create_patient_appointment"("_patient_id" "uuid", "_scheduled_at" timestamp with time zone, "_department" "text", "_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_procedure_note"("_patient_id" "uuid", "_procedure_name" "text", "_template_used" "text", "_indication" "text", "_technique" "text", "_findings" "text", "_complications" "text", "_post_op_plan" "text", "_charge_amount" numeric, "_service_order_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ DECLARE _id UUID; BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife')) THEN RAISE EXCEPTION 'Clinical role required'; END IF; IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF; IF COALESCE(_charge_amount,0)>0 THEN IF _service_order_id IS NULL THEN RAISE EXCEPTION 'A released service order is required for a chargeable procedure'; END IF; IF NOT EXISTS (SELECT 1 FROM public.service_orders WHERE id=_service_order_id AND patient_id=_patient_id AND status IN ('released','in_progress','completed')) THEN RAISE EXCEPTION 'Procedure payment has not been released'; END IF; END IF; INSERT INTO public.procedure_notes(patient_id,procedure_name,template_used,indication,technique,findings,complications,post_op_plan,performed_by,status,charge_amount,service_order_id) VALUES (_patient_id,NULLIF(trim(_procedure_name),''),NULLIF(trim(_template_used),''),NULLIF(trim(_indication),''),NULLIF(trim(_technique),''),NULLIF(trim(_findings),''),NULLIF(trim(_complications),''),NULLIF(trim(_post_op_plan),''),auth.uid(),'completed',GREATEST(COALESCE(_charge_amount,0),0),_service_order_id) RETURNING id INTO _id; RETURN _id; END; $$;


ALTER FUNCTION "public"."create_procedure_note"("_patient_id" "uuid", "_procedure_name" "text", "_template_used" "text", "_indication" "text", "_technique" "text", "_findings" "text", "_complications" "text", "_post_op_plan" "text", "_charge_amount" numeric, "_service_order_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_staff_shift_assignment"("_user_id" "uuid", "_department" "text", "_shift_label" "text", "_starts_at" timestamp with time zone, "_ends_at" timestamp with time zone) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ DECLARE assignment_id UUID; BEGIN IF NOT public.has_role(auth.uid(),'admin') THEN RAISE EXCEPTION 'Shift management access denied'; END IF; IF _user_id IS NULL OR NULLIF(trim(_department),'') IS NULL OR NULLIF(trim(_shift_label),'') IS NULL THEN RAISE EXCEPTION 'Staff, department and shift label are required'; END IF; IF _starts_at IS NULL OR _ends_at IS NULL OR _ends_at<=_starts_at THEN RAISE EXCEPTION 'Shift end must be after shift start'; END IF; IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=_user_id) THEN RAISE EXCEPTION 'Staff profile not found'; END IF; IF EXISTS (SELECT 1 FROM public.staff_shift_assignments s WHERE s.user_id=_user_id AND s.department=_department AND s.active AND tstzrange(s.starts_at,s.ends_at,'[)') && tstzrange(_starts_at,_ends_at,'[)')) THEN RAISE EXCEPTION 'Staff member already has an overlapping active shift in this department'; END IF; INSERT INTO public.staff_shift_assignments(user_id,department,shift_label,starts_at,ends_at,active) VALUES(_user_id,trim(_department),trim(_shift_label),_starts_at,_ends_at,true) RETURNING id INTO assignment_id; RETURN assignment_id; END; $$;


ALTER FUNCTION "public"."create_staff_shift_assignment"("_user_id" "uuid", "_department" "text", "_shift_label" "text", "_starts_at" timestamp with time zone, "_ends_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_theatre_case"("_patient_id" "uuid", "_procedure_name" "text", "_scheduled_start" timestamp with time zone, "_theatre_name" "text" DEFAULT NULL::"text", "_urgency" "text" DEFAULT 'elective'::"text", "_surgeon_id" "uuid" DEFAULT NULL::"uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ DECLARE v_id UUID; v_status TEXT; BEGIN IF auth.uid() IS NULL OR NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse')) THEN RAISE EXCEPTION 'Clinical role required'; END IF; IF _patient_id IS NULL OR NULLIF(trim(_procedure_name),'') IS NULL OR _scheduled_start IS NULL THEN RAISE EXCEPTION 'Patient, procedure and scheduled start are required'; END IF; IF _urgency NOT IN ('emergency','urgent','elective') THEN RAISE EXCEPTION 'Invalid urgency'; END IF; v_status:='planned'; INSERT INTO public.theatre_cases(patient_id,procedure_name,theatre,scheduled_at,status,surgeon_id,created_by) VALUES(_patient_id,trim(_procedure_name),NULLIF(trim(_theatre_name),''),_scheduled_start,v_status,COALESCE(_surgeon_id,auth.uid()),auth.uid()) RETURNING id INTO v_id; RETURN v_id; END; $$;


ALTER FUNCTION "public"."create_theatre_case"("_patient_id" "uuid", "_procedure_name" "text", "_scheduled_start" timestamp with time zone, "_theatre_name" "text", "_urgency" "text", "_surgeon_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_transfusion_record"("_patient_id" "uuid", "_blood_product" "text", "_unit_identifier" "text", "_blood_group" "text" DEFAULT NULL::"text", "_consent_confirmed" boolean DEFAULT false) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ DECLARE v_id UUID; v_component TEXT; BEGIN IF auth.uid() IS NULL OR NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse')) THEN RAISE EXCEPTION 'Clinical role required'; END IF; IF _patient_id IS NULL OR NULLIF(trim(_blood_product),'') IS NULL OR NULLIF(trim(_unit_identifier),'') IS NULL THEN RAISE EXCEPTION 'Patient, blood product and unit identifier are required'; END IF; v_component:=CASE lower(trim(_blood_product)) WHEN 'whole_blood' THEN 'whole_blood' WHEN 'red_cells' THEN 'red_cells' WHEN 'platelets' THEN 'platelets' WHEN 'plasma' THEN 'plasma' WHEN 'cryoprecipitate' THEN 'cryoprecipitate' ELSE 'other' END; INSERT INTO public.transfusion_records(patient_id,component,unit_identifier,blood_group,consent_confirmed,status) VALUES(_patient_id,v_component,trim(_unit_identifier),NULLIF(trim(_blood_group),''),COALESCE(_consent_confirmed,false),'planned') RETURNING id INTO v_id; RETURN v_id; END; $$;


ALTER FUNCTION "public"."create_transfusion_record"("_patient_id" "uuid", "_blood_product" "text", "_unit_identifier" "text", "_blood_group" "text", "_consent_confirmed" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_walk_in_billable_service"("_patient_id" "uuid", "_service_code" "text", "_quantity" integer DEFAULT 1, "_notes" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE t public.service_tariffs%ROWTYPE; o uuid; inv uuid; item uuid;
BEGIN
 IF auth.uid() IS NULL OR NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife')) THEN RAISE EXCEPTION 'Billing access required'; END IF;
 IF _quantity IS NULL OR _quantity<1 THEN RAISE EXCEPTION 'Quantity must be at least one'; END IF;
 SELECT * INTO t FROM public.service_tariffs WHERE service_code=_service_code AND active=true LIMIT 1; IF t.id IS NULL THEN RAISE EXCEPTION 'Active service tariff not found'; END IF;
 SELECT i.id INTO inv FROM public.invoices i WHERE i.patient_id=_patient_id AND i.status NOT IN ('paid','cancelled') ORDER BY i.created_at DESC LIMIT 1;
 IF inv IS NULL THEN INSERT INTO public.invoices(patient_id,total_amount,paid_amount,status,created_by) VALUES(_patient_id,0,0,'pending',auth.uid()) RETURNING id INTO inv; END IF;
 INSERT INTO public.invoice_items(invoice_id,description,quantity,unit_price,amount,category,department,source_type,source_id,paid_amount) VALUES(inv,t.service_name,_quantity,t.amount,t.amount*_quantity,'procedure',t.department,'walk_in',gen_random_uuid(),0) RETURNING id INTO item;
 INSERT INTO public.service_orders(patient_id,department,service_name,amount,status,notes,requested_by,order_type,service_code,quantity,unit_price,payment_required,created_by,invoice_id,invoice_item_id) VALUES(_patient_id,t.department,t.service_name,t.amount*_quantity,'pending_payment_approval',_notes,auth.uid(),'walk_in',t.service_code,_quantity,t.amount,true,auth.uid(),inv,item) RETURNING id INTO o;
 UPDATE public.invoice_items SET service_order_id=o,source_id=o WHERE id=item; RETURN o;
END; $$;


ALTER FUNCTION "public"."create_walk_in_billable_service"("_patient_id" "uuid", "_service_code" "text", "_quantity" integer, "_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_ward_unit"("_name" "text", "_code" "text", "_specialty" "text" DEFAULT NULL::"text", "_gender_policy" "text" DEFAULT 'mixed'::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ DECLARE v_id UUID; BEGIN IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin') THEN RAISE EXCEPTION 'Administrator role required'; END IF; IF NULLIF(trim(_name),'') IS NULL OR NULLIF(trim(_code),'') IS NULL THEN RAISE EXCEPTION 'Ward name and code are required'; END IF; IF _gender_policy NOT IN ('mixed','male','female') THEN RAISE EXCEPTION 'Invalid gender policy'; END IF; INSERT INTO public.wards(name,code,department,gender_policy) VALUES(trim(_name),trim(_code),NULLIF(trim(_specialty),''),_gender_policy) RETURNING id INTO v_id; RETURN v_id; END; $$;


ALTER FUNCTION "public"."create_ward_unit"("_name" "text", "_code" "text", "_specialty" "text", "_gender_policy" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_user_can_edit_patient_record"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT COALESCE((SELECT auth.uid()) IS NOT NULL, false)
     AND EXISTS (
       SELECT 1
       FROM public.user_roles
       WHERE user_id = (SELECT auth.uid())
         AND role IN ('admin','practitioner','nurse','midwife','front_desk')
     );
$$;


ALTER FUNCTION "public"."current_user_can_edit_patient_record"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_user_has_role"("_role" "public"."app_role") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT COALESCE((SELECT auth.uid()) IS NOT NULL, false)
     AND EXISTS (
       SELECT 1
       FROM public.user_roles
       WHERE user_id = (SELECT auth.uid())
         AND role = _role
     );
$$;


ALTER FUNCTION "public"."current_user_has_role"("_role" "public"."app_role") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_user_is_clinical_staff"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT COALESCE((SELECT auth.uid()) IS NOT NULL, false)
     AND EXISTS (
       SELECT 1
       FROM public.user_roles
       WHERE user_id = (SELECT auth.uid())
         AND role IN ('admin','practitioner','nurse','midwife','lab_technician','pharmacist','front_desk')
     );
$$;


ALTER FUNCTION "public"."current_user_is_clinical_staff"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."end_video_session"("_session_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner')) THEN RAISE EXCEPTION 'Telemedicine access requires a practitioner role'; END IF; UPDATE public.video_sessions SET status='completed',ended_at=COALESCE(ended_at,now()) WHERE id=_session_id AND practitioner_id=auth.uid() AND status='active'; RETURN FOUND; END; $$;


ALTER FUNCTION "public"."end_video_session"("_session_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_patient_code"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$ DECLARE next_seq INTEGER; ymd TEXT; BEGIN IF NEW.patient_code IS NULL OR NEW.patient_code = '' THEN ymd := to_char(now(), 'YYYYMMDD'); SELECT COUNT(*) + 1 INTO next_seq FROM public.patients WHERE patient_code LIKE 'MED-' || ymd || '-%'; NEW.patient_code := 'MED-' || ymd || '-' || lpad(next_seq::text, 4, '0'); END IF; RETURN NEW; END; $$;


ALTER FUNCTION "public"."generate_patient_code"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_bmi_category"("_bmi" numeric) RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO 'public'
    AS $$ SELECT CASE WHEN _bmi IS NULL OR _bmi<=0 THEN 'unavailable' WHEN _bmi<18.5 THEN 'underweight' WHEN _bmi<25 THEN 'healthy range' WHEN _bmi<30 THEN 'overweight' ELSE 'obesity range' END; $$;


ALTER FUNCTION "public"."get_bmi_category"("_bmi" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_encounter_clinical_context"("_patient_id" "uuid", "_encounter_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ DECLARE v_user UUID:=auth.uid(); v_patient JSONB; v_history JSONB; v_vitals JSONB; BEGIN IF v_user IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; IF NOT (public.has_role(v_user,'admin') OR public.has_role(v_user,'practitioner') OR public.has_role(v_user,'nurse') OR public.has_role(v_user,'midwife')) THEN RAISE EXCEPTION 'Clinical access required'; END IF; SELECT jsonb_build_object('patient_code',p.patient_code,'name',concat_ws(' ',p.first_name,p.last_name),'blood_group',p.blood_group,'genotype',p.genotype,'allergies',NULLIF(trim(p.allergies),''),'chronic_conditions',NULLIF(trim(p.chronic_conditions),'')) INTO v_patient FROM public.patients p WHERE p.id=_patient_id; IF v_patient IS NULL THEN RAISE EXCEPTION 'Patient not found'; END IF; SELECT COALESCE(jsonb_agg(x ORDER BY x.created_at DESC),'[]'::jsonb) INTO v_history FROM (SELECT jsonb_build_object('id',e.id,'created_at',e.created_at,'status',e.status,'principal_diagnosis',e.principal_diagnosis,'symptoms',e.symptoms,'treatment_plan',e.treatment_plan,'diagnoses',COALESCE((SELECT jsonb_agg(d.diagnosis ORDER BY d.is_principal DESC,d.created_at DESC) FROM public.diagnoses d WHERE d.encounter_id=e.id),'[]'::jsonb)) AS x,e.created_at FROM public.encounters e WHERE e.patient_id=_patient_id AND (_encounter_id IS NULL OR e.id<>_encounter_id) ORDER BY e.created_at DESC LIMIT 8) x; SELECT COALESCE(jsonb_agg(jsonb_build_object('recorded_at',v.recorded_at,'systolic',v.systolic,'diastolic',v.diastolic,'pulse_rate',v.pulse_rate,'temperature',v.temperature,'respiratory_rate',v.respiratory_rate,'oxygen_saturation',v.oxygen_saturation,'weight_kg',v.weight_kg,'bmi',v.bmi,'priority',v.priority,'notes',v.notes) ORDER BY v.recorded_at DESC),'[]'::jsonb) INTO v_vitals FROM (SELECT * FROM public.vital_signs WHERE patient_id=_patient_id ORDER BY recorded_at DESC LIMIT 3) v; RETURN jsonb_build_object('patient',v_patient,'previous_encounters',v_history,'recent_vitals',v_vitals); END; $$;


ALTER FUNCTION "public"."get_encounter_clinical_context"("_patient_id" "uuid", "_encounter_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_patient_bmi_context"("_patient_id" "uuid") RETURNS TABLE("bmi" numeric, "category" "text", "weight_kg" numeric, "height_m" numeric, "recorded_at" timestamp with time zone)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; IF NOT (public.has_role(auth.uid(),'admin'::public.app_role) OR public.has_role(auth.uid(),'practitioner'::public.app_role) OR public.has_role(auth.uid(),'nurse'::public.app_role) OR public.has_role(auth.uid(),'midwife'::public.app_role) OR public.has_role(auth.uid(),'pharmacist'::public.app_role)) THEN RAISE EXCEPTION 'Clinical access required'; END IF; RETURN QUERY SELECT t.bmi,public.get_bmi_category(t.bmi),t.weight_kg,t.height_m,t.created_at FROM public.triage_assessments t WHERE t.patient_id=_patient_id AND t.bmi IS NOT NULL ORDER BY t.created_at DESC LIMIT 1; END; $$;


ALTER FUNCTION "public"."get_patient_bmi_context"("_patient_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  INSERT INTO public.profiles (id, email, first_name, last_name)
  VALUES (
    NEW.id, NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'first_name',''),
    COALESCE(NEW.raw_user_meta_data->>'last_name','')
  )
  ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email,
    first_name = COALESCE(NULLIF(EXCLUDED.first_name,''), public.profiles.first_name),
    last_name = COALESCE(NULLIF(EXCLUDED.last_name,''), public.profiles.last_name);
  INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'patient') ON CONFLICT (user_id, role) DO NOTHING;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."has_role"("_user_id" "uuid", "_role" "public"."app_role") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ SELECT EXISTS(SELECT 1 FROM public.user_roles WHERE user_id=_user_id AND role=_role) $$;


ALTER FUNCTION "public"."has_role"("_user_id" "uuid", "_role" "public"."app_role") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_clinical_staff"("_user_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ SELECT EXISTS(SELECT 1 FROM public.user_roles WHERE user_id=_user_id AND role IN ('admin','practitioner','nurse','midwife','lab_technician','pharmacist','front_desk')) $$;


ALTER FUNCTION "public"."is_clinical_staff"("_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."lock_overdue_medication_slots"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ DECLARE n INTEGER; BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'practitioner')) THEN RAISE EXCEPTION 'Clinical role required'; END IF; UPDATE public.medication_administrations SET locked_at=now(),lock_reason='Administration window expired without documented administration',updated_at=now() WHERE status='scheduled' AND scheduled_at IS NOT NULL AND now()>scheduled_at+(due_window_minutes||' minutes')::interval AND locked_at IS NULL; GET DIAGNOSTICS n=ROW_COUNT; RETURN n; END; $$;


ALTER FUNCTION "public"."lock_overdue_medication_slots"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_notification_read"("_notification_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ DECLARE changed boolean:=false; BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; UPDATE public.notifications SET is_read=true WHERE id=_notification_id AND is_read=false AND (recipient_user_id=auth.uid() OR (recipient_user_id IS NULL AND recipient_role IS NOT NULL AND public.has_role(auth.uid(),recipient_role))); changed:=FOUND; RETURN changed; END; $$;


ALTER FUNCTION "public"."mark_notification_read"("_notification_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_video_session_paid"("_session_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk')) THEN RAISE EXCEPTION 'Payment confirmation requires an accounts or front-desk role'; END IF; UPDATE public.video_sessions SET payment_received=true WHERE id=_session_id AND status IN ('scheduled','ready'); RETURN FOUND; END; $$;


ALTER FUNCTION "public"."mark_video_session_paid"("_session_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_due_medications"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'practitioner')) THEN RAISE EXCEPTION 'Clinical role required'; END IF; RETURN 0; END; $$;


ALTER FUNCTION "public"."notify_due_medications"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."pay_selected_invoice_items"("_invoice_id" "uuid", "_item_ids" "uuid"[], "_method" "text", "_reference" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE uid uuid:=auth.uid(); pid uuid; total numeric:=0; payment_id uuid; iid uuid; due numeric; amt numeric;
BEGIN
 IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'accountant') OR public.has_role(uid,'front_desk')) THEN RAISE EXCEPTION 'Payment collection requires accounts or front-desk role'; END IF;
 SELECT patient_id INTO pid FROM public.invoices WHERE id=_invoice_id FOR UPDATE; IF pid IS NULL THEN RAISE EXCEPTION 'Invoice not found'; END IF;
 IF _item_ids IS NULL OR cardinality(_item_ids)=0 THEN RAISE EXCEPTION 'No invoice items selected'; END IF;
 FOR iid IN SELECT unnest(_item_ids) LOOP SELECT GREATEST(ii.amount-COALESCE(ii.paid_amount,0),0) INTO due FROM public.invoice_items ii WHERE ii.id=iid AND ii.invoice_id=_invoice_id FOR UPDATE; IF due IS NULL THEN RAISE EXCEPTION 'Invoice item does not belong to invoice'; END IF; IF due>0 THEN total:=total+due; END IF; END LOOP;
 IF total<=0 THEN RAISE EXCEPTION 'Selected items have no outstanding balance'; END IF;
 INSERT INTO public.payments(invoice_id,patient_id,amount,method,reference,received_by,notes) VALUES(_invoice_id,pid,total,_method,NULLIF(trim(_reference),''),uid,'Selected invoice items') RETURNING id INTO payment_id;
 FOR iid IN SELECT unnest(_item_ids) LOOP SELECT GREATEST(ii.amount-COALESCE(ii.paid_amount,0),0) INTO amt FROM public.invoice_items ii WHERE ii.id=iid AND ii.invoice_id=_invoice_id FOR UPDATE; IF amt>0 THEN UPDATE public.invoice_items SET paid_amount=COALESCE(paid_amount,0)+amt WHERE id=iid; INSERT INTO public.billing_item_payments(invoice_item_id,payment_id,amount) VALUES(iid,payment_id,amt); UPDATE public.service_orders SET status='released',updated_at=now() WHERE invoice_item_id=iid AND status='pending_payment_approval'; END IF; END LOOP;
 UPDATE public.invoices i SET paid_amount=COALESCE((SELECT SUM(p.amount) FROM public.payments p WHERE p.invoice_id=i.id),0), total_amount=COALESCE((SELECT SUM(ii.amount) FROM public.invoice_items ii WHERE ii.invoice_id=i.id),0), status=CASE WHEN GREATEST(COALESCE((SELECT SUM(ii.amount-COALESCE(ii.paid_amount,0)) FROM public.invoice_items ii WHERE ii.invoice_id=i.id),0),0)=0 THEN 'paid' ELSE 'partial' END, updated_at=now() WHERE i.id=_invoice_id;
 RETURN jsonb_build_object('payment_id',payment_id,'amount',total,'invoice_id',_invoice_id);
END; $$;


ALTER FUNCTION "public"."pay_selected_invoice_items"("_invoice_id" "uuid", "_item_ids" "uuid"[], "_method" "text", "_reference" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prepare_patient_billable_items"("_patient_id" "uuid", "_from" timestamp with time zone, "_to" timestamp with time zone) RETURNS TABLE("invoice_id" "uuid", "invoice_item_id" "uuid", "source_type" "text", "source_id" "uuid", "description" "text", "category" "text", "department" "text", "quantity" integer, "unit_price" numeric, "amount" numeric, "paid_amount" numeric, "outstanding_amount" numeric, "service_order_id" "uuid", "service_order_status" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_invoice uuid;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife')) THEN RAISE EXCEPTION 'Billing access required'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;
 SELECT i.id INTO v_invoice FROM public.invoices i WHERE i.patient_id=_patient_id AND i.status NOT IN ('paid','cancelled') ORDER BY i.created_at DESC LIMIT 1;
 IF v_invoice IS NULL THEN INSERT INTO public.invoices(patient_id,total_amount,paid_amount,status,created_by) VALUES(_patient_id,0,0,'pending',auth.uid()) RETURNING id INTO v_invoice; END IF;
 RETURN QUERY SELECT ii.invoice_id,ii.id,ii.source_type,ii.source_id,ii.description,ii.category,ii.department,ii.quantity,ii.unit_price,ii.amount,COALESCE(ii.paid_amount,0),GREATEST(ii.amount-COALESCE(ii.paid_amount,0),0),ii.service_order_id,so.status FROM public.invoice_items ii LEFT JOIN public.service_orders so ON so.id=ii.service_order_id WHERE ii.invoice_id=v_invoice AND ii.created_at BETWEEN _from AND _to ORDER BY ii.created_at;
END; $$;


ALTER FUNCTION "public"."prepare_patient_billable_items"("_patient_id" "uuid", "_from" timestamp with time zone, "_to" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_ai_clinical_event"("_session_id" "uuid", "_event_type" "text", "_metadata" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ DECLARE _event_id UUID; BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; IF NOT EXISTS(SELECT 1 FROM public.ai_clinical_sessions WHERE id=_session_id AND (created_by=auth.uid() OR public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'pharmacist'))) THEN RAISE EXCEPTION 'AI clinical session is not accessible to this user'; END IF; IF _event_type NOT IN ('session_created','analysis_requested','analysis_completed','review_approved','review_amended','review_rejected') THEN RAISE EXCEPTION 'Unsupported AI clinical event type'; END IF; INSERT INTO public.ai_clinical_events(session_id,event_type,actor_id,metadata) VALUES(_session_id,_event_type,auth.uid(),COALESCE(_metadata,'{}'::jsonb)) RETURNING id INTO _event_id; RETURN _event_id; END; $$;


ALTER FUNCTION "public"."record_ai_clinical_event"("_session_id" "uuid", "_event_type" "text", "_metadata" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_system_audit"("_action" "text", "_module" "text", "_entity_type" "text" DEFAULT NULL::"text", "_entity_id" "uuid" DEFAULT NULL::"uuid", "_severity" "text" DEFAULT 'info'::"text", "_metadata" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_id UUID;
BEGIN
  IF (select auth.uid()) IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  INSERT INTO public.system_audit_log(actor_id, action, module, entity_type, entity_id, severity, metadata)
  VALUES ((select auth.uid()), _action, _module, _entity_type, _entity_id, _severity, COALESCE(_metadata,'{}'::jsonb))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;


ALTER FUNCTION "public"."record_system_audit"("_action" "text", "_module" "text", "_entity_type" "text", "_entity_id" "uuid", "_severity" "text", "_metadata" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_transfusion_event"("_record_id" "uuid", "_status" "text", "_reaction_observed" boolean DEFAULT false, "_reaction_notes" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE uid uuid:=auth.uid(); r public.transfusion_records%ROWTYPE;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
 IF _status NOT IN ('issued','running','completed','stopped','cancelled') THEN RAISE EXCEPTION 'Invalid transfusion status'; END IF;
 SELECT * INTO r FROM public.transfusion_records WHERE id=_record_id FOR UPDATE; IF r.id IS NULL THEN RAISE EXCEPTION 'Transfusion record not found'; END IF;
 UPDATE public.transfusion_records SET status=_status,reaction_observed=_reaction_observed,reaction_notes=CASE WHEN _reaction_observed THEN _reaction_notes ELSE reaction_notes END,started_at=CASE WHEN _status='running' AND started_at IS NULL THEN now() ELSE started_at END,completed_at=CASE WHEN _status IN ('completed','stopped') THEN now() ELSE completed_at END,administered_by=COALESCE(administered_by,uid) WHERE id=_record_id;
 RETURN jsonb_build_object('record_id',_record_id,'status',_status,'reaction_observed',_reaction_observed);
END; $$;


ALTER FUNCTION "public"."record_transfusion_event"("_record_id" "uuid", "_status" "text", "_reaction_observed" boolean, "_reaction_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_triage_assessment"("_patient_id" "uuid", "_systolic" integer, "_diastolic" integer, "_heart_rate" integer, "_temperature" numeric, "_respiratory_rate" integer, "_oxygen_saturation" numeric, "_weight_kg" numeric DEFAULT NULL::numeric, "_height_m" numeric DEFAULT NULL::numeric, "_pain_score" integer DEFAULT NULL::integer, "_consciousness" "text" DEFAULT NULL::"text", "_presenting_complaint" "text" DEFAULT NULL::"text", "_clinical_notes" "text" DEFAULT NULL::"text", "_priority" "text" DEFAULT 'routine'::"text", "_is_critical" boolean DEFAULT false) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ DECLARE v_id UUID; BEGIN IF auth.uid() IS NULL OR NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')) THEN RAISE EXCEPTION 'Not authorized to record triage'; END IF; IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF; INSERT INTO public.triage_assessments(patient_id,recorded_by,systolic,diastolic,heart_rate,temperature,respiratory_rate,oxygen_saturation,weight_kg,height_m,pain_score,consciousness,presenting_complaint,clinical_notes,priority,is_critical) VALUES(_patient_id,auth.uid(),_systolic,_diastolic,_heart_rate,_temperature,_respiratory_rate,_oxygen_saturation,_weight_kg,_height_m,_pain_score,_consciousness,_presenting_complaint,_clinical_notes,_priority,_is_critical) RETURNING id INTO v_id; RETURN v_id; END; $$;


ALTER FUNCTION "public"."record_triage_assessment"("_patient_id" "uuid", "_systolic" integer, "_diastolic" integer, "_heart_rate" integer, "_temperature" numeric, "_respiratory_rate" integer, "_oxygen_saturation" numeric, "_weight_kg" numeric, "_height_m" numeric, "_pain_score" integer, "_consciousness" "text", "_presenting_complaint" "text", "_clinical_notes" "text", "_priority" "text", "_is_critical" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."refresh_invoice_totals"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
DECLARE inv_id UUID; total_paid NUMERIC(10,2); inv_total NUMERIC(10,2);
BEGIN
  inv_id := COALESCE(NEW.invoice_id, OLD.invoice_id);
  IF inv_id IS NULL THEN RETURN NEW; END IF;
  SELECT COALESCE(SUM(amount),0) INTO total_paid FROM public.payments WHERE invoice_id = inv_id;
  SELECT total_amount INTO inv_total FROM public.invoices WHERE id = inv_id;
  UPDATE public.invoices SET paid_amount = total_paid, status = CASE WHEN total_paid <= 0 THEN 'pending' WHEN total_paid < inv_total THEN 'partially_paid' ELSE 'paid' END, updated_at = now() WHERE id = inv_id;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."refresh_invoice_totals"() OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."outside_lab_documents" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "document_type" "text" NOT NULL,
    "title" "text",
    "storage_path" "text" NOT NULL,
    "mime_type" "text",
    "uploaded_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."outside_lab_documents" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."register_outside_lab_document"("_patient_id" "uuid", "_document_type" "text", "_title" "text", "_storage_path" "text", "_mime_type" "text" DEFAULT NULL::"text") RETURNS "public"."outside_lab_documents"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ DECLARE v_doc public.outside_lab_documents; BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse') OR public.has_role(auth.uid(),'lab_technician')) THEN RAISE EXCEPTION 'Outside-lab document upload is not permitted'; END IF; IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF; IF NULLIF(btrim(_document_type),'') IS NULL THEN RAISE EXCEPTION 'Document type is required'; END IF; IF NULLIF(btrim(_storage_path),'') IS NULL OR position('/' IN _storage_path)=0 THEN RAISE EXCEPTION 'Invalid storage path'; END IF; IF split_part(_storage_path,'/',1) <> _patient_id::text THEN RAISE EXCEPTION 'Storage path must be scoped to the patient'; END IF; INSERT INTO public.outside_lab_documents(patient_id,document_type,title,storage_path,mime_type,uploaded_by) VALUES (_patient_id,btrim(_document_type),COALESCE(NULLIF(btrim(_title),''),'Outside laboratory document'),_storage_path,NULLIF(btrim(_mime_type),''),auth.uid()) RETURNING * INTO v_doc; IF to_regprocedure('public.record_system_audit(text,text,text,uuid,text,jsonb)') IS NOT NULL THEN PERFORM public.record_system_audit('outside_lab_document_uploaded','outside_lab','outside_lab_document',v_doc.id,'info',jsonb_build_object('patient_id',_patient_id,'document_type',_document_type)); END IF; RETURN v_doc; END; $$;


ALTER FUNCTION "public"."register_outside_lab_document"("_patient_id" "uuid", "_document_type" "text", "_title" "text", "_storage_path" "text", "_mime_type" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."release_service_order"("_order_id" "uuid", "_reason" "text" DEFAULT NULL::"text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk')) THEN RAISE EXCEPTION 'Accounts release permission required'; END IF;
 UPDATE public.service_orders SET status='released',notes=CASE WHEN _reason IS NULL OR trim(_reason)='' THEN notes ELSE COALESCE(notes,'')||' | Released: '||trim(_reason) END,updated_at=now() WHERE id=_order_id AND status='pending_payment_approval';
 RETURN FOUND;
END; $$;


ALTER FUNCTION "public"."release_service_order"("_order_id" "uuid", "_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."remove_encounter_diagnosis"("_diagnosis_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; IF NOT (public.has_role(auth.uid(),'admin'::public.app_role) OR public.has_role(auth.uid(),'practitioner'::public.app_role) OR public.has_role(auth.uid(),'nurse'::public.app_role) OR public.has_role(auth.uid(),'midwife'::public.app_role)) THEN RAISE EXCEPTION 'Not authorized to remove diagnoses'; END IF; DELETE FROM public.diagnoses WHERE id=_diagnosis_id; END; $$;


ALTER FUNCTION "public"."remove_encounter_diagnosis"("_diagnosis_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reopen_medication_administration"("_record_id" "uuid", "_reason" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife')) THEN RAISE EXCEPTION 'Clinical role required'; END IF; IF length(trim(COALESCE(_reason,'')))<3 THEN RAISE EXCEPTION 'Reopen reason is required'; END IF; UPDATE public.medication_administrations SET locked_at=NULL,lock_reason=NULL,reopened_at=now(),reopen_reason=trim(_reason),updated_at=now() WHERE id=_record_id; IF NOT FOUND THEN RAISE EXCEPTION 'Medication record not found'; END IF; RETURN true; END; $$;


ALTER FUNCTION "public"."reopen_medication_administration"("_record_id" "uuid", "_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."review_ophthalmology_exam"("_exam_id" "uuid", "_advisory" "jsonb" DEFAULT '{}'::"jsonb") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner')) THEN RAISE EXCEPTION 'Clinical review role required'; END IF; UPDATE public.ophthalmology_exams SET status='reviewed',reviewed_by=auth.uid(),reviewed_at=now(),ai_advisory=COALESCE(_advisory,'{}'::jsonb),updated_at=now() WHERE id=_exam_id; RETURN FOUND; END; $$;


ALTER FUNCTION "public"."review_ophthalmology_exam"("_exam_id" "uuid", "_advisory" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."schedule_medication_administration"("_patient_id" "uuid", "_medication_name" "text", "_dose" "text" DEFAULT NULL::"text", "_route" "text" DEFAULT NULL::"text", "_scheduled_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "_notes" "text" DEFAULT NULL::"text", "_due_window_minutes" integer DEFAULT 30) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ DECLARE v_id UUID; BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'pharmacist')) THEN RAISE EXCEPTION 'Clinical medication role required'; END IF; IF NOT EXISTS(SELECT 1 FROM public.patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF; IF NULLIF(trim(_medication_name),'') IS NULL THEN RAISE EXCEPTION 'Medication name is required'; END IF; IF COALESCE(_due_window_minutes,30)<1 OR COALESCE(_due_window_minutes,30)>1440 THEN RAISE EXCEPTION 'Invalid due window'; END IF; INSERT INTO public.medication_administrations(patient_id,medication_name,dose,route,scheduled_at,notes,due_window_minutes,status) VALUES(_patient_id,trim(_medication_name),NULLIF(trim(_dose),''),NULLIF(trim(_route),''),_scheduled_at,NULLIF(trim(_notes),''),COALESCE(_due_window_minutes,30),'scheduled') RETURNING id INTO v_id; RETURN v_id; END; $$;


ALTER FUNCTION "public"."schedule_medication_administration"("_patient_id" "uuid", "_medication_name" "text", "_dose" "text", "_route" "text", "_scheduled_at" timestamp with time zone, "_notes" "text", "_due_window_minutes" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."schedule_video_session"("_patient_id" "uuid", "_scheduled_at" timestamp with time zone, "_provider" "text" DEFAULT 'jitsi'::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ DECLARE v_id UUID; v_room TEXT; BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner')) THEN RAISE EXCEPTION 'Telemedicine scheduling requires a practitioner role'; END IF; IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF; IF _scheduled_at IS NULL OR _scheduled_at < now()-interval '5 minutes' THEN RAISE EXCEPTION 'A valid future appointment time is required'; END IF; v_room := 'harmony-' || replace(gen_random_uuid()::text,'-',''); INSERT INTO public.video_sessions(patient_id,practitioner_id,room_name,provider,scheduled_at,status,payment_required,payment_received) VALUES(_patient_id,auth.uid(),v_room,COALESCE(NULLIF(trim(_provider),''),'jitsi'),_scheduled_at,'scheduled',true,false) RETURNING id INTO v_id; RETURN v_id; END; $$;


ALTER FUNCTION "public"."schedule_video_session"("_patient_id" "uuid", "_scheduled_at" timestamp with time zone, "_provider" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."facility_settings" (
    "id" "text" DEFAULT 'default'::"text" NOT NULL,
    "facility_name" "text" DEFAULT 'Harmony Health Hub'::"text" NOT NULL,
    "payment_flow" "text" DEFAULT 'streamlined'::"text" NOT NULL,
    "routing_mode" "text" DEFAULT 'streamlined'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."facility_settings" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_facility_routing_mode"("_mode" "text") RETURNS "public"."facility_settings"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ DECLARE v public.facility_settings; BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; IF NOT public.has_role(auth.uid(),'admin') THEN RAISE EXCEPTION 'Administrator role required'; END IF; IF _mode NOT IN ('pay_before_each_step','streamlined') THEN RAISE EXCEPTION 'Unsupported routing mode'; END IF; UPDATE public.facility_settings SET routing_mode=_mode,payment_flow=CASE WHEN _mode='pay_before_each_step' THEN 'strict' ELSE 'streamlined' END,updated_at=now() WHERE id='default' RETURNING * INTO v; RETURN v; END; $$;


ALTER FUNCTION "public"."set_facility_routing_mode"("_mode" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_principal_diagnosis"("_encounter_id" "uuid", "_diagnosis_id" "uuid") RETURNS "public"."diagnoses"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ DECLARE result public.diagnoses; BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; IF NOT (public.has_role(auth.uid(),'admin'::public.app_role) OR public.has_role(auth.uid(),'practitioner'::public.app_role) OR public.has_role(auth.uid(),'nurse'::public.app_role) OR public.has_role(auth.uid(),'midwife'::public.app_role)) THEN RAISE EXCEPTION 'Not authorized to set principal diagnosis'; END IF; IF NOT EXISTS (SELECT 1 FROM public.diagnoses WHERE id=_diagnosis_id AND encounter_id=_encounter_id) THEN RAISE EXCEPTION 'Diagnosis does not belong to encounter'; END IF; UPDATE public.diagnoses SET is_principal=false WHERE encounter_id=_encounter_id; UPDATE public.diagnoses SET is_principal=true WHERE id=_diagnosis_id RETURNING * INTO result; UPDATE public.encounters SET principal_diagnosis=result.diagnosis,updated_at=COALESCE(updated_at,now()) WHERE id=_encounter_id; RETURN result; END; $$;


ALTER FUNCTION "public"."set_principal_diagnosis"("_encounter_id" "uuid", "_diagnosis_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_staff_shift_assignment_active"("_assignment_id" "uuid", "_active" boolean) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ BEGIN IF NOT public.has_role(auth.uid(),'admin') THEN RAISE EXCEPTION 'Shift management access denied'; END IF; UPDATE public.staff_shift_assignments SET active=_active WHERE id=_assignment_id; IF NOT FOUND THEN RAISE EXCEPTION 'Shift assignment not found'; END IF; RETURN true; END; $$;


ALTER FUNCTION "public"."set_staff_shift_assignment_active"("_assignment_id" "uuid", "_active" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."start_appointment_encounter"("_appointment_id" "uuid", "_symptoms" "text" DEFAULT NULL::"text", "_clerking_notes" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_user UUID := auth.uid();
  v_appt public.appointments;
  v_encounter UUID;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(v_user,'admin'::public.app_role)
    OR public.has_role(v_user,'practitioner'::public.app_role)
    OR public.has_role(v_user,'nurse'::public.app_role)
    OR public.has_role(v_user,'midwife'::public.app_role)
    OR public.has_role(v_user,'specialist_nurse'::public.app_role)
  ) THEN RAISE EXCEPTION 'Clinical access required'; END IF;

  SELECT * INTO v_appt
  FROM public.appointments
  WHERE id = _appointment_id
  FOR UPDATE;

  IF v_appt.id IS NULL THEN RAISE EXCEPTION 'Appointment not found'; END IF;
  IF v_appt.treatment_status IN ('completed','cancelled','no_show') THEN
    RAISE EXCEPTION 'Appointment is not available for treatment';
  END IF;
  IF v_appt.attending_officer_id IS NOT NULL AND v_appt.attending_officer_id <> v_user THEN
    RAISE EXCEPTION 'Appointment is assigned to another officer';
  END IF;

  UPDATE public.appointments
  SET attending_officer_id = v_user,
      claimed_at = COALESCE(claimed_at, now()),
      treatment_status = 'in_progress',
      started_at = COALESCE(started_at, now()),
      updated_at = now()
  WHERE id = _appointment_id;

  SELECT e.id INTO v_encounter
  FROM public.encounters e
  WHERE e.appointment_id = _appointment_id
  ORDER BY e.created_at DESC
  LIMIT 1;

  IF v_encounter IS NULL THEN
    INSERT INTO public.encounters (
      patient_id, appointment_id, practitioner_id, encounter_type,
      symptoms, clerking_notes, status
    ) VALUES (
      v_appt.patient_id, _appointment_id, v_user, 'consultation',
      NULLIF(trim(_symptoms), ''), NULLIF(trim(_clerking_notes), ''), 'in_progress'
    ) RETURNING id INTO v_encounter;
  ELSE
    UPDATE public.encounters
    SET practitioner_id = COALESCE(practitioner_id, v_user),
        symptoms = COALESCE(NULLIF(trim(_symptoms), ''), symptoms),
        clerking_notes = COALESCE(NULLIF(trim(_clerking_notes), ''), clerking_notes),
        status = CASE WHEN status = 'draft' THEN 'in_progress' ELSE status END,
        updated_at = now()
    WHERE id = v_encounter;
  END IF;

  RETURN v_encounter;
END;
$$;


ALTER FUNCTION "public"."start_appointment_encounter"("_appointment_id" "uuid", "_symptoms" "text", "_clerking_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."start_video_session"("_session_id" "uuid") RETURNS TABLE("id" "uuid", "room_name" "text", "provider" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner')) THEN RAISE EXCEPTION 'Telemedicine access requires a practitioner role'; END IF; UPDATE public.video_sessions SET status='active',started_at=COALESCE(started_at,now()) WHERE video_sessions.id=_session_id AND practitioner_id=auth.uid() AND status IN ('scheduled','ready') AND (NOT payment_required OR payment_received); IF NOT FOUND THEN RAISE EXCEPTION 'Session is unavailable, not assigned to you, or payment is outstanding'; END IF; RETURN QUERY SELECT v.id,v.room_name,v.provider FROM public.video_sessions v WHERE v.id=_session_id; END; $$;


ALTER FUNCTION "public"."start_video_session"("_session_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."touch_care_transition_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$ BEGIN NEW.updated_at=now(); RETURN NEW; END; $$;


ALTER FUNCTION "public"."touch_care_transition_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."touch_global_hims_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;


ALTER FUNCTION "public"."touch_global_hims_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."touch_mar_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$ BEGIN NEW.updated_at=now(); RETURN NEW; END; $$;


ALTER FUNCTION "public"."touch_mar_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."touch_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$ BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;


ALTER FUNCTION "public"."touch_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."transition_medication_administration"("_record_id" "uuid", "_status" "text", "_reason" "text" DEFAULT NULL::"text", "_notes" "text" DEFAULT NULL::"text", "_witnessed_by" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ DECLARE v public.medication_administrations; BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'practitioner')) THEN RAISE EXCEPTION 'Clinical role required'; END IF; IF _status NOT IN ('administered','held','refused','omitted','cancelled') THEN RAISE EXCEPTION 'Unsupported medication status'; END IF; SELECT * INTO v FROM public.medication_administrations WHERE id=_record_id FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'Medication record not found'; END IF; IF v.locked_at IS NOT NULL THEN RAISE EXCEPTION 'Medication slot is locked; reopen it first'; END IF; UPDATE public.medication_administrations SET status=_status,reason=NULLIF(trim(_reason),''),notes=COALESCE(_notes,notes),witnessed_by=COALESCE(_witnessed_by,witnessed_by),administered_at=CASE WHEN _status='administered' THEN now() ELSE administered_at END,administered_by=CASE WHEN _status='administered' THEN auth.uid() ELSE administered_by END,updated_at=now() WHERE id=_record_id RETURNING * INTO v; RETURN to_jsonb(v); END; $$;


ALTER FUNCTION "public"."transition_medication_administration"("_record_id" "uuid", "_status" "text", "_reason" "text", "_notes" "text", "_witnessed_by" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_appointment_workflow"("_appointment_id" "uuid", "_scheduled_at" timestamp with time zone, "_department" "text", "_reason" "text", "_treatment_status" "text", "_treatment_notes" "text" DEFAULT NULL::"text") RETURNS "public"."appointments"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE result public.appointments;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF _treatment_status NOT IN ('scheduled','claimed','in_progress','completed','cancelled','no_show') THEN RAISE EXCEPTION 'Invalid treatment status'; END IF;
 IF NOT (public.has_role(auth.uid(),'admin'::public.app_role) OR public.has_role(auth.uid(),'practitioner'::public.app_role) OR public.has_role(auth.uid(),'nurse'::public.app_role) OR public.has_role(auth.uid(),'midwife'::public.app_role) OR public.has_role(auth.uid(),'specialist_nurse'::public.app_role) OR public.has_role(auth.uid(),'front_desk'::public.app_role)) THEN RAISE EXCEPTION 'You are not authorized to edit appointments'; END IF;
 UPDATE public.appointments SET scheduled_at=_scheduled_at, department=NULLIF(trim(_department),''), reason=NULLIF(trim(_reason),''), treatment_status=_treatment_status, treatment_notes=NULLIF(trim(_treatment_notes),''), started_at=CASE WHEN _treatment_status='in_progress' THEN COALESCE(started_at,now()) ELSE started_at END, completed_at=CASE WHEN _treatment_status='completed' THEN COALESCE(completed_at,now()) ELSE completed_at END, status=CASE WHEN _treatment_status='cancelled' THEN 'cancelled' WHEN _treatment_status='completed' THEN 'completed' ELSE status END, updated_at=now() WHERE id=_appointment_id AND (attending_officer_id=auth.uid() OR public.has_role(auth.uid(),'admin'::public.app_role) OR public.has_role(auth.uid(),'front_desk'::public.app_role)) RETURNING * INTO result;
 IF result.id IS NULL THEN RAISE EXCEPTION 'Appointment not found or not assigned to this officer'; END IF;
 RETURN result;
END; $$;


ALTER FUNCTION "public"."update_appointment_workflow"("_appointment_id" "uuid", "_scheduled_at" timestamp with time zone, "_department" "text", "_reason" "text", "_treatment_status" "text", "_treatment_notes" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."insurance_cases" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "payer_name" "text" NOT NULL,
    "policy_number" "text",
    "eligibility_status" "text" DEFAULT 'unknown'::"text" NOT NULL,
    "eligibility_checked_at" timestamp with time zone,
    "authorization_number" "text",
    "claim_status" "text" DEFAULT 'not_submitted'::"text" NOT NULL,
    "claim_amount" numeric(14,2) DEFAULT 0 NOT NULL,
    "approved_amount" numeric(14,2) DEFAULT 0 NOT NULL,
    "rejection_reason" "text",
    "checked_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "insurance_cases_approved_amount_check" CHECK (("approved_amount" >= (0)::numeric)),
    CONSTRAINT "insurance_cases_claim_amount_check" CHECK (("claim_amount" >= (0)::numeric)),
    CONSTRAINT "insurance_cases_claim_status_check" CHECK (("claim_status" = ANY (ARRAY['not_submitted'::"text", 'draft'::"text", 'submitted'::"text", 'under_review'::"text", 'approved'::"text", 'partially_approved'::"text", 'rejected'::"text", 'paid'::"text", 'appealed'::"text"]))),
    CONSTRAINT "insurance_cases_eligibility_status_check" CHECK (("eligibility_status" = ANY (ARRAY['unknown'::"text", 'eligible'::"text", 'ineligible'::"text", 'pending'::"text", 'expired'::"text"])))
);


ALTER TABLE "public"."insurance_cases" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_insurance_case"("_id" "uuid", "_eligibility" "text", "_authorization" "text", "_claim_status" "text", "_claim_amount" numeric, "_approved_amount" numeric, "_rejection_reason" "text") RETURNS "public"."insurance_cases"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ DECLARE v public.insurance_cases; BEGIN IF auth.uid() IS NULL OR NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk')) THEN RAISE EXCEPTION 'Not authorized'; END IF; IF _eligibility NOT IN ('unknown','eligible','ineligible','pending','expired') THEN RAISE EXCEPTION 'Invalid eligibility status'; END IF; IF _claim_status NOT IN ('not_submitted','draft','submitted','under_review','approved','partially_approved','rejected','paid','appealed') THEN RAISE EXCEPTION 'Invalid claim status'; END IF; UPDATE public.insurance_cases SET eligibility_status=_eligibility,eligibility_checked_at=CASE WHEN _eligibility<>'unknown' THEN now() ELSE eligibility_checked_at END,authorization_number=_authorization,claim_status=_claim_status,claim_amount=GREATEST(COALESCE(_claim_amount,0),0),approved_amount=GREATEST(COALESCE(_approved_amount,0),0),rejection_reason=_rejection_reason,checked_by=auth.uid(),updated_at=now() WHERE id=_id RETURNING * INTO v; IF NOT FOUND THEN RAISE EXCEPTION 'Insurance case not found'; END IF; RETURN v; END; $$;


ALTER FUNCTION "public"."update_insurance_case"("_id" "uuid", "_eligibility" "text", "_authorization" "text", "_claim_status" "text", "_claim_amount" numeric, "_approved_amount" numeric, "_rejection_reason" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."admissions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "admitted_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "discharged_at" timestamp with time zone,
    "ward" "text",
    "bed" "text",
    "admitting_practitioner" "uuid",
    "diagnosis" "text",
    "status" "text" DEFAULT 'admitted'::"text" NOT NULL,
    "notes" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "admissions_status_check" CHECK (("status" = ANY (ARRAY['admitted'::"text", 'discharged'::"text", 'transferred'::"text"])))
);


ALTER TABLE "public"."admissions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ai_clinical_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "session_id" "uuid" NOT NULL,
    "event_type" "text" NOT NULL,
    "actor_id" "uuid" NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."ai_clinical_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ai_clinical_sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "specialist" "text" NOT NULL,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "input_snapshot" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "output_snapshot" "jsonb",
    "model_provider" "text",
    "model_name" "text",
    "provenance" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "review_status" "text" DEFAULT 'not_reviewed'::"text" NOT NULL,
    "reviewed_by" "uuid",
    "reviewed_at" timestamp with time zone,
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."ai_clinical_sessions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."beds" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "ward_id" "uuid" NOT NULL,
    "bed_number" "text" NOT NULL,
    "bed_type" "text" DEFAULT 'standard'::"text" NOT NULL,
    "status" "text" DEFAULT 'available'::"text" NOT NULL,
    "patient_id" "uuid",
    "admission_id" "uuid",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "beds_status_check" CHECK (("status" = ANY (ARRAY['available'::"text", 'occupied'::"text", 'reserved'::"text", 'maintenance'::"text", 'blocked'::"text"])))
);


ALTER TABLE "public"."beds" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."billing_item_payments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "invoice_item_id" "uuid" NOT NULL,
    "payment_id" "uuid" NOT NULL,
    "amount" numeric(14,2) NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "billing_item_payments_amount_check" CHECK (("amount" > (0)::numeric))
);


ALTER TABLE "public"."billing_item_payments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."care_transitions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "admission_id" "uuid",
    "transition_type" "text" NOT NULL,
    "status" "text" DEFAULT 'planned'::"text" NOT NULL,
    "destination" "text",
    "summary" "text",
    "medications_reconciled" boolean DEFAULT false NOT NULL,
    "follow_up_required" boolean DEFAULT false NOT NULL,
    "follow_up_date" "date",
    "instructions" "text",
    "responsible_officer" "uuid",
    "completed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "care_transitions_status_check" CHECK (("status" = ANY (ARRAY['planned'::"text", 'ready'::"text", 'completed'::"text", 'cancelled'::"text"]))),
    CONSTRAINT "care_transitions_transition_type_check" CHECK (("transition_type" = ANY (ARRAY['discharge'::"text", 'transfer'::"text", 'follow_up'::"text"])))
);


ALTER TABLE "public"."care_transitions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."dental_records" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "examination" "text",
    "treatment_plan" "text",
    "procedures_performed" "text",
    "performed_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."dental_records" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."department_queues" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "department" "text" NOT NULL,
    "status" "text" DEFAULT 'waiting'::"text" NOT NULL,
    "priority" "text" DEFAULT 'routine'::"text" NOT NULL,
    "reason" "text",
    "related_encounter_id" "uuid",
    "related_invoice_id" "uuid",
    "payment_required" boolean DEFAULT false NOT NULL,
    "payment_satisfied" boolean DEFAULT false NOT NULL,
    "created_by" "uuid",
    "assigned_to" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "completed_at" timestamp with time zone
);

ALTER TABLE ONLY "public"."department_queues" REPLICA IDENTITY FULL;


ALTER TABLE "public"."department_queues" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."emergency_cases" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "patient_id" "uuid",
    "arrival_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "arrival_mode" "text" DEFAULT 'walk_in'::"text" NOT NULL,
    "triage_priority" "text" DEFAULT 'urgent'::"text" NOT NULL,
    "chief_complaint" "text",
    "assigned_officer" "uuid",
    "status" "text" DEFAULT 'waiting'::"text" NOT NULL,
    "disposition" "text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "emergency_cases_arrival_mode_check" CHECK (("arrival_mode" = ANY (ARRAY['walk_in'::"text", 'ambulance'::"text", 'referral'::"text", 'police'::"text", 'other'::"text"]))),
    CONSTRAINT "emergency_cases_status_check" CHECK (("status" = ANY (ARRAY['waiting'::"text", 'triage'::"text", 'treatment'::"text", 'observation'::"text", 'admitted'::"text", 'transferred'::"text", 'discharged'::"text", 'deceased'::"text"]))),
    CONSTRAINT "emergency_cases_triage_priority_check" CHECK (("triage_priority" = ANY (ARRAY['critical'::"text", 'urgent'::"text", 'moderate'::"text", 'routine'::"text"])))
);


ALTER TABLE "public"."emergency_cases" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."facility_configuration" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "facility_name" "text" DEFAULT 'Harmony Health Hub'::"text" NOT NULL,
    "facility_code" "text",
    "phone" "text",
    "email" "text",
    "address" "text",
    "country" "text" DEFAULT 'Ghana'::"text" NOT NULL,
    "currency" "text" DEFAULT 'GHS'::"text" NOT NULL,
    "timezone" "text" DEFAULT 'Africa/Accra'::"text" NOT NULL,
    "routing_mode" "text" DEFAULT 'pay_before_each_step'::"text" NOT NULL,
    "appointment_buffer_minutes" integer DEFAULT 15 NOT NULL,
    "maintenance_mode" boolean DEFAULT false NOT NULL,
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "facility_configuration_appointment_buffer_minutes_check" CHECK (("appointment_buffer_minutes" >= 0)),
    CONSTRAINT "facility_configuration_routing_mode_check" CHECK (("routing_mode" = ANY (ARRAY['pay_before_each_step'::"text", 'streamlined'::"text"])))
);


ALTER TABLE "public"."facility_configuration" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."fertility_cycles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "partner_name" "text",
    "cycle_type" "text" NOT NULL,
    "cycle_number" integer DEFAULT 1,
    "start_date" "date" NOT NULL,
    "expected_retrieval_date" "date",
    "expected_transfer_date" "date",
    "protocol" "text",
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "outcome" "text",
    "assigned_specialist" "uuid",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."fertility_cycles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."fertility_monitoring" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "cycle_id" "uuid" NOT NULL,
    "visit_date" "date" NOT NULL,
    "cycle_day" integer,
    "estradiol" numeric(10,2),
    "lh" numeric(10,2),
    "fsh" numeric(10,2),
    "progesterone" numeric(10,2),
    "follicle_count_left" integer,
    "follicle_count_right" integer,
    "endometrial_thickness" numeric(4,1),
    "medication_adjustments" "text",
    "notes" "text",
    "recorded_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."fertility_monitoring" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."imaging_orders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "encounter_id" "uuid",
    "modality" "text" NOT NULL,
    "study_name" "text" NOT NULL,
    "body_site" "text",
    "priority" "text" DEFAULT 'routine'::"text" NOT NULL,
    "clinical_indication" "text",
    "amount" numeric DEFAULT 0 NOT NULL,
    "status" "text" DEFAULT 'pending_payment_approval'::"text" NOT NULL,
    "service_order_id" "uuid",
    "requested_by" "uuid",
    "performed_by" "uuid",
    "report" "text",
    "impression" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "imaging_orders_amount_check" CHECK (("amount" >= (0)::numeric))
);


ALTER TABLE "public"."imaging_orders" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."insurance_claims" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "invoice_id" "uuid" NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "provider" "text" NOT NULL,
    "policy_number" "text",
    "amount_claimed" numeric(10,2) NOT NULL,
    "amount_approved" numeric(10,2),
    "status" "text" DEFAULT 'submitted'::"text" NOT NULL,
    "notes" "text",
    "submitted_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "resolved_at" timestamp with time zone
);


ALTER TABLE "public"."insurance_claims" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."invoice_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "invoice_id" "uuid" NOT NULL,
    "description" "text" NOT NULL,
    "quantity" integer DEFAULT 1 NOT NULL,
    "unit_price" numeric(10,2) NOT NULL,
    "amount" numeric(10,2) NOT NULL,
    "category" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "source_type" "text",
    "source_id" "uuid",
    "department" "text",
    "service_order_id" "uuid",
    "paid_amount" numeric(14,2) DEFAULT 0 NOT NULL
);


ALTER TABLE "public"."invoice_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."invoices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "invoice_number" "text" NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "encounter_id" "uuid",
    "total_amount" numeric(10,2) DEFAULT 0 NOT NULL,
    "paid_amount" numeric(10,2) DEFAULT 0 NOT NULL,
    "outstanding_amount" numeric(10,2) GENERATED ALWAYS AS (("total_amount" - "paid_amount")) STORED,
    "insurance_covered" numeric(10,2) DEFAULT 0,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "notes" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."invoices" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."lab_orders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "encounter_id" "uuid",
    "ordered_by" "uuid",
    "test_name" "text" NOT NULL,
    "test_category" "text",
    "priority" "text" DEFAULT 'routine'::"text",
    "clinical_notes" "text",
    "status" "text" DEFAULT 'ordered'::"text" NOT NULL,
    "sample_collected_at" timestamp with time zone,
    "collected_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."lab_orders" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."lab_results" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "lab_order_id" "uuid" NOT NULL,
    "result_data" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "interpretation" "text",
    "is_abnormal" boolean DEFAULT false,
    "entered_by" "uuid",
    "entered_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "approved_by" "uuid",
    "approved_at" timestamp with time zone,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE ONLY "public"."lab_results" REPLICA IDENTITY FULL;


ALTER TABLE "public"."lab_results" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."maternity_episodes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "gravida" integer,
    "para" integer,
    "living_children" integer,
    "lmp" "date",
    "edd" "date",
    "gestational_age_weeks" numeric(5,2),
    "blood_pressure" "text",
    "fetal_heart_rate" integer,
    "fundal_height_cm" numeric(5,2),
    "presentation" "text",
    "risk_level" "text" DEFAULT 'routine'::"text" NOT NULL,
    "status" "text" DEFAULT 'antenatal'::"text" NOT NULL,
    "notes" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "maternity_episodes_gravida_check" CHECK ((("gravida" IS NULL) OR ("gravida" >= 0))),
    CONSTRAINT "maternity_episodes_living_children_check" CHECK ((("living_children" IS NULL) OR ("living_children" >= 0))),
    CONSTRAINT "maternity_episodes_para_check" CHECK ((("para" IS NULL) OR ("para" >= 0))),
    CONSTRAINT "maternity_episodes_risk_level_check" CHECK (("risk_level" = ANY (ARRAY['routine'::"text", 'high'::"text", 'critical'::"text"]))),
    CONSTRAINT "maternity_episodes_status_check" CHECK (("status" = ANY (ARRAY['antenatal'::"text", 'labour'::"text", 'postpartum'::"text", 'completed'::"text", 'cancelled'::"text"])))
);


ALTER TABLE "public"."maternity_episodes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."maternity_observations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "episode_id" "uuid" NOT NULL,
    "observed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "blood_pressure" "text",
    "pulse" integer,
    "temperature" numeric(5,2),
    "fetal_heart_rate" integer,
    "contractions_per_10_min" integer,
    "cervical_dilation_cm" numeric(4,1),
    "effacement_percent" integer,
    "station" "text",
    "membrane_status" "text",
    "notes" "text",
    "recorded_by" "uuid"
);


ALTER TABLE "public"."maternity_observations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."medication_administrations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "prescription_id" "uuid",
    "medication_name" "text" NOT NULL,
    "dose" "text",
    "route" "text",
    "scheduled_at" timestamp with time zone,
    "administered_at" timestamp with time zone,
    "status" "text" DEFAULT 'scheduled'::"text" NOT NULL,
    "reason" "text",
    "administered_by" "uuid",
    "witnessed_by" "uuid",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "due_window_minutes" integer DEFAULT 30 NOT NULL,
    "locked_at" timestamp with time zone,
    "lock_reason" "text",
    "reopened_at" timestamp with time zone,
    "reopen_reason" "text",
    CONSTRAINT "medication_administrations_status_check" CHECK (("status" = ANY (ARRAY['scheduled'::"text", 'administered'::"text", 'held'::"text", 'refused'::"text", 'omitted'::"text", 'cancelled'::"text"])))
);


ALTER TABLE "public"."medication_administrations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recipient_role" "public"."app_role",
    "recipient_user_id" "uuid",
    "title" "text" NOT NULL,
    "message" "text" NOT NULL,
    "severity" "text" DEFAULT 'info'::"text" NOT NULL,
    "category" "text",
    "link" "text",
    "related_patient_id" "uuid",
    "related_entity_id" "uuid",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "is_read" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "notifications_check" CHECK ((("recipient_role" IS NOT NULL) OR ("recipient_user_id" IS NOT NULL)))
);

ALTER TABLE ONLY "public"."notifications" REPLICA IDENTITY FULL;


ALTER TABLE "public"."notifications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nursing_care_plans" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "admission_id" "uuid",
    "problem" "text" NOT NULL,
    "goal" "text" NOT NULL,
    "interventions" "text",
    "evaluation" "text",
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "priority" "text" DEFAULT 'routine'::"text" NOT NULL,
    "created_by" "uuid" NOT NULL,
    "reviewed_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "nursing_care_plans_priority_check" CHECK (("priority" = ANY (ARRAY['routine'::"text", 'high'::"text", 'critical'::"text"]))),
    CONSTRAINT "nursing_care_plans_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'on_hold'::"text", 'completed'::"text", 'cancelled'::"text"])))
);


ALTER TABLE "public"."nursing_care_plans" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nursing_shift_handovers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "admission_id" "uuid",
    "outgoing_officer" "uuid",
    "incoming_officer" "uuid",
    "shift_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "shift_name" "text" DEFAULT 'general'::"text" NOT NULL,
    "clinical_summary" "text" NOT NULL,
    "outstanding_tasks" "text",
    "risks_and_alerts" "text",
    "escalation_required" boolean DEFAULT false NOT NULL,
    "acknowledged_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."nursing_shift_handovers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ophthalmology_exams" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "visual_acuity" "text",
    "refraction" "text",
    "keratometry" "text",
    "intraocular_pressure" numeric(6,2),
    "color_vision" "text",
    "fundus_notes" "text",
    "image_path" "text",
    "ai_advisory" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "status" "text" DEFAULT 'completed'::"text" NOT NULL,
    "performed_by" "uuid",
    "reviewed_by" "uuid",
    "reviewed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ophthalmology_exams_intraocular_pressure_check" CHECK ((("intraocular_pressure" IS NULL) OR ("intraocular_pressure" >= (0)::numeric))),
    CONSTRAINT "ophthalmology_exams_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'completed'::"text", 'reviewed'::"text"])))
);


ALTER TABLE "public"."ophthalmology_exams" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."patient_audit" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "actor_user_id" "uuid",
    "operation" "text" NOT NULL,
    "changed_fields" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "old_record" "jsonb",
    "new_record" "jsonb",
    "occurred_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "patient_audit_operation_check" CHECK (("operation" = ANY (ARRAY['INSERT'::"text", 'UPDATE'::"text", 'DELETE'::"text"])))
);


ALTER TABLE "public"."patient_audit" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."patient_documents" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "document_type" "text" DEFAULT 'other'::"text" NOT NULL,
    "file_name" "text" NOT NULL,
    "storage_path" "text",
    "mime_type" "text",
    "file_size" bigint,
    "notes" "text",
    "uploaded_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."patient_documents" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."patient_referrals" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "encounter_id" "uuid",
    "referred_by" "uuid",
    "destination" "text" NOT NULL,
    "specialty" "text",
    "reason" "text" NOT NULL,
    "urgency" "text" DEFAULT 'routine'::"text" NOT NULL,
    "status" "text" DEFAULT 'requested'::"text" NOT NULL,
    "clinical_summary" "text",
    "appointment_date" timestamp with time zone,
    "receiving_notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "patient_referrals_status_check" CHECK (("status" = ANY (ARRAY['requested'::"text", 'accepted'::"text", 'scheduled'::"text", 'completed'::"text", 'declined'::"text", 'cancelled'::"text"]))),
    CONSTRAINT "patient_referrals_urgency_check" CHECK (("urgency" = ANY (ARRAY['routine'::"text", 'urgent'::"text", 'emergency'::"text"])))
);


ALTER TABLE "public"."patient_referrals" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."patients" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "patient_code" "text",
    "first_name" "text" NOT NULL,
    "last_name" "text" NOT NULL,
    "date_of_birth" "date",
    "gender" "text",
    "phone" "text",
    "email" "text",
    "address" "text",
    "city" "text",
    "ghana_card_number" "text",
    "blood_group" "text",
    "genotype" "text",
    "allergies" "text",
    "chronic_conditions" "text",
    "insurance_provider" "text",
    "insurance_number" "text",
    "emergency_contact_name" "text",
    "emergency_contact_phone" "text",
    "emergency_contact_relation" "text",
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "insurance_expiry" "date",
    "insurance_group_number" "text",
    CONSTRAINT "patients_gender_check" CHECK (("gender" = ANY (ARRAY['male'::"text", 'female'::"text", 'other'::"text"])))
);


ALTER TABLE "public"."patients" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."payments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "invoice_id" "uuid",
    "patient_id" "uuid" NOT NULL,
    "amount" numeric(10,2) NOT NULL,
    "method" "text",
    "reference" "text",
    "received_by" "uuid",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE ONLY "public"."payments" REPLICA IDENTITY FULL;


ALTER TABLE "public"."payments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."procedure_notes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "procedure_name" "text",
    "template_used" "text",
    "indication" "text",
    "technique" "text",
    "findings" "text",
    "complications" "text",
    "post_op_plan" "text",
    "performed_by" "uuid",
    "status" "text" DEFAULT 'completed'::"text" NOT NULL,
    "charge_amount" numeric DEFAULT 0 NOT NULL,
    "service_order_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."procedure_notes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "email" "text",
    "first_name" "text",
    "last_name" "text",
    "phone" "text",
    "department" "text",
    "specialization" "text",
    "avatar_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."service_orders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "department" "text" NOT NULL,
    "service_name" "text" NOT NULL,
    "related_entity_id" "uuid",
    "amount" numeric(14,2) DEFAULT 0 NOT NULL,
    "status" "text" DEFAULT 'pending_payment_approval'::"text" NOT NULL,
    "notes" "text",
    "requested_by" "uuid",
    "order_type" "text" DEFAULT 'service'::"text" NOT NULL,
    "service_code" "text",
    "quantity" integer DEFAULT 1 NOT NULL,
    "unit_price" numeric(14,2) DEFAULT 0 NOT NULL,
    "payment_required" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "invoice_id" "uuid",
    "invoice_item_id" "uuid",
    "started_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "encounter_id" "uuid",
    CONSTRAINT "service_orders_amount_check" CHECK (("amount" >= (0)::numeric)),
    CONSTRAINT "service_orders_quantity_check" CHECK (("quantity" > 0)),
    CONSTRAINT "service_orders_status_check" CHECK (("status" = ANY (ARRAY['pending_payment_approval'::"text", 'released'::"text", 'in_progress'::"text", 'completed'::"text", 'cancelled'::"text"]))),
    CONSTRAINT "service_orders_unit_price_check" CHECK (("unit_price" >= (0)::numeric))
);


ALTER TABLE "public"."service_orders" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."service_tariffs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "service_code" "text" NOT NULL,
    "service_name" "text" NOT NULL,
    "department" "text" NOT NULL,
    "unit" "text" DEFAULT 'service'::"text" NOT NULL,
    "amount" numeric(14,2) DEFAULT 0 NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "service_tariffs_amount_check" CHECK (("amount" >= (0)::numeric))
);


ALTER TABLE "public"."service_tariffs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."staff_shift_assignments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "department" "text" NOT NULL,
    "shift_label" "text" NOT NULL,
    "starts_at" timestamp with time zone NOT NULL,
    "ends_at" timestamp with time zone NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "staff_shift_assignments_check" CHECK (("ends_at" > "starts_at"))
);


ALTER TABLE "public"."staff_shift_assignments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."system_audit_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "actor_id" "uuid",
    "action" "text" NOT NULL,
    "module" "text" NOT NULL,
    "entity_type" "text",
    "entity_id" "uuid",
    "severity" "text" DEFAULT 'info'::"text" NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "system_audit_log_severity_check" CHECK (("severity" = ANY (ARRAY['info'::"text", 'warning'::"text", 'critical'::"text"])))
);


ALTER TABLE "public"."system_audit_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."theatre_cases" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "procedure_name" "text" NOT NULL,
    "theatre" "text",
    "surgeon_id" "uuid",
    "anaesthetist_id" "uuid",
    "scheduled_at" timestamp with time zone,
    "status" "text" DEFAULT 'planned'::"text" NOT NULL,
    "anaesthetic_cleared" boolean DEFAULT false NOT NULL,
    "consent_confirmed" boolean DEFAULT false NOT NULL,
    "notes" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "theatre_cases_status_check" CHECK (("status" = ANY (ARRAY['planned'::"text", 'cleared'::"text", 'in_progress'::"text", 'completed'::"text", 'cancelled'::"text", 'postponed'::"text"])))
);


ALTER TABLE "public"."theatre_cases" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."transfusion_records" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "blood_group" "text",
    "component" "text" NOT NULL,
    "unit_identifier" "text",
    "compatibility_checked" boolean DEFAULT false NOT NULL,
    "consent_confirmed" boolean DEFAULT false NOT NULL,
    "started_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "status" "text" DEFAULT 'planned'::"text" NOT NULL,
    "reaction_notes" "text",
    "administered_by" "uuid",
    "witnessed_by" "uuid",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "reaction_observed" boolean DEFAULT false NOT NULL,
    CONSTRAINT "transfusion_records_component_check" CHECK (("component" = ANY (ARRAY['whole_blood'::"text", 'red_cells'::"text", 'platelets'::"text", 'plasma'::"text", 'cryoprecipitate'::"text", 'other'::"text"]))),
    CONSTRAINT "transfusion_records_status_check" CHECK (("status" = ANY (ARRAY['planned'::"text", 'verified'::"text", 'running'::"text", 'completed'::"text", 'stopped'::"text", 'reaction'::"text"])))
);


ALTER TABLE "public"."transfusion_records" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."triage_assessments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "recorded_by" "uuid" NOT NULL,
    "systolic" integer NOT NULL,
    "diastolic" integer NOT NULL,
    "heart_rate" integer NOT NULL,
    "temperature" numeric(4,1) NOT NULL,
    "respiratory_rate" integer NOT NULL,
    "oxygen_saturation" numeric(5,2) NOT NULL,
    "weight_kg" numeric(6,2),
    "height_m" numeric(4,2),
    "pain_score" integer,
    "consciousness" "text",
    "presenting_complaint" "text",
    "clinical_notes" "text",
    "priority" "text" NOT NULL,
    "is_critical" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "bmi" numeric(5,2),
    CONSTRAINT "triage_assessments_diastolic_check" CHECK ((("diastolic" > 0) AND ("diastolic" < 300))),
    CONSTRAINT "triage_assessments_heart_rate_check" CHECK ((("heart_rate" > 0) AND ("heart_rate" < 300))),
    CONSTRAINT "triage_assessments_height_m_check" CHECK ((("height_m" IS NULL) OR ("height_m" > (0)::numeric))),
    CONSTRAINT "triage_assessments_oxygen_saturation_check" CHECK ((("oxygen_saturation" >= (0)::numeric) AND ("oxygen_saturation" <= (100)::numeric))),
    CONSTRAINT "triage_assessments_pain_score_check" CHECK ((("pain_score" IS NULL) OR (("pain_score" >= 0) AND ("pain_score" <= 10)))),
    CONSTRAINT "triage_assessments_priority_check" CHECK (("priority" = ANY (ARRAY['critical'::"text", 'urgent'::"text", 'moderate'::"text", 'routine'::"text"]))),
    CONSTRAINT "triage_assessments_respiratory_rate_check" CHECK ((("respiratory_rate" > 0) AND ("respiratory_rate" < 100))),
    CONSTRAINT "triage_assessments_systolic_check" CHECK ((("systolic" > 0) AND ("systolic" < 400))),
    CONSTRAINT "triage_assessments_temperature_check" CHECK ((("temperature" > (20)::numeric) AND ("temperature" < (50)::numeric))),
    CONSTRAINT "triage_assessments_weight_kg_check" CHECK ((("weight_kg" IS NULL) OR ("weight_kg" > (0)::numeric)))
);


ALTER TABLE "public"."triage_assessments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_roles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role" "public"."app_role" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."user_roles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."video_sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "appointment_id" "uuid",
    "patient_id" "uuid" NOT NULL,
    "practitioner_id" "uuid",
    "room_name" "text" NOT NULL,
    "provider" "text" DEFAULT 'daily'::"text",
    "scheduled_at" timestamp with time zone NOT NULL,
    "started_at" timestamp with time zone,
    "ended_at" timestamp with time zone,
    "status" "text" DEFAULT 'scheduled'::"text" NOT NULL,
    "payment_required" boolean DEFAULT true,
    "payment_received" boolean DEFAULT false,
    "recording_url" "text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE ONLY "public"."video_sessions" REPLICA IDENTITY FULL;


ALTER TABLE "public"."video_sessions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."vital_signs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "appointment_id" "uuid",
    "recorded_by" "uuid",
    "systolic" integer,
    "diastolic" integer,
    "pulse_rate" integer,
    "temperature" numeric(4,1),
    "respiratory_rate" integer,
    "oxygen_saturation" integer,
    "weight_kg" numeric(5,2),
    "height_cm" numeric(5,2),
    "bmi" numeric(4,1),
    "priority" "text",
    "notes" "text",
    "recorded_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE ONLY "public"."vital_signs" REPLICA IDENTITY FULL;


ALTER TABLE "public"."vital_signs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."wards" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "code" "text" NOT NULL,
    "department" "text",
    "floor" "text",
    "gender_policy" "text" DEFAULT 'mixed'::"text" NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "wards_gender_policy_check" CHECK (("gender_policy" = ANY (ARRAY['mixed'::"text", 'male'::"text", 'female'::"text", 'paediatric'::"text"])))
);


ALTER TABLE "public"."wards" OWNER TO "postgres";


ALTER TABLE ONLY "public"."admissions"
    ADD CONSTRAINT "admissions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ai_clinical_events"
    ADD CONSTRAINT "ai_clinical_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ai_clinical_sessions"
    ADD CONSTRAINT "ai_clinical_sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."appointments"
    ADD CONSTRAINT "appointments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."beds"
    ADD CONSTRAINT "beds_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."beds"
    ADD CONSTRAINT "beds_ward_id_bed_number_key" UNIQUE ("ward_id", "bed_number");



ALTER TABLE ONLY "public"."billing_item_payments"
    ADD CONSTRAINT "billing_item_payments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."care_transitions"
    ADD CONSTRAINT "care_transitions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."dental_records"
    ADD CONSTRAINT "dental_records_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."department_queues"
    ADD CONSTRAINT "department_queues_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."diagnoses"
    ADD CONSTRAINT "diagnoses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."emergency_cases"
    ADD CONSTRAINT "emergency_cases_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."encounters"
    ADD CONSTRAINT "encounters_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."facility_configuration"
    ADD CONSTRAINT "facility_configuration_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."facility_settings"
    ADD CONSTRAINT "facility_settings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."fertility_cycles"
    ADD CONSTRAINT "fertility_cycles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."fertility_monitoring"
    ADD CONSTRAINT "fertility_monitoring_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."imaging_orders"
    ADD CONSTRAINT "imaging_orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."insurance_cases"
    ADD CONSTRAINT "insurance_cases_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."insurance_claims"
    ADD CONSTRAINT "insurance_claims_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invoice_items"
    ADD CONSTRAINT "invoice_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invoices"
    ADD CONSTRAINT "invoices_invoice_number_key" UNIQUE ("invoice_number");



ALTER TABLE ONLY "public"."invoices"
    ADD CONSTRAINT "invoices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."lab_orders"
    ADD CONSTRAINT "lab_orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."lab_results"
    ADD CONSTRAINT "lab_results_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."maternity_episodes"
    ADD CONSTRAINT "maternity_episodes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."maternity_observations"
    ADD CONSTRAINT "maternity_observations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."medication_administrations"
    ADD CONSTRAINT "medication_administrations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nursing_care_plans"
    ADD CONSTRAINT "nursing_care_plans_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nursing_shift_handovers"
    ADD CONSTRAINT "nursing_shift_handovers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ophthalmology_exams"
    ADD CONSTRAINT "ophthalmology_exams_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."outside_lab_documents"
    ADD CONSTRAINT "outside_lab_documents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."patient_audit"
    ADD CONSTRAINT "patient_audit_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."patient_documents"
    ADD CONSTRAINT "patient_documents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."patient_referrals"
    ADD CONSTRAINT "patient_referrals_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."patients"
    ADD CONSTRAINT "patients_patient_code_key" UNIQUE ("patient_code");



ALTER TABLE ONLY "public"."patients"
    ADD CONSTRAINT "patients_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."prescriptions"
    ADD CONSTRAINT "prescriptions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."procedure_notes"
    ADD CONSTRAINT "procedure_notes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."service_orders"
    ADD CONSTRAINT "service_orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."service_tariffs"
    ADD CONSTRAINT "service_tariffs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."service_tariffs"
    ADD CONSTRAINT "service_tariffs_service_code_key" UNIQUE ("service_code");



ALTER TABLE ONLY "public"."staff_shift_assignments"
    ADD CONSTRAINT "staff_shift_assignments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."system_audit_log"
    ADD CONSTRAINT "system_audit_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."theatre_cases"
    ADD CONSTRAINT "theatre_cases_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."transfusion_records"
    ADD CONSTRAINT "transfusion_records_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."triage_assessments"
    ADD CONSTRAINT "triage_assessments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_user_id_role_key" UNIQUE ("user_id", "role");



ALTER TABLE ONLY "public"."video_sessions"
    ADD CONSTRAINT "video_sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."vital_signs"
    ADD CONSTRAINT "vital_signs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wards"
    ADD CONSTRAINT "wards_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."wards"
    ADD CONSTRAINT "wards_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_admissions_admitting_practitioner_id" ON "public"."admissions" USING "btree" ("admitting_practitioner");



CREATE INDEX "idx_admissions_created_by" ON "public"."admissions" USING "btree" ("created_by");



CREATE INDEX "idx_admissions_patient_time" ON "public"."admissions" USING "btree" ("patient_id", "admitted_at" DESC);



CREATE INDEX "idx_ai_clinical_events_session_time" ON "public"."ai_clinical_events" USING "btree" ("session_id", "created_at" DESC);



CREATE INDEX "idx_ai_clinical_sessions_patient_time" ON "public"."ai_clinical_sessions" USING "btree" ("patient_id", "created_at" DESC);



CREATE INDEX "idx_appointments_attending_officer" ON "public"."appointments" USING "btree" ("attending_officer_id", "scheduled_at" DESC);



CREATE INDEX "idx_appointments_patient_schedule" ON "public"."appointments" USING "btree" ("patient_id", "scheduled_at" DESC);



CREATE INDEX "idx_appointments_practitioner_id" ON "public"."appointments" USING "btree" ("practitioner_id");



CREATE INDEX "idx_appointments_treatment_status" ON "public"."appointments" USING "btree" ("treatment_status", "scheduled_at" DESC);



CREATE INDEX "idx_beds_patient" ON "public"."beds" USING "btree" ("patient_id");



CREATE INDEX "idx_beds_ward_status" ON "public"."beds" USING "btree" ("ward_id", "status");



CREATE INDEX "idx_billing_item_payments_invoice_item_id" ON "public"."billing_item_payments" USING "btree" ("invoice_item_id");



CREATE INDEX "idx_billing_item_payments_payment_id" ON "public"."billing_item_payments" USING "btree" ("payment_id");



CREATE INDEX "idx_care_transitions_patient" ON "public"."care_transitions" USING "btree" ("patient_id", "created_at" DESC);



CREATE INDEX "idx_care_transitions_status" ON "public"."care_transitions" USING "btree" ("status", "transition_type");



CREATE INDEX "idx_careplans_patient_status" ON "public"."nursing_care_plans" USING "btree" ("patient_id", "status");



CREATE INDEX "idx_dental_records_patient" ON "public"."dental_records" USING "btree" ("patient_id", "created_at" DESC);



CREATE INDEX "idx_diagnoses_encounter_created_at" ON "public"."diagnoses" USING "btree" ("encounter_id", "created_at" DESC);



CREATE INDEX "idx_dq_dept_status" ON "public"."department_queues" USING "btree" ("department", "status");



CREATE INDEX "idx_dq_priority" ON "public"."department_queues" USING "btree" ("priority");



CREATE INDEX "idx_emergency_status_priority" ON "public"."emergency_cases" USING "btree" ("status", "triage_priority", "arrival_at");



CREATE INDEX "idx_encounters_appointment_id" ON "public"."encounters" USING "btree" ("appointment_id") WHERE ("appointment_id" IS NOT NULL);



CREATE INDEX "idx_encounters_patient_created_at" ON "public"."encounters" USING "btree" ("patient_id", "created_at" DESC);



CREATE INDEX "idx_encounters_practitioner_id" ON "public"."encounters" USING "btree" ("practitioner_id");



CREATE INDEX "idx_fertility_cycles_assigned_specialist" ON "public"."fertility_cycles" USING "btree" ("assigned_specialist");



CREATE INDEX "idx_fertility_cycles_patient_id" ON "public"."fertility_cycles" USING "btree" ("patient_id");



CREATE INDEX "idx_fertility_monitoring_cycle_id" ON "public"."fertility_monitoring" USING "btree" ("cycle_id");



CREATE INDEX "idx_fertility_monitoring_recorded_by" ON "public"."fertility_monitoring" USING "btree" ("recorded_by");



CREATE INDEX "idx_handover_patient_date" ON "public"."nursing_shift_handovers" USING "btree" ("patient_id", "shift_date" DESC);



CREATE INDEX "idx_imaging_orders_patient" ON "public"."imaging_orders" USING "btree" ("patient_id", "created_at" DESC);



CREATE INDEX "idx_imaging_orders_status" ON "public"."imaging_orders" USING "btree" ("status", "created_at" DESC);



CREATE INDEX "idx_insurance_claims_invoice_id" ON "public"."insurance_claims" USING "btree" ("invoice_id");



CREATE INDEX "idx_insurance_claims_patient_id" ON "public"."insurance_claims" USING "btree" ("patient_id");



CREATE INDEX "idx_insurance_patient_status" ON "public"."insurance_cases" USING "btree" ("patient_id", "claim_status");



CREATE INDEX "idx_invoice_items_invoice_id" ON "public"."invoice_items" USING "btree" ("invoice_id");



CREATE INDEX "idx_invoice_items_service_order" ON "public"."invoice_items" USING "btree" ("service_order_id");



CREATE INDEX "idx_invoice_items_source" ON "public"."invoice_items" USING "btree" ("source_type", "source_id");



CREATE INDEX "idx_invoices_created_by" ON "public"."invoices" USING "btree" ("created_by");



CREATE INDEX "idx_invoices_encounter_id" ON "public"."invoices" USING "btree" ("encounter_id");



CREATE INDEX "idx_invoices_patient_id" ON "public"."invoices" USING "btree" ("patient_id");



CREATE INDEX "idx_lab_orders_collected_by" ON "public"."lab_orders" USING "btree" ("collected_by");



CREATE INDEX "idx_lab_orders_encounter_id" ON "public"."lab_orders" USING "btree" ("encounter_id");



CREATE INDEX "idx_lab_orders_ordered_by" ON "public"."lab_orders" USING "btree" ("ordered_by");



CREATE INDEX "idx_lab_orders_patient_id" ON "public"."lab_orders" USING "btree" ("patient_id");



CREATE INDEX "idx_lab_results_approved_by" ON "public"."lab_results" USING "btree" ("approved_by");



CREATE INDEX "idx_lab_results_entered_by" ON "public"."lab_results" USING "btree" ("entered_by");



CREATE INDEX "idx_lab_results_lab_order_id" ON "public"."lab_results" USING "btree" ("lab_order_id");



CREATE INDEX "idx_mar_patient_time" ON "public"."medication_administrations" USING "btree" ("patient_id", "scheduled_at" DESC);



CREATE INDEX "idx_mar_status_time" ON "public"."medication_administrations" USING "btree" ("status", "scheduled_at");



CREATE INDEX "idx_maternity_episodes_patient" ON "public"."maternity_episodes" USING "btree" ("patient_id", "created_at" DESC);



CREATE INDEX "idx_maternity_observations_episode" ON "public"."maternity_observations" USING "btree" ("episode_id", "observed_at" DESC);



CREATE INDEX "idx_notif_created" ON "public"."notifications" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_notif_role_unread" ON "public"."notifications" USING "btree" ("recipient_role") WHERE ("is_read" = false);



CREATE INDEX "idx_notif_user_unread" ON "public"."notifications" USING "btree" ("recipient_user_id") WHERE ("is_read" = false);



CREATE INDEX "idx_ophthalmology_exams_patient" ON "public"."ophthalmology_exams" USING "btree" ("patient_id", "created_at" DESC);



CREATE INDEX "idx_outside_lab_documents_patient" ON "public"."outside_lab_documents" USING "btree" ("patient_id", "created_at" DESC);



CREATE INDEX "idx_patient_audit_actor_time" ON "public"."patient_audit" USING "btree" ("actor_user_id", "occurred_at" DESC);



CREATE INDEX "idx_patient_audit_patient_time" ON "public"."patient_audit" USING "btree" ("patient_id", "occurred_at" DESC);



CREATE INDEX "idx_patient_documents_patient_time" ON "public"."patient_documents" USING "btree" ("patient_id", "created_at" DESC);



CREATE INDEX "idx_patient_documents_uploaded_by" ON "public"."patient_documents" USING "btree" ("uploaded_by");



CREATE INDEX "idx_patient_referrals_patient" ON "public"."patient_referrals" USING "btree" ("patient_id", "created_at" DESC);



CREATE INDEX "idx_patient_referrals_status" ON "public"."patient_referrals" USING "btree" ("status", "urgency", "created_at" DESC);



CREATE INDEX "idx_patients_created_by" ON "public"."patients" USING "btree" ("created_by");



CREATE INDEX "idx_patients_patient_code" ON "public"."patients" USING "btree" ("patient_code");



CREATE INDEX "idx_patients_user_id" ON "public"."patients" USING "btree" ("user_id");



CREATE INDEX "idx_payments_invoice_id" ON "public"."payments" USING "btree" ("invoice_id");



CREATE INDEX "idx_payments_patient_id" ON "public"."payments" USING "btree" ("patient_id");



CREATE INDEX "idx_payments_received_by" ON "public"."payments" USING "btree" ("received_by");



CREATE INDEX "idx_prescriptions_dispensed_by" ON "public"."prescriptions" USING "btree" ("dispensed_by");



CREATE INDEX "idx_prescriptions_encounter_id" ON "public"."prescriptions" USING "btree" ("encounter_id");



CREATE INDEX "idx_prescriptions_patient_id" ON "public"."prescriptions" USING "btree" ("patient_id");



CREATE INDEX "idx_prescriptions_prescribed_by" ON "public"."prescriptions" USING "btree" ("prescribed_by");



CREATE INDEX "idx_procedure_notes_patient" ON "public"."procedure_notes" USING "btree" ("patient_id", "created_at" DESC);



CREATE INDEX "idx_service_orders_created_by" ON "public"."service_orders" USING "btree" ("created_by");



CREATE INDEX "idx_service_orders_invoice_id" ON "public"."service_orders" USING "btree" ("invoice_id");



CREATE INDEX "idx_service_orders_invoice_item_id" ON "public"."service_orders" USING "btree" ("invoice_item_id");



CREATE INDEX "idx_service_orders_patient_status" ON "public"."service_orders" USING "btree" ("patient_id", "status", "created_at" DESC);



CREATE INDEX "idx_service_orders_related" ON "public"."service_orders" USING "btree" ("related_entity_id");



CREATE INDEX "idx_service_orders_requested_by" ON "public"."service_orders" USING "btree" ("requested_by");



CREATE INDEX "idx_staff_shift_on_duty" ON "public"."staff_shift_assignments" USING "btree" ("department", "starts_at", "ends_at") WHERE "active";



CREATE INDEX "idx_system_audit_log_actor" ON "public"."system_audit_log" USING "btree" ("actor_id", "created_at" DESC);



CREATE INDEX "idx_system_audit_log_created_at" ON "public"."system_audit_log" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_system_audit_log_module" ON "public"."system_audit_log" USING "btree" ("module", "created_at" DESC);



CREATE INDEX "idx_theatre_schedule_status" ON "public"."theatre_cases" USING "btree" ("scheduled_at", "status");



CREATE INDEX "idx_transfusion_patient_status" ON "public"."transfusion_records" USING "btree" ("patient_id", "status");



CREATE INDEX "idx_triage_assessments_patient_created_at" ON "public"."triage_assessments" USING "btree" ("patient_id", "created_at" DESC);



CREATE INDEX "idx_triage_assessments_recorded_by" ON "public"."triage_assessments" USING "btree" ("recorded_by");



CREATE INDEX "idx_triage_patient_bmi_time" ON "public"."triage_assessments" USING "btree" ("patient_id", "created_at" DESC) WHERE ("bmi" IS NOT NULL);



CREATE INDEX "idx_triage_priority_time" ON "public"."triage_assessments" USING "btree" ("priority", "created_at" DESC);



CREATE INDEX "idx_video_sessions_appointment_id" ON "public"."video_sessions" USING "btree" ("appointment_id");



CREATE INDEX "idx_video_sessions_patient_id" ON "public"."video_sessions" USING "btree" ("patient_id");



CREATE INDEX "idx_video_sessions_practitioner_id" ON "public"."video_sessions" USING "btree" ("practitioner_id");



CREATE INDEX "idx_vital_signs_appointment_id" ON "public"."vital_signs" USING "btree" ("appointment_id");



CREATE INDEX "idx_vital_signs_patient_id" ON "public"."vital_signs" USING "btree" ("patient_id");



CREATE INDEX "idx_vital_signs_recorded_by" ON "public"."vital_signs" USING "btree" ("recorded_by");



CREATE UNIQUE INDEX "ux_facility_configuration_singleton" ON "public"."facility_configuration" USING "btree" ((true));



CREATE OR REPLACE TRIGGER "payments_refresh_invoice" AFTER INSERT OR DELETE OR UPDATE ON "public"."payments" FOR EACH ROW EXECUTE FUNCTION "public"."refresh_invoice_totals"();



CREATE OR REPLACE TRIGGER "t_admissions_updated" BEFORE UPDATE ON "public"."admissions" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "t_appointments_updated" BEFORE UPDATE ON "public"."appointments" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "t_beds_updated_at" BEFORE UPDATE ON "public"."beds" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "t_emergency_cases_updated_at" BEFORE UPDATE ON "public"."emergency_cases" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "t_encounters_updated" BEFORE UPDATE ON "public"."encounters" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "t_facility_configuration_updated_at" BEFORE UPDATE ON "public"."facility_configuration" FOR EACH ROW EXECUTE FUNCTION "public"."touch_global_hims_updated_at"();



CREATE OR REPLACE TRIGGER "t_fertility_cycles_updated" BEFORE UPDATE ON "public"."fertility_cycles" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "t_insurance_cases_updated_at" BEFORE UPDATE ON "public"."insurance_cases" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "t_invoices_updated" BEFORE UPDATE ON "public"."invoices" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "t_lab_orders_updated" BEFORE UPDATE ON "public"."lab_orders" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "t_lab_results_updated" BEFORE UPDATE ON "public"."lab_results" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "t_mar_updated_at" BEFORE UPDATE ON "public"."medication_administrations" FOR EACH ROW EXECUTE FUNCTION "public"."touch_mar_updated_at"();



CREATE OR REPLACE TRIGGER "t_maternity_episode_updated_at" BEFORE UPDATE ON "public"."maternity_episodes" FOR EACH ROW EXECUTE FUNCTION "public"."touch_global_hims_updated_at"();



CREATE OR REPLACE TRIGGER "t_nursing_care_plans_updated_at" BEFORE UPDATE ON "public"."nursing_care_plans" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "t_patient_documents_updated" BEFORE UPDATE ON "public"."patient_documents" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "t_patients_updated" BEFORE UPDATE ON "public"."patients" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "t_profiles_updated" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "t_referral_updated_at" BEFORE UPDATE ON "public"."patient_referrals" FOR EACH ROW EXECUTE FUNCTION "public"."touch_care_transition_updated_at"();



CREATE OR REPLACE TRIGGER "t_theatre_cases_updated_at" BEFORE UPDATE ON "public"."theatre_cases" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "t_transfusion_records_updated_at" BEFORE UPDATE ON "public"."transfusion_records" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "t_transition_updated_at" BEFORE UPDATE ON "public"."care_transitions" FOR EACH ROW EXECUTE FUNCTION "public"."touch_care_transition_updated_at"();



CREATE OR REPLACE TRIGGER "t_triage_updated" BEFORE UPDATE ON "public"."triage_assessments" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "t_wards_updated_at" BEFORE UPDATE ON "public"."wards" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "trg_calculate_triage_bmi" BEFORE INSERT OR UPDATE OF "weight_kg", "height_m" ON "public"."triage_assessments" FOR EACH ROW EXECUTE FUNCTION "public"."calculate_triage_bmi"();



CREATE OR REPLACE TRIGGER "trg_dq_touch" BEFORE UPDATE ON "public"."department_queues" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "trg_patient_audit" AFTER INSERT OR DELETE OR UPDATE ON "public"."patients" FOR EACH ROW EXECUTE FUNCTION "public"."audit_patient_change"();



CREATE OR REPLACE TRIGGER "trg_patient_code" BEFORE INSERT ON "public"."patients" FOR EACH ROW EXECUTE FUNCTION "public"."generate_patient_code"();



CREATE OR REPLACE TRIGGER "trg_refresh_invoice_totals" AFTER INSERT OR DELETE OR UPDATE ON "public"."payments" FOR EACH ROW EXECUTE FUNCTION "public"."refresh_invoice_totals"();



ALTER TABLE ONLY "public"."admissions"
    ADD CONSTRAINT "admissions_admitting_practitioner_fkey" FOREIGN KEY ("admitting_practitioner") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."admissions"
    ADD CONSTRAINT "admissions_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."admissions"
    ADD CONSTRAINT "admissions_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "public"."patients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ai_clinical_events"
    ADD CONSTRAINT "ai_clinical_events_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."ai_clinical_events"
    ADD CONSTRAINT "ai_clinical_events_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."ai_clinical_sessions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ai_clinical_sessions"
    ADD CONSTRAINT "ai_clinical_sessions_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."ai_clinical_sessions"
    ADD CONSTRAINT "ai_clinical_sessions_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "public"."patients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ai_clinical_sessions"
    ADD CONSTRAINT "ai_clinical_sessions_reviewed_by_fkey" FOREIGN KEY ("reviewed_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."appointments"
    ADD CONSTRAINT "appointments_attending_officer_id_fkey" FOREIGN KEY ("attending_officer_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."appointments"
    ADD CONSTRAINT "appointments_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "public"."patients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."appointments"
    ADD CONSTRAINT "appointments_practitioner_id_fkey" FOREIGN KEY ("practitioner_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."beds"
    ADD CONSTRAINT "beds_ward_id_fkey" FOREIGN KEY ("ward_id") REFERENCES "public"."wards"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."billing_item_payments"
    ADD CONSTRAINT "billing_item_payments_invoice_item_id_fkey" FOREIGN KEY ("invoice_item_id") REFERENCES "public"."invoice_items"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."billing_item_payments"
    ADD CONSTRAINT "billing_item_payments_payment_id_fkey" FOREIGN KEY ("payment_id") REFERENCES "public"."payments"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."care_transitions"
    ADD CONSTRAINT "care_transitions_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "public"."patients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."care_transitions"
    ADD CONSTRAINT "care_transitions_responsible_officer_fkey" FOREIGN KEY ("responsible_officer") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."dental_records"
    ADD CONSTRAINT "dental_records_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "public"."patients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dental_records"
    ADD CONSTRAINT "dental_records_performed_by_fkey" FOREIGN KEY ("performed_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."diagnoses"
    ADD CONSTRAINT "diagnoses_encounter_id_fkey" FOREIGN KEY ("encounter_id") REFERENCES "public"."encounters"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."emergency_cases"
    ADD CONSTRAINT "emergency_cases_assigned_officer_fkey" FOREIGN KEY ("assigned_officer") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."encounters"
    ADD CONSTRAINT "encounters_appointment_id_fkey" FOREIGN KEY ("appointment_id") REFERENCES "public"."appointments"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."encounters"
    ADD CONSTRAINT "encounters_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "public"."patients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."encounters"
    ADD CONSTRAINT "encounters_practitioner_id_fkey" FOREIGN KEY ("practitioner_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."facility_configuration"
    ADD CONSTRAINT "facility_configuration_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."fertility_cycles"
    ADD CONSTRAINT "fertility_cycles_assigned_specialist_fkey" FOREIGN KEY ("assigned_specialist") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."fertility_cycles"
    ADD CONSTRAINT "fertility_cycles_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "public"."patients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."fertility_monitoring"
    ADD CONSTRAINT "fertility_monitoring_cycle_id_fkey" FOREIGN KEY ("cycle_id") REFERENCES "public"."fertility_cycles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."fertility_monitoring"
    ADD CONSTRAINT "fertility_monitoring_recorded_by_fkey" FOREIGN KEY ("recorded_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."imaging_orders"
    ADD CONSTRAINT "imaging_orders_encounter_id_fkey" FOREIGN KEY ("encounter_id") REFERENCES "public"."encounters"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."imaging_orders"
    ADD CONSTRAINT "imaging_orders_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "public"."patients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."imaging_orders"
    ADD CONSTRAINT "imaging_orders_performed_by_fkey" FOREIGN KEY ("performed_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."imaging_orders"
    ADD CONSTRAINT "imaging_orders_requested_by_fkey" FOREIGN KEY ("requested_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."imaging_orders"
    ADD CONSTRAINT "imaging_orders_service_order_id_fkey" FOREIGN KEY ("service_order_id") REFERENCES "public"."service_orders"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."insurance_cases"
    ADD CONSTRAINT "insurance_cases_checked_by_fkey" FOREIGN KEY ("checked_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."insurance_claims"
    ADD CONSTRAINT "insurance_claims_invoice_id_fkey" FOREIGN KEY ("invoice_id") REFERENCES "public"."invoices"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."insurance_claims"
    ADD CONSTRAINT "insurance_claims_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "public"."patients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."invoice_items"
    ADD CONSTRAINT "invoice_items_invoice_id_fkey" FOREIGN KEY ("invoice_id") REFERENCES "public"."invoices"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."invoice_items"
    ADD CONSTRAINT "invoice_items_service_order_id_fkey" FOREIGN KEY ("service_order_id") REFERENCES "public"."service_orders"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."invoices"
    ADD CONSTRAINT "invoices_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."invoices"
    ADD CONSTRAINT "invoices_encounter_id_fkey" FOREIGN KEY ("encounter_id") REFERENCES "public"."encounters"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."invoices"
    ADD CONSTRAINT "invoices_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "public"."patients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."lab_orders"
    ADD CONSTRAINT "lab_orders_collected_by_fkey" FOREIGN KEY ("collected_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."lab_orders"
    ADD CONSTRAINT "lab_orders_encounter_id_fkey" FOREIGN KEY ("encounter_id") REFERENCES "public"."encounters"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."lab_orders"
    ADD CONSTRAINT "lab_orders_ordered_by_fkey" FOREIGN KEY ("ordered_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."lab_orders"
    ADD CONSTRAINT "lab_orders_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "public"."patients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."lab_results"
    ADD CONSTRAINT "lab_results_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."lab_results"
    ADD CONSTRAINT "lab_results_entered_by_fkey" FOREIGN KEY ("entered_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."lab_results"
    ADD CONSTRAINT "lab_results_lab_order_id_fkey" FOREIGN KEY ("lab_order_id") REFERENCES "public"."lab_orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."maternity_episodes"
    ADD CONSTRAINT "maternity_episodes_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."maternity_episodes"
    ADD CONSTRAINT "maternity_episodes_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "public"."patients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."maternity_observations"
    ADD CONSTRAINT "maternity_observations_episode_id_fkey" FOREIGN KEY ("episode_id") REFERENCES "public"."maternity_episodes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."maternity_observations"
    ADD CONSTRAINT "maternity_observations_recorded_by_fkey" FOREIGN KEY ("recorded_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."medication_administrations"
    ADD CONSTRAINT "medication_administrations_administered_by_fkey" FOREIGN KEY ("administered_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."medication_administrations"
    ADD CONSTRAINT "medication_administrations_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "public"."patients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."medication_administrations"
    ADD CONSTRAINT "medication_administrations_witnessed_by_fkey" FOREIGN KEY ("witnessed_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."nursing_care_plans"
    ADD CONSTRAINT "nursing_care_plans_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."nursing_care_plans"
    ADD CONSTRAINT "nursing_care_plans_reviewed_by_fkey" FOREIGN KEY ("reviewed_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."nursing_shift_handovers"
    ADD CONSTRAINT "nursing_shift_handovers_incoming_officer_fkey" FOREIGN KEY ("incoming_officer") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."nursing_shift_handovers"
    ADD CONSTRAINT "nursing_shift_handovers_outgoing_officer_fkey" FOREIGN KEY ("outgoing_officer") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."ophthalmology_exams"
    ADD CONSTRAINT "ophthalmology_exams_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "public"."patients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ophthalmology_exams"
    ADD CONSTRAINT "ophthalmology_exams_performed_by_fkey" FOREIGN KEY ("performed_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."ophthalmology_exams"
    ADD CONSTRAINT "ophthalmology_exams_reviewed_by_fkey" FOREIGN KEY ("reviewed_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."outside_lab_documents"
    ADD CONSTRAINT "outside_lab_documents_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "public"."patients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."outside_lab_documents"
    ADD CONSTRAINT "outside_lab_documents_uploaded_by_fkey" FOREIGN KEY ("uploaded_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."patient_audit"
    ADD CONSTRAINT "patient_audit_actor_user_id_fkey" FOREIGN KEY ("actor_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."patient_audit"
    ADD CONSTRAINT "patient_audit_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "public"."patients"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."patient_documents"
    ADD CONSTRAINT "patient_documents_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "public"."patients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."patient_documents"
    ADD CONSTRAINT "patient_documents_uploaded_by_fkey" FOREIGN KEY ("uploaded_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."patient_referrals"
    ADD CONSTRAINT "patient_referrals_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "public"."patients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."patient_referrals"
    ADD CONSTRAINT "patient_referrals_referred_by_fkey" FOREIGN KEY ("referred_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."patients"
    ADD CONSTRAINT "patients_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."patients"
    ADD CONSTRAINT "patients_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_invoice_id_fkey" FOREIGN KEY ("invoice_id") REFERENCES "public"."invoices"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "public"."patients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_received_by_fkey" FOREIGN KEY ("received_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."prescriptions"
    ADD CONSTRAINT "prescriptions_dispensed_by_fkey" FOREIGN KEY ("dispensed_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."prescriptions"
    ADD CONSTRAINT "prescriptions_encounter_id_fkey" FOREIGN KEY ("encounter_id") REFERENCES "public"."encounters"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."prescriptions"
    ADD CONSTRAINT "prescriptions_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "public"."patients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."prescriptions"
    ADD CONSTRAINT "prescriptions_prescribed_by_fkey" FOREIGN KEY ("prescribed_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."procedure_notes"
    ADD CONSTRAINT "procedure_notes_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "public"."patients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."procedure_notes"
    ADD CONSTRAINT "procedure_notes_performed_by_fkey" FOREIGN KEY ("performed_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."procedure_notes"
    ADD CONSTRAINT "procedure_notes_service_order_id_fkey" FOREIGN KEY ("service_order_id") REFERENCES "public"."service_orders"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."service_orders"
    ADD CONSTRAINT "service_orders_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."service_orders"
    ADD CONSTRAINT "service_orders_invoice_id_fkey" FOREIGN KEY ("invoice_id") REFERENCES "public"."invoices"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."service_orders"
    ADD CONSTRAINT "service_orders_invoice_item_id_fkey" FOREIGN KEY ("invoice_item_id") REFERENCES "public"."invoice_items"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."service_orders"
    ADD CONSTRAINT "service_orders_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "public"."patients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."service_orders"
    ADD CONSTRAINT "service_orders_requested_by_fkey" FOREIGN KEY ("requested_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."staff_shift_assignments"
    ADD CONSTRAINT "staff_shift_assignments_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."system_audit_log"
    ADD CONSTRAINT "system_audit_log_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."theatre_cases"
    ADD CONSTRAINT "theatre_cases_anaesthetist_id_fkey" FOREIGN KEY ("anaesthetist_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."theatre_cases"
    ADD CONSTRAINT "theatre_cases_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."theatre_cases"
    ADD CONSTRAINT "theatre_cases_surgeon_id_fkey" FOREIGN KEY ("surgeon_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."transfusion_records"
    ADD CONSTRAINT "transfusion_records_administered_by_fkey" FOREIGN KEY ("administered_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."transfusion_records"
    ADD CONSTRAINT "transfusion_records_witnessed_by_fkey" FOREIGN KEY ("witnessed_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."triage_assessments"
    ADD CONSTRAINT "triage_assessments_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "public"."patients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."triage_assessments"
    ADD CONSTRAINT "triage_assessments_recorded_by_fkey" FOREIGN KEY ("recorded_by") REFERENCES "auth"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."video_sessions"
    ADD CONSTRAINT "video_sessions_appointment_id_fkey" FOREIGN KEY ("appointment_id") REFERENCES "public"."appointments"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."video_sessions"
    ADD CONSTRAINT "video_sessions_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "public"."patients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."video_sessions"
    ADD CONSTRAINT "video_sessions_practitioner_id_fkey" FOREIGN KEY ("practitioner_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."vital_signs"
    ADD CONSTRAINT "vital_signs_appointment_id_fkey" FOREIGN KEY ("appointment_id") REFERENCES "public"."appointments"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."vital_signs"
    ADD CONSTRAINT "vital_signs_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "public"."patients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."vital_signs"
    ADD CONSTRAINT "vital_signs_recorded_by_fkey" FOREIGN KEY ("recorded_by") REFERENCES "auth"."users"("id");



CREATE POLICY "AI clinical events read" ON "public"."ai_clinical_events" FOR SELECT TO "authenticated" USING (("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'practitioner'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'nurse'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'midwife'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'pharmacist'::"public"."app_role")));



CREATE POLICY "AI clinical session read" ON "public"."ai_clinical_sessions" FOR SELECT TO "authenticated" USING (("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'practitioner'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'nurse'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'midwife'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'pharmacist'::"public"."app_role") OR ("created_by" = "auth"."uid"())));



CREATE POLICY "admins delete profiles" ON "public"."profiles" FOR DELETE TO "authenticated" USING (( SELECT "public"."current_user_has_role"('admin'::"public"."app_role") AS "current_user_has_role"));



CREATE POLICY "admins insert profiles" ON "public"."profiles" FOR INSERT TO "authenticated" WITH CHECK (( SELECT "public"."current_user_has_role"('admin'::"public"."app_role") AS "current_user_has_role"));



CREATE POLICY "admins read patient audit" ON "public"."patient_audit" FOR SELECT TO "authenticated" USING ("public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'admin'::"public"."app_role"));



CREATE POLICY "admins update triage" ON "public"."triage_assessments" FOR UPDATE TO "authenticated" USING ("public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'admin'::"public"."app_role")) WITH CHECK ("public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'admin'::"public"."app_role"));



ALTER TABLE "public"."admissions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ai_clinical_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ai_clinical_sessions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."appointments" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "authorized users read patient documents" ON "public"."patient_documents" FOR SELECT TO "authenticated" USING ((( SELECT "public"."current_user_is_clinical_staff"() AS "current_user_is_clinical_staff") OR ( SELECT "public"."current_user_has_role"('accountant'::"public"."app_role") AS "current_user_has_role")));



CREATE POLICY "authorized users read patients" ON "public"."patients" FOR SELECT TO "authenticated" USING ((("user_id" = ( SELECT "auth"."uid"() AS "uid")) OR ( SELECT "public"."current_user_is_clinical_staff"() AS "current_user_is_clinical_staff") OR ( SELECT "public"."current_user_has_role"('accountant'::"public"."app_role") AS "current_user_has_role")));



CREATE POLICY "authorized users read profiles" ON "public"."profiles" FOR SELECT TO "authenticated" USING ((("id" = ( SELECT "auth"."uid"() AS "uid")) OR ( SELECT "public"."current_user_is_clinical_staff"() AS "current_user_is_clinical_staff") OR ( SELECT "public"."current_user_has_role"('accountant'::"public"."app_role") AS "current_user_has_role")));



CREATE POLICY "authorized users read queues" ON "public"."department_queues" FOR SELECT TO "authenticated" USING (((EXISTS ( SELECT 1
   FROM "public"."patients" "p"
  WHERE (("p"."id" = "department_queues"."patient_id") AND ("p"."user_id" = ( SELECT "auth"."uid"() AS "uid"))))) OR ( SELECT "public"."current_user_is_clinical_staff"() AS "current_user_is_clinical_staff") OR ( SELECT "public"."current_user_has_role"('accountant'::"public"."app_role") AS "current_user_has_role")));



CREATE POLICY "authorized users update profiles" ON "public"."profiles" FOR UPDATE TO "authenticated" USING ((("id" = ( SELECT "auth"."uid"() AS "uid")) OR ( SELECT "public"."current_user_has_role"('admin'::"public"."app_role") AS "current_user_has_role"))) WITH CHECK ((("id" = ( SELECT "auth"."uid"() AS "uid")) OR ( SELECT "public"."current_user_has_role"('admin'::"public"."app_role") AS "current_user_has_role")));



ALTER TABLE "public"."beds" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."billing_item_payments" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "billing_item_payments_accounts_read" ON "public"."billing_item_payments" FOR SELECT TO "authenticated" USING (("public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'admin'::"public"."app_role") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'accountant'::"public"."app_role") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'front_desk'::"public"."app_role")));



CREATE POLICY "care referrals clinical access" ON "public"."patient_referrals" TO "authenticated" USING (("public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'admin'::"public"."app_role") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'practitioner'::"public"."app_role") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'nurse'::"public"."app_role") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'midwife'::"public"."app_role") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'front_desk'::"public"."app_role"))) WITH CHECK ((("referred_by" = ( SELECT "auth"."uid"() AS "uid")) OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'admin'::"public"."app_role")));



CREATE POLICY "care transitions clinical access" ON "public"."care_transitions" TO "authenticated" USING (("public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'admin'::"public"."app_role") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'practitioner'::"public"."app_role") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'nurse'::"public"."app_role") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'midwife'::"public"."app_role"))) WITH CHECK ((("responsible_officer" = ( SELECT "auth"."uid"() AS "uid")) OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'admin'::"public"."app_role")));



ALTER TABLE "public"."care_transitions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "clinical operations manage" ON "public"."beds" TO "authenticated" USING (("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'nurse'::"public"."app_role"))) WITH CHECK (("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'nurse'::"public"."app_role")));



CREATE POLICY "clinical operations read" ON "public"."wards" FOR SELECT TO "authenticated" USING (("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'practitioner'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'nurse'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'midwife'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'front_desk'::"public"."app_role")));



CREATE POLICY "clinical operations read beds" ON "public"."beds" FOR SELECT TO "authenticated" USING (("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'practitioner'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'nurse'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'midwife'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'front_desk'::"public"."app_role")));



CREATE POLICY "clinical staff create triage" ON "public"."triage_assessments" FOR INSERT TO "authenticated" WITH CHECK (((( SELECT "public"."current_user_is_clinical_staff"() AS "current_user_is_clinical_staff") OR ( SELECT "public"."current_user_has_role"('nurse'::"public"."app_role") AS "current_user_has_role")) AND ("recorded_by" = ( SELECT "auth"."uid"() AS "uid"))));



CREATE POLICY "clinical staff read triage" ON "public"."triage_assessments" FOR SELECT TO "authenticated" USING ((( SELECT "public"."current_user_is_clinical_staff"() AS "current_user_is_clinical_staff") OR ( SELECT "public"."current_user_has_role"('nurse'::"public"."app_role") AS "current_user_has_role") OR ( SELECT "public"."current_user_has_role"('admin'::"public"."app_role") AS "current_user_has_role")));



CREATE POLICY "dental clinical read" ON "public"."dental_records" FOR SELECT TO "authenticated" USING (("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'practitioner'::"public"."app_role")));



ALTER TABLE "public"."dental_records" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."department_queues" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."diagnoses" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "emergency clinical" ON "public"."emergency_cases" TO "authenticated" USING (("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'practitioner'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'nurse'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'midwife'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'front_desk'::"public"."app_role"))) WITH CHECK (("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'practitioner'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'nurse'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'midwife'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'front_desk'::"public"."app_role")));



ALTER TABLE "public"."emergency_cases" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."encounters" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "facility configuration admin manage" ON "public"."facility_configuration" TO "authenticated" USING ("public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'admin'::"public"."app_role")) WITH CHECK ("public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'admin'::"public"."app_role"));



CREATE POLICY "facility configuration authenticated read" ON "public"."facility_configuration" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "facility settings admin manage" ON "public"."facility_settings" TO "authenticated" USING ("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role")) WITH CHECK ("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role"));



CREATE POLICY "facility settings authenticated read" ON "public"."facility_settings" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."facility_configuration" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."facility_settings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."fertility_cycles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."fertility_monitoring" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "handover clinical" ON "public"."nursing_shift_handovers" TO "authenticated" USING (("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'nurse'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'midwife'::"public"."app_role"))) WITH CHECK (("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'nurse'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'midwife'::"public"."app_role")));



ALTER TABLE "public"."imaging_orders" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "imaging_orders_clinical_insert" ON "public"."imaging_orders" FOR INSERT TO "authenticated" WITH CHECK (("public"."is_clinical_staff"("auth"."uid"()) AND ("requested_by" = "auth"."uid"())));



CREATE POLICY "imaging_orders_clinical_read" ON "public"."imaging_orders" FOR SELECT TO "authenticated" USING (("public"."is_clinical_staff"("auth"."uid"()) OR ("patient_id" = "auth"."uid"())));



CREATE POLICY "insurance clinical accounts" ON "public"."insurance_cases" TO "authenticated" USING (("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'practitioner'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'front_desk'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'accountant'::"public"."app_role"))) WITH CHECK (("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'practitioner'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'front_desk'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'accountant'::"public"."app_role")));



ALTER TABLE "public"."insurance_cases" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."insurance_claims" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."invoice_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."invoices" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."lab_orders" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."lab_results" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "mar clinical access" ON "public"."medication_administrations" TO "authenticated" USING (("public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'admin'::"public"."app_role") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'practitioner'::"public"."app_role") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'nurse'::"public"."app_role") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'midwife'::"public"."app_role") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'pharmacist'::"public"."app_role"))) WITH CHECK ((("administered_by" IS NULL) OR ("administered_by" = ( SELECT "auth"."uid"() AS "uid")) OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'admin'::"public"."app_role")));



CREATE POLICY "maternity clinical read" ON "public"."maternity_episodes" FOR SELECT TO "authenticated" USING (("public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'admin'::"public"."app_role") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'practitioner'::"public"."app_role") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'nurse'::"public"."app_role") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'midwife'::"public"."app_role")));



CREATE POLICY "maternity clinical write" ON "public"."maternity_episodes" TO "authenticated" USING (("public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'admin'::"public"."app_role") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'practitioner'::"public"."app_role") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'nurse'::"public"."app_role") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'midwife'::"public"."app_role"))) WITH CHECK ((("created_by" = ( SELECT "auth"."uid"() AS "uid")) OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'admin'::"public"."app_role")));



CREATE POLICY "maternity observations clinical read" ON "public"."maternity_observations" FOR SELECT TO "authenticated" USING (("public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'admin'::"public"."app_role") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'practitioner'::"public"."app_role") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'nurse'::"public"."app_role") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'midwife'::"public"."app_role")));



CREATE POLICY "maternity observations clinical write" ON "public"."maternity_observations" TO "authenticated" USING (("public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'admin'::"public"."app_role") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'practitioner'::"public"."app_role") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'nurse'::"public"."app_role") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'midwife'::"public"."app_role"))) WITH CHECK ((("recorded_by" = ( SELECT "auth"."uid"() AS "uid")) OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'admin'::"public"."app_role")));



ALTER TABLE "public"."maternity_episodes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."maternity_observations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."medication_administrations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notifications" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "nursing care plans clinical" ON "public"."nursing_care_plans" TO "authenticated" USING (("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'practitioner'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'nurse'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'midwife'::"public"."app_role"))) WITH CHECK (("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'practitioner'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'nurse'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'midwife'::"public"."app_role")));



ALTER TABLE "public"."nursing_care_plans" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nursing_shift_handovers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ophthalmology clinical read" ON "public"."ophthalmology_exams" FOR SELECT TO "authenticated" USING (("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'practitioner'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'nurse'::"public"."app_role")));



ALTER TABLE "public"."ophthalmology_exams" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "outside lab staff read" ON "public"."outside_lab_documents" FOR SELECT TO "authenticated" USING (("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'practitioner'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'nurse'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'midwife'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'specialist_nurse'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'lab_technician'::"public"."app_role")));



ALTER TABLE "public"."outside_lab_documents" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."patient_audit" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."patient_documents" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."patient_referrals" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."patients" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "patients read own admissions" ON "public"."admissions" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."patients" "p"
  WHERE (("p"."id" = "admissions"."patient_id") AND ("p"."user_id" = ( SELECT "auth"."uid"() AS "uid"))))));



ALTER TABLE "public"."payments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."prescriptions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "procedure clinical read" ON "public"."procedure_notes" FOR SELECT TO "authenticated" USING (("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'practitioner'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'nurse'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'midwife'::"public"."app_role")));



ALTER TABLE "public"."procedure_notes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."service_orders" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "service_orders_authenticated_read" ON "public"."service_orders" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."service_tariffs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "service_tariffs_authenticated_read" ON "public"."service_tariffs" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "staff delete admissions" ON "public"."admissions" FOR DELETE TO "authenticated" USING (( SELECT "public"."current_user_is_clinical_staff"() AS "current_user_is_clinical_staff"));



CREATE POLICY "staff delete patient documents" ON "public"."patient_documents" FOR DELETE TO "authenticated" USING (( SELECT "public"."current_user_can_edit_patient_record"() AS "current_user_can_edit_patient_record"));



CREATE POLICY "staff delete patients" ON "public"."patients" FOR DELETE TO "authenticated" USING (( SELECT "public"."current_user_is_clinical_staff"() AS "current_user_is_clinical_staff"));



CREATE POLICY "staff delete queues" ON "public"."department_queues" FOR DELETE TO "authenticated" USING ((( SELECT "public"."current_user_is_clinical_staff"() AS "current_user_is_clinical_staff") OR ( SELECT "public"."current_user_has_role"('accountant'::"public"."app_role") AS "current_user_has_role")));



CREATE POLICY "staff insert admissions" ON "public"."admissions" FOR INSERT TO "authenticated" WITH CHECK (( SELECT "public"."current_user_is_clinical_staff"() AS "current_user_is_clinical_staff"));



CREATE POLICY "staff insert notifications" ON "public"."notifications" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "public"."current_user_is_clinical_staff"() AS "current_user_is_clinical_staff") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'accountant'::"public"."app_role") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'admin'::"public"."app_role")));



CREATE POLICY "staff insert patient documents" ON "public"."patient_documents" FOR INSERT TO "authenticated" WITH CHECK (( SELECT "public"."current_user_can_edit_patient_record"() AS "current_user_can_edit_patient_record"));



CREATE POLICY "staff insert patients" ON "public"."patients" FOR INSERT TO "authenticated" WITH CHECK (( SELECT "public"."current_user_is_clinical_staff"() AS "current_user_is_clinical_staff"));



CREATE POLICY "staff insert queues" ON "public"."department_queues" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "public"."current_user_is_clinical_staff"() AS "current_user_is_clinical_staff") OR ( SELECT "public"."current_user_has_role"('accountant'::"public"."app_role") AS "current_user_has_role")));



CREATE POLICY "staff manage appointments" ON "public"."appointments" TO "authenticated" USING ((( SELECT "public"."current_user_is_clinical_staff"() AS "current_user_is_clinical_staff") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'admin'::"public"."app_role"))) WITH CHECK ((( SELECT "public"."current_user_is_clinical_staff"() AS "current_user_is_clinical_staff") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'admin'::"public"."app_role")));



CREATE POLICY "staff read billing" ON "public"."invoices" FOR SELECT TO "authenticated" USING ((( SELECT "public"."current_user_is_clinical_staff"() AS "current_user_is_clinical_staff") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'accountant'::"public"."app_role") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'admin'::"public"."app_role")));



CREATE POLICY "staff read claims" ON "public"."insurance_claims" FOR SELECT TO "authenticated" USING (("public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'accountant'::"public"."app_role") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'admin'::"public"."app_role")));



CREATE POLICY "staff read clinical" ON "public"."vital_signs" FOR SELECT TO "authenticated" USING (( SELECT "public"."current_user_is_clinical_staff"() AS "current_user_is_clinical_staff"));



CREATE POLICY "staff read diagnoses" ON "public"."diagnoses" FOR SELECT TO "authenticated" USING (( SELECT "public"."current_user_is_clinical_staff"() AS "current_user_is_clinical_staff"));



CREATE POLICY "staff read encounters" ON "public"."encounters" FOR SELECT TO "authenticated" USING (( SELECT "public"."current_user_is_clinical_staff"() AS "current_user_is_clinical_staff"));



CREATE POLICY "staff read fertility" ON "public"."fertility_cycles" FOR SELECT TO "authenticated" USING (( SELECT "public"."current_user_is_clinical_staff"() AS "current_user_is_clinical_staff"));



CREATE POLICY "staff read fertility monitoring" ON "public"."fertility_monitoring" FOR SELECT TO "authenticated" USING (( SELECT "public"."current_user_is_clinical_staff"() AS "current_user_is_clinical_staff"));



CREATE POLICY "staff read invoice items" ON "public"."invoice_items" FOR SELECT TO "authenticated" USING ((( SELECT "public"."current_user_is_clinical_staff"() AS "current_user_is_clinical_staff") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'accountant'::"public"."app_role") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'admin'::"public"."app_role")));



CREATE POLICY "staff read lab results" ON "public"."lab_results" FOR SELECT TO "authenticated" USING (( SELECT "public"."current_user_is_clinical_staff"() AS "current_user_is_clinical_staff"));



CREATE POLICY "staff read labs" ON "public"."lab_orders" FOR SELECT TO "authenticated" USING (( SELECT "public"."current_user_is_clinical_staff"() AS "current_user_is_clinical_staff"));



CREATE POLICY "staff read own shift assignments" ON "public"."staff_shift_assignments" FOR SELECT TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role")));



CREATE POLICY "staff read payments" ON "public"."payments" FOR SELECT TO "authenticated" USING (("public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'accountant'::"public"."app_role") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'admin'::"public"."app_role")));



CREATE POLICY "staff read prescriptions" ON "public"."prescriptions" FOR SELECT TO "authenticated" USING (( SELECT "public"."current_user_is_clinical_staff"() AS "current_user_is_clinical_staff"));



CREATE POLICY "staff read telemedicine" ON "public"."video_sessions" FOR SELECT TO "authenticated" USING (( SELECT "public"."current_user_is_clinical_staff"() AS "current_user_is_clinical_staff"));



CREATE POLICY "staff update admissions" ON "public"."admissions" FOR UPDATE TO "authenticated" USING (( SELECT "public"."current_user_is_clinical_staff"() AS "current_user_is_clinical_staff")) WITH CHECK (( SELECT "public"."current_user_is_clinical_staff"() AS "current_user_is_clinical_staff"));



CREATE POLICY "staff update patient documents" ON "public"."patient_documents" FOR UPDATE TO "authenticated" USING (( SELECT "public"."current_user_can_edit_patient_record"() AS "current_user_can_edit_patient_record")) WITH CHECK (( SELECT "public"."current_user_can_edit_patient_record"() AS "current_user_can_edit_patient_record"));



CREATE POLICY "staff update patients" ON "public"."patients" FOR UPDATE TO "authenticated" USING (( SELECT "public"."current_user_can_edit_patient_record"() AS "current_user_can_edit_patient_record")) WITH CHECK (( SELECT "public"."current_user_can_edit_patient_record"() AS "current_user_can_edit_patient_record"));



CREATE POLICY "staff update queues" ON "public"."department_queues" FOR UPDATE TO "authenticated" USING ((( SELECT "public"."current_user_is_clinical_staff"() AS "current_user_is_clinical_staff") OR ( SELECT "public"."current_user_has_role"('accountant'::"public"."app_role") AS "current_user_has_role"))) WITH CHECK ((( SELECT "public"."current_user_is_clinical_staff"() AS "current_user_is_clinical_staff") OR ( SELECT "public"."current_user_has_role"('accountant'::"public"."app_role") AS "current_user_has_role")));



ALTER TABLE "public"."staff_shift_assignments" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "system audit admin read" ON "public"."system_audit_log" FOR SELECT TO "authenticated" USING ("public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'admin'::"public"."app_role"));



CREATE POLICY "system audit authenticated insert" ON "public"."system_audit_log" FOR INSERT TO "authenticated" WITH CHECK (("actor_id" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."system_audit_log" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "theatre clinical" ON "public"."theatre_cases" TO "authenticated" USING (("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'practitioner'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'nurse'::"public"."app_role"))) WITH CHECK (("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'practitioner'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'nurse'::"public"."app_role")));



ALTER TABLE "public"."theatre_cases" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "transfusion clinical" ON "public"."transfusion_records" TO "authenticated" USING (("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'practitioner'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'nurse'::"public"."app_role"))) WITH CHECK (("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'practitioner'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'nurse'::"public"."app_role")));



ALTER TABLE "public"."transfusion_records" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."triage_assessments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_roles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "user_roles_select_own" ON "public"."user_roles" FOR SELECT TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "users mark their own notifications read" ON "public"."notifications" FOR UPDATE TO "authenticated" USING ((("recipient_user_id" = ( SELECT "auth"."uid"() AS "uid")) OR (("recipient_role" IS NOT NULL) AND "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), "recipient_role"))));



CREATE POLICY "users see notifications for their role or themselves" ON "public"."notifications" FOR SELECT TO "authenticated" USING ((("recipient_user_id" = ( SELECT "auth"."uid"() AS "uid")) OR (("recipient_role" IS NOT NULL) AND "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), "recipient_role"))));



ALTER TABLE "public"."video_sessions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."vital_signs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."wards" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."appointments";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."department_queues";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."lab_results";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."notifications";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."payments";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."prescriptions";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."video_sessions";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."vital_signs";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON TYPE "public"."app_role" TO "authenticated";






















































































































































GRANT ALL ON TABLE "public"."diagnoses" TO "anon";
GRANT ALL ON TABLE "public"."diagnoses" TO "authenticated";
GRANT ALL ON TABLE "public"."diagnoses" TO "service_role";



REVOKE ALL ON FUNCTION "public"."add_encounter_diagnosis"("_encounter_id" "uuid", "_diagnosis" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."add_encounter_diagnosis"("_encounter_id" "uuid", "_diagnosis" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."add_encounter_diagnosis"("_encounter_id" "uuid", "_diagnosis" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."audit_patient_change"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."audit_patient_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."audit_patient_change"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."calculate_triage_bmi"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."calculate_triage_bmi"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_triage_bmi"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."can_edit_patient_record"("_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."can_edit_patient_record"("_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_edit_patient_record"("_user_id" "uuid") TO "service_role";



GRANT ALL ON TABLE "public"."appointments" TO "anon";
GRANT ALL ON TABLE "public"."appointments" TO "authenticated";
GRANT ALL ON TABLE "public"."appointments" TO "service_role";



REVOKE ALL ON FUNCTION "public"."claim_appointment"("_appointment_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."claim_appointment"("_appointment_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."claim_appointment"("_appointment_id" "uuid") TO "service_role";



GRANT ALL ON TABLE "public"."encounters" TO "anon";
GRANT ALL ON TABLE "public"."encounters" TO "authenticated";
GRANT ALL ON TABLE "public"."encounters" TO "service_role";



REVOKE ALL ON FUNCTION "public"."complete_encounter_workflow"("_encounter_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."complete_encounter_workflow"("_encounter_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."complete_encounter_workflow"("_encounter_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_appointment_workflow"("_patient_id" "uuid", "_scheduled_at" timestamp with time zone, "_department" "text", "_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_appointment_workflow"("_patient_id" "uuid", "_scheduled_at" timestamp with time zone, "_department" "text", "_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_appointment_workflow"("_patient_id" "uuid", "_scheduled_at" timestamp with time zone, "_department" "text", "_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_dental_record"("_patient_id" "uuid", "_examination" "text", "_treatment_plan" "text", "_procedures_performed" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_dental_record"("_patient_id" "uuid", "_examination" "text", "_treatment_plan" "text", "_procedures_performed" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_dental_record"("_patient_id" "uuid", "_examination" "text", "_treatment_plan" "text", "_procedures_performed" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_emergency_case"("_patient_id" "uuid", "_chief_complaint" "text", "_acuity" "text", "_arrival_mode" "text", "_assigned_officer" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_emergency_case"("_patient_id" "uuid", "_chief_complaint" "text", "_acuity" "text", "_arrival_mode" "text", "_assigned_officer" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_emergency_case"("_patient_id" "uuid", "_chief_complaint" "text", "_acuity" "text", "_arrival_mode" "text", "_assigned_officer" "uuid") TO "service_role";



GRANT ALL ON TABLE "public"."prescriptions" TO "anon";
GRANT ALL ON TABLE "public"."prescriptions" TO "authenticated";
GRANT ALL ON TABLE "public"."prescriptions" TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_encounter_prescription"("_encounter_id" "uuid", "_medication" "text", "_dosage" "text", "_frequency" "text", "_duration" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_encounter_prescription"("_encounter_id" "uuid", "_medication" "text", "_dosage" "text", "_frequency" "text", "_duration" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_encounter_prescription"("_encounter_id" "uuid", "_medication" "text", "_dosage" "text", "_frequency" "text", "_duration" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_encounter_workflow"("_patient_id" "uuid", "_symptoms" "text", "_clerking_notes" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_encounter_workflow"("_patient_id" "uuid", "_symptoms" "text", "_clerking_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_encounter_workflow"("_patient_id" "uuid", "_symptoms" "text", "_clerking_notes" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_imaging_order_with_payment_gate"("_patient_id" "uuid", "_encounter_id" "uuid", "_modality" "text", "_study_name" "text", "_body_site" "text", "_priority" "text", "_clinical_indication" "text", "_amount" numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_imaging_order_with_payment_gate"("_patient_id" "uuid", "_encounter_id" "uuid", "_modality" "text", "_study_name" "text", "_body_site" "text", "_priority" "text", "_clinical_indication" "text", "_amount" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_imaging_order_with_payment_gate"("_patient_id" "uuid", "_encounter_id" "uuid", "_modality" "text", "_study_name" "text", "_body_site" "text", "_priority" "text", "_clinical_indication" "text", "_amount" numeric) TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_lab_order_with_payment_gate"("_patient_id" "uuid", "_test_name" "text", "_test_category" "text", "_priority" "text", "_clinical_notes" "text", "_amount" numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_lab_order_with_payment_gate"("_patient_id" "uuid", "_test_name" "text", "_test_category" "text", "_priority" "text", "_clinical_notes" "text", "_amount" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_lab_order_with_payment_gate"("_patient_id" "uuid", "_test_name" "text", "_test_category" "text", "_priority" "text", "_clinical_notes" "text", "_amount" numeric) TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_ophthalmology_exam"("_patient_id" "uuid", "_visual_acuity" "text", "_refraction" "text", "_keratometry" "text", "_intraocular_pressure" numeric, "_color_vision" "text", "_fundus_notes" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_ophthalmology_exam"("_patient_id" "uuid", "_visual_acuity" "text", "_refraction" "text", "_keratometry" "text", "_intraocular_pressure" numeric, "_color_vision" "text", "_fundus_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_ophthalmology_exam"("_patient_id" "uuid", "_visual_acuity" "text", "_refraction" "text", "_keratometry" "text", "_intraocular_pressure" numeric, "_color_vision" "text", "_fundus_notes" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_patient_appointment"("_patient_id" "uuid", "_scheduled_at" timestamp with time zone, "_department" "text", "_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_patient_appointment"("_patient_id" "uuid", "_scheduled_at" timestamp with time zone, "_department" "text", "_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_patient_appointment"("_patient_id" "uuid", "_scheduled_at" timestamp with time zone, "_department" "text", "_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_procedure_note"("_patient_id" "uuid", "_procedure_name" "text", "_template_used" "text", "_indication" "text", "_technique" "text", "_findings" "text", "_complications" "text", "_post_op_plan" "text", "_charge_amount" numeric, "_service_order_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_procedure_note"("_patient_id" "uuid", "_procedure_name" "text", "_template_used" "text", "_indication" "text", "_technique" "text", "_findings" "text", "_complications" "text", "_post_op_plan" "text", "_charge_amount" numeric, "_service_order_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_procedure_note"("_patient_id" "uuid", "_procedure_name" "text", "_template_used" "text", "_indication" "text", "_technique" "text", "_findings" "text", "_complications" "text", "_post_op_plan" "text", "_charge_amount" numeric, "_service_order_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_staff_shift_assignment"("_user_id" "uuid", "_department" "text", "_shift_label" "text", "_starts_at" timestamp with time zone, "_ends_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_staff_shift_assignment"("_user_id" "uuid", "_department" "text", "_shift_label" "text", "_starts_at" timestamp with time zone, "_ends_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_staff_shift_assignment"("_user_id" "uuid", "_department" "text", "_shift_label" "text", "_starts_at" timestamp with time zone, "_ends_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_theatre_case"("_patient_id" "uuid", "_procedure_name" "text", "_scheduled_start" timestamp with time zone, "_theatre_name" "text", "_urgency" "text", "_surgeon_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_theatre_case"("_patient_id" "uuid", "_procedure_name" "text", "_scheduled_start" timestamp with time zone, "_theatre_name" "text", "_urgency" "text", "_surgeon_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_theatre_case"("_patient_id" "uuid", "_procedure_name" "text", "_scheduled_start" timestamp with time zone, "_theatre_name" "text", "_urgency" "text", "_surgeon_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_transfusion_record"("_patient_id" "uuid", "_blood_product" "text", "_unit_identifier" "text", "_blood_group" "text", "_consent_confirmed" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_transfusion_record"("_patient_id" "uuid", "_blood_product" "text", "_unit_identifier" "text", "_blood_group" "text", "_consent_confirmed" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_transfusion_record"("_patient_id" "uuid", "_blood_product" "text", "_unit_identifier" "text", "_blood_group" "text", "_consent_confirmed" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_walk_in_billable_service"("_patient_id" "uuid", "_service_code" "text", "_quantity" integer, "_notes" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_walk_in_billable_service"("_patient_id" "uuid", "_service_code" "text", "_quantity" integer, "_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_walk_in_billable_service"("_patient_id" "uuid", "_service_code" "text", "_quantity" integer, "_notes" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_ward_unit"("_name" "text", "_code" "text", "_specialty" "text", "_gender_policy" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_ward_unit"("_name" "text", "_code" "text", "_specialty" "text", "_gender_policy" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_ward_unit"("_name" "text", "_code" "text", "_specialty" "text", "_gender_policy" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."current_user_can_edit_patient_record"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."current_user_can_edit_patient_record"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_user_can_edit_patient_record"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."current_user_has_role"("_role" "public"."app_role") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."current_user_has_role"("_role" "public"."app_role") TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_user_has_role"("_role" "public"."app_role") TO "service_role";



REVOKE ALL ON FUNCTION "public"."current_user_is_clinical_staff"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."current_user_is_clinical_staff"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_user_is_clinical_staff"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."end_video_session"("_session_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."end_video_session"("_session_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."end_video_session"("_session_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."generate_patient_code"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."generate_patient_code"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_patient_code"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_bmi_category"("_bmi" numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_bmi_category"("_bmi" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_bmi_category"("_bmi" numeric) TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_encounter_clinical_context"("_patient_id" "uuid", "_encounter_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_encounter_clinical_context"("_patient_id" "uuid", "_encounter_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_encounter_clinical_context"("_patient_id" "uuid", "_encounter_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_patient_bmi_context"("_patient_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_patient_bmi_context"("_patient_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_patient_bmi_context"("_patient_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."handle_new_user"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."has_role"("_user_id" "uuid", "_role" "public"."app_role") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."has_role"("_user_id" "uuid", "_role" "public"."app_role") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_role"("_user_id" "uuid", "_role" "public"."app_role") TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_clinical_staff"("_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_clinical_staff"("_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_clinical_staff"("_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."lock_overdue_medication_slots"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."lock_overdue_medication_slots"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."lock_overdue_medication_slots"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."mark_notification_read"("_notification_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mark_notification_read"("_notification_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mark_notification_read"("_notification_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mark_video_session_paid"("_session_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mark_video_session_paid"("_session_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mark_video_session_paid"("_session_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."notify_due_medications"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."notify_due_medications"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_due_medications"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."pay_selected_invoice_items"("_invoice_id" "uuid", "_item_ids" "uuid"[], "_method" "text", "_reference" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."pay_selected_invoice_items"("_invoice_id" "uuid", "_item_ids" "uuid"[], "_method" "text", "_reference" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pay_selected_invoice_items"("_invoice_id" "uuid", "_item_ids" "uuid"[], "_method" "text", "_reference" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."prepare_patient_billable_items"("_patient_id" "uuid", "_from" timestamp with time zone, "_to" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."prepare_patient_billable_items"("_patient_id" "uuid", "_from" timestamp with time zone, "_to" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."prepare_patient_billable_items"("_patient_id" "uuid", "_from" timestamp with time zone, "_to" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_ai_clinical_event"("_session_id" "uuid", "_event_type" "text", "_metadata" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_ai_clinical_event"("_session_id" "uuid", "_event_type" "text", "_metadata" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_ai_clinical_event"("_session_id" "uuid", "_event_type" "text", "_metadata" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_system_audit"("_action" "text", "_module" "text", "_entity_type" "text", "_entity_id" "uuid", "_severity" "text", "_metadata" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_system_audit"("_action" "text", "_module" "text", "_entity_type" "text", "_entity_id" "uuid", "_severity" "text", "_metadata" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_system_audit"("_action" "text", "_module" "text", "_entity_type" "text", "_entity_id" "uuid", "_severity" "text", "_metadata" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_transfusion_event"("_record_id" "uuid", "_status" "text", "_reaction_observed" boolean, "_reaction_notes" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_transfusion_event"("_record_id" "uuid", "_status" "text", "_reaction_observed" boolean, "_reaction_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_transfusion_event"("_record_id" "uuid", "_status" "text", "_reaction_observed" boolean, "_reaction_notes" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_triage_assessment"("_patient_id" "uuid", "_systolic" integer, "_diastolic" integer, "_heart_rate" integer, "_temperature" numeric, "_respiratory_rate" integer, "_oxygen_saturation" numeric, "_weight_kg" numeric, "_height_m" numeric, "_pain_score" integer, "_consciousness" "text", "_presenting_complaint" "text", "_clinical_notes" "text", "_priority" "text", "_is_critical" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_triage_assessment"("_patient_id" "uuid", "_systolic" integer, "_diastolic" integer, "_heart_rate" integer, "_temperature" numeric, "_respiratory_rate" integer, "_oxygen_saturation" numeric, "_weight_kg" numeric, "_height_m" numeric, "_pain_score" integer, "_consciousness" "text", "_presenting_complaint" "text", "_clinical_notes" "text", "_priority" "text", "_is_critical" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_triage_assessment"("_patient_id" "uuid", "_systolic" integer, "_diastolic" integer, "_heart_rate" integer, "_temperature" numeric, "_respiratory_rate" integer, "_oxygen_saturation" numeric, "_weight_kg" numeric, "_height_m" numeric, "_pain_score" integer, "_consciousness" "text", "_presenting_complaint" "text", "_clinical_notes" "text", "_priority" "text", "_is_critical" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."refresh_invoice_totals"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."refresh_invoice_totals"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."refresh_invoice_totals"() TO "service_role";



GRANT ALL ON TABLE "public"."outside_lab_documents" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."outside_lab_documents" TO "authenticated";
GRANT ALL ON TABLE "public"."outside_lab_documents" TO "service_role";



REVOKE ALL ON FUNCTION "public"."register_outside_lab_document"("_patient_id" "uuid", "_document_type" "text", "_title" "text", "_storage_path" "text", "_mime_type" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."register_outside_lab_document"("_patient_id" "uuid", "_document_type" "text", "_title" "text", "_storage_path" "text", "_mime_type" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."register_outside_lab_document"("_patient_id" "uuid", "_document_type" "text", "_title" "text", "_storage_path" "text", "_mime_type" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."release_service_order"("_order_id" "uuid", "_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."release_service_order"("_order_id" "uuid", "_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."release_service_order"("_order_id" "uuid", "_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."remove_encounter_diagnosis"("_diagnosis_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."remove_encounter_diagnosis"("_diagnosis_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."remove_encounter_diagnosis"("_diagnosis_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."reopen_medication_administration"("_record_id" "uuid", "_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."reopen_medication_administration"("_record_id" "uuid", "_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."reopen_medication_administration"("_record_id" "uuid", "_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."review_ophthalmology_exam"("_exam_id" "uuid", "_advisory" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."review_ophthalmology_exam"("_exam_id" "uuid", "_advisory" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."review_ophthalmology_exam"("_exam_id" "uuid", "_advisory" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."review_ophthalmology_exam"("_exam_id" "uuid", "_advisory" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."schedule_medication_administration"("_patient_id" "uuid", "_medication_name" "text", "_dose" "text", "_route" "text", "_scheduled_at" timestamp with time zone, "_notes" "text", "_due_window_minutes" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."schedule_medication_administration"("_patient_id" "uuid", "_medication_name" "text", "_dose" "text", "_route" "text", "_scheduled_at" timestamp with time zone, "_notes" "text", "_due_window_minutes" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."schedule_medication_administration"("_patient_id" "uuid", "_medication_name" "text", "_dose" "text", "_route" "text", "_scheduled_at" timestamp with time zone, "_notes" "text", "_due_window_minutes" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."schedule_video_session"("_patient_id" "uuid", "_scheduled_at" timestamp with time zone, "_provider" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."schedule_video_session"("_patient_id" "uuid", "_scheduled_at" timestamp with time zone, "_provider" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."schedule_video_session"("_patient_id" "uuid", "_scheduled_at" timestamp with time zone, "_provider" "text") TO "service_role";



GRANT ALL ON TABLE "public"."facility_settings" TO "anon";
GRANT ALL ON TABLE "public"."facility_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."facility_settings" TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_facility_routing_mode"("_mode" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_facility_routing_mode"("_mode" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_facility_routing_mode"("_mode" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_principal_diagnosis"("_encounter_id" "uuid", "_diagnosis_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_principal_diagnosis"("_encounter_id" "uuid", "_diagnosis_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_principal_diagnosis"("_encounter_id" "uuid", "_diagnosis_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_staff_shift_assignment_active"("_assignment_id" "uuid", "_active" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_staff_shift_assignment_active"("_assignment_id" "uuid", "_active" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_staff_shift_assignment_active"("_assignment_id" "uuid", "_active" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."start_appointment_encounter"("_appointment_id" "uuid", "_symptoms" "text", "_clerking_notes" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."start_appointment_encounter"("_appointment_id" "uuid", "_symptoms" "text", "_clerking_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."start_appointment_encounter"("_appointment_id" "uuid", "_symptoms" "text", "_clerking_notes" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."start_video_session"("_session_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."start_video_session"("_session_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."start_video_session"("_session_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."touch_care_transition_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."touch_care_transition_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."touch_care_transition_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."touch_global_hims_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."touch_global_hims_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."touch_global_hims_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."touch_mar_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."touch_mar_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."touch_mar_updated_at"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."touch_updated_at"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."touch_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."touch_updated_at"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."transition_medication_administration"("_record_id" "uuid", "_status" "text", "_reason" "text", "_notes" "text", "_witnessed_by" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."transition_medication_administration"("_record_id" "uuid", "_status" "text", "_reason" "text", "_notes" "text", "_witnessed_by" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."transition_medication_administration"("_record_id" "uuid", "_status" "text", "_reason" "text", "_notes" "text", "_witnessed_by" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_appointment_workflow"("_appointment_id" "uuid", "_scheduled_at" timestamp with time zone, "_department" "text", "_reason" "text", "_treatment_status" "text", "_treatment_notes" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_appointment_workflow"("_appointment_id" "uuid", "_scheduled_at" timestamp with time zone, "_department" "text", "_reason" "text", "_treatment_status" "text", "_treatment_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_appointment_workflow"("_appointment_id" "uuid", "_scheduled_at" timestamp with time zone, "_department" "text", "_reason" "text", "_treatment_status" "text", "_treatment_notes" "text") TO "service_role";



GRANT ALL ON TABLE "public"."insurance_cases" TO "anon";
GRANT ALL ON TABLE "public"."insurance_cases" TO "authenticated";
GRANT ALL ON TABLE "public"."insurance_cases" TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_insurance_case"("_id" "uuid", "_eligibility" "text", "_authorization" "text", "_claim_status" "text", "_claim_amount" numeric, "_approved_amount" numeric, "_rejection_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_insurance_case"("_id" "uuid", "_eligibility" "text", "_authorization" "text", "_claim_status" "text", "_claim_amount" numeric, "_approved_amount" numeric, "_rejection_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_insurance_case"("_id" "uuid", "_eligibility" "text", "_authorization" "text", "_claim_status" "text", "_claim_amount" numeric, "_approved_amount" numeric, "_rejection_reason" "text") TO "service_role";


















GRANT ALL ON TABLE "public"."admissions" TO "anon";
GRANT ALL ON TABLE "public"."admissions" TO "authenticated";
GRANT ALL ON TABLE "public"."admissions" TO "service_role";



GRANT ALL ON TABLE "public"."ai_clinical_events" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."ai_clinical_events" TO "authenticated";
GRANT ALL ON TABLE "public"."ai_clinical_events" TO "service_role";



GRANT ALL ON TABLE "public"."ai_clinical_sessions" TO "anon";
GRANT ALL ON TABLE "public"."ai_clinical_sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."ai_clinical_sessions" TO "service_role";



GRANT ALL ON TABLE "public"."beds" TO "anon";
GRANT ALL ON TABLE "public"."beds" TO "authenticated";
GRANT ALL ON TABLE "public"."beds" TO "service_role";



GRANT ALL ON TABLE "public"."billing_item_payments" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."billing_item_payments" TO "authenticated";
GRANT ALL ON TABLE "public"."billing_item_payments" TO "service_role";



GRANT ALL ON TABLE "public"."care_transitions" TO "anon";
GRANT ALL ON TABLE "public"."care_transitions" TO "authenticated";
GRANT ALL ON TABLE "public"."care_transitions" TO "service_role";



GRANT ALL ON TABLE "public"."dental_records" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."dental_records" TO "authenticated";
GRANT ALL ON TABLE "public"."dental_records" TO "service_role";



GRANT ALL ON TABLE "public"."department_queues" TO "anon";
GRANT ALL ON TABLE "public"."department_queues" TO "authenticated";
GRANT ALL ON TABLE "public"."department_queues" TO "service_role";



GRANT ALL ON TABLE "public"."emergency_cases" TO "anon";
GRANT ALL ON TABLE "public"."emergency_cases" TO "authenticated";
GRANT ALL ON TABLE "public"."emergency_cases" TO "service_role";



GRANT ALL ON TABLE "public"."facility_configuration" TO "anon";
GRANT ALL ON TABLE "public"."facility_configuration" TO "authenticated";
GRANT ALL ON TABLE "public"."facility_configuration" TO "service_role";



GRANT ALL ON TABLE "public"."fertility_cycles" TO "anon";
GRANT ALL ON TABLE "public"."fertility_cycles" TO "authenticated";
GRANT ALL ON TABLE "public"."fertility_cycles" TO "service_role";



GRANT ALL ON TABLE "public"."fertility_monitoring" TO "anon";
GRANT ALL ON TABLE "public"."fertility_monitoring" TO "authenticated";
GRANT ALL ON TABLE "public"."fertility_monitoring" TO "service_role";



GRANT ALL ON TABLE "public"."imaging_orders" TO "anon";
GRANT ALL ON TABLE "public"."imaging_orders" TO "authenticated";
GRANT ALL ON TABLE "public"."imaging_orders" TO "service_role";



GRANT ALL ON TABLE "public"."insurance_claims" TO "anon";
GRANT ALL ON TABLE "public"."insurance_claims" TO "authenticated";
GRANT ALL ON TABLE "public"."insurance_claims" TO "service_role";



GRANT ALL ON TABLE "public"."invoice_items" TO "anon";
GRANT ALL ON TABLE "public"."invoice_items" TO "authenticated";
GRANT ALL ON TABLE "public"."invoice_items" TO "service_role";



GRANT ALL ON TABLE "public"."invoices" TO "anon";
GRANT ALL ON TABLE "public"."invoices" TO "authenticated";
GRANT ALL ON TABLE "public"."invoices" TO "service_role";



GRANT ALL ON TABLE "public"."lab_orders" TO "anon";
GRANT ALL ON TABLE "public"."lab_orders" TO "authenticated";
GRANT ALL ON TABLE "public"."lab_orders" TO "service_role";



GRANT ALL ON TABLE "public"."lab_results" TO "anon";
GRANT ALL ON TABLE "public"."lab_results" TO "authenticated";
GRANT ALL ON TABLE "public"."lab_results" TO "service_role";



GRANT ALL ON TABLE "public"."maternity_episodes" TO "anon";
GRANT ALL ON TABLE "public"."maternity_episodes" TO "authenticated";
GRANT ALL ON TABLE "public"."maternity_episodes" TO "service_role";



GRANT ALL ON TABLE "public"."maternity_observations" TO "anon";
GRANT ALL ON TABLE "public"."maternity_observations" TO "authenticated";
GRANT ALL ON TABLE "public"."maternity_observations" TO "service_role";



GRANT ALL ON TABLE "public"."medication_administrations" TO "anon";
GRANT ALL ON TABLE "public"."medication_administrations" TO "authenticated";
GRANT ALL ON TABLE "public"."medication_administrations" TO "service_role";



GRANT ALL ON TABLE "public"."notifications" TO "anon";
GRANT ALL ON TABLE "public"."notifications" TO "authenticated";
GRANT ALL ON TABLE "public"."notifications" TO "service_role";



GRANT ALL ON TABLE "public"."nursing_care_plans" TO "anon";
GRANT ALL ON TABLE "public"."nursing_care_plans" TO "authenticated";
GRANT ALL ON TABLE "public"."nursing_care_plans" TO "service_role";



GRANT ALL ON TABLE "public"."nursing_shift_handovers" TO "anon";
GRANT ALL ON TABLE "public"."nursing_shift_handovers" TO "authenticated";
GRANT ALL ON TABLE "public"."nursing_shift_handovers" TO "service_role";



GRANT ALL ON TABLE "public"."ophthalmology_exams" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."ophthalmology_exams" TO "authenticated";
GRANT ALL ON TABLE "public"."ophthalmology_exams" TO "service_role";



GRANT ALL ON TABLE "public"."patient_audit" TO "anon";
GRANT ALL ON TABLE "public"."patient_audit" TO "authenticated";
GRANT ALL ON TABLE "public"."patient_audit" TO "service_role";



GRANT ALL ON TABLE "public"."patient_documents" TO "anon";
GRANT ALL ON TABLE "public"."patient_documents" TO "authenticated";
GRANT ALL ON TABLE "public"."patient_documents" TO "service_role";



GRANT ALL ON TABLE "public"."patient_referrals" TO "anon";
GRANT ALL ON TABLE "public"."patient_referrals" TO "authenticated";
GRANT ALL ON TABLE "public"."patient_referrals" TO "service_role";



GRANT ALL ON TABLE "public"."patients" TO "anon";
GRANT ALL ON TABLE "public"."patients" TO "authenticated";
GRANT ALL ON TABLE "public"."patients" TO "service_role";



GRANT ALL ON TABLE "public"."payments" TO "anon";
GRANT ALL ON TABLE "public"."payments" TO "authenticated";
GRANT ALL ON TABLE "public"."payments" TO "service_role";



GRANT ALL ON TABLE "public"."procedure_notes" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."procedure_notes" TO "authenticated";
GRANT ALL ON TABLE "public"."procedure_notes" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."service_orders" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."service_orders" TO "authenticated";
GRANT ALL ON TABLE "public"."service_orders" TO "service_role";



GRANT ALL ON TABLE "public"."service_tariffs" TO "anon";
GRANT ALL ON TABLE "public"."service_tariffs" TO "authenticated";
GRANT ALL ON TABLE "public"."service_tariffs" TO "service_role";



GRANT ALL ON TABLE "public"."staff_shift_assignments" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."staff_shift_assignments" TO "authenticated";
GRANT ALL ON TABLE "public"."staff_shift_assignments" TO "service_role";



GRANT ALL ON TABLE "public"."system_audit_log" TO "anon";
GRANT ALL ON TABLE "public"."system_audit_log" TO "authenticated";
GRANT ALL ON TABLE "public"."system_audit_log" TO "service_role";



GRANT ALL ON TABLE "public"."theatre_cases" TO "anon";
GRANT ALL ON TABLE "public"."theatre_cases" TO "authenticated";
GRANT ALL ON TABLE "public"."theatre_cases" TO "service_role";



GRANT ALL ON TABLE "public"."transfusion_records" TO "anon";
GRANT ALL ON TABLE "public"."transfusion_records" TO "authenticated";
GRANT ALL ON TABLE "public"."transfusion_records" TO "service_role";



GRANT ALL ON TABLE "public"."triage_assessments" TO "anon";
GRANT ALL ON TABLE "public"."triage_assessments" TO "authenticated";
GRANT ALL ON TABLE "public"."triage_assessments" TO "service_role";



GRANT ALL ON TABLE "public"."user_roles" TO "anon";
GRANT ALL ON TABLE "public"."user_roles" TO "authenticated";
GRANT ALL ON TABLE "public"."user_roles" TO "service_role";



GRANT ALL ON TABLE "public"."video_sessions" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."video_sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."video_sessions" TO "service_role";



GRANT ALL ON TABLE "public"."vital_signs" TO "anon";
GRANT ALL ON TABLE "public"."vital_signs" TO "authenticated";
GRANT ALL ON TABLE "public"."vital_signs" TO "service_role";



GRANT ALL ON TABLE "public"."wards" TO "anon";
GRANT ALL ON TABLE "public"."wards" TO "authenticated";
GRANT ALL ON TABLE "public"."wards" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";































drop extension if exists "pg_net";

revoke delete on table "public"."ai_clinical_events" from "authenticated";

revoke insert on table "public"."ai_clinical_events" from "authenticated";

revoke update on table "public"."ai_clinical_events" from "authenticated";

revoke delete on table "public"."billing_item_payments" from "authenticated";

revoke insert on table "public"."billing_item_payments" from "authenticated";

revoke update on table "public"."billing_item_payments" from "authenticated";

revoke delete on table "public"."dental_records" from "authenticated";

revoke insert on table "public"."dental_records" from "authenticated";

revoke update on table "public"."dental_records" from "authenticated";

revoke delete on table "public"."ophthalmology_exams" from "authenticated";

revoke insert on table "public"."ophthalmology_exams" from "authenticated";

revoke update on table "public"."ophthalmology_exams" from "authenticated";

revoke delete on table "public"."outside_lab_documents" from "authenticated";

revoke insert on table "public"."outside_lab_documents" from "authenticated";

revoke update on table "public"."outside_lab_documents" from "authenticated";

revoke delete on table "public"."procedure_notes" from "authenticated";

revoke insert on table "public"."procedure_notes" from "authenticated";

revoke update on table "public"."procedure_notes" from "authenticated";

revoke delete on table "public"."service_orders" from "authenticated";

revoke insert on table "public"."service_orders" from "authenticated";

revoke update on table "public"."service_orders" from "authenticated";

revoke delete on table "public"."staff_shift_assignments" from "authenticated";

revoke insert on table "public"."staff_shift_assignments" from "authenticated";

revoke update on table "public"."staff_shift_assignments" from "authenticated";

revoke delete on table "public"."video_sessions" from "authenticated";

revoke insert on table "public"."video_sessions" from "authenticated";

revoke update on table "public"."video_sessions" from "authenticated";

CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


  create policy "clinical staff delete patient documents storage"
  on "storage"."objects"
  as permissive
  for delete
  to authenticated
using (((bucket_id = 'patient-documents'::text) AND public.can_edit_patient_record(auth.uid())));



  create policy "clinical staff read patient documents storage"
  on "storage"."objects"
  as permissive
  for select
  to authenticated
using (((bucket_id = 'patient-documents'::text) AND (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(), 'accountant'::public.app_role))));



  create policy "clinical staff update patient documents storage"
  on "storage"."objects"
  as permissive
  for update
  to authenticated
using (((bucket_id = 'patient-documents'::text) AND public.can_edit_patient_record(auth.uid())))
with check (((bucket_id = 'patient-documents'::text) AND public.can_edit_patient_record(auth.uid())));



  create policy "clinical staff upload patient documents"
  on "storage"."objects"
  as permissive
  for insert
  to authenticated
with check (((bucket_id = 'patient-documents'::text) AND public.can_edit_patient_record(auth.uid())));



  create policy "outside lab storage delete"
  on "storage"."objects"
  as permissive
  for delete
  to authenticated
using (((bucket_id = 'outside-lab'::text) AND (public.has_role(auth.uid(), 'admin'::public.app_role) OR public.has_role(auth.uid(), 'practitioner'::public.app_role))));



  create policy "outside lab storage read"
  on "storage"."objects"
  as permissive
  for select
  to authenticated
using (((bucket_id = 'outside-lab'::text) AND (public.has_role(auth.uid(), 'admin'::public.app_role) OR public.has_role(auth.uid(), 'practitioner'::public.app_role) OR public.has_role(auth.uid(), 'nurse'::public.app_role) OR public.has_role(auth.uid(), 'midwife'::public.app_role) OR public.has_role(auth.uid(), 'specialist_nurse'::public.app_role) OR public.has_role(auth.uid(), 'lab_technician'::public.app_role)) AND (split_part(name, '/'::text, 1) IN ( SELECT (patients.id)::text AS id
   FROM public.patients))));



  create policy "outside lab storage upload"
  on "storage"."objects"
  as permissive
  for insert
  to authenticated
with check (((bucket_id = 'outside-lab'::text) AND (public.has_role(auth.uid(), 'admin'::public.app_role) OR public.has_role(auth.uid(), 'practitioner'::public.app_role) OR public.has_role(auth.uid(), 'nurse'::public.app_role) OR public.has_role(auth.uid(), 'midwife'::public.app_role) OR public.has_role(auth.uid(), 'specialist_nurse'::public.app_role) OR public.has_role(auth.uid(), 'lab_technician'::public.app_role)) AND (split_part(name, '/'::text, 1) IN ( SELECT (patients.id)::text AS id
   FROM public.patients))));



