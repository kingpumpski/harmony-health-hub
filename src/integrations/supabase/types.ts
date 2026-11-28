export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.17"
  }
  public: {
    Tables: {
      admissions: {
        Row: {
          admitted_at: string
          admitted_by: string | null
          admitting_practitioner: string | null
          bed: string | null
          created_at: string
          created_by: string | null
          diagnosis: string | null
          discharge_summary: string | null
          discharged_at: string | null
          encounter_id: string | null
          facility_id: string | null
          id: string
          notes: string | null
          patient_id: string
          reason: string | null
          status: string
          updated_at: string
          ward: string | null
        }
        Insert: {
          admitted_at?: string
          admitted_by?: string | null
          admitting_practitioner?: string | null
          bed?: string | null
          created_at?: string
          created_by?: string | null
          diagnosis?: string | null
          discharge_summary?: string | null
          discharged_at?: string | null
          encounter_id?: string | null
          facility_id?: string | null
          id?: string
          notes?: string | null
          patient_id: string
          reason?: string | null
          status?: string
          updated_at?: string
          ward?: string | null
        }
        Update: {
          admitted_at?: string
          admitted_by?: string | null
          admitting_practitioner?: string | null
          bed?: string | null
          created_at?: string
          created_by?: string | null
          diagnosis?: string | null
          discharge_summary?: string | null
          discharged_at?: string | null
          encounter_id?: string | null
          facility_id?: string | null
          id?: string
          notes?: string | null
          patient_id?: string
          reason?: string | null
          status?: string
          updated_at?: string
          ward?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "admissions_encounter_id_fkey"
            columns: ["encounter_id"]
            isOneToOne: false
            referencedRelation: "encounters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "admissions_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "admissions_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_case_memory: {
        Row: {
          age_group: string | null
          created_at: string
          diagnosis: string | null
          encounter_id: string | null
          facility_id: string | null
          gender: string | null
          icd_code: string | null
          id: string
          outcome: string | null
          outcome_notes: string | null
          patient_id: string | null
          prescriptions: Json | null
          symptoms: string | null
        }
        Insert: {
          age_group?: string | null
          created_at?: string
          diagnosis?: string | null
          encounter_id?: string | null
          facility_id?: string | null
          gender?: string | null
          icd_code?: string | null
          id?: string
          outcome?: string | null
          outcome_notes?: string | null
          patient_id?: string | null
          prescriptions?: Json | null
          symptoms?: string | null
        }
        Update: {
          age_group?: string | null
          created_at?: string
          diagnosis?: string | null
          encounter_id?: string | null
          facility_id?: string | null
          gender?: string | null
          icd_code?: string | null
          id?: string
          outcome?: string | null
          outcome_notes?: string | null
          patient_id?: string | null
          prescriptions?: Json | null
          symptoms?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ai_case_memory_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_clinical_events: {
        Row: {
          actor_id: string
          created_at: string
          event_type: string
          id: string
          metadata: Json
          session_id: string
        }
        Insert: {
          actor_id: string
          created_at?: string
          event_type: string
          id?: string
          metadata?: Json
          session_id: string
        }
        Update: {
          actor_id?: string
          created_at?: string
          event_type?: string
          id?: string
          metadata?: Json
          session_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_clinical_events_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "ai_clinical_sessions"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_clinical_sessions: {
        Row: {
          created_at: string
          created_by: string
          facility_id: string | null
          id: string
          input_snapshot: Json
          model_name: string | null
          model_provider: string | null
          output_snapshot: Json | null
          patient_id: string
          provenance: Json
          review_status: string
          reviewed_at: string | null
          reviewed_by: string | null
          specialist: string
          status: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by: string
          facility_id?: string | null
          id?: string
          input_snapshot?: Json
          model_name?: string | null
          model_provider?: string | null
          output_snapshot?: Json | null
          patient_id: string
          provenance?: Json
          review_status?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          specialist: string
          status?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string
          facility_id?: string | null
          id?: string
          input_snapshot?: Json
          model_name?: string | null
          model_provider?: string | null
          output_snapshot?: Json | null
          patient_id?: string
          provenance?: Json
          review_status?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          specialist?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_clinical_sessions_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_clinical_sessions_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_diagnosis_suggestions: {
        Row: {
          accepted: boolean | null
          created_at: string | null
          encounter_id: string | null
          facility_id: string | null
          id: string
          model_version: string | null
          reasoning: string | null
          suggested_icd: string | null
        }
        Insert: {
          accepted?: boolean | null
          created_at?: string | null
          encounter_id?: string | null
          facility_id?: string | null
          id?: string
          model_version?: string | null
          reasoning?: string | null
          suggested_icd?: string | null
        }
        Update: {
          accepted?: boolean | null
          created_at?: string | null
          encounter_id?: string | null
          facility_id?: string | null
          id?: string
          model_version?: string | null
          reasoning?: string | null
          suggested_icd?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ai_diagnosis_suggestions_encounter_id_fkey"
            columns: ["encounter_id"]
            isOneToOne: false
            referencedRelation: "encounters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_diagnosis_suggestions_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_diagnosis_suggestions_suggested_icd_fkey"
            columns: ["suggested_icd"]
            isOneToOne: false
            referencedRelation: "icd_codes"
            referencedColumns: ["code"]
          },
        ]
      }
      ai_protocols: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          case_count: number | null
          created_at: string
          diagnosis: string
          icd_code: string | null
          id: string
          protocol_text: string
          status: string
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          case_count?: number | null
          created_at?: string
          diagnosis: string
          icd_code?: string | null
          id?: string
          protocol_text: string
          status?: string
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          case_count?: number | null
          created_at?: string
          diagnosis?: string
          icd_code?: string | null
          id?: string
          protocol_text?: string
          status?: string
        }
        Relationships: []
      }
      ai_report_requests: {
        Row: {
          completed_at: string | null
          content: string | null
          created_at: string
          error: string | null
          facility_id: string | null
          id: string
          patient_id: string
          report_type: string
          requested_by: string | null
          status: string
        }
        Insert: {
          completed_at?: string | null
          content?: string | null
          created_at?: string
          error?: string | null
          facility_id?: string | null
          id?: string
          patient_id: string
          report_type?: string
          requested_by?: string | null
          status?: string
        }
        Update: {
          completed_at?: string | null
          content?: string | null
          created_at?: string
          error?: string | null
          facility_id?: string | null
          id?: string
          patient_id?: string
          report_type?: string
          requested_by?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_report_requests_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_report_requests_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_symptom_icd_map: {
        Row: {
          confidence: number | null
          created_at: string | null
          icd_code: string | null
          id: string
          symptom: string
        }
        Insert: {
          confidence?: number | null
          created_at?: string | null
          icd_code?: string | null
          id?: string
          symptom: string
        }
        Update: {
          confidence?: number | null
          created_at?: string | null
          icd_code?: string | null
          id?: string
          symptom?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_symptom_icd_map_icd_code_fkey"
            columns: ["icd_code"]
            isOneToOne: false
            referencedRelation: "icd_codes"
            referencedColumns: ["code"]
          },
        ]
      }
      anesthetic_assessments: {
        Row: {
          airway_assessment: string | null
          allergies: string | null
          asa_class: string | null
          cardiovascular: string | null
          cleared_by: string | null
          cleared_for_procedure: boolean | null
          conclusions: string | null
          created_at: string
          encounter_id: string | null
          facility_id: string | null
          fasting_status: string | null
          id: string
          medications: string | null
          patient_id: string
          questionnaire: Json | null
          respiratory: string | null
          status: string
          updated_at: string
        }
        Insert: {
          airway_assessment?: string | null
          allergies?: string | null
          asa_class?: string | null
          cardiovascular?: string | null
          cleared_by?: string | null
          cleared_for_procedure?: boolean | null
          conclusions?: string | null
          created_at?: string
          encounter_id?: string | null
          facility_id?: string | null
          fasting_status?: string | null
          id?: string
          medications?: string | null
          patient_id: string
          questionnaire?: Json | null
          respiratory?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          airway_assessment?: string | null
          allergies?: string | null
          asa_class?: string | null
          cardiovascular?: string | null
          cleared_by?: string | null
          cleared_for_procedure?: boolean | null
          conclusions?: string | null
          created_at?: string
          encounter_id?: string | null
          facility_id?: string | null
          fasting_status?: string | null
          id?: string
          medications?: string | null
          patient_id?: string
          questionnaire?: Json | null
          respiratory?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "anesthetic_assessments_encounter_id_fkey"
            columns: ["encounter_id"]
            isOneToOne: false
            referencedRelation: "encounters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "anesthetic_assessments_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "anesthetic_assessments_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      appointments: {
        Row: {
          appointment_date: string | null
          attending_officer_id: string | null
          claimed_at: string | null
          completed_at: string | null
          consultation_type: string
          created_at: string
          department: string | null
          duration_minutes: number | null
          facility_id: string | null
          id: string
          notes: string | null
          patient_id: string
          practitioner_id: string | null
          provider_id: string | null
          reason: string | null
          scheduled_at: string
          started_at: string | null
          status: string
          treatment_notes: string | null
          treatment_status: string
          updated_at: string
        }
        Insert: {
          appointment_date?: string | null
          attending_officer_id?: string | null
          claimed_at?: string | null
          completed_at?: string | null
          consultation_type?: string
          created_at?: string
          department?: string | null
          duration_minutes?: number | null
          facility_id?: string | null
          id?: string
          notes?: string | null
          patient_id: string
          practitioner_id?: string | null
          provider_id?: string | null
          reason?: string | null
          scheduled_at: string
          started_at?: string | null
          status?: string
          treatment_notes?: string | null
          treatment_status?: string
          updated_at?: string
        }
        Update: {
          appointment_date?: string | null
          attending_officer_id?: string | null
          claimed_at?: string | null
          completed_at?: string | null
          consultation_type?: string
          created_at?: string
          department?: string | null
          duration_minutes?: number | null
          facility_id?: string | null
          id?: string
          notes?: string | null
          patient_id?: string
          practitioner_id?: string | null
          provider_id?: string | null
          reason?: string | null
          scheduled_at?: string
          started_at?: string | null
          status?: string
          treatment_notes?: string | null
          treatment_status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "appointments_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "appointments_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      audit_logs: {
        Row: {
          action: string | null
          created_at: string | null
          id: string
          new_data: Json | null
          old_data: Json | null
          record_id: string | null
          table_name: string | null
          user_id: string | null
        }
        Insert: {
          action?: string | null
          created_at?: string | null
          id?: string
          new_data?: Json | null
          old_data?: Json | null
          record_id?: string | null
          table_name?: string | null
          user_id?: string | null
        }
        Update: {
          action?: string | null
          created_at?: string | null
          id?: string
          new_data?: Json | null
          old_data?: Json | null
          record_id?: string | null
          table_name?: string | null
          user_id?: string | null
        }
        Relationships: []
      }
      beds: {
        Row: {
          admission_id: string | null
          bed_number: string
          bed_type: string
          created_at: string
          facility_id: string | null
          id: string
          notes: string | null
          patient_id: string | null
          status: string
          updated_at: string
          ward_id: string
        }
        Insert: {
          admission_id?: string | null
          bed_number: string
          bed_type?: string
          created_at?: string
          facility_id?: string | null
          id?: string
          notes?: string | null
          patient_id?: string | null
          status?: string
          updated_at?: string
          ward_id: string
        }
        Update: {
          admission_id?: string | null
          bed_number?: string
          bed_type?: string
          created_at?: string
          facility_id?: string | null
          id?: string
          notes?: string | null
          patient_id?: string | null
          status?: string
          updated_at?: string
          ward_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "beds_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "beds_ward_id_fkey"
            columns: ["ward_id"]
            isOneToOne: false
            referencedRelation: "wards"
            referencedColumns: ["id"]
          },
        ]
      }
      billing_item_payments: {
        Row: {
          amount: number
          created_at: string
          id: string
          invoice_item_id: string
          payment_id: string
        }
        Insert: {
          amount: number
          created_at?: string
          id?: string
          invoice_item_id: string
          payment_id: string
        }
        Update: {
          amount?: number
          created_at?: string
          id?: string
          invoice_item_id?: string
          payment_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "billing_item_payments_invoice_item_id_fkey"
            columns: ["invoice_item_id"]
            isOneToOne: false
            referencedRelation: "invoice_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "billing_item_payments_payment_id_fkey"
            columns: ["payment_id"]
            isOneToOne: false
            referencedRelation: "payments"
            referencedColumns: ["id"]
          },
        ]
      }
      billing_overrides: {
        Row: {
          approved_at: string | null
          approved_by: string
          created_at: string
          department: string
          facility_id: string | null
          id: string
          overridden_by: string
          patient_id: string
          reason: string
          related_entity_id: string | null
          service_order_id: string | null
        }
        Insert: {
          approved_at?: string | null
          approved_by: string
          created_at?: string
          department: string
          facility_id?: string | null
          id?: string
          overridden_by: string
          patient_id: string
          reason: string
          related_entity_id?: string | null
          service_order_id?: string | null
        }
        Update: {
          approved_at?: string | null
          approved_by?: string
          created_at?: string
          department?: string
          facility_id?: string | null
          id?: string
          overridden_by?: string
          patient_id?: string
          reason?: string
          related_entity_id?: string | null
          service_order_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "billing_overrides_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "billing_overrides_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "billing_overrides_service_order_fk"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "billing_overrides_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      billing_tariff_adjustments: {
        Row: {
          adjusted_at: string
          adjusted_by: string
          adjusted_unit_price: number
          adjustment_type: string
          id: string
          invoice_item_id: string
          previous_unit_price: number
          quantity: number
          reason: string
          service_code: string | null
          service_name: string
          service_order_id: string | null
        }
        Insert: {
          adjusted_at?: string
          adjusted_by: string
          adjusted_unit_price: number
          adjustment_type?: string
          id?: string
          invoice_item_id: string
          previous_unit_price?: number
          quantity?: number
          reason: string
          service_code?: string | null
          service_name: string
          service_order_id?: string | null
        }
        Update: {
          adjusted_at?: string
          adjusted_by?: string
          adjusted_unit_price?: number
          adjustment_type?: string
          id?: string
          invoice_item_id?: string
          previous_unit_price?: number
          quantity?: number
          reason?: string
          service_code?: string | null
          service_name?: string
          service_order_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "billing_tariff_adjustments_invoice_item_id_fkey"
            columns: ["invoice_item_id"]
            isOneToOne: false
            referencedRelation: "invoice_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "billing_tariff_adjustments_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      bulk_import_jobs: {
        Row: {
          created_at: string
          created_by: string | null
          entity: string
          errors: Json
          failed_rows: number
          filename: string | null
          id: string
          inserted_rows: number
          status: string
          total_rows: number
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          entity: string
          errors?: Json
          failed_rows?: number
          filename?: string | null
          id?: string
          inserted_rows?: number
          status?: string
          total_rows?: number
        }
        Update: {
          created_at?: string
          created_by?: string | null
          entity?: string
          errors?: Json
          failed_rows?: number
          filename?: string | null
          id?: string
          inserted_rows?: number
          status?: string
          total_rows?: number
        }
        Relationships: []
      }
      care_transitions: {
        Row: {
          admission_id: string | null
          completed_at: string | null
          created_at: string
          destination: string | null
          facility_id: string | null
          follow_up_date: string | null
          follow_up_required: boolean
          id: string
          instructions: string | null
          medications_reconciled: boolean
          patient_id: string
          responsible_officer: string | null
          status: string
          summary: string | null
          transition_type: string
          updated_at: string
        }
        Insert: {
          admission_id?: string | null
          completed_at?: string | null
          created_at?: string
          destination?: string | null
          facility_id?: string | null
          follow_up_date?: string | null
          follow_up_required?: boolean
          id?: string
          instructions?: string | null
          medications_reconciled?: boolean
          patient_id: string
          responsible_officer?: string | null
          status?: string
          summary?: string | null
          transition_type: string
          updated_at?: string
        }
        Update: {
          admission_id?: string | null
          completed_at?: string | null
          created_at?: string
          destination?: string | null
          facility_id?: string | null
          follow_up_date?: string | null
          follow_up_required?: boolean
          id?: string
          instructions?: string | null
          medications_reconciled?: boolean
          patient_id?: string
          responsible_officer?: string | null
          status?: string
          summary?: string | null
          transition_type?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "care_transitions_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "care_transitions_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      clinical_reference_values: {
        Row: {
          created_at: string
          created_by: string | null
          display_text: string
          effective_date: string
          id: string
          is_active: boolean
          last_reviewed_at: string
          normal_max: number | null
          normal_min: number | null
          parameter: string
          population_scope: string
          review_due_at: string
          source_is_ghana_specific: boolean
          source_name: string
          source_reference: string
          source_url: string
          thresholds: Json
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          display_text: string
          effective_date: string
          id?: string
          is_active?: boolean
          last_reviewed_at?: string
          normal_max?: number | null
          normal_min?: number | null
          parameter: string
          population_scope?: string
          review_due_at: string
          source_is_ghana_specific?: boolean
          source_name: string
          source_reference: string
          source_url: string
          thresholds?: Json
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          display_text?: string
          effective_date?: string
          id?: string
          is_active?: boolean
          last_reviewed_at?: string
          normal_max?: number | null
          normal_min?: number | null
          parameter?: string
          population_scope?: string
          review_due_at?: string
          source_is_ghana_specific?: boolean
          source_name?: string
          source_reference?: string
          source_url?: string
          thresholds?: Json
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      data_migration_batches: {
        Row: {
          accepted_rows: number
          approved_at: string | null
          approved_by: string | null
          completed_at: string | null
          created_at: string
          created_by: string | null
          entity_type: string
          file_name: string | null
          id: string
          mapping_profile: string | null
          metadata: Json
          rejected_rows: number
          source_format: string
          source_system: string
          source_version: string | null
          staged_rows: number
          status: string
          total_rows: number
          validation_errors: Json
        }
        Insert: {
          accepted_rows?: number
          approved_at?: string | null
          approved_by?: string | null
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          entity_type: string
          file_name?: string | null
          id?: string
          mapping_profile?: string | null
          metadata?: Json
          rejected_rows?: number
          source_format?: string
          source_system: string
          source_version?: string | null
          staged_rows?: number
          status?: string
          total_rows?: number
          validation_errors?: Json
        }
        Update: {
          accepted_rows?: number
          approved_at?: string | null
          approved_by?: string | null
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          entity_type?: string
          file_name?: string | null
          id?: string
          mapping_profile?: string | null
          metadata?: Json
          rejected_rows?: number
          source_format?: string
          source_system?: string
          source_version?: string | null
          staged_rows?: number
          status?: string
          total_rows?: number
          validation_errors?: Json
        }
        Relationships: []
      }
      data_migration_rows: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          batch_id: string
          created_at: string
          id: string
          match_confidence: number | null
          match_method: string | null
          normalized_data: Json | null
          patient_id: string | null
          promoted_at: string | null
          promoted_by: string | null
          raw_data: Json
          reconciled_at: string | null
          reconciled_by: string | null
          rejection_reason: string | null
          row_status: string
          source_key: string | null
          source_row_number: number
          target_id: string | null
          target_table: string | null
          validation_errors: Json
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          batch_id: string
          created_at?: string
          id?: string
          match_confidence?: number | null
          match_method?: string | null
          normalized_data?: Json | null
          patient_id?: string | null
          promoted_at?: string | null
          promoted_by?: string | null
          raw_data: Json
          reconciled_at?: string | null
          reconciled_by?: string | null
          rejection_reason?: string | null
          row_status?: string
          source_key?: string | null
          source_row_number: number
          target_id?: string | null
          target_table?: string | null
          validation_errors?: Json
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          batch_id?: string
          created_at?: string
          id?: string
          match_confidence?: number | null
          match_method?: string | null
          normalized_data?: Json | null
          patient_id?: string | null
          promoted_at?: string | null
          promoted_by?: string | null
          raw_data?: Json
          reconciled_at?: string | null
          reconciled_by?: string | null
          rejection_reason?: string | null
          row_status?: string
          source_key?: string | null
          source_row_number?: number
          target_id?: string | null
          target_table?: string | null
          validation_errors?: Json
        }
        Relationships: [
          {
            foreignKeyName: "data_migration_rows_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "data_migration_batches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "data_migration_rows_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      dental_assessments: {
        Row: {
          created_at: string
          created_by: string
          encounter_id: string
          facility_id: string
          id: string
          oral_hygiene_instructions: string | null
          patient_id: string
          pending_procedures: Json
          periodontal_status: string | null
          procedures_performed: Json
          tooth_chart_data: Json
          tooth_chart_system: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by: string
          encounter_id: string
          facility_id: string
          id?: string
          oral_hygiene_instructions?: string | null
          patient_id: string
          pending_procedures?: Json
          periodontal_status?: string | null
          procedures_performed?: Json
          tooth_chart_data?: Json
          tooth_chart_system?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string
          encounter_id?: string
          facility_id?: string
          id?: string
          oral_hygiene_instructions?: string | null
          patient_id?: string
          pending_procedures?: Json
          periodontal_status?: string | null
          procedures_performed?: Json
          tooth_chart_data?: Json
          tooth_chart_system?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "dental_assessments_encounter_id_fkey"
            columns: ["encounter_id"]
            isOneToOne: false
            referencedRelation: "encounters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "dental_assessments_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      dental_records: {
        Row: {
          created_at: string
          encounter_id: string | null
          examination: string | null
          facility_id: string | null
          id: string
          patient_id: string
          performed_by: string | null
          procedures_performed: string | null
          tooth_chart: Json
          treatment_plan: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          encounter_id?: string | null
          examination?: string | null
          facility_id?: string | null
          id?: string
          patient_id: string
          performed_by?: string | null
          procedures_performed?: string | null
          tooth_chart?: Json
          treatment_plan?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          encounter_id?: string | null
          examination?: string | null
          facility_id?: string | null
          id?: string
          patient_id?: string
          performed_by?: string | null
          procedures_performed?: string | null
          tooth_chart?: Json
          treatment_plan?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "dental_records_encounter_id_fkey"
            columns: ["encounter_id"]
            isOneToOne: false
            referencedRelation: "encounters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "dental_records_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "dental_records_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      department_queues: {
        Row: {
          assigned_to: string | null
          claimed_at: string | null
          claimed_by: string | null
          completed_at: string | null
          created_at: string
          created_by: string | null
          department: string
          facility_id: string | null
          id: string
          patient_id: string
          payment_required: boolean
          payment_satisfied: boolean
          priority: string
          queued_at: string
          reason: string | null
          related_encounter_id: string | null
          related_invoice_id: string | null
          service_order_id: string | null
          status: string
          updated_at: string
        }
        Insert: {
          assigned_to?: string | null
          claimed_at?: string | null
          claimed_by?: string | null
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          department: string
          facility_id?: string | null
          id?: string
          patient_id: string
          payment_required?: boolean
          payment_satisfied?: boolean
          priority?: string
          queued_at?: string
          reason?: string | null
          related_encounter_id?: string | null
          related_invoice_id?: string | null
          service_order_id?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          assigned_to?: string | null
          claimed_at?: string | null
          claimed_by?: string | null
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          department?: string
          facility_id?: string | null
          id?: string
          patient_id?: string
          payment_required?: boolean
          payment_satisfied?: boolean
          priority?: string
          queued_at?: string
          reason?: string | null
          related_encounter_id?: string | null
          related_invoice_id?: string | null
          service_order_id?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "department_queues_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "department_queues_service_order_fk"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "department_queues_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      diagnoses: {
        Row: {
          ai_suggested: boolean | null
          created_at: string
          diagnosis: string
          encounter_id: string
          facility_id: string | null
          icd_code: string | null
          id: string
          is_principal: boolean | null
          is_provisional: boolean | null
          notes: string | null
          patient_id: string | null
          updated_at: string
        }
        Insert: {
          ai_suggested?: boolean | null
          created_at?: string
          diagnosis: string
          encounter_id: string
          facility_id?: string | null
          icd_code?: string | null
          id?: string
          is_principal?: boolean | null
          is_provisional?: boolean | null
          notes?: string | null
          patient_id?: string | null
          updated_at?: string
        }
        Update: {
          ai_suggested?: boolean | null
          created_at?: string
          diagnosis?: string
          encounter_id?: string
          facility_id?: string | null
          icd_code?: string | null
          id?: string
          is_principal?: boolean | null
          is_provisional?: boolean | null
          notes?: string | null
          patient_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "diagnoses_encounter_id_fkey"
            columns: ["encounter_id"]
            isOneToOne: false
            referencedRelation: "encounters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "diagnoses_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_diagnoses_icd_completeness"
            columns: ["icd_code"]
            isOneToOne: false
            referencedRelation: "icd_codes"
            referencedColumns: ["code"]
          },
        ]
      }
      diagnosis_import_batches: {
        Row: {
          accepted_rows: number
          approved_at: string | null
          approved_by: string | null
          assessment_only: boolean
          completed_at: string | null
          created_at: string
          created_by: string | null
          duplicate_rows: number
          file_name: string | null
          id: string
          rejected_rows: number
          sheet_assessments: Json
          source_format: string
          source_version: string | null
          standard_id: string | null
          status: string
          total_rows: number
          total_sheets: number
          unmapped_rows: number
          validation_errors: Json
        }
        Insert: {
          accepted_rows?: number
          approved_at?: string | null
          approved_by?: string | null
          assessment_only?: boolean
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          duplicate_rows?: number
          file_name?: string | null
          id?: string
          rejected_rows?: number
          sheet_assessments?: Json
          source_format?: string
          source_version?: string | null
          standard_id?: string | null
          status?: string
          total_rows?: number
          total_sheets?: number
          unmapped_rows?: number
          validation_errors?: Json
        }
        Update: {
          accepted_rows?: number
          approved_at?: string | null
          approved_by?: string | null
          assessment_only?: boolean
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          duplicate_rows?: number
          file_name?: string | null
          id?: string
          rejected_rows?: number
          sheet_assessments?: Json
          source_format?: string
          source_version?: string | null
          standard_id?: string | null
          status?: string
          total_rows?: number
          total_sheets?: number
          unmapped_rows?: number
          validation_errors?: Json
        }
        Relationships: [
          {
            foreignKeyName: "diagnosis_import_batches_standard_id_fkey"
            columns: ["standard_id"]
            isOneToOne: false
            referencedRelation: "diagnosis_standards"
            referencedColumns: ["id"]
          },
        ]
      }
      diagnosis_import_rows: {
        Row: {
          batch_id: string
          category: string | null
          created_at: string
          description: string | null
          display_name: string | null
          icd10_code: string | null
          icd10_code_id: string | null
          id: string
          normalized_key: string
          rejection_reason: string | null
          row_status: string
          sheet_name: string
          source_code: string | null
          source_row_number: number
          synonyms: string[]
        }
        Insert: {
          batch_id: string
          category?: string | null
          created_at?: string
          description?: string | null
          display_name?: string | null
          icd10_code?: string | null
          icd10_code_id?: string | null
          id?: string
          normalized_key: string
          rejection_reason?: string | null
          row_status?: string
          sheet_name: string
          source_code?: string | null
          source_row_number: number
          synonyms?: string[]
        }
        Update: {
          batch_id?: string
          category?: string | null
          created_at?: string
          description?: string | null
          display_name?: string | null
          icd10_code?: string | null
          icd10_code_id?: string | null
          id?: string
          normalized_key?: string
          rejection_reason?: string | null
          row_status?: string
          sheet_name?: string
          source_code?: string | null
          source_row_number?: number
          synonyms?: string[]
        }
        Relationships: [
          {
            foreignKeyName: "diagnosis_import_rows_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "diagnosis_import_batches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "diagnosis_import_rows_icd10_code_id_fkey"
            columns: ["icd10_code_id"]
            isOneToOne: false
            referencedRelation: "icd_codes"
            referencedColumns: ["id"]
          },
        ]
      }
      diagnosis_standard_mappings: {
        Row: {
          confidence: number | null
          created_at: string
          icd10_code_id: string
          id: string
          mapping_type: string
          reviewed_at: string | null
          reviewed_by: string | null
          source_reference: string | null
          stg_diagnosis_id: string
        }
        Insert: {
          confidence?: number | null
          created_at?: string
          icd10_code_id: string
          id?: string
          mapping_type?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          source_reference?: string | null
          stg_diagnosis_id: string
        }
        Update: {
          confidence?: number | null
          created_at?: string
          icd10_code_id?: string
          id?: string
          mapping_type?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          source_reference?: string | null
          stg_diagnosis_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "diagnosis_standard_mappings_icd10_code_id_fkey"
            columns: ["icd10_code_id"]
            isOneToOne: false
            referencedRelation: "icd_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "diagnosis_standard_mappings_stg_diagnosis_id_fkey"
            columns: ["stg_diagnosis_id"]
            isOneToOne: false
            referencedRelation: "stg_diagnoses"
            referencedColumns: ["id"]
          },
        ]
      }
      diagnosis_standards: {
        Row: {
          code: string
          created_at: string
          effective_from: string | null
          effective_to: string | null
          id: string
          is_active: boolean
          is_default: boolean
          jurisdiction: string
          name: string
          publisher: string | null
          source_uri: string | null
          updated_at: string
          version: string | null
        }
        Insert: {
          code: string
          created_at?: string
          effective_from?: string | null
          effective_to?: string | null
          id?: string
          is_active?: boolean
          is_default?: boolean
          jurisdiction: string
          name: string
          publisher?: string | null
          source_uri?: string | null
          updated_at?: string
          version?: string | null
        }
        Update: {
          code?: string
          created_at?: string
          effective_from?: string | null
          effective_to?: string | null
          id?: string
          is_active?: boolean
          is_default?: boolean
          jurisdiction?: string
          name?: string
          publisher?: string | null
          source_uri?: string | null
          updated_at?: string
          version?: string | null
        }
        Relationships: []
      }
      dietary_assessments: {
        Row: {
          adherence_notes: string | null
          biochemical_data: Json
          bmi: number | null
          clinical_assessment: string | null
          created_at: string
          created_by: string
          dietary_recall: Json
          encounter_id: string
          facility_id: string
          height_cm: number | null
          id: string
          meal_plan: Json
          meal_plan_review_due: string | null
          nutritional_diagnosis: string | null
          patient_id: string
          updated_at: string
          waist_circumference_cm: number | null
          weight_kg: number | null
        }
        Insert: {
          adherence_notes?: string | null
          biochemical_data?: Json
          bmi?: number | null
          clinical_assessment?: string | null
          created_at?: string
          created_by: string
          dietary_recall?: Json
          encounter_id: string
          facility_id: string
          height_cm?: number | null
          id?: string
          meal_plan?: Json
          meal_plan_review_due?: string | null
          nutritional_diagnosis?: string | null
          patient_id: string
          updated_at?: string
          waist_circumference_cm?: number | null
          weight_kg?: number | null
        }
        Update: {
          adherence_notes?: string | null
          biochemical_data?: Json
          bmi?: number | null
          clinical_assessment?: string | null
          created_at?: string
          created_by?: string
          dietary_recall?: Json
          encounter_id?: string
          facility_id?: string
          height_cm?: number | null
          id?: string
          meal_plan?: Json
          meal_plan_review_due?: string | null
          nutritional_diagnosis?: string | null
          patient_id?: string
          updated_at?: string
          waist_circumference_cm?: number | null
          weight_kg?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "dietary_assessments_encounter_id_fkey"
            columns: ["encounter_id"]
            isOneToOne: false
            referencedRelation: "encounters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "dietary_assessments_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      dietary_meal_orders: {
        Row: {
          created_at: string
          created_by: string
          diet_code: string
          diet_name: string
          dietary_assessment_id: string
          effective_from: string
          effective_until: string | null
          encounter_id: string
          facility_id: string
          id: string
          kitchen_acknowledged_at: string | null
          meal_plan: Json
          patient_id: string
          status: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by: string
          diet_code: string
          diet_name: string
          dietary_assessment_id: string
          effective_from?: string
          effective_until?: string | null
          encounter_id: string
          facility_id: string
          id?: string
          kitchen_acknowledged_at?: string | null
          meal_plan?: Json
          patient_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string
          diet_code?: string
          diet_name?: string
          dietary_assessment_id?: string
          effective_from?: string
          effective_until?: string | null
          encounter_id?: string
          facility_id?: string
          id?: string
          kitchen_acknowledged_at?: string | null
          meal_plan?: Json
          patient_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "dietary_meal_orders_dietary_assessment_id_fkey"
            columns: ["dietary_assessment_id"]
            isOneToOne: false
            referencedRelation: "dietary_assessments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "dietary_meal_orders_encounter_id_fkey"
            columns: ["encounter_id"]
            isOneToOne: false
            referencedRelation: "encounters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "dietary_meal_orders_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      document_versions: {
        Row: {
          action: string
          changed_at: string
          changed_by: string | null
          entity_id: string
          entity_type: string
          id: string
          snapshot: Json
          version_no: number
        }
        Insert: {
          action: string
          changed_at?: string
          changed_by?: string | null
          entity_id: string
          entity_type: string
          id?: string
          snapshot?: Json
          version_no: number
        }
        Update: {
          action?: string
          changed_at?: string
          changed_by?: string | null
          entity_id?: string
          entity_type?: string
          id?: string
          snapshot?: Json
          version_no?: number
        }
        Relationships: []
      }
      emergency_cases: {
        Row: {
          acuity: string | null
          arrival_at: string
          arrival_mode: string
          arrival_time: string | null
          assigned_officer: string | null
          chief_complaint: string | null
          created_at: string
          disposition: string | null
          facility_id: string | null
          id: string
          notes: string | null
          patient_id: string | null
          status: string
          triage_priority: string
          updated_at: string
        }
        Insert: {
          acuity?: string | null
          arrival_at?: string
          arrival_mode?: string
          arrival_time?: string | null
          assigned_officer?: string | null
          chief_complaint?: string | null
          created_at?: string
          disposition?: string | null
          facility_id?: string | null
          id?: string
          notes?: string | null
          patient_id?: string | null
          status?: string
          triage_priority?: string
          updated_at?: string
        }
        Update: {
          acuity?: string | null
          arrival_at?: string
          arrival_mode?: string
          arrival_time?: string | null
          assigned_officer?: string | null
          chief_complaint?: string | null
          created_at?: string
          disposition?: string | null
          facility_id?: string | null
          id?: string
          notes?: string | null
          patient_id?: string | null
          status?: string
          triage_priority?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "emergency_cases_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
        ]
      }
      encounters: {
        Row: {
          admission_id: string | null
          appointment_id: string | null
          assessment: string | null
          chief_complaint: string | null
          clerking_notes: string | null
          completed_at: string | null
          created_at: string
          encounter_type: string | null
          facility_id: string | null
          follow_up_date: string | null
          history_of_present_illness: string | null
          id: string
          locked_at: string | null
          patient_id: string
          plan: string | null
          practitioner_id: string | null
          principal_diagnosis: string | null
          provider_id: string | null
          started_at: string | null
          status: string
          submitted_at: string | null
          submitted_by: string | null
          symptoms: string | null
          treatment_plan: string | null
          updated_at: string
          version_no: number
        }
        Insert: {
          admission_id?: string | null
          appointment_id?: string | null
          assessment?: string | null
          chief_complaint?: string | null
          clerking_notes?: string | null
          completed_at?: string | null
          created_at?: string
          encounter_type?: string | null
          facility_id?: string | null
          follow_up_date?: string | null
          history_of_present_illness?: string | null
          id?: string
          locked_at?: string | null
          patient_id: string
          plan?: string | null
          practitioner_id?: string | null
          principal_diagnosis?: string | null
          provider_id?: string | null
          started_at?: string | null
          status?: string
          submitted_at?: string | null
          submitted_by?: string | null
          symptoms?: string | null
          treatment_plan?: string | null
          updated_at?: string
          version_no?: number
        }
        Update: {
          admission_id?: string | null
          appointment_id?: string | null
          assessment?: string | null
          chief_complaint?: string | null
          clerking_notes?: string | null
          completed_at?: string | null
          created_at?: string
          encounter_type?: string | null
          facility_id?: string | null
          follow_up_date?: string | null
          history_of_present_illness?: string | null
          id?: string
          locked_at?: string | null
          patient_id?: string
          plan?: string | null
          practitioner_id?: string | null
          principal_diagnosis?: string | null
          provider_id?: string | null
          started_at?: string | null
          status?: string
          submitted_at?: string | null
          submitted_by?: string | null
          symptoms?: string | null
          treatment_plan?: string | null
          updated_at?: string
          version_no?: number
        }
        Relationships: [
          {
            foreignKeyName: "encounters_admission_id_fkey"
            columns: ["admission_id"]
            isOneToOne: false
            referencedRelation: "admissions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "encounters_appointment_id_fkey"
            columns: ["appointment_id"]
            isOneToOne: false
            referencedRelation: "appointments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "encounters_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "encounters_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      facility_configuration: {
        Row: {
          address: string | null
          admission_financial_override_enabled: boolean
          allow_clinical_emergency_override: boolean
          allow_treatment_before_deposit: boolean
          appointment_buffer_minutes: number
          country: string
          created_at: string
          currency: string
          email: string | null
          facility_code: string | null
          facility_name: string
          id: string
          inherit_inpatient_diagnoses: boolean
          maintenance_mode: boolean
          notification_sound_enabled: boolean
          phone: string | null
          require_accounts_release_after_deposit: boolean
          require_principal_diagnosis_for_final: boolean
          routing_mode: string
          timezone: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          address?: string | null
          admission_financial_override_enabled?: boolean
          allow_clinical_emergency_override?: boolean
          allow_treatment_before_deposit?: boolean
          appointment_buffer_minutes?: number
          country?: string
          created_at?: string
          currency?: string
          email?: string | null
          facility_code?: string | null
          facility_name?: string
          id?: string
          inherit_inpatient_diagnoses?: boolean
          maintenance_mode?: boolean
          notification_sound_enabled?: boolean
          phone?: string | null
          require_accounts_release_after_deposit?: boolean
          require_principal_diagnosis_for_final?: boolean
          routing_mode?: string
          timezone?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          address?: string | null
          admission_financial_override_enabled?: boolean
          allow_clinical_emergency_override?: boolean
          allow_treatment_before_deposit?: boolean
          appointment_buffer_minutes?: number
          country?: string
          created_at?: string
          currency?: string
          email?: string | null
          facility_code?: string | null
          facility_name?: string
          id?: string
          inherit_inpatient_diagnoses?: boolean
          maintenance_mode?: boolean
          notification_sound_enabled?: boolean
          phone?: string | null
          require_accounts_release_after_deposit?: boolean
          require_principal_diagnosis_for_final?: boolean
          routing_mode?: string
          timezone?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      facility_data_sharing_agreement_scopes: {
        Row: {
          agreement_id: string
          created_at: string
          scope_code: string
        }
        Insert: {
          agreement_id: string
          created_at?: string
          scope_code: string
        }
        Update: {
          agreement_id?: string
          created_at?: string
          scope_code?: string
        }
        Relationships: [
          {
            foreignKeyName: "facility_data_sharing_agreement_scopes_agreement_id_fkey"
            columns: ["agreement_id"]
            isOneToOne: false
            referencedRelation: "facility_data_sharing_agreements"
            referencedColumns: ["id"]
          },
        ]
      }
      facility_data_sharing_agreements: {
        Row: {
          created_at: string
          created_by: string
          effective_from: string
          effective_to: string | null
          facility_a_approved_at: string | null
          facility_a_approved_by: string | null
          facility_a_id: string
          facility_b_approved_at: string | null
          facility_b_approved_by: string | null
          facility_b_id: string
          id: string
          metadata: Json
          purpose: string
          revoked_at: string | null
          revoked_by: string | null
          status: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by: string
          effective_from?: string
          effective_to?: string | null
          facility_a_approved_at?: string | null
          facility_a_approved_by?: string | null
          facility_a_id: string
          facility_b_approved_at?: string | null
          facility_b_approved_by?: string | null
          facility_b_id: string
          id?: string
          metadata?: Json
          purpose: string
          revoked_at?: string | null
          revoked_by?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string
          effective_from?: string
          effective_to?: string | null
          facility_a_approved_at?: string | null
          facility_a_approved_by?: string | null
          facility_a_id?: string
          facility_b_approved_at?: string | null
          facility_b_approved_by?: string | null
          facility_b_id?: string
          id?: string
          metadata?: Json
          purpose?: string
          revoked_at?: string | null
          revoked_by?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "facility_data_sharing_agreements_facility_a_id_fkey"
            columns: ["facility_a_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "facility_data_sharing_agreements_facility_b_id_fkey"
            columns: ["facility_b_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
        ]
      }
      facility_diagnosis_standards: {
        Row: {
          created_at: string
          facility_id: string
          is_active: boolean
          priority: number
          standard_id: string
        }
        Insert: {
          created_at?: string
          facility_id: string
          is_active?: boolean
          priority?: number
          standard_id: string
        }
        Update: {
          created_at?: string
          facility_id?: string
          is_active?: boolean
          priority?: number
          standard_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "facility_diagnosis_standards_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "facility_diagnosis_standards_standard_id_fkey"
            columns: ["standard_id"]
            isOneToOne: false
            referencedRelation: "diagnosis_standards"
            referencedColumns: ["id"]
          },
        ]
      }
      facility_memberships: {
        Row: {
          access_scope: string
          created_at: string
          facility_id: string
          id: string
          is_active: boolean
          user_id: string
        }
        Insert: {
          access_scope?: string
          created_at?: string
          facility_id: string
          id?: string
          is_active?: boolean
          user_id: string
        }
        Update: {
          access_scope?: string
          created_at?: string
          facility_id?: string
          id?: string
          is_active?: boolean
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "facility_memberships_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
        ]
      }
      facility_notification_config: {
        Row: {
          branding: Json
          compliance_policy: Json
          consent_policy: Json
          created_at: string
          created_by: string | null
          default_locale: string
          default_timezone: string
          delivery_policy: Json
          deployment_secret_namespace: string | null
          enabled: boolean
          enabled_channels: Json
          environment: string
          facility_id: string
          id: string
          kill_switch: boolean
          onboarding_status: string
          operational_contacts: Json
          production_approved_at: string | null
          production_approved_by: string | null
          provider_config: Json
          provider_defaults: Json
          quiet_hours_end: string
          quiet_hours_start: string
          rollout_percent: number
          sender_config: Json
          updated_at: string
          updated_by: string | null
          verified_at: string | null
          verified_by: string | null
          webhook_config: Json
          webhook_policy: Json
        }
        Insert: {
          branding?: Json
          compliance_policy?: Json
          consent_policy?: Json
          created_at?: string
          created_by?: string | null
          default_locale?: string
          default_timezone?: string
          delivery_policy?: Json
          deployment_secret_namespace?: string | null
          enabled?: boolean
          enabled_channels?: Json
          environment?: string
          facility_id: string
          id?: string
          kill_switch?: boolean
          onboarding_status?: string
          operational_contacts?: Json
          production_approved_at?: string | null
          production_approved_by?: string | null
          provider_config?: Json
          provider_defaults?: Json
          quiet_hours_end?: string
          quiet_hours_start?: string
          rollout_percent?: number
          sender_config?: Json
          updated_at?: string
          updated_by?: string | null
          verified_at?: string | null
          verified_by?: string | null
          webhook_config?: Json
          webhook_policy?: Json
        }
        Update: {
          branding?: Json
          compliance_policy?: Json
          consent_policy?: Json
          created_at?: string
          created_by?: string | null
          default_locale?: string
          default_timezone?: string
          delivery_policy?: Json
          deployment_secret_namespace?: string | null
          enabled?: boolean
          enabled_channels?: Json
          environment?: string
          facility_id?: string
          id?: string
          kill_switch?: boolean
          onboarding_status?: string
          operational_contacts?: Json
          production_approved_at?: string | null
          production_approved_by?: string | null
          provider_config?: Json
          provider_defaults?: Json
          quiet_hours_end?: string
          quiet_hours_start?: string
          rollout_percent?: number
          sender_config?: Json
          updated_at?: string
          updated_by?: string | null
          verified_at?: string | null
          verified_by?: string | null
          webhook_config?: Json
          webhook_policy?: Json
        }
        Relationships: [
          {
            foreignKeyName: "facility_notification_config_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: true
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
        ]
      }
      facility_notification_provider_connections: {
        Row: {
          account_reference: string | null
          channel: string
          created_at: string
          created_by: string | null
          environment: string
          facility_id: string
          id: string
          is_primary: boolean
          last_error: string | null
          last_verified_at: string | null
          metadata: Json
          priority: number
          provider: string
          secret_reference: string | null
          sender_identity: string | null
          status: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          account_reference?: string | null
          channel: string
          created_at?: string
          created_by?: string | null
          environment?: string
          facility_id: string
          id?: string
          is_primary?: boolean
          last_error?: string | null
          last_verified_at?: string | null
          metadata?: Json
          priority?: number
          provider: string
          secret_reference?: string | null
          sender_identity?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          account_reference?: string | null
          channel?: string
          created_at?: string
          created_by?: string | null
          environment?: string
          facility_id?: string
          id?: string
          is_primary?: boolean
          last_error?: string | null
          last_verified_at?: string | null
          metadata?: Json
          priority?: number
          provider?: string
          secret_reference?: string | null
          sender_identity?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "facility_notification_provider_connections_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
        ]
      }
      facility_report_config: {
        Row: {
          created_at: string
          custom_parameters: Json
          facility_id: string
          id: string
          is_enabled: boolean
          report_id: string
          submission_deadline_day: number | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          custom_parameters?: Json
          facility_id: string
          id?: string
          is_enabled?: boolean
          report_id: string
          submission_deadline_day?: number | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          custom_parameters?: Json
          facility_id?: string
          id?: string
          is_enabled?: boolean
          report_id?: string
          submission_deadline_day?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "facility_report_config_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "facility_report_config_report_id_fkey"
            columns: ["report_id"]
            isOneToOne: false
            referencedRelation: "report_definitions"
            referencedColumns: ["id"]
          },
        ]
      }
      facility_settings: {
        Row: {
          admission_financial_override_enabled: boolean
          allow_clinical_emergency_override: boolean
          allow_treatment_before_deposit: boolean
          created_at: string
          facility_name: string
          id: string
          payment_flow: string
          require_accounts_release_after_deposit: boolean
          routing_mode: string
          updated_at: string
        }
        Insert: {
          admission_financial_override_enabled?: boolean
          allow_clinical_emergency_override?: boolean
          allow_treatment_before_deposit?: boolean
          created_at?: string
          facility_name?: string
          id?: string
          payment_flow?: string
          require_accounts_release_after_deposit?: boolean
          routing_mode?: string
          updated_at?: string
        }
        Update: {
          admission_financial_override_enabled?: boolean
          allow_clinical_emergency_override?: boolean
          allow_treatment_before_deposit?: boolean
          created_at?: string
          facility_name?: string
          id?: string
          payment_flow?: string
          require_accounts_release_after_deposit?: boolean
          routing_mode?: string
          updated_at?: string
        }
        Relationships: []
      }
      fertility_cycles: {
        Row: {
          assigned_specialist: string | null
          created_at: string
          cycle_number: number | null
          cycle_type: string
          expected_retrieval_date: string | null
          expected_transfer_date: string | null
          facility_id: string | null
          id: string
          notes: string | null
          outcome: string | null
          partner_name: string | null
          patient_id: string
          protocol: string | null
          start_date: string
          status: string
          updated_at: string
        }
        Insert: {
          assigned_specialist?: string | null
          created_at?: string
          cycle_number?: number | null
          cycle_type: string
          expected_retrieval_date?: string | null
          expected_transfer_date?: string | null
          facility_id?: string | null
          id?: string
          notes?: string | null
          outcome?: string | null
          partner_name?: string | null
          patient_id: string
          protocol?: string | null
          start_date: string
          status?: string
          updated_at?: string
        }
        Update: {
          assigned_specialist?: string | null
          created_at?: string
          cycle_number?: number | null
          cycle_type?: string
          expected_retrieval_date?: string | null
          expected_transfer_date?: string | null
          facility_id?: string | null
          id?: string
          notes?: string | null
          outcome?: string | null
          partner_name?: string | null
          patient_id?: string
          protocol?: string | null
          start_date?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "fertility_cycles_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fertility_cycles_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      fertility_monitoring: {
        Row: {
          created_at: string
          cycle_day: number | null
          cycle_id: string
          endometrial_thickness: number | null
          estradiol: number | null
          follicle_count_left: number | null
          follicle_count_right: number | null
          fsh: number | null
          id: string
          lh: number | null
          medication_adjustments: string | null
          notes: string | null
          progesterone: number | null
          recorded_by: string | null
          visit_date: string
        }
        Insert: {
          created_at?: string
          cycle_day?: number | null
          cycle_id: string
          endometrial_thickness?: number | null
          estradiol?: number | null
          follicle_count_left?: number | null
          follicle_count_right?: number | null
          fsh?: number | null
          id?: string
          lh?: number | null
          medication_adjustments?: string | null
          notes?: string | null
          progesterone?: number | null
          recorded_by?: string | null
          visit_date: string
        }
        Update: {
          created_at?: string
          cycle_day?: number | null
          cycle_id?: string
          endometrial_thickness?: number | null
          estradiol?: number | null
          follicle_count_left?: number | null
          follicle_count_right?: number | null
          fsh?: number | null
          id?: string
          lh?: number | null
          medication_adjustments?: string | null
          notes?: string | null
          progesterone?: number | null
          recorded_by?: string | null
          visit_date?: string
        }
        Relationships: [
          {
            foreignKeyName: "fertility_monitoring_cycle_id_fkey"
            columns: ["cycle_id"]
            isOneToOne: false
            referencedRelation: "fertility_cycles"
            referencedColumns: ["id"]
          },
        ]
      }
      healthcare_facilities: {
        Row: {
          created_at: string
          created_by: string | null
          dhims2_uid: string | null
          district: string | null
          facility_code: string | null
          facility_type: string
          id: string
          is_active: boolean
          name: string
          region: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          dhims2_uid?: string | null
          district?: string | null
          facility_code?: string | null
          facility_type: string
          id?: string
          is_active?: boolean
          name: string
          region?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          dhims2_uid?: string | null
          district?: string | null
          facility_code?: string | null
          facility_type?: string
          id?: string
          is_active?: boolean
          name?: string
          region?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      hms_test_runtime: {
        Row: {
          enabled: boolean
          environment: string
          id: boolean
          updated_at: string
        }
        Insert: {
          enabled?: boolean
          environment?: string
          id?: boolean
          updated_at?: string
        }
        Update: {
          enabled?: boolean
          environment?: string
          id?: boolean
          updated_at?: string
        }
        Relationships: []
      }
      hms_test_runtime_audit: {
        Row: {
          changed_at: string
          changed_by: string
          id: string
          new_enabled: boolean
          previous_enabled: boolean
          reason: string
        }
        Insert: {
          changed_at?: string
          changed_by: string
          id?: string
          new_enabled: boolean
          previous_enabled: boolean
          reason: string
        }
        Update: {
          changed_at?: string
          changed_by?: string
          id?: string
          new_enabled?: boolean
          previous_enabled?: boolean
          reason?: string
        }
        Relationships: []
      }
      hms_test_users: {
        Row: {
          created_at: string
          enabled: boolean
          reason: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          enabled?: boolean
          reason?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          enabled?: boolean
          reason?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      hr_employees: {
        Row: {
          archived_at: string | null
          archived_by: string | null
          bank_account_name: string | null
          bank_account_number: string | null
          bank_name: string | null
          base_salary: number
          created_at: string
          created_by: string | null
          department: string | null
          email: string | null
          employee_number: string
          employment_status: string
          employment_type: string
          end_date: string | null
          facility_id: string
          first_name: string
          id: string
          job_title: string
          last_name: string
          pay_frequency: string
          phone: string | null
          profile_id: string | null
          ssnit_number: string | null
          start_date: string
          tax_identifier: string | null
          updated_at: string
        }
        Insert: {
          archived_at?: string | null
          archived_by?: string | null
          bank_account_name?: string | null
          bank_account_number?: string | null
          bank_name?: string | null
          base_salary?: number
          created_at?: string
          created_by?: string | null
          department?: string | null
          email?: string | null
          employee_number: string
          employment_status?: string
          employment_type?: string
          end_date?: string | null
          facility_id: string
          first_name: string
          id?: string
          job_title: string
          last_name: string
          pay_frequency?: string
          phone?: string | null
          profile_id?: string | null
          ssnit_number?: string | null
          start_date: string
          tax_identifier?: string | null
          updated_at?: string
        }
        Update: {
          archived_at?: string | null
          archived_by?: string | null
          bank_account_name?: string | null
          bank_account_number?: string | null
          bank_name?: string | null
          base_salary?: number
          created_at?: string
          created_by?: string | null
          department?: string | null
          email?: string | null
          employee_number?: string
          employment_status?: string
          employment_type?: string
          end_date?: string | null
          facility_id?: string
          first_name?: string
          id?: string
          job_title?: string
          last_name?: string
          pay_frequency?: string
          phone?: string | null
          profile_id?: string | null
          ssnit_number?: string | null
          start_date?: string
          tax_identifier?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "hr_employees_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hr_employees_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      icd_codes: {
        Row: {
          category: string | null
          code: string
          created_at: string
          description: string
          id: string
          version: string
        }
        Insert: {
          category?: string | null
          code: string
          created_at?: string
          description: string
          id?: string
          version?: string
        }
        Update: {
          category?: string | null
          code?: string
          created_at?: string
          description?: string
          id?: string
          version?: string
        }
        Relationships: []
      }
      imaging_orders: {
        Row: {
          acknowledged_at: string | null
          acknowledged_by: string | null
          amount: number
          body_site: string | null
          clinical_indication: string | null
          completed_at: string | null
          created_at: string
          encounter_id: string | null
          facility_id: string | null
          id: string
          impression: string | null
          modality: string
          patient_id: string
          performed_by: string | null
          priority: string
          report: string | null
          requested_by: string | null
          service_order_id: string | null
          started_at: string | null
          status: string
          study_name: string
          updated_at: string
        }
        Insert: {
          acknowledged_at?: string | null
          acknowledged_by?: string | null
          amount?: number
          body_site?: string | null
          clinical_indication?: string | null
          completed_at?: string | null
          created_at?: string
          encounter_id?: string | null
          facility_id?: string | null
          id?: string
          impression?: string | null
          modality: string
          patient_id: string
          performed_by?: string | null
          priority?: string
          report?: string | null
          requested_by?: string | null
          service_order_id?: string | null
          started_at?: string | null
          status?: string
          study_name: string
          updated_at?: string
        }
        Update: {
          acknowledged_at?: string | null
          acknowledged_by?: string | null
          amount?: number
          body_site?: string | null
          clinical_indication?: string | null
          completed_at?: string | null
          created_at?: string
          encounter_id?: string | null
          facility_id?: string | null
          id?: string
          impression?: string | null
          modality?: string
          patient_id?: string
          performed_by?: string | null
          priority?: string
          report?: string | null
          requested_by?: string | null
          service_order_id?: string | null
          started_at?: string | null
          status?: string
          study_name?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "imaging_orders_encounter_id_fkey"
            columns: ["encounter_id"]
            isOneToOne: false
            referencedRelation: "encounters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "imaging_orders_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "imaging_orders_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "imaging_orders_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      inpatient_bed_movements: {
        Row: {
          admission_id: string
          destination_bed_id: string
          facility_id: string | null
          id: string
          moved_at: string
          moved_by: string | null
          movement_type: string
          notes: string | null
          patient_id: string
          reason: string | null
          source_bed_id: string | null
        }
        Insert: {
          admission_id: string
          destination_bed_id: string
          facility_id?: string | null
          id?: string
          moved_at?: string
          moved_by?: string | null
          movement_type: string
          notes?: string | null
          patient_id: string
          reason?: string | null
          source_bed_id?: string | null
        }
        Update: {
          admission_id?: string
          destination_bed_id?: string
          facility_id?: string | null
          id?: string
          moved_at?: string
          moved_by?: string | null
          movement_type?: string
          notes?: string | null
          patient_id?: string
          reason?: string | null
          source_bed_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "inpatient_bed_movements_admission_id_fkey"
            columns: ["admission_id"]
            isOneToOne: false
            referencedRelation: "admissions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inpatient_bed_movements_destination_bed_id_fkey"
            columns: ["destination_bed_id"]
            isOneToOne: false
            referencedRelation: "ward_beds"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inpatient_bed_movements_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inpatient_bed_movements_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inpatient_bed_movements_source_bed_id_fkey"
            columns: ["source_bed_id"]
            isOneToOne: false
            referencedRelation: "ward_beds"
            referencedColumns: ["id"]
          },
        ]
      }
      inpatient_reviews: {
        Row: {
          admission_id: string
          created_at: string
          facility_id: string | null
          findings: string | null
          id: string
          patient_id: string
          plan: string | null
          review_type: string
          reviewed_by: string | null
          reviewer_name: string | null
          reviewer_role: string | null
          seen_at: string
        }
        Insert: {
          admission_id: string
          created_at?: string
          facility_id?: string | null
          findings?: string | null
          id?: string
          patient_id: string
          plan?: string | null
          review_type?: string
          reviewed_by?: string | null
          reviewer_name?: string | null
          reviewer_role?: string | null
          seen_at?: string
        }
        Update: {
          admission_id?: string
          created_at?: string
          facility_id?: string | null
          findings?: string | null
          id?: string
          patient_id?: string
          plan?: string | null
          review_type?: string
          reviewed_by?: string | null
          reviewer_name?: string | null
          reviewer_role?: string | null
          seen_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "inpatient_reviews_admission_id_fkey"
            columns: ["admission_id"]
            isOneToOne: false
            referencedRelation: "admissions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inpatient_reviews_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inpatient_reviews_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      insurance_cases: {
        Row: {
          approved_amount: number
          authorization_number: string | null
          checked_by: string | null
          claim_amount: number
          claim_status: string
          created_at: string
          eligibility_checked_at: string | null
          eligibility_status: string
          facility_id: string | null
          id: string
          insurance_company_id: string | null
          patient_id: string
          payer_name: string
          policy_number: string | null
          rejection_reason: string | null
          updated_at: string
        }
        Insert: {
          approved_amount?: number
          authorization_number?: string | null
          checked_by?: string | null
          claim_amount?: number
          claim_status?: string
          created_at?: string
          eligibility_checked_at?: string | null
          eligibility_status?: string
          facility_id?: string | null
          id?: string
          insurance_company_id?: string | null
          patient_id: string
          payer_name: string
          policy_number?: string | null
          rejection_reason?: string | null
          updated_at?: string
        }
        Update: {
          approved_amount?: number
          authorization_number?: string | null
          checked_by?: string | null
          claim_amount?: number
          claim_status?: string
          created_at?: string
          eligibility_checked_at?: string | null
          eligibility_status?: string
          facility_id?: string | null
          id?: string
          insurance_company_id?: string | null
          patient_id?: string
          payer_name?: string
          policy_number?: string | null
          rejection_reason?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "insurance_cases_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "insurance_cases_insurance_company_id_fkey"
            columns: ["insurance_company_id"]
            isOneToOne: false
            referencedRelation: "insurance_companies"
            referencedColumns: ["id"]
          },
        ]
      }
      insurance_claims: {
        Row: {
          amount_approved: number | null
          amount_claimed: number
          amount_paid: number
          claim_number: string | null
          created_at: string
          facility_id: string | null
          id: string
          insurance_company_id: string | null
          invoice_id: string
          member_number: string | null
          notes: string | null
          patient_id: string
          payer_name: string
          policy_number: string | null
          provider: string
          rejection_reason: string | null
          resolved_at: string | null
          service_from: string | null
          service_to: string | null
          status: string
          submitted_at: string
          updated_at: string
        }
        Insert: {
          amount_approved?: number | null
          amount_claimed: number
          amount_paid?: number
          claim_number?: string | null
          created_at?: string
          facility_id?: string | null
          id?: string
          insurance_company_id?: string | null
          invoice_id: string
          member_number?: string | null
          notes?: string | null
          patient_id: string
          payer_name: string
          policy_number?: string | null
          provider: string
          rejection_reason?: string | null
          resolved_at?: string | null
          service_from?: string | null
          service_to?: string | null
          status?: string
          submitted_at?: string
          updated_at?: string
        }
        Update: {
          amount_approved?: number | null
          amount_claimed?: number
          amount_paid?: number
          claim_number?: string | null
          created_at?: string
          facility_id?: string | null
          id?: string
          insurance_company_id?: string | null
          invoice_id?: string
          member_number?: string | null
          notes?: string | null
          patient_id?: string
          payer_name?: string
          policy_number?: string | null
          provider?: string
          rejection_reason?: string | null
          resolved_at?: string | null
          service_from?: string | null
          service_to?: string | null
          status?: string
          submitted_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "insurance_claims_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "insurance_claims_insurance_company_id_fkey"
            columns: ["insurance_company_id"]
            isOneToOne: false
            referencedRelation: "insurance_companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "insurance_claims_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "insurance_claims_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      insurance_companies: {
        Row: {
          active: boolean
          address: string | null
          code: string
          contact_person: string | null
          created_at: string
          created_by: string | null
          email: string | null
          id: string
          metadata: Json
          name: string
          phone: string | null
          short_name: string | null
          updated_at: string
        }
        Insert: {
          active?: boolean
          address?: string | null
          code: string
          contact_person?: string | null
          created_at?: string
          created_by?: string | null
          email?: string | null
          id?: string
          metadata?: Json
          name: string
          phone?: string | null
          short_name?: string | null
          updated_at?: string
        }
        Update: {
          active?: boolean
          address?: string | null
          code?: string
          contact_person?: string | null
          created_at?: string
          created_by?: string | null
          email?: string | null
          id?: string
          metadata?: Json
          name?: string
          phone?: string | null
          short_name?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      insurance_service_tariffs: {
        Row: {
          active: boolean
          base_charge: number
          created_at: string
          created_by: string | null
          effective_from: string
          effective_to: string | null
          id: string
          insurance_charge: number
          insurance_company_id: string | null
          metadata: Json
          payer_name: string
          service_code: string
          service_name: string | null
          top_up: number
          updated_at: string
        }
        Insert: {
          active?: boolean
          base_charge?: number
          created_at?: string
          created_by?: string | null
          effective_from?: string
          effective_to?: string | null
          id?: string
          insurance_charge?: number
          insurance_company_id?: string | null
          metadata?: Json
          payer_name: string
          service_code: string
          service_name?: string | null
          top_up?: number
          updated_at?: string
        }
        Update: {
          active?: boolean
          base_charge?: number
          created_at?: string
          created_by?: string | null
          effective_from?: string
          effective_to?: string | null
          id?: string
          insurance_charge?: number
          insurance_company_id?: string | null
          metadata?: Json
          payer_name?: string
          service_code?: string
          service_name?: string | null
          top_up?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "insurance_service_tariffs_insurance_company_id_fkey"
            columns: ["insurance_company_id"]
            isOneToOne: false
            referencedRelation: "insurance_companies"
            referencedColumns: ["id"]
          },
        ]
      }
      invoice_item_payments: {
        Row: {
          amount: number
          created_at: string
          id: string
          invoice_item_id: string
          payment_id: string
        }
        Insert: {
          amount: number
          created_at?: string
          id?: string
          invoice_item_id: string
          payment_id: string
        }
        Update: {
          amount?: number
          created_at?: string
          id?: string
          invoice_item_id?: string
          payment_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "invoice_item_payments_invoice_item_id_fkey"
            columns: ["invoice_item_id"]
            isOneToOne: false
            referencedRelation: "invoice_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoice_item_payments_payment_id_fkey"
            columns: ["payment_id"]
            isOneToOne: false
            referencedRelation: "payments"
            referencedColumns: ["id"]
          },
        ]
      }
      invoice_items: {
        Row: {
          amount: number
          billed_at: string | null
          billed_by: string | null
          category: string | null
          created_at: string
          department: string | null
          description: string
          facility_id: string | null
          id: string
          insurance_charge: number
          invoice_id: string
          paid_amount: number
          paid_at: string | null
          paid_by: string | null
          patient_id: string | null
          quantity: number
          service_code: string | null
          service_order_id: string | null
          source_id: string | null
          source_type: string | null
          top_up: number
          total_price: number | null
          unit_price: number
          updated_at: string
        }
        Insert: {
          amount: number
          billed_at?: string | null
          billed_by?: string | null
          category?: string | null
          created_at?: string
          department?: string | null
          description: string
          facility_id?: string | null
          id?: string
          insurance_charge?: number
          invoice_id: string
          paid_amount?: number
          paid_at?: string | null
          paid_by?: string | null
          patient_id?: string | null
          quantity?: number
          service_code?: string | null
          service_order_id?: string | null
          source_id?: string | null
          source_type?: string | null
          top_up?: number
          total_price?: number | null
          unit_price: number
          updated_at?: string
        }
        Update: {
          amount?: number
          billed_at?: string | null
          billed_by?: string | null
          category?: string | null
          created_at?: string
          department?: string | null
          description?: string
          facility_id?: string | null
          id?: string
          insurance_charge?: number
          invoice_id?: string
          paid_amount?: number
          paid_at?: string | null
          paid_by?: string | null
          patient_id?: string | null
          quantity?: number
          service_code?: string | null
          service_order_id?: string | null
          source_id?: string | null
          source_type?: string | null
          top_up?: number
          total_price?: number | null
          unit_price?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "invoice_items_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoice_items_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoice_items_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      invoices: {
        Row: {
          created_at: string
          created_by: string | null
          encounter_id: string | null
          facility_id: string | null
          id: string
          insurance_covered: number | null
          invoice_number: string
          notes: string | null
          outstanding_amount: number | null
          paid_amount: number
          patient_id: string
          status: string
          total_amount: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          encounter_id?: string | null
          facility_id?: string | null
          id?: string
          insurance_covered?: number | null
          invoice_number?: string
          notes?: string | null
          outstanding_amount?: number | null
          paid_amount?: number
          patient_id: string
          status?: string
          total_amount?: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          encounter_id?: string | null
          facility_id?: string | null
          id?: string
          insurance_covered?: number | null
          invoice_number?: string
          notes?: string | null
          outstanding_amount?: number | null
          paid_amount?: number
          patient_id?: string
          status?: string
          total_amount?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "invoices_encounter_id_fkey"
            columns: ["encounter_id"]
            isOneToOne: false
            referencedRelation: "encounters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoices_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoices_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      lab_orders: {
        Row: {
          clinical_notes: string | null
          collected_by: string | null
          created_at: string
          encounter_id: string | null
          facility_id: string | null
          group_id: string | null
          id: string
          lab_test_catalogue_id: string | null
          ordered_by: string | null
          parent_order_id: string | null
          patient_id: string
          priority: string | null
          sample_collected_at: string | null
          status: string
          test_category: string | null
          test_name: string
          updated_at: string
        }
        Insert: {
          clinical_notes?: string | null
          collected_by?: string | null
          created_at?: string
          encounter_id?: string | null
          facility_id?: string | null
          group_id?: string | null
          id?: string
          lab_test_catalogue_id?: string | null
          ordered_by?: string | null
          parent_order_id?: string | null
          patient_id: string
          priority?: string | null
          sample_collected_at?: string | null
          status?: string
          test_category?: string | null
          test_name: string
          updated_at?: string
        }
        Update: {
          clinical_notes?: string | null
          collected_by?: string | null
          created_at?: string
          encounter_id?: string | null
          facility_id?: string | null
          group_id?: string | null
          id?: string
          lab_test_catalogue_id?: string | null
          ordered_by?: string | null
          parent_order_id?: string | null
          patient_id?: string
          priority?: string | null
          sample_collected_at?: string | null
          status?: string
          test_category?: string | null
          test_name?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "lab_orders_encounter_id_fkey"
            columns: ["encounter_id"]
            isOneToOne: false
            referencedRelation: "encounters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lab_orders_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lab_orders_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "lab_test_groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lab_orders_lab_test_catalogue_id_fkey"
            columns: ["lab_test_catalogue_id"]
            isOneToOne: false
            referencedRelation: "lab_test_catalogue"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lab_orders_parent_order_id_fkey"
            columns: ["parent_order_id"]
            isOneToOne: false
            referencedRelation: "lab_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lab_orders_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      lab_result_attachments: {
        Row: {
          attachment_type: string | null
          attachment_url: string | null
          created_at: string
          facility_id: string
          file_name: string
          file_size_bytes: number
          id: string
          lab_order_id: string
          lab_result_id: string | null
          mime_type: string
          storage_path: string
          uploaded_by: string
        }
        Insert: {
          attachment_type?: string | null
          attachment_url?: string | null
          created_at?: string
          facility_id: string
          file_name: string
          file_size_bytes: number
          id?: string
          lab_order_id: string
          lab_result_id?: string | null
          mime_type: string
          storage_path: string
          uploaded_by: string
        }
        Update: {
          attachment_type?: string | null
          attachment_url?: string | null
          created_at?: string
          facility_id?: string
          file_name?: string
          file_size_bytes?: number
          id?: string
          lab_order_id?: string
          lab_result_id?: string | null
          mime_type?: string
          storage_path?: string
          uploaded_by?: string
        }
        Relationships: [
          {
            foreignKeyName: "lab_result_attachments_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lab_result_attachments_lab_order_id_fkey"
            columns: ["lab_order_id"]
            isOneToOne: false
            referencedRelation: "lab_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lab_result_attachments_lab_result_id_fkey"
            columns: ["lab_result_id"]
            isOneToOne: false
            referencedRelation: "lab_results"
            referencedColumns: ["id"]
          },
        ]
      }
      lab_results: {
        Row: {
          abnormal_flag: string | null
          acknowledged_at: string | null
          acknowledged_by: string | null
          approved_at: string | null
          approved_by: string | null
          created_at: string
          entered_at: string
          entered_by: string | null
          facility_id: string | null
          id: string
          interpretation: string | null
          is_abnormal: boolean | null
          lab_order_id: string
          notes: string | null
          numeric_value: number | null
          parameter_results: Json
          patient_id: string | null
          reference_high: number | null
          reference_low: number | null
          result: string | null
          result_data: Json
          status: string
          unit: string | null
          updated_at: string
        }
        Insert: {
          abnormal_flag?: string | null
          acknowledged_at?: string | null
          acknowledged_by?: string | null
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          entered_at?: string
          entered_by?: string | null
          facility_id?: string | null
          id?: string
          interpretation?: string | null
          is_abnormal?: boolean | null
          lab_order_id: string
          notes?: string | null
          numeric_value?: number | null
          parameter_results?: Json
          patient_id?: string | null
          reference_high?: number | null
          reference_low?: number | null
          result?: string | null
          result_data?: Json
          status?: string
          unit?: string | null
          updated_at?: string
        }
        Update: {
          abnormal_flag?: string | null
          acknowledged_at?: string | null
          acknowledged_by?: string | null
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          entered_at?: string
          entered_by?: string | null
          facility_id?: string | null
          id?: string
          interpretation?: string | null
          is_abnormal?: boolean | null
          lab_order_id?: string
          notes?: string | null
          numeric_value?: number | null
          parameter_results?: Json
          patient_id?: string | null
          reference_high?: number | null
          reference_low?: number | null
          result?: string | null
          result_data?: Json
          status?: string
          unit?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "lab_results_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lab_results_lab_order_id_fkey"
            columns: ["lab_order_id"]
            isOneToOne: false
            referencedRelation: "lab_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      lab_specimens: {
        Row: {
          accession_number: string
          barcode_value: string
          collected_at: string
          collected_by: string
          created_at: string
          id: string
          lab_order_id: string
          recollection_of_id: string | null
          rejected_at: string | null
          rejected_by: string | null
          rejection_reason: string | null
          specimen_type: string | null
          status: string
          updated_at: string
        }
        Insert: {
          accession_number: string
          barcode_value: string
          collected_at?: string
          collected_by: string
          created_at?: string
          id?: string
          lab_order_id: string
          recollection_of_id?: string | null
          rejected_at?: string | null
          rejected_by?: string | null
          rejection_reason?: string | null
          specimen_type?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          accession_number?: string
          barcode_value?: string
          collected_at?: string
          collected_by?: string
          created_at?: string
          id?: string
          lab_order_id?: string
          recollection_of_id?: string | null
          rejected_at?: string | null
          rejected_by?: string | null
          rejection_reason?: string | null
          specimen_type?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "lab_specimens_lab_order_id_fkey"
            columns: ["lab_order_id"]
            isOneToOne: false
            referencedRelation: "lab_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lab_specimens_recollection_of_id_fkey"
            columns: ["recollection_of_id"]
            isOneToOne: false
            referencedRelation: "lab_specimens"
            referencedColumns: ["id"]
          },
        ]
      }
      lab_test_catalog: {
        Row: {
          active: boolean
          category: string | null
          code: string | null
          created_at: string
          created_by: string | null
          id: string
          method: string | null
          name: string
          notes: string | null
          price: number
          specimen: string | null
          turnaround_hours: number | null
          updated_at: string
        }
        Insert: {
          active?: boolean
          category?: string | null
          code?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          method?: string | null
          name: string
          notes?: string | null
          price?: number
          specimen?: string | null
          turnaround_hours?: number | null
          updated_at?: string
        }
        Update: {
          active?: boolean
          category?: string | null
          code?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          method?: string | null
          name?: string
          notes?: string | null
          price?: number
          specimen?: string | null
          turnaround_hours?: number | null
          updated_at?: string
        }
        Relationships: []
      }
      lab_test_catalogue: {
        Row: {
          active: boolean
          category: string | null
          created_at: string
          default_charge: number
          id: string
          parameters: Json
          reference_high: number | null
          reference_low: number | null
          reference_text: string | null
          sample_quantity: string | null
          specimen_type: string | null
          test_code: string
          test_name: string
          turnaround_minutes: number | null
          unit: string | null
          updated_at: string
        }
        Insert: {
          active?: boolean
          category?: string | null
          created_at?: string
          default_charge?: number
          id?: string
          parameters?: Json
          reference_high?: number | null
          reference_low?: number | null
          reference_text?: string | null
          sample_quantity?: string | null
          specimen_type?: string | null
          test_code: string
          test_name: string
          turnaround_minutes?: number | null
          unit?: string | null
          updated_at?: string
        }
        Update: {
          active?: boolean
          category?: string | null
          created_at?: string
          default_charge?: number
          id?: string
          parameters?: Json
          reference_high?: number | null
          reference_low?: number | null
          reference_text?: string | null
          sample_quantity?: string | null
          specimen_type?: string | null
          test_code?: string
          test_name?: string
          turnaround_minutes?: number | null
          unit?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      lab_test_group_items: {
        Row: {
          created_at: string
          display_order: number | null
          group_id: string | null
          id: string
          lab_test_group_id: string
          required: boolean
          sort_order: number
          test_catalogue_id: string
          test_id: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          display_order?: number | null
          group_id?: string | null
          id?: string
          lab_test_group_id: string
          required?: boolean
          sort_order?: number
          test_catalogue_id: string
          test_id?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          display_order?: number | null
          group_id?: string | null
          id?: string
          lab_test_group_id?: string
          required?: boolean
          sort_order?: number
          test_catalogue_id?: string
          test_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "lab_test_group_items_lab_test_group_id_fkey"
            columns: ["lab_test_group_id"]
            isOneToOne: false
            referencedRelation: "lab_test_groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lab_test_group_items_test_id_fkey"
            columns: ["test_id"]
            isOneToOne: false
            referencedRelation: "lab_test_catalogue"
            referencedColumns: ["id"]
          },
        ]
      }
      lab_test_groups: {
        Row: {
          created_at: string
          created_by: string | null
          default_charge: number
          description: string | null
          facility_id: string | null
          group_code: string | null
          group_name: string | null
          id: string
          is_active: boolean
          name: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          default_charge?: number
          description?: string | null
          facility_id?: string | null
          group_code?: string | null
          group_name?: string | null
          id?: string
          is_active?: boolean
          name: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          default_charge?: number
          description?: string | null
          facility_id?: string | null
          group_code?: string | null
          group_name?: string | null
          id?: string
          is_active?: boolean
          name?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "lab_test_groups_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
        ]
      }
      lab_test_parameters: {
        Row: {
          created_at: string
          display_order: number
          id: string
          interpretation: string | null
          name: string
          ref_high: number | null
          ref_low: number | null
          ref_text: string | null
          test_id: string
          unit: string | null
        }
        Insert: {
          created_at?: string
          display_order?: number
          id?: string
          interpretation?: string | null
          name: string
          ref_high?: number | null
          ref_low?: number | null
          ref_text?: string | null
          test_id: string
          unit?: string | null
        }
        Update: {
          created_at?: string
          display_order?: number
          id?: string
          interpretation?: string | null
          name?: string
          ref_high?: number | null
          ref_low?: number | null
          ref_text?: string | null
          test_id?: string
          unit?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "lab_test_parameters_test_id_fkey"
            columns: ["test_id"]
            isOneToOne: false
            referencedRelation: "lab_test_catalog"
            referencedColumns: ["id"]
          },
        ]
      }
      lab_tests: {
        Row: {
          created_at: string | null
          id: string
          loinc_code: string | null
          normal_range: string | null
          specimen: string | null
          test_name: string | null
        }
        Insert: {
          created_at?: string | null
          id?: string
          loinc_code?: string | null
          normal_range?: string | null
          specimen?: string | null
          test_name?: string | null
        }
        Update: {
          created_at?: string | null
          id?: string
          loinc_code?: string | null
          normal_range?: string | null
          specimen?: string | null
          test_name?: string | null
        }
        Relationships: []
      }
      legacy_clinical_records: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          author_name: string | null
          batch_id: string | null
          clinical_summary: string | null
          created_at: string
          department: string | null
          encounter_reference: string | null
          id: string
          imported_at: string | null
          imported_by: string | null
          match_confidence: number | null
          match_method: string | null
          migration_status: string
          occurred_at: string | null
          patient_id: string | null
          raw_record: Json
          reconciled_at: string | null
          reconciled_by: string | null
          record_type: string
          source_patient_key: string | null
          source_record_id: string | null
          source_system: string
          validation_errors: Json
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          author_name?: string | null
          batch_id?: string | null
          clinical_summary?: string | null
          created_at?: string
          department?: string | null
          encounter_reference?: string | null
          id?: string
          imported_at?: string | null
          imported_by?: string | null
          match_confidence?: number | null
          match_method?: string | null
          migration_status?: string
          occurred_at?: string | null
          patient_id?: string | null
          raw_record?: Json
          reconciled_at?: string | null
          reconciled_by?: string | null
          record_type: string
          source_patient_key?: string | null
          source_record_id?: string | null
          source_system: string
          validation_errors?: Json
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          author_name?: string | null
          batch_id?: string | null
          clinical_summary?: string | null
          created_at?: string
          department?: string | null
          encounter_reference?: string | null
          id?: string
          imported_at?: string | null
          imported_by?: string | null
          match_confidence?: number | null
          match_method?: string | null
          migration_status?: string
          occurred_at?: string | null
          patient_id?: string | null
          raw_record?: Json
          reconciled_at?: string | null
          reconciled_by?: string | null
          record_type?: string
          source_patient_key?: string | null
          source_record_id?: string | null
          source_system?: string
          validation_errors?: Json
        }
        Relationships: [
          {
            foreignKeyName: "legacy_clinical_records_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "data_migration_batches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legacy_clinical_records_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      maternity_episodes: {
        Row: {
          blood_pressure: string | null
          created_at: string
          created_by: string | null
          edd: string | null
          facility_id: string | null
          fetal_heart_rate: number | null
          fundal_height_cm: number | null
          gestational_age_weeks: number | null
          gravida: number | null
          id: string
          living_children: number | null
          lmp: string | null
          notes: string | null
          para: number | null
          patient_id: string
          presentation: string | null
          risk_level: string
          status: string
          updated_at: string
        }
        Insert: {
          blood_pressure?: string | null
          created_at?: string
          created_by?: string | null
          edd?: string | null
          facility_id?: string | null
          fetal_heart_rate?: number | null
          fundal_height_cm?: number | null
          gestational_age_weeks?: number | null
          gravida?: number | null
          id?: string
          living_children?: number | null
          lmp?: string | null
          notes?: string | null
          para?: number | null
          patient_id: string
          presentation?: string | null
          risk_level?: string
          status?: string
          updated_at?: string
        }
        Update: {
          blood_pressure?: string | null
          created_at?: string
          created_by?: string | null
          edd?: string | null
          facility_id?: string | null
          fetal_heart_rate?: number | null
          fundal_height_cm?: number | null
          gestational_age_weeks?: number | null
          gravida?: number | null
          id?: string
          living_children?: number | null
          lmp?: string | null
          notes?: string | null
          para?: number | null
          patient_id?: string
          presentation?: string | null
          risk_level?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "maternity_episodes_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "maternity_episodes_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      maternity_observations: {
        Row: {
          blood_pressure: string | null
          cervical_dilation_cm: number | null
          contractions_per_10_min: number | null
          effacement_percent: number | null
          episode_id: string
          fetal_heart_rate: number | null
          id: string
          membrane_status: string | null
          notes: string | null
          observed_at: string
          pulse: number | null
          recorded_by: string | null
          station: string | null
          temperature: number | null
        }
        Insert: {
          blood_pressure?: string | null
          cervical_dilation_cm?: number | null
          contractions_per_10_min?: number | null
          effacement_percent?: number | null
          episode_id: string
          fetal_heart_rate?: number | null
          id?: string
          membrane_status?: string | null
          notes?: string | null
          observed_at?: string
          pulse?: number | null
          recorded_by?: string | null
          station?: string | null
          temperature?: number | null
        }
        Update: {
          blood_pressure?: string | null
          cervical_dilation_cm?: number | null
          contractions_per_10_min?: number | null
          effacement_percent?: number | null
          episode_id?: string
          fetal_heart_rate?: number | null
          id?: string
          membrane_status?: string | null
          notes?: string | null
          observed_at?: string
          pulse?: number | null
          recorded_by?: string | null
          station?: string | null
          temperature?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "maternity_observations_episode_id_fkey"
            columns: ["episode_id"]
            isOneToOne: false
            referencedRelation: "maternity_episodes"
            referencedColumns: ["id"]
          },
        ]
      }
      meal_menu_items: {
        Row: {
          active: boolean
          allergens: string[]
          created_at: string
          description: string | null
          dietary_tags: string[]
          id: string
          ingredients: string | null
          menu_id: string
          name: string
          sort_order: number
          updated_at: string
        }
        Insert: {
          active?: boolean
          allergens?: string[]
          created_at?: string
          description?: string | null
          dietary_tags?: string[]
          id?: string
          ingredients?: string | null
          menu_id: string
          name: string
          sort_order?: number
          updated_at?: string
        }
        Update: {
          active?: boolean
          allergens?: string[]
          created_at?: string
          description?: string | null
          dietary_tags?: string[]
          id?: string
          ingredients?: string | null
          menu_id?: string
          name?: string
          sort_order?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "meal_menu_items_menu_id_fkey"
            columns: ["menu_id"]
            isOneToOne: false
            referencedRelation: "meal_menus"
            referencedColumns: ["id"]
          },
        ]
      }
      meal_menus: {
        Row: {
          available_from: string | null
          available_until: string | null
          created_at: string
          created_by: string
          id: string
          meal_period: string
          notes: string | null
          service_date: string
          status: string
          updated_at: string
        }
        Insert: {
          available_from?: string | null
          available_until?: string | null
          created_at?: string
          created_by?: string
          id?: string
          meal_period: string
          notes?: string | null
          service_date: string
          status?: string
          updated_at?: string
        }
        Update: {
          available_from?: string | null
          available_until?: string | null
          created_at?: string
          created_by?: string
          id?: string
          meal_period?: string
          notes?: string | null
          service_date?: string
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      meal_orders: {
        Row: {
          created_at: string
          delivered_at: string | null
          facility_id: string | null
          id: string
          meal_plan_id: string | null
          meal_type: string
          notes: string | null
          patient_id: string
          scheduled_for: string
          status: string
        }
        Insert: {
          created_at?: string
          delivered_at?: string | null
          facility_id?: string | null
          id?: string
          meal_plan_id?: string | null
          meal_type: string
          notes?: string | null
          patient_id: string
          scheduled_for: string
          status?: string
        }
        Update: {
          created_at?: string
          delivered_at?: string | null
          facility_id?: string | null
          id?: string
          meal_plan_id?: string | null
          meal_type?: string
          notes?: string | null
          patient_id?: string
          scheduled_for?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "meal_orders_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meal_orders_meal_plan_id_fkey"
            columns: ["meal_plan_id"]
            isOneToOne: false
            referencedRelation: "meal_plans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meal_orders_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      meal_plans: {
        Row: {
          active: boolean | null
          ai_recommendations: string | null
          created_at: string
          created_by: string | null
          description: string | null
          facility_id: string | null
          id: string
          meals_per_day: number | null
          patient_id: string
          plan_type: string
          restrictions: string | null
          updated_at: string
        }
        Insert: {
          active?: boolean | null
          ai_recommendations?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          facility_id?: string | null
          id?: string
          meals_per_day?: number | null
          patient_id: string
          plan_type: string
          restrictions?: string | null
          updated_at?: string
        }
        Update: {
          active?: boolean | null
          ai_recommendations?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          facility_id?: string | null
          id?: string
          meals_per_day?: number | null
          patient_id?: string
          plan_type?: string
          restrictions?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "meal_plans_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meal_plans_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      medication_administrations: {
        Row: {
          administered_at: string | null
          administered_by: string | null
          alert_acknowledged_at: string | null
          alert_acknowledged_by: string | null
          created_at: string
          dose: string | null
          due_window_minutes: number
          facility_id: string | null
          id: string
          lock_reason: string | null
          locked_at: string | null
          medication_name: string
          notes: string | null
          patient_id: string
          prescription_id: string | null
          reason: string | null
          reopen_reason: string | null
          reopened_at: string | null
          route: string | null
          scheduled_at: string | null
          status: string
          updated_at: string
          witnessed_by: string | null
        }
        Insert: {
          administered_at?: string | null
          administered_by?: string | null
          alert_acknowledged_at?: string | null
          alert_acknowledged_by?: string | null
          created_at?: string
          dose?: string | null
          due_window_minutes?: number
          facility_id?: string | null
          id?: string
          lock_reason?: string | null
          locked_at?: string | null
          medication_name: string
          notes?: string | null
          patient_id: string
          prescription_id?: string | null
          reason?: string | null
          reopen_reason?: string | null
          reopened_at?: string | null
          route?: string | null
          scheduled_at?: string | null
          status?: string
          updated_at?: string
          witnessed_by?: string | null
        }
        Update: {
          administered_at?: string | null
          administered_by?: string | null
          alert_acknowledged_at?: string | null
          alert_acknowledged_by?: string | null
          created_at?: string
          dose?: string | null
          due_window_minutes?: number
          facility_id?: string | null
          id?: string
          lock_reason?: string | null
          locked_at?: string | null
          medication_name?: string
          notes?: string | null
          patient_id?: string
          prescription_id?: string | null
          reason?: string | null
          reopen_reason?: string | null
          reopened_at?: string | null
          route?: string | null
          scheduled_at?: string | null
          status?: string
          updated_at?: string
          witnessed_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "medication_administrations_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "medication_administrations_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      medication_catalogue: {
        Row: {
          active: boolean
          category: string
          created_at: string
          created_by: string | null
          form: string | null
          generic_name: string | null
          id: string
          name: string
          strength: string | null
          updated_at: string
        }
        Insert: {
          active?: boolean
          category?: string
          created_at?: string
          created_by?: string | null
          form?: string | null
          generic_name?: string | null
          id?: string
          name: string
          strength?: string | null
          updated_at?: string
        }
        Update: {
          active?: boolean
          category?: string
          created_at?: string
          created_by?: string | null
          form?: string | null
          generic_name?: string | null
          id?: string
          name?: string
          strength?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      notification_audit: {
        Row: {
          action: string
          actor_id: string | null
          channel: string | null
          created_at: string
          event_name: string | null
          id: string
          metadata: Json
          notification_id: string | null
          outcome: string | null
          queue_id: string | null
          reason: string | null
          tenant_id: string | null
          user_id: string | null
        }
        Insert: {
          action: string
          actor_id?: string | null
          channel?: string | null
          created_at?: string
          event_name?: string | null
          id?: string
          metadata?: Json
          notification_id?: string | null
          outcome?: string | null
          queue_id?: string | null
          reason?: string | null
          tenant_id?: string | null
          user_id?: string | null
        }
        Update: {
          action?: string
          actor_id?: string | null
          channel?: string | null
          created_at?: string
          event_name?: string | null
          id?: string
          metadata?: Json
          notification_id?: string | null
          outcome?: string | null
          queue_id?: string | null
          reason?: string | null
          tenant_id?: string | null
          user_id?: string | null
        }
        Relationships: []
      }
      notification_channel_preferences: {
        Row: {
          allow_clinical_content: boolean
          email_enabled: boolean
          push_enabled: boolean
          sms_enabled: boolean
          updated_at: string
          user_id: string
          whatsapp_enabled: boolean
        }
        Insert: {
          allow_clinical_content?: boolean
          email_enabled?: boolean
          push_enabled?: boolean
          sms_enabled?: boolean
          updated_at?: string
          user_id: string
          whatsapp_enabled?: boolean
        }
        Update: {
          allow_clinical_content?: boolean
          email_enabled?: boolean
          push_enabled?: boolean
          sms_enabled?: boolean
          updated_at?: string
          user_id?: string
          whatsapp_enabled?: boolean
        }
        Relationships: []
      }
      notification_channels: {
        Row: {
          code: string
          config: Json
          created_at: string
          enabled: boolean
          environment: string
          id: string
          priority: number
          provider: string | null
          updated_at: string
          webhook_enabled: boolean
        }
        Insert: {
          code: string
          config?: Json
          created_at?: string
          enabled?: boolean
          environment?: string
          id?: string
          priority?: number
          provider?: string | null
          updated_at?: string
          webhook_enabled?: boolean
        }
        Update: {
          code?: string
          config?: Json
          created_at?: string
          enabled?: boolean
          environment?: string
          id?: string
          priority?: number
          provider?: string | null
          updated_at?: string
          webhook_enabled?: boolean
        }
        Relationships: []
      }
      notification_consent_audit: {
        Row: {
          category: string
          channel: string
          consent_ip: unknown
          consent_version: string | null
          consented_at: string
          granted: boolean
          id: string
          tenant_id: string | null
          user_agent: string | null
          user_id: string
        }
        Insert: {
          category: string
          channel: string
          consent_ip?: unknown
          consent_version?: string | null
          consented_at?: string
          granted: boolean
          id?: string
          tenant_id?: string | null
          user_agent?: string | null
          user_id: string
        }
        Update: {
          category?: string
          channel?: string
          consent_ip?: unknown
          consent_version?: string | null
          consented_at?: string
          granted?: boolean
          id?: string
          tenant_id?: string | null
          user_agent?: string | null
          user_id?: string
        }
        Relationships: []
      }
      notification_deliveries: {
        Row: {
          attempts: number
          channel: string
          created_at: string
          delivered_at: string | null
          destination_hash: string | null
          id: string
          last_error: string | null
          provider: string | null
          provider_message_id: string | null
          queue_id: string
          status: string
          updated_at: string
          user_id: string | null
        }
        Insert: {
          attempts?: number
          channel: string
          created_at?: string
          delivered_at?: string | null
          destination_hash?: string | null
          id?: string
          last_error?: string | null
          provider?: string | null
          provider_message_id?: string | null
          queue_id: string
          status?: string
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          attempts?: number
          channel?: string
          created_at?: string
          delivered_at?: string | null
          destination_hash?: string | null
          id?: string
          last_error?: string | null
          provider?: string | null
          provider_message_id?: string | null
          queue_id?: string
          status?: string
          updated_at?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "notification_deliveries_queue_id_fkey"
            columns: ["queue_id"]
            isOneToOne: false
            referencedRelation: "notification_queue"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_delivery_logs: {
        Row: {
          attempt: number
          channel: string
          clicked_at: string | null
          created_at: string
          delivered_at: string | null
          error_code: string | null
          error_message: string | null
          id: string
          latency_ms: number | null
          metadata: Json
          notification_id: string | null
          provider: string | null
          provider_message_id: string | null
          queue_id: string | null
          read_at: string | null
          status: string
          tenant_id: string | null
          user_id: string | null
        }
        Insert: {
          attempt?: number
          channel: string
          clicked_at?: string | null
          created_at?: string
          delivered_at?: string | null
          error_code?: string | null
          error_message?: string | null
          id?: string
          latency_ms?: number | null
          metadata?: Json
          notification_id?: string | null
          provider?: string | null
          provider_message_id?: string | null
          queue_id?: string | null
          read_at?: string | null
          status: string
          tenant_id?: string | null
          user_id?: string | null
        }
        Update: {
          attempt?: number
          channel?: string
          clicked_at?: string | null
          created_at?: string
          delivered_at?: string | null
          error_code?: string | null
          error_message?: string | null
          id?: string
          latency_ms?: number | null
          metadata?: Json
          notification_id?: string | null
          provider?: string | null
          provider_message_id?: string | null
          queue_id?: string | null
          read_at?: string | null
          status?: string
          tenant_id?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "notification_delivery_logs_notification_id_fkey"
            columns: ["notification_id"]
            isOneToOne: false
            referencedRelation: "notifications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notification_delivery_logs_queue_id_fkey"
            columns: ["queue_id"]
            isOneToOne: false
            referencedRelation: "notification_queue"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_devices: {
        Row: {
          active: boolean
          created_at: string
          device_label: string | null
          id: string
          last_seen_at: string
          platform: string
          provider: string
          token: string
          updated_at: string
          user_id: string
        }
        Insert: {
          active?: boolean
          created_at?: string
          device_label?: string | null
          id?: string
          last_seen_at?: string
          platform: string
          provider: string
          token: string
          updated_at?: string
          user_id: string
        }
        Update: {
          active?: boolean
          created_at?: string
          device_label?: string | null
          id?: string
          last_seen_at?: string
          platform?: string
          provider?: string
          token?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      notification_events: {
        Row: {
          audience: Json
          channel_priority: Json
          created_at: string
          description: string
          enabled: boolean
          event_name: string
          id: string
          locale_aware: boolean
          opt_out_allowed: boolean
          priority_level: string
          quiet_hours_behavior: string
          retry_policy: Json
          template_key: string
          trigger_source: string
          updated_at: string
        }
        Insert: {
          audience?: Json
          channel_priority?: Json
          created_at?: string
          description: string
          enabled?: boolean
          event_name: string
          id?: string
          locale_aware?: boolean
          opt_out_allowed?: boolean
          priority_level?: string
          quiet_hours_behavior?: string
          retry_policy?: Json
          template_key: string
          trigger_source: string
          updated_at?: string
        }
        Update: {
          audience?: Json
          channel_priority?: Json
          created_at?: string
          description?: string
          enabled?: boolean
          event_name?: string
          id?: string
          locale_aware?: boolean
          opt_out_allowed?: boolean
          priority_level?: string
          quiet_hours_behavior?: string
          retry_policy?: Json
          template_key?: string
          trigger_source?: string
          updated_at?: string
        }
        Relationships: []
      }
      notification_feature_flags: {
        Row: {
          config: Json
          enabled: boolean
          key: string
          kill_switch: boolean
          rollout_percent: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          config?: Json
          enabled?: boolean
          key: string
          kill_switch?: boolean
          rollout_percent?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          config?: Json
          enabled?: boolean
          key?: string
          kill_switch?: boolean
          rollout_percent?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      notification_inbound_emails: {
        Row: {
          attachments: Json
          cc_addresses: string[]
          created_at: string
          facility_id: string | null
          from_address: string | null
          html_body: string | null
          id: string
          message_id: string | null
          processing_status: string
          provider: string
          provider_message_id: string | null
          raw_event: Json
          received_at: string | null
          subject: string | null
          text_body: string | null
          to_addresses: string[]
        }
        Insert: {
          attachments?: Json
          cc_addresses?: string[]
          created_at?: string
          facility_id?: string | null
          from_address?: string | null
          html_body?: string | null
          id?: string
          message_id?: string | null
          processing_status?: string
          provider?: string
          provider_message_id?: string | null
          raw_event?: Json
          received_at?: string | null
          subject?: string | null
          text_body?: string | null
          to_addresses?: string[]
        }
        Update: {
          attachments?: Json
          cc_addresses?: string[]
          created_at?: string
          facility_id?: string | null
          from_address?: string | null
          html_body?: string | null
          id?: string
          message_id?: string | null
          processing_status?: string
          provider?: string
          provider_message_id?: string | null
          raw_event?: Json
          received_at?: string | null
          subject?: string | null
          text_body?: string | null
          to_addresses?: string[]
        }
        Relationships: [
          {
            foreignKeyName: "notification_inbound_emails_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_provider_credentials: {
        Row: {
          channel: string
          created_at: string
          created_by: string | null
          credentials_ciphertext: string
          environment: string
          facility_id: string
          id: string
          last_error: string | null
          last_tested_at: string | null
          provider: string
          secret_version: number
          status: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          channel: string
          created_at?: string
          created_by?: string | null
          credentials_ciphertext: string
          environment: string
          facility_id: string
          id?: string
          last_error?: string | null
          last_tested_at?: string | null
          provider: string
          secret_version?: number
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          channel?: string
          created_at?: string
          created_by?: string | null
          credentials_ciphertext?: string
          environment?: string
          facility_id?: string
          id?: string
          last_error?: string | null
          last_tested_at?: string | null
          provider?: string
          secret_version?: number
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "notification_provider_credentials_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_provider_health: {
        Row: {
          channel: string
          circuit_state: string
          consecutive_failures: number
          last_error: string | null
          next_probe_at: string | null
          opened_at: string | null
          provider: string
          updated_at: string
        }
        Insert: {
          channel: string
          circuit_state?: string
          consecutive_failures?: number
          last_error?: string | null
          next_probe_at?: string | null
          opened_at?: string | null
          provider: string
          updated_at?: string
        }
        Update: {
          channel?: string
          circuit_state?: string
          consecutive_failures?: number
          last_error?: string | null
          next_probe_at?: string | null
          opened_at?: string | null
          provider?: string
          updated_at?: string
        }
        Relationships: []
      }
      notification_provider_secret_requirements: {
        Row: {
          channel: string
          created_at: string
          description: string
          environment: string
          id: string
          provider: string
          required: boolean
          secret_name: string
          secret_reference_example: string | null
        }
        Insert: {
          channel: string
          created_at?: string
          description: string
          environment?: string
          id?: string
          provider: string
          required?: boolean
          secret_name: string
          secret_reference_example?: string | null
        }
        Update: {
          channel?: string
          created_at?: string
          description?: string
          environment?: string
          id?: string
          provider?: string
          required?: boolean
          secret_name?: string
          secret_reference_example?: string | null
        }
        Relationships: []
      }
      notification_push_subscriptions: {
        Row: {
          created_at: string
          endpoint: string
          id: string
          subscription: Json
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          endpoint: string
          id?: string
          subscription: Json
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          endpoint?: string
          id?: string
          subscription?: Json
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      notification_queue: {
        Row: {
          attempts: number
          channel: string
          created_at: string
          delivered_at: string | null
          event_name: string | null
          facility_id: string | null
          fallback_channels: Json
          id: string
          idempotency_key: string | null
          last_attempt_at: string | null
          last_error: string | null
          locale: string | null
          max_attempts: number
          next_attempt_at: string
          payload: Json
          priority: string
          scheduled_for: string | null
          status: string
          template_key: string | null
          tenant_id: string | null
          timezone: string | null
          updated_at: string
          user_id: string | null
        }
        Insert: {
          attempts?: number
          channel?: string
          created_at?: string
          delivered_at?: string | null
          event_name?: string | null
          facility_id?: string | null
          fallback_channels?: Json
          id?: string
          idempotency_key?: string | null
          last_attempt_at?: string | null
          last_error?: string | null
          locale?: string | null
          max_attempts?: number
          next_attempt_at?: string
          payload: Json
          priority?: string
          scheduled_for?: string | null
          status?: string
          template_key?: string | null
          tenant_id?: string | null
          timezone?: string | null
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          attempts?: number
          channel?: string
          created_at?: string
          delivered_at?: string | null
          event_name?: string | null
          facility_id?: string | null
          fallback_channels?: Json
          id?: string
          idempotency_key?: string | null
          last_attempt_at?: string | null
          last_error?: string | null
          locale?: string | null
          max_attempts?: number
          next_attempt_at?: string
          payload?: Json
          priority?: string
          scheduled_for?: string | null
          status?: string
          template_key?: string | null
          tenant_id?: string | null
          timezone?: string | null
          updated_at?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "notification_queue_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_templates: {
        Row: {
          active: boolean
          body_template: string
          channel: string
          created_at: string
          created_by: string | null
          id: string
          locale: string
          metadata: Json
          subject_template: string | null
          template_key: string
          updated_at: string
          version: number
        }
        Insert: {
          active?: boolean
          body_template: string
          channel: string
          created_at?: string
          created_by?: string | null
          id?: string
          locale?: string
          metadata?: Json
          subject_template?: string | null
          template_key: string
          updated_at?: string
          version?: number
        }
        Update: {
          active?: boolean
          body_template?: string
          channel?: string
          created_at?: string
          created_by?: string | null
          id?: string
          locale?: string
          metadata?: Json
          subject_template?: string | null
          template_key?: string
          updated_at?: string
          version?: number
        }
        Relationships: []
      }
      notification_webhook_events: {
        Row: {
          event_type: string
          external_event_id: string
          id: string
          payload: Json
          processed_at: string | null
          provider: string
          received_at: string
        }
        Insert: {
          event_type: string
          external_event_id: string
          id?: string
          payload?: Json
          processed_at?: string | null
          provider: string
          received_at?: string
        }
        Update: {
          event_type?: string
          external_event_id?: string
          id?: string
          payload?: Json
          processed_at?: string | null
          provider?: string
          received_at?: string
        }
        Relationships: []
      }
      notifications: {
        Row: {
          category: string | null
          created_at: string
          id: string
          is_read: boolean
          link: string | null
          message: string
          metadata: Json | null
          read_at: string | null
          recipient_role: Database["public"]["Enums"]["app_role"] | null
          recipient_user_id: string | null
          related_entity_id: string | null
          related_patient_id: string | null
          severity: string
          source_queue_id: string | null
          title: string
        }
        Insert: {
          category?: string | null
          created_at?: string
          id?: string
          is_read?: boolean
          link?: string | null
          message: string
          metadata?: Json | null
          read_at?: string | null
          recipient_role?: Database["public"]["Enums"]["app_role"] | null
          recipient_user_id?: string | null
          related_entity_id?: string | null
          related_patient_id?: string | null
          severity?: string
          source_queue_id?: string | null
          title: string
        }
        Update: {
          category?: string | null
          created_at?: string
          id?: string
          is_read?: boolean
          link?: string | null
          message?: string
          metadata?: Json | null
          read_at?: string | null
          recipient_role?: Database["public"]["Enums"]["app_role"] | null
          recipient_user_id?: string | null
          related_entity_id?: string | null
          related_patient_id?: string | null
          severity?: string
          source_queue_id?: string | null
          title?: string
        }
        Relationships: []
      }
      nursing_care_plans: {
        Row: {
          admission_id: string | null
          created_at: string
          created_by: string
          encounter_id: string | null
          evaluation: string | null
          facility_id: string | null
          goal: string
          id: string
          interventions: string | null
          patient_id: string
          priority: string
          problem: string
          reviewed_by: string | null
          status: string
          updated_at: string
        }
        Insert: {
          admission_id?: string | null
          created_at?: string
          created_by: string
          encounter_id?: string | null
          evaluation?: string | null
          facility_id?: string | null
          goal: string
          id?: string
          interventions?: string | null
          patient_id: string
          priority?: string
          problem: string
          reviewed_by?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          admission_id?: string | null
          created_at?: string
          created_by?: string
          encounter_id?: string | null
          evaluation?: string | null
          facility_id?: string | null
          goal?: string
          id?: string
          interventions?: string | null
          patient_id?: string
          priority?: string
          problem?: string
          reviewed_by?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "nursing_care_plans_encounter_id_fkey"
            columns: ["encounter_id"]
            isOneToOne: false
            referencedRelation: "encounters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "nursing_care_plans_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
        ]
      }
      nursing_notes: {
        Row: {
          admission_id: string | null
          assessment: string | null
          author_id: string
          created_at: string
          encounter_id: string | null
          evaluation: string | null
          facility_id: string | null
          id: string
          intervention: string | null
          note_text: string
          note_type: string
          patient_id: string
          updated_at: string
        }
        Insert: {
          admission_id?: string | null
          assessment?: string | null
          author_id: string
          created_at?: string
          encounter_id?: string | null
          evaluation?: string | null
          facility_id?: string | null
          id?: string
          intervention?: string | null
          note_text: string
          note_type?: string
          patient_id: string
          updated_at?: string
        }
        Update: {
          admission_id?: string | null
          assessment?: string | null
          author_id?: string
          created_at?: string
          encounter_id?: string | null
          evaluation?: string | null
          facility_id?: string | null
          id?: string
          intervention?: string | null
          note_text?: string
          note_type?: string
          patient_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "nursing_notes_admission_id_fkey"
            columns: ["admission_id"]
            isOneToOne: false
            referencedRelation: "admissions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "nursing_notes_encounter_id_fkey"
            columns: ["encounter_id"]
            isOneToOne: false
            referencedRelation: "encounters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "nursing_notes_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "nursing_notes_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      nursing_shift_handovers: {
        Row: {
          acknowledged_at: string | null
          admission_id: string | null
          clinical_summary: string
          created_at: string
          escalation_required: boolean
          facility_id: string | null
          id: string
          incoming_officer: string | null
          outgoing_officer: string | null
          outstanding_tasks: string | null
          patient_id: string
          pending_tasks: string | null
          risks_and_alerts: string | null
          safety_concerns: string | null
          shift_date: string
          shift_label: string | null
          shift_name: string
        }
        Insert: {
          acknowledged_at?: string | null
          admission_id?: string | null
          clinical_summary: string
          created_at?: string
          escalation_required?: boolean
          facility_id?: string | null
          id?: string
          incoming_officer?: string | null
          outgoing_officer?: string | null
          outstanding_tasks?: string | null
          patient_id: string
          pending_tasks?: string | null
          risks_and_alerts?: string | null
          safety_concerns?: string | null
          shift_date?: string
          shift_label?: string | null
          shift_name?: string
        }
        Update: {
          acknowledged_at?: string | null
          admission_id?: string | null
          clinical_summary?: string
          created_at?: string
          escalation_required?: boolean
          facility_id?: string | null
          id?: string
          incoming_officer?: string | null
          outgoing_officer?: string | null
          outstanding_tasks?: string | null
          patient_id?: string
          pending_tasks?: string | null
          risks_and_alerts?: string | null
          safety_concerns?: string | null
          shift_date?: string
          shift_label?: string | null
          shift_name?: string
        }
        Relationships: [
          {
            foreignKeyName: "nursing_shift_handovers_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "nursing_shift_handovers_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      ophthalmology_assessments: {
        Row: {
          created_at: string
          created_by: string
          encounter_id: string
          facility_id: string
          fundoscopy_findings: string | null
          id: string
          intraocular_pressure: Json
          patient_id: string
          post_op_review_due: string | null
          refraction: Json
          slit_lamp_findings: string | null
          specialized_test_orders: Json
          updated_at: string
          visual_acuity_left: string | null
          visual_acuity_right: string | null
        }
        Insert: {
          created_at?: string
          created_by: string
          encounter_id: string
          facility_id: string
          fundoscopy_findings?: string | null
          id?: string
          intraocular_pressure?: Json
          patient_id: string
          post_op_review_due?: string | null
          refraction?: Json
          slit_lamp_findings?: string | null
          specialized_test_orders?: Json
          updated_at?: string
          visual_acuity_left?: string | null
          visual_acuity_right?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string
          encounter_id?: string
          facility_id?: string
          fundoscopy_findings?: string | null
          id?: string
          intraocular_pressure?: Json
          patient_id?: string
          post_op_review_due?: string | null
          refraction?: Json
          slit_lamp_findings?: string | null
          specialized_test_orders?: Json
          updated_at?: string
          visual_acuity_left?: string | null
          visual_acuity_right?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ophthalmology_assessments_encounter_id_fkey"
            columns: ["encounter_id"]
            isOneToOne: false
            referencedRelation: "encounters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ophthalmology_assessments_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      ophthalmology_exams: {
        Row: {
          ai_advisory: Json
          color_vision: string | null
          created_at: string
          facility_id: string | null
          fundus_notes: string | null
          id: string
          image_path: string | null
          intraocular_pressure: number | null
          keratometry: string | null
          patient_id: string
          performed_by: string | null
          refraction: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
          updated_at: string
          visual_acuity: string | null
        }
        Insert: {
          ai_advisory?: Json
          color_vision?: string | null
          created_at?: string
          facility_id?: string | null
          fundus_notes?: string | null
          id?: string
          image_path?: string | null
          intraocular_pressure?: number | null
          keratometry?: string | null
          patient_id: string
          performed_by?: string | null
          refraction?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          updated_at?: string
          visual_acuity?: string | null
        }
        Update: {
          ai_advisory?: Json
          color_vision?: string | null
          created_at?: string
          facility_id?: string | null
          fundus_notes?: string | null
          id?: string
          image_path?: string | null
          intraocular_pressure?: number | null
          keratometry?: string | null
          patient_id?: string
          performed_by?: string | null
          refraction?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          updated_at?: string
          visual_acuity?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ophthalmology_exams_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ophthalmology_exams_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      outside_lab_documents: {
        Row: {
          ai_analysis: string | null
          ai_analyzed_at: string | null
          created_at: string
          document_type: string
          facility_id: string | null
          id: string
          mime_type: string | null
          notes: string | null
          patient_id: string
          reviewed_at: string | null
          reviewed_by: string | null
          storage_path: string
          title: string | null
          uploaded_by: string | null
        }
        Insert: {
          ai_analysis?: string | null
          ai_analyzed_at?: string | null
          created_at?: string
          document_type: string
          facility_id?: string | null
          id?: string
          mime_type?: string | null
          notes?: string | null
          patient_id: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          storage_path: string
          title?: string | null
          uploaded_by?: string | null
        }
        Update: {
          ai_analysis?: string | null
          ai_analyzed_at?: string | null
          created_at?: string
          document_type?: string
          facility_id?: string | null
          id?: string
          mime_type?: string | null
          notes?: string | null
          patient_id?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          storage_path?: string
          title?: string | null
          uploaded_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "outside_lab_documents_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "outside_lab_documents_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      patient_account_credits: {
        Row: {
          amount: number
          created_at: string
          created_by: string
          entry_type: string
          facility_id: string | null
          id: string
          invoice_id: string | null
          notes: string | null
          patient_id: string
          payment_id: string | null
          reference: string | null
        }
        Insert: {
          amount: number
          created_at?: string
          created_by: string
          entry_type: string
          facility_id?: string | null
          id?: string
          invoice_id?: string | null
          notes?: string | null
          patient_id: string
          payment_id?: string | null
          reference?: string | null
        }
        Update: {
          amount?: number
          created_at?: string
          created_by?: string
          entry_type?: string
          facility_id?: string | null
          id?: string
          invoice_id?: string | null
          notes?: string | null
          patient_id?: string
          payment_id?: string | null
          reference?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "patient_account_credits_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "patient_account_credits_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "patient_account_credits_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "patient_account_credits_payment_id_fkey"
            columns: ["payment_id"]
            isOneToOne: false
            referencedRelation: "payments"
            referencedColumns: ["id"]
          },
        ]
      }
      patient_audit: {
        Row: {
          actor_user_id: string | null
          changed_fields: Json
          id: string
          new_record: Json | null
          occurred_at: string
          old_record: Json | null
          operation: string
          patient_id: string
        }
        Insert: {
          actor_user_id?: string | null
          changed_fields?: Json
          id?: string
          new_record?: Json | null
          occurred_at?: string
          old_record?: Json | null
          operation: string
          patient_id: string
        }
        Update: {
          actor_user_id?: string | null
          changed_fields?: Json
          id?: string
          new_record?: Json | null
          occurred_at?: string
          old_record?: Json | null
          operation?: string
          patient_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "patient_audit_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      patient_audit_log: {
        Row: {
          action: string
          changed_at: string
          changed_by: string | null
          changed_fields: string[]
          id: string
          new_record: Json | null
          old_record: Json | null
          patient_id: string | null
        }
        Insert: {
          action: string
          changed_at?: string
          changed_by?: string | null
          changed_fields?: string[]
          id?: string
          new_record?: Json | null
          old_record?: Json | null
          patient_id?: string | null
        }
        Update: {
          action?: string
          changed_at?: string
          changed_by?: string | null
          changed_fields?: string[]
          id?: string
          new_record?: Json | null
          old_record?: Json | null
          patient_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "patient_audit_log_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      patient_documents: {
        Row: {
          created_at: string
          document_type: string
          facility_id: string | null
          file_name: string
          file_size: number | null
          id: string
          mime_type: string | null
          notes: string | null
          patient_id: string
          storage_path: string | null
          updated_at: string
          uploaded_by: string | null
        }
        Insert: {
          created_at?: string
          document_type?: string
          facility_id?: string | null
          file_name: string
          file_size?: number | null
          id?: string
          mime_type?: string | null
          notes?: string | null
          patient_id: string
          storage_path?: string | null
          updated_at?: string
          uploaded_by?: string | null
        }
        Update: {
          created_at?: string
          document_type?: string
          facility_id?: string | null
          file_name?: string
          file_size?: number | null
          id?: string
          mime_type?: string | null
          notes?: string | null
          patient_id?: string
          storage_path?: string | null
          updated_at?: string
          uploaded_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "patient_documents_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "patient_documents_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      patient_referrals: {
        Row: {
          appointment_date: string | null
          clinical_summary: string | null
          created_at: string
          destination: string
          encounter_id: string | null
          facility_id: string | null
          id: string
          patient_id: string
          reason: string
          receiving_notes: string | null
          referral_type: string
          referred_by: string | null
          source_field: string | null
          source_text: string | null
          specialty: string | null
          status: string
          updated_at: string
          urgency: string
        }
        Insert: {
          appointment_date?: string | null
          clinical_summary?: string | null
          created_at?: string
          destination: string
          encounter_id?: string | null
          facility_id?: string | null
          id?: string
          patient_id: string
          reason: string
          receiving_notes?: string | null
          referral_type?: string
          referred_by?: string | null
          source_field?: string | null
          source_text?: string | null
          specialty?: string | null
          status?: string
          updated_at?: string
          urgency?: string
        }
        Update: {
          appointment_date?: string | null
          clinical_summary?: string | null
          created_at?: string
          destination?: string
          encounter_id?: string | null
          facility_id?: string | null
          id?: string
          patient_id?: string
          reason?: string
          receiving_notes?: string | null
          referral_type?: string
          referred_by?: string | null
          source_field?: string | null
          source_text?: string | null
          specialty?: string | null
          status?: string
          updated_at?: string
          urgency?: string
        }
        Relationships: [
          {
            foreignKeyName: "patient_referrals_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "patient_referrals_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      patient_visit_authorizations: {
        Row: {
          activated_by: string
          activation_source: string
          active: boolean
          appointment_id: string | null
          authorization_date: string
          coverage_type: string
          created_at: string
          facility_id: string | null
          id: string
          patient_id: string
          payer_name: string
        }
        Insert: {
          activated_by: string
          activation_source: string
          active?: boolean
          appointment_id?: string | null
          authorization_date?: string
          coverage_type: string
          created_at?: string
          facility_id?: string | null
          id?: string
          patient_id: string
          payer_name: string
        }
        Update: {
          activated_by?: string
          activation_source?: string
          active?: boolean
          appointment_id?: string | null
          authorization_date?: string
          coverage_type?: string
          created_at?: string
          facility_id?: string | null
          id?: string
          patient_id?: string
          payer_name?: string
        }
        Relationships: [
          {
            foreignKeyName: "patient_visit_authorizations_appointment_id_fkey"
            columns: ["appointment_id"]
            isOneToOne: false
            referencedRelation: "appointments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "patient_visit_authorizations_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "patient_visit_authorizations_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      patients: {
        Row: {
          address: string | null
          allergies: string | null
          blood_group: string | null
          chronic_conditions: string | null
          city: string | null
          created_at: string
          created_by: string | null
          date_of_birth: string | null
          email: string | null
          emergency_contact_name: string | null
          emergency_contact_phone: string | null
          emergency_contact_relation: string | null
          facility_id: string | null
          first_name: string
          gender: string | null
          genotype: string | null
          ghana_card_number: string | null
          id: string
          insurance_company_id: string | null
          insurance_expiry: string | null
          insurance_group_number: string | null
          insurance_number: string | null
          insurance_provider: string | null
          last_name: string
          membership_expires_at: string | null
          membership_type: string
          partner_company: string | null
          partner_member_number: string | null
          patient_code: string | null
          phone: string | null
          registration_reason: string | null
          status: string
          updated_at: string
          user_id: string | null
        }
        Insert: {
          address?: string | null
          allergies?: string | null
          blood_group?: string | null
          chronic_conditions?: string | null
          city?: string | null
          created_at?: string
          created_by?: string | null
          date_of_birth?: string | null
          email?: string | null
          emergency_contact_name?: string | null
          emergency_contact_phone?: string | null
          emergency_contact_relation?: string | null
          facility_id?: string | null
          first_name: string
          gender?: string | null
          genotype?: string | null
          ghana_card_number?: string | null
          id?: string
          insurance_company_id?: string | null
          insurance_expiry?: string | null
          insurance_group_number?: string | null
          insurance_number?: string | null
          insurance_provider?: string | null
          last_name: string
          membership_expires_at?: string | null
          membership_type?: string
          partner_company?: string | null
          partner_member_number?: string | null
          patient_code?: string | null
          phone?: string | null
          registration_reason?: string | null
          status?: string
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          address?: string | null
          allergies?: string | null
          blood_group?: string | null
          chronic_conditions?: string | null
          city?: string | null
          created_at?: string
          created_by?: string | null
          date_of_birth?: string | null
          email?: string | null
          emergency_contact_name?: string | null
          emergency_contact_phone?: string | null
          emergency_contact_relation?: string | null
          facility_id?: string | null
          first_name?: string
          gender?: string | null
          genotype?: string | null
          ghana_card_number?: string | null
          id?: string
          insurance_company_id?: string | null
          insurance_expiry?: string | null
          insurance_group_number?: string | null
          insurance_number?: string | null
          insurance_provider?: string | null
          last_name?: string
          membership_expires_at?: string | null
          membership_type?: string
          partner_company?: string | null
          partner_member_number?: string | null
          patient_code?: string | null
          phone?: string | null
          registration_reason?: string | null
          status?: string
          updated_at?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "patients_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "patients_insurance_company_id_fkey"
            columns: ["insurance_company_id"]
            isOneToOne: false
            referencedRelation: "insurance_companies"
            referencedColumns: ["id"]
          },
        ]
      }
      payments: {
        Row: {
          amount: number
          created_at: string
          facility_id: string | null
          id: string
          invoice_id: string | null
          method: string | null
          notes: string | null
          paid_at: string | null
          patient_id: string
          payment_method: string | null
          received_by: string | null
          reference: string | null
          status: string
        }
        Insert: {
          amount: number
          created_at?: string
          facility_id?: string | null
          id?: string
          invoice_id?: string | null
          method?: string | null
          notes?: string | null
          paid_at?: string | null
          patient_id: string
          payment_method?: string | null
          received_by?: string | null
          reference?: string | null
          status?: string
        }
        Update: {
          amount?: number
          created_at?: string
          facility_id?: string | null
          id?: string
          invoice_id?: string | null
          method?: string | null
          notes?: string | null
          paid_at?: string | null
          patient_id?: string
          payment_method?: string | null
          received_by?: string | null
          reference?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "payments_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payments_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payments_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      payroll_items: {
        Row: {
          allowances: number
          basic_pay: number
          created_at: string
          employee_id: string
          gross_pay: number
          id: string
          net_pay: number
          other_deductions: number
          other_earnings: number
          payment_reference: string | null
          payroll_period_id: string
          status: string
          statutory_deductions: number
          updated_at: string
        }
        Insert: {
          allowances?: number
          basic_pay?: number
          created_at?: string
          employee_id: string
          gross_pay?: number
          id?: string
          net_pay?: number
          other_deductions?: number
          other_earnings?: number
          payment_reference?: string | null
          payroll_period_id: string
          status?: string
          statutory_deductions?: number
          updated_at?: string
        }
        Update: {
          allowances?: number
          basic_pay?: number
          created_at?: string
          employee_id?: string
          gross_pay?: number
          id?: string
          net_pay?: number
          other_deductions?: number
          other_earnings?: number
          payment_reference?: string | null
          payroll_period_id?: string
          status?: string
          statutory_deductions?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payroll_items_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "hr_employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payroll_items_payroll_period_id_fkey"
            columns: ["payroll_period_id"]
            isOneToOne: false
            referencedRelation: "payroll_periods"
            referencedColumns: ["id"]
          },
        ]
      }
      payroll_periods: {
        Row: {
          created_at: string
          created_by: string | null
          facility_id: string
          id: string
          name: string
          pay_date: string
          period_end: string
          period_start: string
          status: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          facility_id: string
          id?: string
          name: string
          pay_date: string
          period_end: string
          period_start: string
          status?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          facility_id?: string
          id?: string
          name?: string
          pay_date?: string
          period_end?: string
          period_start?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payroll_periods_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
        ]
      }
      permissions: {
        Row: {
          created_at: string
          description: string
          is_active: boolean
          permission_key: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          description?: string
          is_active?: boolean
          permission_key: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          description?: string
          is_active?: boolean
          permission_key?: string
          updated_at?: string
        }
        Relationships: []
      }
      pharmacy_dispensing_plans: {
        Row: {
          computed_quantity: number | null
          created_at: string
          dispensed_at: string | null
          dispensed_by: string | null
          facility_id: string | null
          id: string
          inventory_id: string | null
          invoice_item_id: string | null
          medication_name: string
          nhis_claim_amount: number
          notes: string | null
          patient_charge: number
          patient_id: string
          prepared_at: string
          prepared_by: string | null
          prepared_quantity: number
          prescribed_dose: string | null
          prescribed_duration: string | null
          prescribed_frequency: string | null
          prescription_id: string
          service_order_id: string | null
          status: string
          updated_at: string
        }
        Insert: {
          computed_quantity?: number | null
          created_at?: string
          dispensed_at?: string | null
          dispensed_by?: string | null
          facility_id?: string | null
          id?: string
          inventory_id?: string | null
          invoice_item_id?: string | null
          medication_name: string
          nhis_claim_amount?: number
          notes?: string | null
          patient_charge?: number
          patient_id: string
          prepared_at?: string
          prepared_by?: string | null
          prepared_quantity: number
          prescribed_dose?: string | null
          prescribed_duration?: string | null
          prescribed_frequency?: string | null
          prescription_id: string
          service_order_id?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          computed_quantity?: number | null
          created_at?: string
          dispensed_at?: string | null
          dispensed_by?: string | null
          facility_id?: string | null
          id?: string
          inventory_id?: string | null
          invoice_item_id?: string | null
          medication_name?: string
          nhis_claim_amount?: number
          notes?: string | null
          patient_charge?: number
          patient_id?: string
          prepared_at?: string
          prepared_by?: string | null
          prepared_quantity?: number
          prescribed_dose?: string | null
          prescribed_duration?: string | null
          prescribed_frequency?: string | null
          prescription_id?: string
          service_order_id?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "pharmacy_dispensing_plans_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pharmacy_dispensing_plans_inventory_id_fkey"
            columns: ["inventory_id"]
            isOneToOne: false
            referencedRelation: "pharmacy_inventory"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pharmacy_dispensing_plans_invoice_item_id_fkey"
            columns: ["invoice_item_id"]
            isOneToOne: false
            referencedRelation: "invoice_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pharmacy_dispensing_plans_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pharmacy_dispensing_plans_prescription_id_fkey"
            columns: ["prescription_id"]
            isOneToOne: false
            referencedRelation: "prescriptions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pharmacy_dispensing_plans_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      pharmacy_goods_receipts: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          created_at: string
          drug_name: string
          expiry_date: string | null
          id: string
          inventory_id: string | null
          invoice_number: string | null
          notes: string | null
          quantity: number
          received_by: string | null
          rejection_reason: string | null
          status: string
          supplier: string | null
          unit_cost: number | null
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          drug_name: string
          expiry_date?: string | null
          id?: string
          inventory_id?: string | null
          invoice_number?: string | null
          notes?: string | null
          quantity: number
          received_by?: string | null
          rejection_reason?: string | null
          status?: string
          supplier?: string | null
          unit_cost?: number | null
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          drug_name?: string
          expiry_date?: string | null
          id?: string
          inventory_id?: string | null
          invoice_number?: string | null
          notes?: string | null
          quantity?: number
          received_by?: string | null
          rejection_reason?: string | null
          status?: string
          supplier?: string | null
          unit_cost?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "pharmacy_goods_receipts_inventory_id_fkey"
            columns: ["inventory_id"]
            isOneToOne: false
            referencedRelation: "pharmacy_inventory"
            referencedColumns: ["id"]
          },
        ]
      }
      pharmacy_inventory: {
        Row: {
          active: boolean
          barcode: string | null
          batch_number: string | null
          brand_name: string | null
          catalogue_id: string | null
          created_at: string
          drug_name: string
          expiry_date: string | null
          facility_id: string | null
          form: string | null
          generic_name: string | null
          id: string
          nhis_claim_amount: number
          nhis_patient_price: number
          pack_size: number | null
          reorder_level: number | null
          stock_quantity: number
          strength: string | null
          supplier: string | null
          unit_price: number | null
          updated_at: string
        }
        Insert: {
          active?: boolean
          barcode?: string | null
          batch_number?: string | null
          brand_name?: string | null
          catalogue_id?: string | null
          created_at?: string
          drug_name: string
          expiry_date?: string | null
          facility_id?: string | null
          form?: string | null
          generic_name?: string | null
          id?: string
          nhis_claim_amount?: number
          nhis_patient_price?: number
          pack_size?: number | null
          reorder_level?: number | null
          stock_quantity?: number
          strength?: string | null
          supplier?: string | null
          unit_price?: number | null
          updated_at?: string
        }
        Update: {
          active?: boolean
          barcode?: string | null
          batch_number?: string | null
          brand_name?: string | null
          catalogue_id?: string | null
          created_at?: string
          drug_name?: string
          expiry_date?: string | null
          facility_id?: string | null
          form?: string | null
          generic_name?: string | null
          id?: string
          nhis_claim_amount?: number
          nhis_patient_price?: number
          pack_size?: number | null
          reorder_level?: number | null
          stock_quantity?: number
          strength?: string | null
          supplier?: string | null
          unit_price?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "pharmacy_inventory_catalogue_id_fkey"
            columns: ["catalogue_id"]
            isOneToOne: false
            referencedRelation: "medication_catalogue"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pharmacy_inventory_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
        ]
      }
      pharmacy_pos_sales: {
        Row: {
          created_at: string
          created_by: string | null
          dispensed_at: string | null
          dispensed_by: string | null
          facility_id: string | null
          id: string
          inventory_id: string | null
          medication: string
          patient_id: string | null
          quantity: number
          service_order_id: string | null
          status: string
          total_amount: number | null
          unit_price: number
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          dispensed_at?: string | null
          dispensed_by?: string | null
          facility_id?: string | null
          id?: string
          inventory_id?: string | null
          medication: string
          patient_id?: string | null
          quantity: number
          service_order_id?: string | null
          status?: string
          total_amount?: number | null
          unit_price: number
        }
        Update: {
          created_at?: string
          created_by?: string | null
          dispensed_at?: string | null
          dispensed_by?: string | null
          facility_id?: string | null
          id?: string
          inventory_id?: string | null
          medication?: string
          patient_id?: string | null
          quantity?: number
          service_order_id?: string | null
          status?: string
          total_amount?: number | null
          unit_price?: number
        }
        Relationships: [
          {
            foreignKeyName: "pharmacy_pos_sales_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pharmacy_pos_sales_inventory_id_fkey"
            columns: ["inventory_id"]
            isOneToOne: false
            referencedRelation: "pharmacy_inventory"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pharmacy_pos_sales_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pharmacy_pos_sales_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      physio_assessments: {
        Row: {
          assessment_type: string
          chief_complaint: string | null
          created_at: string
          created_by: string
          encounter_id: string
          facility_id: string
          functional_goals: string[]
          id: string
          muscle_strength: Json
          next_session_date: string | null
          pain_scale: number | null
          patient_id: string
          progress_notes: string | null
          range_of_motion: Json
          treatment_given: string | null
          treatment_plan: string | null
          updated_at: string
        }
        Insert: {
          assessment_type?: string
          chief_complaint?: string | null
          created_at?: string
          created_by: string
          encounter_id: string
          facility_id: string
          functional_goals?: string[]
          id?: string
          muscle_strength?: Json
          next_session_date?: string | null
          pain_scale?: number | null
          patient_id: string
          progress_notes?: string | null
          range_of_motion?: Json
          treatment_given?: string | null
          treatment_plan?: string | null
          updated_at?: string
        }
        Update: {
          assessment_type?: string
          chief_complaint?: string | null
          created_at?: string
          created_by?: string
          encounter_id?: string
          facility_id?: string
          functional_goals?: string[]
          id?: string
          muscle_strength?: Json
          next_session_date?: string | null
          pain_scale?: number | null
          patient_id?: string
          progress_notes?: string | null
          range_of_motion?: Json
          treatment_given?: string | null
          treatment_plan?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "physio_assessments_encounter_id_fkey"
            columns: ["encounter_id"]
            isOneToOne: false
            referencedRelation: "encounters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "physio_assessments_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      physio_treatment_plans: {
        Row: {
          assessment_id: string
          completed_sessions: number
          created_at: string
          created_by: string
          facility_id: string
          id: string
          initial_encounter_id: string
          notes: string | null
          package_service_code: string | null
          patient_id: string
          planned_sessions: number
          start_date: string
          status: string
          target_end_date: string | null
          updated_at: string
        }
        Insert: {
          assessment_id: string
          completed_sessions?: number
          created_at?: string
          created_by: string
          facility_id: string
          id?: string
          initial_encounter_id: string
          notes?: string | null
          package_service_code?: string | null
          patient_id: string
          planned_sessions: number
          start_date?: string
          status?: string
          target_end_date?: string | null
          updated_at?: string
        }
        Update: {
          assessment_id?: string
          completed_sessions?: number
          created_at?: string
          created_by?: string
          facility_id?: string
          id?: string
          initial_encounter_id?: string
          notes?: string | null
          package_service_code?: string | null
          patient_id?: string
          planned_sessions?: number
          start_date?: string
          status?: string
          target_end_date?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "physio_treatment_plans_assessment_id_fkey"
            columns: ["assessment_id"]
            isOneToOne: false
            referencedRelation: "physio_assessments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "physio_treatment_plans_initial_encounter_id_fkey"
            columns: ["initial_encounter_id"]
            isOneToOne: false
            referencedRelation: "encounters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "physio_treatment_plans_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      prescriptions: {
        Row: {
          computed_quantity: number | null
          created_at: string
          diagnosis_id: string | null
          dispensed_at: string | null
          dispensed_by: string | null
          dispensed_quantity: number
          dosage: string | null
          duration: string | null
          encounter_id: string | null
          facility_id: string | null
          frequency: string | null
          id: string
          instructions: string | null
          medication: string
          medication_name: string | null
          patient_id: string
          prescribed_by: string | null
          route: string | null
          status: string
          updated_at: string
        }
        Insert: {
          computed_quantity?: number | null
          created_at?: string
          diagnosis_id?: string | null
          dispensed_at?: string | null
          dispensed_by?: string | null
          dispensed_quantity?: number
          dosage?: string | null
          duration?: string | null
          encounter_id?: string | null
          facility_id?: string | null
          frequency?: string | null
          id?: string
          instructions?: string | null
          medication: string
          medication_name?: string | null
          patient_id: string
          prescribed_by?: string | null
          route?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          computed_quantity?: number | null
          created_at?: string
          diagnosis_id?: string | null
          dispensed_at?: string | null
          dispensed_by?: string | null
          dispensed_quantity?: number
          dosage?: string | null
          duration?: string | null
          encounter_id?: string | null
          facility_id?: string | null
          frequency?: string | null
          id?: string
          instructions?: string | null
          medication?: string
          medication_name?: string | null
          patient_id?: string
          prescribed_by?: string | null
          route?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "prescriptions_diagnosis_id_fkey"
            columns: ["diagnosis_id"]
            isOneToOne: false
            referencedRelation: "diagnoses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "prescriptions_encounter_id_fkey"
            columns: ["encounter_id"]
            isOneToOne: false
            referencedRelation: "encounters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "prescriptions_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "prescriptions_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      procedure_notes: {
        Row: {
          assistants: string | null
          charge_amount: number
          complications: string | null
          created_at: string
          encounter_id: string | null
          facility_id: string | null
          findings: string | null
          id: string
          indication: string | null
          patient_id: string
          performed_at: string | null
          performed_by: string | null
          post_op_plan: string | null
          procedure_code: string | null
          procedure_name: string | null
          service_order_id: string | null
          status: string
          technique: string | null
          template_used: string | null
          updated_at: string
        }
        Insert: {
          assistants?: string | null
          charge_amount?: number
          complications?: string | null
          created_at?: string
          encounter_id?: string | null
          facility_id?: string | null
          findings?: string | null
          id?: string
          indication?: string | null
          patient_id: string
          performed_at?: string | null
          performed_by?: string | null
          post_op_plan?: string | null
          procedure_code?: string | null
          procedure_name?: string | null
          service_order_id?: string | null
          status?: string
          technique?: string | null
          template_used?: string | null
          updated_at?: string
        }
        Update: {
          assistants?: string | null
          charge_amount?: number
          complications?: string | null
          created_at?: string
          encounter_id?: string | null
          facility_id?: string | null
          findings?: string | null
          id?: string
          indication?: string | null
          patient_id?: string
          performed_at?: string | null
          performed_by?: string | null
          post_op_plan?: string | null
          procedure_code?: string | null
          procedure_name?: string | null
          service_order_id?: string | null
          status?: string
          technique?: string | null
          template_used?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "procedure_notes_encounter_id_fkey"
            columns: ["encounter_id"]
            isOneToOne: false
            referencedRelation: "encounters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "procedure_notes_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "procedure_notes_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "procedure_notes_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          avatar_url: string | null
          created_at: string
          department: string | null
          email: string | null
          first_name: string | null
          full_name: string | null
          id: string
          last_name: string | null
          phone: string | null
          specialization: string | null
          title: string | null
          updated_at: string
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string
          department?: string | null
          email?: string | null
          first_name?: string | null
          full_name?: string | null
          id: string
          last_name?: string | null
          phone?: string | null
          specialization?: string | null
          title?: string | null
          updated_at?: string
        }
        Update: {
          avatar_url?: string | null
          created_at?: string
          department?: string | null
          email?: string | null
          first_name?: string | null
          full_name?: string | null
          id?: string
          last_name?: string | null
          phone?: string | null
          specialization?: string | null
          title?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      report_categories: {
        Row: {
          display_order: number
          id: string
          name: string
        }
        Insert: {
          display_order?: number
          id?: string
          name: string
        }
        Update: {
          display_order?: number
          id?: string
          name?: string
        }
        Relationships: []
      }
      report_definitions: {
        Row: {
          audience_roles: string[]
          category_id: string | null
          created_at: string
          default_parameters: Json
          department_code: string | null
          description: string | null
          extractor_key: string
          frequency: string
          id: string
          implementation_status: string
          is_active: boolean
          parameters: Json
          report_code: string
          report_name: string
          report_scope: string
          submission_deadline_day: number
          supported_formats: string[]
          updated_at: string
        }
        Insert: {
          audience_roles?: string[]
          category_id?: string | null
          created_at?: string
          default_parameters?: Json
          department_code?: string | null
          description?: string | null
          extractor_key: string
          frequency?: string
          id?: string
          implementation_status?: string
          is_active?: boolean
          parameters?: Json
          report_code: string
          report_name: string
          report_scope?: string
          submission_deadline_day?: number
          supported_formats?: string[]
          updated_at?: string
        }
        Update: {
          audience_roles?: string[]
          category_id?: string | null
          created_at?: string
          default_parameters?: Json
          department_code?: string | null
          description?: string | null
          extractor_key?: string
          frequency?: string
          id?: string
          implementation_status?: string
          is_active?: boolean
          parameters?: Json
          report_code?: string
          report_name?: string
          report_scope?: string
          submission_deadline_day?: number
          supported_formats?: string[]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "report_definitions_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "report_categories"
            referencedColumns: ["id"]
          },
        ]
      }
      report_generation_items: {
        Row: {
          completed_at: string | null
          created_at: string
          data_snapshot: Json
          error_message: string | null
          file_name: string | null
          id: string
          output_format: string
          report_definition_id: string | null
          report_id: string
          run_id: string
          started_at: string | null
          status: string
          updated_at: string
          validation_messages: Json
        }
        Insert: {
          completed_at?: string | null
          created_at?: string
          data_snapshot?: Json
          error_message?: string | null
          file_name?: string | null
          id?: string
          output_format?: string
          report_definition_id?: string | null
          report_id: string
          run_id: string
          started_at?: string | null
          status?: string
          updated_at?: string
          validation_messages?: Json
        }
        Update: {
          completed_at?: string | null
          created_at?: string
          data_snapshot?: Json
          error_message?: string | null
          file_name?: string | null
          id?: string
          output_format?: string
          report_definition_id?: string | null
          report_id?: string
          run_id?: string
          started_at?: string | null
          status?: string
          updated_at?: string
          validation_messages?: Json
        }
        Relationships: [
          {
            foreignKeyName: "report_generation_items_report_id_fkey"
            columns: ["report_id"]
            isOneToOne: false
            referencedRelation: "report_definitions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "report_generation_items_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "report_generation_runs"
            referencedColumns: ["id"]
          },
        ]
      }
      report_generation_runs: {
        Row: {
          bundle_manifest: Json
          completed_at: string | null
          created_at: string
          created_by: string | null
          facility_id: string
          failed_count: number
          frequency: string
          id: string
          parameters: Json
          period_end: string
          period_start: string
          reporting_period_end: string | null
          reporting_period_start: string | null
          started_at: string | null
          status: string
          success_count: number
          total_reports: number
          updated_at: string
          warning_count: number
        }
        Insert: {
          bundle_manifest?: Json
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          facility_id: string
          failed_count?: number
          frequency?: string
          id?: string
          parameters?: Json
          period_end: string
          period_start: string
          reporting_period_end?: string | null
          reporting_period_start?: string | null
          started_at?: string | null
          status?: string
          success_count?: number
          total_reports?: number
          updated_at?: string
          warning_count?: number
        }
        Update: {
          bundle_manifest?: Json
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          facility_id?: string
          failed_count?: number
          frequency?: string
          id?: string
          parameters?: Json
          period_end?: string
          period_start?: string
          reporting_period_end?: string | null
          reporting_period_start?: string | null
          started_at?: string | null
          status?: string
          success_count?: number
          total_reports?: number
          updated_at?: string
          warning_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "report_generation_runs_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
        ]
      }
      report_submissions: {
        Row: {
          created_at: string
          data_snapshot: Json
          due_date: string
          facility_id: string
          id: string
          period_end: string
          period_start: string
          report_definition_id: string | null
          report_id: string
          reporting_period_end: string | null
          reporting_period_start: string | null
          status: string
          submission_reference: string | null
          submitted_at: string | null
          submitted_by: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          data_snapshot?: Json
          due_date: string
          facility_id: string
          id?: string
          period_end: string
          period_start: string
          report_definition_id?: string | null
          report_id: string
          reporting_period_end?: string | null
          reporting_period_start?: string | null
          status?: string
          submission_reference?: string | null
          submitted_at?: string | null
          submitted_by?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          data_snapshot?: Json
          due_date?: string
          facility_id?: string
          id?: string
          period_end?: string
          period_start?: string
          report_definition_id?: string | null
          report_id?: string
          reporting_period_end?: string | null
          reporting_period_start?: string | null
          status?: string
          submission_reference?: string | null
          submitted_at?: string | null
          submitted_by?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "report_submissions_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "report_submissions_report_id_fkey"
            columns: ["report_id"]
            isOneToOne: false
            referencedRelation: "report_definitions"
            referencedColumns: ["id"]
          },
        ]
      }
      role_permissions: {
        Row: {
          created_at: string
          permission_key: string
          role: Database["public"]["Enums"]["app_role"]
        }
        Insert: {
          created_at?: string
          permission_key: string
          role: Database["public"]["Enums"]["app_role"]
        }
        Update: {
          created_at?: string
          permission_key?: string
          role?: Database["public"]["Enums"]["app_role"]
        }
        Relationships: [
          {
            foreignKeyName: "role_permissions_permission_key_fkey"
            columns: ["permission_key"]
            isOneToOne: false
            referencedRelation: "permissions"
            referencedColumns: ["permission_key"]
          },
        ]
      }
      scheduled_notifications: {
        Row: {
          channels: Json
          created_at: string
          created_by: string | null
          event_name: string
          facility_id: string | null
          id: string
          idempotency_key: string
          locale: string | null
          payload: Json
          priority: string
          recurrence: string | null
          run_at: string
          status: string
          template_key: string
          tenant_id: string | null
          timezone: string | null
          updated_at: string
          user_id: string | null
        }
        Insert: {
          channels?: Json
          created_at?: string
          created_by?: string | null
          event_name: string
          facility_id?: string | null
          id?: string
          idempotency_key: string
          locale?: string | null
          payload?: Json
          priority?: string
          recurrence?: string | null
          run_at: string
          status?: string
          template_key: string
          tenant_id?: string | null
          timezone?: string | null
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          channels?: Json
          created_at?: string
          created_by?: string | null
          event_name?: string
          facility_id?: string | null
          id?: string
          idempotency_key?: string
          locale?: string | null
          payload?: Json
          priority?: string
          recurrence?: string | null
          run_at?: string
          status?: string
          template_key?: string
          tenant_id?: string | null
          timezone?: string | null
          updated_at?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "scheduled_notifications_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
        ]
      }
      service_order_events: {
        Row: {
          actor_id: string | null
          created_at: string
          from_status: string | null
          id: string
          metadata: Json
          reason: string | null
          service_order_id: string
          to_status: string
        }
        Insert: {
          actor_id?: string | null
          created_at?: string
          from_status?: string | null
          id?: string
          metadata?: Json
          reason?: string | null
          service_order_id: string
          to_status: string
        }
        Update: {
          actor_id?: string | null
          created_at?: string
          from_status?: string | null
          id?: string
          metadata?: Json
          reason?: string | null
          service_order_id?: string
          to_status?: string
        }
        Relationships: [
          {
            foreignKeyName: "service_order_events_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      service_orders: {
        Row: {
          amount: number
          approved_at: string | null
          approved_by: string | null
          cancelled_at: string | null
          completed_at: string | null
          created_at: string
          created_by: string | null
          department: string
          encounter_id: string | null
          facility_id: string | null
          id: string
          invoice_id: string | null
          invoice_item_id: string | null
          notes: string | null
          order_type: string
          patient_id: string
          payment_required: boolean
          quantity: number
          related_entity_id: string | null
          release_reason: string | null
          released_at: string | null
          released_by: string | null
          requested_by: string | null
          service_code: string | null
          service_name: string
          started_at: string | null
          status: string
          unit_price: number
          updated_at: string
        }
        Insert: {
          amount?: number
          approved_at?: string | null
          approved_by?: string | null
          cancelled_at?: string | null
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          department: string
          encounter_id?: string | null
          facility_id?: string | null
          id?: string
          invoice_id?: string | null
          invoice_item_id?: string | null
          notes?: string | null
          order_type?: string
          patient_id: string
          payment_required?: boolean
          quantity?: number
          related_entity_id?: string | null
          release_reason?: string | null
          released_at?: string | null
          released_by?: string | null
          requested_by?: string | null
          service_code?: string | null
          service_name: string
          started_at?: string | null
          status?: string
          unit_price?: number
          updated_at?: string
        }
        Update: {
          amount?: number
          approved_at?: string | null
          approved_by?: string | null
          cancelled_at?: string | null
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          department?: string
          encounter_id?: string | null
          facility_id?: string | null
          id?: string
          invoice_id?: string | null
          invoice_item_id?: string | null
          notes?: string | null
          order_type?: string
          patient_id?: string
          payment_required?: boolean
          quantity?: number
          related_entity_id?: string | null
          release_reason?: string | null
          released_at?: string | null
          released_by?: string | null
          requested_by?: string | null
          service_code?: string | null
          service_name?: string
          started_at?: string | null
          status?: string
          unit_price?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "service_orders_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_orders_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      service_tariffs: {
        Row: {
          active: boolean
          amount: number
          created_at: string
          currency: string
          department: string
          effective_from: string | null
          effective_to: string | null
          id: string
          is_session_package: boolean
          metadata: Json
          package_session_count: number | null
          service_code: string
          service_name: string
          source_standard: string | null
          specialty_category: string | null
          unit: string
          updated_at: string
        }
        Insert: {
          active?: boolean
          amount?: number
          created_at?: string
          currency?: string
          department: string
          effective_from?: string | null
          effective_to?: string | null
          id?: string
          is_session_package?: boolean
          metadata?: Json
          package_session_count?: number | null
          service_code: string
          service_name: string
          source_standard?: string | null
          specialty_category?: string | null
          unit?: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          amount?: number
          created_at?: string
          currency?: string
          department?: string
          effective_from?: string | null
          effective_to?: string | null
          id?: string
          is_session_package?: boolean
          metadata?: Json
          package_session_count?: number | null
          service_code?: string
          service_name?: string
          source_standard?: string | null
          specialty_category?: string | null
          unit?: string
          updated_at?: string
        }
        Relationships: []
      }
      specialist_review_sessions: {
        Row: {
          appointment_id: string | null
          completed_at: string | null
          created_at: string
          created_by: string
          encounter_id: string
          facility_id: string
          id: string
          patient_id: string
          progress_notes: string | null
          review_data: Json
          scheduled_for: string | null
          source_assessment_id: string
          specialty: string
          status: string
          updated_at: string
        }
        Insert: {
          appointment_id?: string | null
          completed_at?: string | null
          created_at?: string
          created_by: string
          encounter_id: string
          facility_id: string
          id?: string
          patient_id: string
          progress_notes?: string | null
          review_data?: Json
          scheduled_for?: string | null
          source_assessment_id: string
          specialty: string
          status?: string
          updated_at?: string
        }
        Update: {
          appointment_id?: string | null
          completed_at?: string | null
          created_at?: string
          created_by?: string
          encounter_id?: string
          facility_id?: string
          id?: string
          patient_id?: string
          progress_notes?: string | null
          review_data?: Json
          scheduled_for?: string | null
          source_assessment_id?: string
          specialty?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "specialist_review_sessions_appointment_id_fkey"
            columns: ["appointment_id"]
            isOneToOne: false
            referencedRelation: "appointments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "specialist_review_sessions_encounter_id_fkey"
            columns: ["encounter_id"]
            isOneToOne: false
            referencedRelation: "encounters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "specialist_review_sessions_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      staff_shift_assignments: {
        Row: {
          active: boolean
          created_at: string
          department: string
          ends_at: string
          id: string
          shift_label: string
          starts_at: string
          user_id: string
        }
        Insert: {
          active?: boolean
          created_at?: string
          department: string
          ends_at: string
          id?: string
          shift_label: string
          starts_at: string
          user_id: string
        }
        Update: {
          active?: boolean
          created_at?: string
          department?: string
          ends_at?: string
          id?: string
          shift_label?: string
          starts_at?: string
          user_id?: string
        }
        Relationships: []
      }
      staff_signatures: {
        Row: {
          created_at: string
          facility_id: string | null
          id: string
          signature_data: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          facility_id?: string | null
          id?: string
          signature_data: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          facility_id?: string | null
          id?: string
          signature_data?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "staff_signatures_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
        ]
      }
      stg_diagnoses: {
        Row: {
          category: string | null
          code: string
          created_at: string
          description: string | null
          display_name: string
          icd10_code_id: string | null
          id: string
          is_active: boolean
          source_reference: string | null
          standard_id: string
          synonyms: string[]
          updated_at: string
        }
        Insert: {
          category?: string | null
          code: string
          created_at?: string
          description?: string | null
          display_name: string
          icd10_code_id?: string | null
          id?: string
          is_active?: boolean
          source_reference?: string | null
          standard_id: string
          synonyms?: string[]
          updated_at?: string
        }
        Update: {
          category?: string | null
          code?: string
          created_at?: string
          description?: string | null
          display_name?: string
          icd10_code_id?: string | null
          id?: string
          is_active?: boolean
          source_reference?: string | null
          standard_id?: string
          synonyms?: string[]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "stg_diagnoses_icd10_code_id_fkey"
            columns: ["icd10_code_id"]
            isOneToOne: false
            referencedRelation: "icd_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stg_diagnoses_standard_id_fkey"
            columns: ["standard_id"]
            isOneToOne: false
            referencedRelation: "diagnosis_standards"
            referencedColumns: ["id"]
          },
        ]
      }
      stg_guidelines: {
        Row: {
          condition: string
          created_at: string
          icd_code: string | null
          id: string
          medications: Json | null
          recommended_action: string | null
          summary: string | null
        }
        Insert: {
          condition: string
          created_at?: string
          icd_code?: string | null
          id?: string
          medications?: Json | null
          recommended_action?: string | null
          summary?: string | null
        }
        Update: {
          condition?: string
          created_at?: string
          icd_code?: string | null
          id?: string
          medications?: Json | null
          recommended_action?: string | null
          summary?: string | null
        }
        Relationships: []
      }
      sync_queue: {
        Row: {
          id: string
          payload: Json | null
          synced: boolean | null
          table_name: string | null
        }
        Insert: {
          id?: string
          payload?: Json | null
          synced?: boolean | null
          table_name?: string | null
        }
        Update: {
          id?: string
          payload?: Json | null
          synced?: boolean | null
          table_name?: string | null
        }
        Relationships: []
      }
      system_audit_log: {
        Row: {
          action: string
          actor_id: string | null
          created_at: string
          entity_id: string | null
          entity_type: string | null
          id: string
          metadata: Json
          module: string
          severity: string
        }
        Insert: {
          action: string
          actor_id?: string | null
          created_at?: string
          entity_id?: string | null
          entity_type?: string | null
          id?: string
          metadata?: Json
          module: string
          severity?: string
        }
        Update: {
          action?: string
          actor_id?: string | null
          created_at?: string
          entity_id?: string | null
          entity_type?: string | null
          id?: string
          metadata?: Json
          module?: string
          severity?: string
        }
        Relationships: []
      }
      system_master_data: {
        Row: {
          active: boolean
          attributes: Json
          code: string
          created_at: string
          created_by: string | null
          description: string | null
          domain: string
          effective_from: string | null
          effective_to: string | null
          id: string
          name: string
          source_system: string | null
          source_version: string | null
          updated_at: string
        }
        Insert: {
          active?: boolean
          attributes?: Json
          code: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          domain: string
          effective_from?: string | null
          effective_to?: string | null
          id?: string
          name: string
          source_system?: string | null
          source_version?: string | null
          updated_at?: string
        }
        Update: {
          active?: boolean
          attributes?: Json
          code?: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          domain?: string
          effective_from?: string | null
          effective_to?: string | null
          id?: string
          name?: string
          source_system?: string | null
          source_version?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      theatre_cases: {
        Row: {
          anaesthetic_cleared: boolean
          anaesthetist_id: string | null
          anesthetist_id: string | null
          consent_confirmed: boolean
          created_at: string
          created_by: string | null
          encounter_id: string | null
          facility_id: string | null
          id: string
          notes: string | null
          patient_id: string
          procedure_name: string
          scheduled_at: string | null
          scheduled_start: string | null
          status: string
          surgeon_id: string | null
          theatre: string | null
          theatre_name: string | null
          updated_at: string
          urgency: string
        }
        Insert: {
          anaesthetic_cleared?: boolean
          anaesthetist_id?: string | null
          anesthetist_id?: string | null
          consent_confirmed?: boolean
          created_at?: string
          created_by?: string | null
          encounter_id?: string | null
          facility_id?: string | null
          id?: string
          notes?: string | null
          patient_id: string
          procedure_name: string
          scheduled_at?: string | null
          scheduled_start?: string | null
          status?: string
          surgeon_id?: string | null
          theatre?: string | null
          theatre_name?: string | null
          updated_at?: string
          urgency?: string
        }
        Update: {
          anaesthetic_cleared?: boolean
          anaesthetist_id?: string | null
          anesthetist_id?: string | null
          consent_confirmed?: boolean
          created_at?: string
          created_by?: string | null
          encounter_id?: string | null
          facility_id?: string | null
          id?: string
          notes?: string | null
          patient_id?: string
          procedure_name?: string
          scheduled_at?: string | null
          scheduled_start?: string | null
          status?: string
          surgeon_id?: string | null
          theatre?: string | null
          theatre_name?: string | null
          updated_at?: string
          urgency?: string
        }
        Relationships: [
          {
            foreignKeyName: "theatre_cases_encounter_id_fkey"
            columns: ["encounter_id"]
            isOneToOne: false
            referencedRelation: "encounters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "theatre_cases_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "theatre_cases_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      transfusion_records: {
        Row: {
          administered_by: string | null
          blood_group: string | null
          blood_product: string | null
          compatibility_checked: boolean
          completed_at: string | null
          component: string
          consent_confirmed: boolean
          created_at: string
          encounter_id: string | null
          facility_id: string | null
          id: string
          notes: string | null
          patient_id: string
          reaction_notes: string | null
          reaction_observed: boolean
          started_at: string | null
          status: string
          unit_identifier: string | null
          updated_at: string
          witnessed_by: string | null
        }
        Insert: {
          administered_by?: string | null
          blood_group?: string | null
          blood_product?: string | null
          compatibility_checked?: boolean
          completed_at?: string | null
          component: string
          consent_confirmed?: boolean
          created_at?: string
          encounter_id?: string | null
          facility_id?: string | null
          id?: string
          notes?: string | null
          patient_id: string
          reaction_notes?: string | null
          reaction_observed?: boolean
          started_at?: string | null
          status?: string
          unit_identifier?: string | null
          updated_at?: string
          witnessed_by?: string | null
        }
        Update: {
          administered_by?: string | null
          blood_group?: string | null
          blood_product?: string | null
          compatibility_checked?: boolean
          completed_at?: string | null
          component?: string
          consent_confirmed?: boolean
          created_at?: string
          encounter_id?: string | null
          facility_id?: string | null
          id?: string
          notes?: string | null
          patient_id?: string
          reaction_notes?: string | null
          reaction_observed?: boolean
          started_at?: string | null
          status?: string
          unit_identifier?: string | null
          updated_at?: string
          witnessed_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "transfusion_records_encounter_id_fkey"
            columns: ["encounter_id"]
            isOneToOne: false
            referencedRelation: "encounters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transfusion_records_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
        ]
      }
      treatment_templates: {
        Row: {
          created_at: string
          created_by: string | null
          description: string | null
          diagnosis: string | null
          icd_code: string | null
          id: string
          is_ai_generated: boolean | null
          lab_orders: Json | null
          name: string
          notes: string | null
          prescriptions: Json | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          diagnosis?: string | null
          icd_code?: string | null
          id?: string
          is_ai_generated?: boolean | null
          lab_orders?: Json | null
          name: string
          notes?: string | null
          prescriptions?: Json | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          diagnosis?: string | null
          icd_code?: string | null
          id?: string
          is_ai_generated?: boolean | null
          lab_orders?: Json | null
          name?: string
          notes?: string | null
          prescriptions?: Json | null
          updated_at?: string
        }
        Relationships: []
      }
      triage_assessments: {
        Row: {
          bmi: number | null
          clinical_notes: string | null
          consciousness: string | null
          created_at: string
          diastolic: number | null
          facility_id: string | null
          heart_rate: number | null
          height_m: number | null
          id: string
          is_critical: boolean
          oxygen_saturation: number | null
          pain_score: number | null
          patient_id: string
          presenting_complaint: string | null
          priority: string
          recorded_by: string
          respiratory_rate: number | null
          systolic: number | null
          temperature: number | null
          updated_at: string
          weight_kg: number | null
        }
        Insert: {
          bmi?: number | null
          clinical_notes?: string | null
          consciousness?: string | null
          created_at?: string
          diastolic?: number | null
          facility_id?: string | null
          heart_rate?: number | null
          height_m?: number | null
          id?: string
          is_critical?: boolean
          oxygen_saturation?: number | null
          pain_score?: number | null
          patient_id: string
          presenting_complaint?: string | null
          priority: string
          recorded_by: string
          respiratory_rate?: number | null
          systolic?: number | null
          temperature?: number | null
          updated_at?: string
          weight_kg?: number | null
        }
        Update: {
          bmi?: number | null
          clinical_notes?: string | null
          consciousness?: string | null
          created_at?: string
          diastolic?: number | null
          facility_id?: string | null
          heart_rate?: number | null
          height_m?: number | null
          id?: string
          is_critical?: boolean
          oxygen_saturation?: number | null
          pain_score?: number | null
          patient_id?: string
          presenting_complaint?: string | null
          priority?: string
          recorded_by?: string
          respiratory_rate?: number | null
          systolic?: number | null
          temperature?: number | null
          updated_at?: string
          weight_kg?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "triage_assessments_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "triage_assessments_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      user_active_facilities: {
        Row: {
          facility_id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          facility_id: string
          updated_at?: string
          user_id: string
        }
        Update: {
          facility_id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_active_facilities_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
        ]
      }
      user_document_signatures: {
        Row: {
          created_at: string
          display_name: string
          id: string
          is_active: boolean
          professional_title: string | null
          signature_data: string
          signature_hash: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          display_name: string
          id?: string
          is_active?: boolean
          professional_title?: string | null
          signature_data: string
          signature_hash: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          display_name?: string
          id?: string
          is_active?: boolean
          professional_title?: string | null
          signature_data?: string
          signature_hash?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      user_notification_preferences: {
        Row: {
          category_preferences: Json
          channel_preferences: Json
          consent_ip: unknown
          consent_version: string | null
          consented_at: string | null
          id: string
          locale: string
          pause_non_critical: boolean
          quiet_hours_end: string
          quiet_hours_start: string
          tenant_id: string | null
          timezone: string
          updated_at: string
          user_id: string
        }
        Insert: {
          category_preferences?: Json
          channel_preferences?: Json
          consent_ip?: unknown
          consent_version?: string | null
          consented_at?: string | null
          id?: string
          locale?: string
          pause_non_critical?: boolean
          quiet_hours_end?: string
          quiet_hours_start?: string
          tenant_id?: string | null
          timezone?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          category_preferences?: Json
          channel_preferences?: Json
          consent_ip?: unknown
          consent_version?: string | null
          consented_at?: string | null
          id?: string
          locale?: string
          pause_non_critical?: boolean
          quiet_hours_end?: string
          quiet_hours_start?: string
          tenant_id?: string | null
          timezone?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      user_preferences: {
        Row: {
          date_format: string
          density: string
          email_notifications_enabled: boolean
          locale: string
          notification_sound_enabled: boolean
          theme: string
          time_format: string
          timezone: string
          updated_at: string
          user_id: string
        }
        Insert: {
          date_format?: string
          density?: string
          email_notifications_enabled?: boolean
          locale?: string
          notification_sound_enabled?: boolean
          theme?: string
          time_format?: string
          timezone?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          date_format?: string
          density?: string
          email_notifications_enabled?: boolean
          locale?: string
          notification_sound_enabled?: boolean
          theme?: string
          time_format?: string
          timezone?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      user_roles: {
        Row: {
          created_at: string
          id: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          role?: Database["public"]["Enums"]["app_role"]
          user_id?: string
        }
        Relationships: []
      }
      video_sessions: {
        Row: {
          appointment_id: string | null
          created_at: string
          ended_at: string | null
          facility_id: string | null
          id: string
          notes: string | null
          patient_id: string
          payment_received: boolean | null
          payment_required: boolean | null
          practitioner_id: string | null
          provider: string | null
          recording_url: string | null
          room_name: string
          scheduled_at: string
          service_order_id: string | null
          started_at: string | null
          status: string
        }
        Insert: {
          appointment_id?: string | null
          created_at?: string
          ended_at?: string | null
          facility_id?: string | null
          id?: string
          notes?: string | null
          patient_id: string
          payment_received?: boolean | null
          payment_required?: boolean | null
          practitioner_id?: string | null
          provider?: string | null
          recording_url?: string | null
          room_name: string
          scheduled_at: string
          service_order_id?: string | null
          started_at?: string | null
          status?: string
        }
        Update: {
          appointment_id?: string | null
          created_at?: string
          ended_at?: string | null
          facility_id?: string | null
          id?: string
          notes?: string | null
          patient_id?: string
          payment_received?: boolean | null
          payment_required?: boolean | null
          practitioner_id?: string | null
          provider?: string | null
          recording_url?: string | null
          room_name?: string
          scheduled_at?: string
          service_order_id?: string | null
          started_at?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "video_sessions_appointment_id_fkey"
            columns: ["appointment_id"]
            isOneToOne: false
            referencedRelation: "appointments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "video_sessions_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "video_sessions_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "video_sessions_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      vital_alerts: {
        Row: {
          acknowledged_at: string | null
          acknowledged_by: string | null
          alert_type: string
          created_at: string
          details: string | null
          facility_id: string | null
          id: string
          patient_id: string
          severity: string
          vital_signs_id: string | null
        }
        Insert: {
          acknowledged_at?: string | null
          acknowledged_by?: string | null
          alert_type: string
          created_at?: string
          details?: string | null
          facility_id?: string | null
          id?: string
          patient_id: string
          severity?: string
          vital_signs_id?: string | null
        }
        Update: {
          acknowledged_at?: string | null
          acknowledged_by?: string | null
          alert_type?: string
          created_at?: string
          details?: string | null
          facility_id?: string | null
          id?: string
          patient_id?: string
          severity?: string
          vital_signs_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "vital_alerts_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vital_alerts_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      vital_signs: {
        Row: {
          appointment_id: string | null
          bmi: number | null
          created_at: string
          diastolic: number | null
          encounter_id: string | null
          entered_by: string | null
          facility_id: string | null
          height: number | null
          height_cm: number | null
          id: string
          notes: string | null
          oxygen_saturation: number | null
          patient_id: string
          priority: string | null
          pulse_rate: number | null
          recorded_at: string
          recorded_by: string | null
          respiratory_rate: number | null
          systolic: number | null
          temperature: number | null
          weight: number | null
          weight_kg: number | null
        }
        Insert: {
          appointment_id?: string | null
          bmi?: number | null
          created_at?: string
          diastolic?: number | null
          encounter_id?: string | null
          entered_by?: string | null
          facility_id?: string | null
          height?: number | null
          height_cm?: number | null
          id?: string
          notes?: string | null
          oxygen_saturation?: number | null
          patient_id: string
          priority?: string | null
          pulse_rate?: number | null
          recorded_at?: string
          recorded_by?: string | null
          respiratory_rate?: number | null
          systolic?: number | null
          temperature?: number | null
          weight?: number | null
          weight_kg?: number | null
        }
        Update: {
          appointment_id?: string | null
          bmi?: number | null
          created_at?: string
          diastolic?: number | null
          encounter_id?: string | null
          entered_by?: string | null
          facility_id?: string | null
          height?: number | null
          height_cm?: number | null
          id?: string
          notes?: string | null
          oxygen_saturation?: number | null
          patient_id?: string
          priority?: string | null
          pulse_rate?: number | null
          recorded_at?: string
          recorded_by?: string | null
          respiratory_rate?: number | null
          systolic?: number | null
          temperature?: number | null
          weight?: number | null
          weight_kg?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "vital_signs_appointment_id_fkey"
            columns: ["appointment_id"]
            isOneToOne: false
            referencedRelation: "appointments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vital_signs_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vital_signs_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      ward_beds: {
        Row: {
          admission_id: string | null
          bed_number: string
          created_at: string
          facility_id: string | null
          id: string
          notes: string | null
          occupied_at: string | null
          patient_id: string | null
          released_at: string | null
          status: string
          updated_at: string
          ward_id: string
        }
        Insert: {
          admission_id?: string | null
          bed_number: string
          created_at?: string
          facility_id?: string | null
          id?: string
          notes?: string | null
          occupied_at?: string | null
          patient_id?: string | null
          released_at?: string | null
          status?: string
          updated_at?: string
          ward_id: string
        }
        Update: {
          admission_id?: string | null
          bed_number?: string
          created_at?: string
          facility_id?: string | null
          id?: string
          notes?: string | null
          occupied_at?: string | null
          patient_id?: string | null
          released_at?: string | null
          status?: string
          updated_at?: string
          ward_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ward_beds_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ward_beds_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ward_beds_ward_id_fkey"
            columns: ["ward_id"]
            isOneToOne: false
            referencedRelation: "ward_units"
            referencedColumns: ["id"]
          },
        ]
      }
      ward_units: {
        Row: {
          active: boolean
          code: string
          created_at: string
          facility_id: string | null
          gender_policy: string
          id: string
          name: string
          specialty: string | null
          updated_at: string
        }
        Insert: {
          active?: boolean
          code: string
          created_at?: string
          facility_id?: string | null
          gender_policy?: string
          id?: string
          name: string
          specialty?: string | null
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string
          created_at?: string
          facility_id?: string | null
          gender_policy?: string
          id?: string
          name?: string
          specialty?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ward_units_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
        ]
      }
      wards: {
        Row: {
          active: boolean
          code: string
          created_at: string
          department: string | null
          facility_id: string | null
          floor: string | null
          gender_policy: string
          id: string
          name: string
          updated_at: string
        }
        Insert: {
          active?: boolean
          code: string
          created_at?: string
          department?: string | null
          facility_id?: string | null
          floor?: string | null
          gender_policy?: string
          id?: string
          name: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string
          created_at?: string
          department?: string | null
          facility_id?: string | null
          floor?: string | null
          gender_policy?: string
          id?: string
          name?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "wards_facility_id_fkey"
            columns: ["facility_id"]
            isOneToOne: false
            referencedRelation: "healthcare_facilities"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      acknowledge_imaging_result: {
        Args: { _result_id: string }
        Returns: boolean
      }
      acknowledge_lab_result: { Args: { _result_id: string }; Returns: boolean }
      acknowledge_medication_alert: {
        Args: { _record_id: string }
        Returns: Json
      }
      acknowledge_nursing_handover: {
        Args: { _handover_id: string }
        Returns: Json
      }
      acknowledge_vital_alert: {
        Args: { _alert_id: string }
        Returns: {
          acknowledged_at: string | null
          acknowledged_by: string | null
          alert_type: string
          created_at: string
          details: string | null
          facility_id: string | null
          id: string
          patient_id: string
          severity: string
          vital_signs_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "vital_alerts"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      activate_patient_visit_coverage: {
        Args: {
          _appointment_id?: string
          _authorization_date?: string
          _patient_id: string
          _source: string
        }
        Returns: {
          activated_by: string
          activation_source: string
          active: boolean
          appointment_id: string | null
          authorization_date: string
          coverage_type: string
          created_at: string
          facility_id: string | null
          id: string
          patient_id: string
          payer_name: string
        }
        SetofOptions: {
          from: "*"
          to: "patient_visit_authorizations"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      add_encounter_diagnosis: {
        Args: { _diagnosis: string; _encounter_id: string; _icd_code?: string }
        Returns: {
          ai_suggested: boolean | null
          created_at: string
          diagnosis: string
          encounter_id: string
          facility_id: string | null
          icd_code: string | null
          id: string
          is_principal: boolean | null
          is_provisional: boolean | null
          notes: string | null
          patient_id: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "diagnoses"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      add_global_medication_to_facility: {
        Args: { _catalogue_id: string }
        Returns: {
          active: boolean
          barcode: string | null
          batch_number: string | null
          brand_name: string | null
          catalogue_id: string | null
          created_at: string
          drug_name: string
          expiry_date: string | null
          facility_id: string | null
          form: string | null
          generic_name: string | null
          id: string
          nhis_claim_amount: number
          nhis_patient_price: number
          pack_size: number | null
          reorder_level: number | null
          stock_quantity: number
          strength: string | null
          supplier: string | null
          unit_price: number | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "pharmacy_inventory"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      adjust_invoice_item_tariff: {
        Args: {
          _adjusted_unit_price: number
          _adjustment_type?: string
          _invoice_item_id: string
          _reason: string
        }
        Returns: Json
      }
      admit_encounter_workflow: {
        Args: {
          _emergency_override?: boolean
          _encounter_id: string
          _reason?: string
          _ward?: string
        }
        Returns: Json
      }
      amend_encounter_workflow: {
        Args: {
          _clerking_notes?: string
          _encounter_id: string
          _principal_diagnosis?: string
          _reason?: string
          _symptoms?: string
          _treatment_plan?: string
        }
        Returns: Json
      }
      approve_diagnosis_import_batch: {
        Args: { p_batch_id: string }
        Returns: Json
      }
      approve_facility_data_sharing_agreement: {
        Args: { _agreement_id: string }
        Returns: undefined
      }
      approve_lab_result: { Args: { _lab_result_id: string }; Returns: Json }
      approve_legacy_migration_batch: {
        Args: { _batch_id: string }
        Returns: Json
      }
      assert_patient_facility_context: {
        Args: { _patient_id: string }
        Returns: string
      }
      assert_patient_facility_read_context: {
        Args: { _patient_id: string }
        Returns: string
      }
      assign_unattributed_pharmacy_inventory: {
        Args: { _item_id: string; _reason: string }
        Returns: {
          active: boolean
          barcode: string | null
          batch_number: string | null
          brand_name: string | null
          catalogue_id: string | null
          created_at: string
          drug_name: string
          expiry_date: string | null
          facility_id: string | null
          form: string | null
          generic_name: string | null
          id: string
          nhis_claim_amount: number
          nhis_patient_price: number
          pack_size: number | null
          reorder_level: number | null
          stock_quantity: number
          strength: string | null
          supplier: string | null
          unit_price: number | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "pharmacy_inventory"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      assign_ward_bed: {
        Args: { _admission_id?: string; _bed_id: string; _patient_id: string }
        Returns: Json
      }
      assign_ward_unit_facility: {
        Args: { _facility_id: string; _ward_id: string }
        Returns: string
      }
      can_edit_patient_record: { Args: { _user_id: string }; Returns: boolean }
      cancel_service_order: {
        Args: { _reason?: string; _service_order_id: string }
        Returns: {
          amount: number
          approved_at: string | null
          approved_by: string | null
          cancelled_at: string | null
          completed_at: string | null
          created_at: string
          created_by: string | null
          department: string
          encounter_id: string | null
          facility_id: string | null
          id: string
          invoice_id: string | null
          invoice_item_id: string | null
          notes: string | null
          order_type: string
          patient_id: string
          payment_required: boolean
          quantity: number
          related_entity_id: string | null
          release_reason: string | null
          released_at: string | null
          released_by: string | null
          requested_by: string | null
          service_code: string | null
          service_name: string
          started_at: string | null
          status: string
          unit_price: number
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "service_orders"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      claim_appointment: {
        Args: { _appointment_id: string }
        Returns: {
          appointment_date: string | null
          attending_officer_id: string | null
          claimed_at: string | null
          completed_at: string | null
          consultation_type: string
          created_at: string
          department: string | null
          duration_minutes: number | null
          facility_id: string | null
          id: string
          notes: string | null
          patient_id: string
          practitioner_id: string | null
          provider_id: string | null
          reason: string | null
          scheduled_at: string
          started_at: string | null
          status: string
          treatment_notes: string | null
          treatment_status: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "appointments"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      claim_notification_queue: {
        Args: { _limit?: number }
        Returns: {
          attempts: number
          channel: string
          created_at: string
          delivered_at: string | null
          event_name: string | null
          facility_id: string | null
          fallback_channels: Json
          id: string
          idempotency_key: string | null
          last_attempt_at: string | null
          last_error: string | null
          locale: string | null
          max_attempts: number
          next_attempt_at: string
          payload: Json
          priority: string
          scheduled_for: string | null
          status: string
          template_key: string | null
          tenant_id: string | null
          timezone: string | null
          updated_at: string
          user_id: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "notification_queue"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      collect_lab_sample: { Args: { _lab_order_id: string }; Returns: Json }
      complete_ai_report_request: {
        Args: { _content?: string; _error?: string; _request_id: string }
        Returns: {
          completed_at: string | null
          content: string | null
          created_at: string
          error: string | null
          facility_id: string | null
          id: string
          patient_id: string
          report_type: string
          requested_by: string | null
          status: string
        }
        SetofOptions: {
          from: "*"
          to: "ai_report_requests"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      complete_encounter_workflow: {
        Args: { _encounter_id: string }
        Returns: {
          admission_id: string | null
          appointment_id: string | null
          assessment: string | null
          chief_complaint: string | null
          clerking_notes: string | null
          completed_at: string | null
          created_at: string
          encounter_type: string | null
          facility_id: string | null
          follow_up_date: string | null
          history_of_present_illness: string | null
          id: string
          locked_at: string | null
          patient_id: string
          plan: string | null
          practitioner_id: string | null
          principal_diagnosis: string | null
          provider_id: string | null
          started_at: string | null
          status: string
          submitted_at: string | null
          submitted_by: string | null
          symptoms: string | null
          treatment_plan: string | null
          updated_at: string
          version_no: number
        }
        SetofOptions: {
          from: "*"
          to: "encounters"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      complete_imaging_order: {
        Args: {
          _imaging_order_id: string
          _impression: string
          _report: string
        }
        Returns: {
          acknowledged_at: string | null
          acknowledged_by: string | null
          amount: number
          body_site: string | null
          clinical_indication: string | null
          completed_at: string | null
          created_at: string
          encounter_id: string | null
          facility_id: string | null
          id: string
          impression: string | null
          modality: string
          patient_id: string
          performed_by: string | null
          priority: string
          report: string | null
          requested_by: string | null
          service_order_id: string | null
          started_at: string | null
          status: string
          study_name: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "imaging_orders"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      complete_outside_lab_ai_analysis: {
        Args: { _analysis: string; _document_id: string }
        Returns: {
          ai_analysis: string | null
          ai_analyzed_at: string | null
          created_at: string
          document_type: string
          facility_id: string | null
          id: string
          mime_type: string | null
          notes: string | null
          patient_id: string
          reviewed_at: string | null
          reviewed_by: string | null
          storage_path: string
          title: string | null
          uploaded_by: string | null
        }
        SetofOptions: {
          from: "*"
          to: "outside_lab_documents"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      complete_service_order: {
        Args: { _service_order_id: string }
        Returns: {
          amount: number
          approved_at: string | null
          approved_by: string | null
          cancelled_at: string | null
          completed_at: string | null
          created_at: string
          created_by: string | null
          department: string
          encounter_id: string | null
          facility_id: string | null
          id: string
          invoice_id: string | null
          invoice_item_id: string | null
          notes: string | null
          order_type: string
          patient_id: string
          payment_required: boolean
          quantity: number
          related_entity_id: string | null
          release_reason: string | null
          released_at: string | null
          released_by: string | null
          requested_by: string | null
          service_code: string | null
          service_name: string
          started_at: string | null
          status: string
          unit_price: number
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "service_orders"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      confirm_pharmacy_dispense: { Args: { _plan_id: string }; Returns: Json }
      confirm_pharmacy_pos_sale: {
        Args: { _sale_id: string }
        Returns: {
          created_at: string
          created_by: string | null
          dispensed_at: string | null
          dispensed_by: string | null
          facility_id: string | null
          id: string
          inventory_id: string | null
          medication: string
          patient_id: string | null
          quantity: number
          service_order_id: string | null
          status: string
          total_amount: number | null
          unit_price: number
        }
        SetofOptions: {
          from: "*"
          to: "pharmacy_pos_sales"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_admission_workflow: {
        Args: {
          _bed?: string
          _patient_id: string
          _reason?: string
          _ward: string
        }
        Returns: Json
      }
      create_ai_clinical_session: {
        Args: {
          _input_snapshot: Json
          _patient_id: string
          _provenance?: Json
          _specialist: string
        }
        Returns: {
          created_at: string
          created_by: string
          facility_id: string | null
          id: string
          input_snapshot: Json
          model_name: string | null
          model_provider: string | null
          output_snapshot: Json | null
          patient_id: string
          provenance: Json
          review_status: string
          reviewed_at: string | null
          reviewed_by: string | null
          specialist: string
          status: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "ai_clinical_sessions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_ai_protocol_draft: {
        Args: {
          _case_count: number
          _diagnosis: string
          _icd_code?: string
          _protocol_text: string
        }
        Returns: {
          approved_at: string | null
          approved_by: string | null
          case_count: number | null
          created_at: string
          diagnosis: string
          icd_code: string | null
          id: string
          protocol_text: string
          status: string
        }
        SetofOptions: {
          from: "*"
          to: "ai_protocols"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_ai_report_request: {
        Args: { _patient_id: string; _report_type?: string }
        Returns: {
          completed_at: string | null
          content: string | null
          created_at: string
          error: string | null
          facility_id: string | null
          id: string
          patient_id: string
          report_type: string
          requested_by: string | null
          status: string
        }
        SetofOptions: {
          from: "*"
          to: "ai_report_requests"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_anesthetic_assessment: {
        Args: {
          _airway_assessment?: string
          _allergies?: string
          _asa_class?: string
          _cardiovascular?: string
          _cleared_for_procedure?: boolean
          _conclusions?: string
          _fasting_status?: string
          _medications?: string
          _patient_id: string
          _respiratory?: string
        }
        Returns: {
          airway_assessment: string | null
          allergies: string | null
          asa_class: string | null
          cardiovascular: string | null
          cleared_by: string | null
          cleared_for_procedure: boolean | null
          conclusions: string | null
          created_at: string
          encounter_id: string | null
          facility_id: string | null
          fasting_status: string | null
          id: string
          medications: string | null
          patient_id: string
          questionnaire: Json | null
          respiratory: string | null
          status: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "anesthetic_assessments"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_appointment_workflow:
        | {
            Args: {
              _department: string
              _patient_id: string
              _reason?: string
              _scheduled_at: string
            }
            Returns: {
              appointment_date: string | null
              attending_officer_id: string | null
              claimed_at: string | null
              completed_at: string | null
              consultation_type: string
              created_at: string
              department: string | null
              duration_minutes: number | null
              facility_id: string | null
              id: string
              notes: string | null
              patient_id: string
              practitioner_id: string | null
              provider_id: string | null
              reason: string | null
              scheduled_at: string
              started_at: string | null
              status: string
              treatment_notes: string | null
              treatment_status: string
              updated_at: string
            }
            SetofOptions: {
              from: "*"
              to: "appointments"
              isOneToOne: true
              isSetofReturn: false
            }
          }
        | {
            Args: {
              _consultation_type: string
              _department: string
              _patient_id: string
              _practitioner_id?: string
              _reason: string
              _scheduled_at: string
            }
            Returns: {
              appointment_date: string | null
              attending_officer_id: string | null
              claimed_at: string | null
              completed_at: string | null
              consultation_type: string
              created_at: string
              department: string | null
              duration_minutes: number | null
              facility_id: string | null
              id: string
              notes: string | null
              patient_id: string
              practitioner_id: string | null
              provider_id: string | null
              reason: string | null
              scheduled_at: string
              started_at: string | null
              status: string
              treatment_notes: string | null
              treatment_status: string
              updated_at: string
            }
            SetofOptions: {
              from: "*"
              to: "appointments"
              isOneToOne: true
              isSetofReturn: false
            }
          }
      create_care_transition_workflow: {
        Args: {
          _destination?: string
          _follow_up_date?: string
          _follow_up_required?: boolean
          _instructions?: string
          _medications_reconciled?: boolean
          _patient_id: string
          _summary?: string
          _transition_type: string
        }
        Returns: Json
      }
      create_data_migration_batch: {
        Args: {
          _entity_type: string
          _file_name?: string
          _source_format?: string
          _source_system: string
          _source_version?: string
          _total_rows?: number
        }
        Returns: string
      }
      create_dental_record: {
        Args: {
          _examination: string
          _patient_id: string
          _procedures_performed: string
          _treatment_plan: string
        }
        Returns: string
      }
      create_discharge_insurance_claim: {
        Args: {
          _member_number?: string
          _notification_id: string
          _payer_name?: string
        }
        Returns: Json
      }
      create_emergency_case: {
        Args: {
          _acuity?: string
          _arrival_mode?: string
          _assigned_officer?: string
          _chief_complaint: string
          _patient_id: string
        }
        Returns: string
      }
      create_encounter_imaging_order: {
        Args: {
          _body_site?: string
          _clinical_indication?: string
          _encounter_id: string
          _modality: string
          _priority?: string
          _study_name: string
        }
        Returns: Json
      }
      create_encounter_lab_order: {
        Args: {
          _clinical_notes?: string
          _encounter_id: string
          _priority?: string
          _test_code: string
        }
        Returns: Json
      }
      create_encounter_prescription:
        | {
            Args: {
              _dosage?: string
              _duration?: string
              _encounter_id: string
              _frequency?: string
              _medication: string
            }
            Returns: {
              computed_quantity: number | null
              created_at: string
              diagnosis_id: string | null
              dispensed_at: string | null
              dispensed_by: string | null
              dispensed_quantity: number
              dosage: string | null
              duration: string | null
              encounter_id: string | null
              facility_id: string | null
              frequency: string | null
              id: string
              instructions: string | null
              medication: string
              medication_name: string | null
              patient_id: string
              prescribed_by: string | null
              route: string | null
              status: string
              updated_at: string
            }
            SetofOptions: {
              from: "*"
              to: "prescriptions"
              isOneToOne: true
              isSetofReturn: false
            }
          }
        | {
            Args: {
              _diagnosis_id?: string
              _dosage?: string
              _duration?: string
              _encounter_id: string
              _frequency?: string
              _medication: string
            }
            Returns: {
              computed_quantity: number | null
              created_at: string
              diagnosis_id: string | null
              dispensed_at: string | null
              dispensed_by: string | null
              dispensed_quantity: number
              dosage: string | null
              duration: string | null
              encounter_id: string | null
              facility_id: string | null
              frequency: string | null
              id: string
              instructions: string | null
              medication: string
              medication_name: string | null
              patient_id: string
              prescribed_by: string | null
              route: string | null
              status: string
              updated_at: string
            }
            SetofOptions: {
              from: "*"
              to: "prescriptions"
              isOneToOne: true
              isSetofReturn: false
            }
          }
      create_encounter_service_order: {
        Args: { _encounter_id: string; _notes?: string; _service_code: string }
        Returns: Json
      }
      create_encounter_workflow: {
        Args: {
          _clerking_notes?: string
          _patient_id: string
          _symptoms?: string
        }
        Returns: {
          admission_id: string | null
          appointment_id: string | null
          assessment: string | null
          chief_complaint: string | null
          clerking_notes: string | null
          completed_at: string | null
          created_at: string
          encounter_type: string | null
          facility_id: string | null
          follow_up_date: string | null
          history_of_present_illness: string | null
          id: string
          locked_at: string | null
          patient_id: string
          plan: string | null
          practitioner_id: string | null
          principal_diagnosis: string | null
          provider_id: string | null
          started_at: string | null
          status: string
          submitted_at: string | null
          submitted_by: string | null
          symptoms: string | null
          treatment_plan: string | null
          updated_at: string
          version_no: number
        }
        SetofOptions: {
          from: "*"
          to: "encounters"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_facility_data_sharing_agreement: {
        Args: {
          _effective_from: string
          _effective_to: string
          _facility_a_id: string
          _facility_b_id: string
          _purpose: string
          _scopes: string[]
        }
        Returns: string
      }
      create_fertility_cycle_workflow: {
        Args: {
          _cycle_type?: string
          _partner_name?: string
          _patient_id: string
          _protocol?: string
          _start_date?: string
        }
        Returns: {
          assigned_specialist: string | null
          created_at: string
          cycle_number: number | null
          cycle_type: string
          expected_retrieval_date: string | null
          expected_transfer_date: string | null
          facility_id: string | null
          id: string
          notes: string | null
          outcome: string | null
          partner_name: string | null
          patient_id: string
          protocol: string | null
          start_date: string
          status: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "fertility_cycles"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_icd_code_workflow: {
        Args: {
          _category?: string
          _code: string
          _description: string
          _version?: string
        }
        Returns: {
          category: string | null
          code: string
          created_at: string
          description: string
          id: string
          version: string
        }
        SetofOptions: {
          from: "*"
          to: "icd_codes"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_imaging_order_with_payment_gate: {
        Args: {
          _amount?: number
          _body_site?: string
          _clinical_indication?: string
          _encounter_id?: string
          _modality?: string
          _patient_id: string
          _priority?: string
          _study_name?: string
        }
        Returns: Json
      }
      create_inpatient_review: {
        Args: {
          _admission_id: string
          _assessment?: string
          _findings?: string
          _plan?: string
          _review_type?: string
        }
        Returns: {
          admission_id: string
          created_at: string
          facility_id: string | null
          findings: string | null
          id: string
          patient_id: string
          plan: string | null
          review_type: string
          reviewed_by: string | null
          reviewer_name: string | null
          reviewer_role: string | null
          seen_at: string
        }
        SetofOptions: {
          from: "*"
          to: "inpatient_reviews"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_insurance_claim_draft: {
        Args: {
          _amount_claimed?: number
          _invoice_id?: string
          _member_number?: string
          _patient_id: string
          _payer_name?: string
        }
        Returns: {
          amount_approved: number | null
          amount_claimed: number
          amount_paid: number
          claim_number: string | null
          created_at: string
          facility_id: string | null
          id: string
          insurance_company_id: string | null
          invoice_id: string
          member_number: string | null
          notes: string | null
          patient_id: string
          payer_name: string
          policy_number: string | null
          provider: string
          rejection_reason: string | null
          resolved_at: string | null
          service_from: string | null
          service_to: string | null
          status: string
          submitted_at: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "insurance_claims"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_insurance_company: {
        Args: {
          _address?: string
          _code: string
          _contact_person?: string
          _email?: string
          _name: string
          _phone?: string
          _short_name?: string
        }
        Returns: string
      }
      create_insurance_service_tariff: {
        Args: {
          _base_charge: number
          _effective_from: string
          _effective_to?: string
          _insurance_charge: number
          _insurance_company_id: string
          _service_code: string
          _service_name: string
          _top_up: number
        }
        Returns: {
          active: boolean
          base_charge: number
          created_at: string
          created_by: string | null
          effective_from: string
          effective_to: string | null
          id: string
          insurance_charge: number
          insurance_company_id: string | null
          metadata: Json
          payer_name: string
          service_code: string
          service_name: string | null
          top_up: number
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "insurance_service_tariffs"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_lab_order_with_catalogue_atomic: {
        Args: {
          _amount: number
          _catalogue_id: string
          _clinical_notes: string
          _encounter_id: string
          _patient_id: string
          _priority: string
          _test_category: string
          _test_name: string
        }
        Returns: Json
      }
      create_lab_order_with_payment_gate: {
        Args: {
          _amount?: number
          _clinical_notes?: string
          _encounter_id?: string
          _patient_id: string
          _priority?: string
          _test_category?: string
          _test_name: string
        }
        Returns: Json
      }
      create_lab_test_catalogue_item: {
        Args: {
          _category: string
          _default_charge: number
          _reference_high: number
          _reference_low: number
          _reference_text: string
          _specimen_type: string
          _test_code: string
          _test_name: string
          _turnaround_minutes: number
          _unit: string
        }
        Returns: {
          active: boolean
          category: string | null
          created_at: string
          default_charge: number
          id: string
          parameters: Json
          reference_high: number | null
          reference_low: number | null
          reference_text: string | null
          sample_quantity: string | null
          specimen_type: string | null
          test_code: string
          test_name: string
          turnaround_minutes: number | null
          unit: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "lab_test_catalogue"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_lab_test_catalogue_item_with_parameters: {
        Args: {
          _category: string
          _default_charge: number
          _parameters?: Json
          _reference_high: number
          _reference_low: number
          _reference_text: string
          _specimen_type: string
          _test_code: string
          _test_name: string
          _turnaround_minutes: number
          _unit: string
        }
        Returns: {
          active: boolean
          category: string | null
          created_at: string
          default_charge: number
          id: string
          parameters: Json
          reference_high: number | null
          reference_low: number | null
          reference_text: string | null
          sample_quantity: string | null
          specimen_type: string | null
          test_code: string
          test_name: string
          turnaround_minutes: number | null
          unit: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "lab_test_catalogue"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_lab_test_catalogue_item_with_sample_quantity: {
        Args: {
          _category: string
          _default_charge: number
          _parameters?: Json
          _reference_high: number
          _reference_low: number
          _reference_text: string
          _sample_quantity: string
          _specimen_type: string
          _test_code: string
          _test_name: string
          _turnaround_minutes: number
          _unit: string
        }
        Returns: {
          active: boolean
          category: string | null
          created_at: string
          default_charge: number
          id: string
          parameters: Json
          reference_high: number | null
          reference_low: number | null
          reference_text: string | null
          sample_quantity: string | null
          specimen_type: string | null
          test_code: string
          test_name: string
          turnaround_minutes: number | null
          unit: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "lab_test_catalogue"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_maternity_episode_workflow: {
        Args: {
          _edd?: string
          _gravida?: number
          _lmp?: string
          _notes?: string
          _para?: number
          _patient_id: string
          _risk_level?: string
          _status?: string
        }
        Returns: Json
      }
      create_meal_plan_workflow: {
        Args: {
          _patient_id: string
          _plan_type: string
          _restrictions?: string
        }
        Returns: {
          active: boolean | null
          ai_recommendations: string | null
          created_at: string
          created_by: string | null
          description: string | null
          facility_id: string | null
          id: string
          meals_per_day: number | null
          patient_id: string
          plan_type: string
          restrictions: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "meal_plans"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_nursing_care_plan: {
        Args: {
          _admission_id?: string
          _encounter_id?: string
          _goal: string
          _interventions: string
          _patient_id: string
          _priority?: string
          _problem: string
        }
        Returns: string
      }
      create_nursing_note: {
        Args: {
          _admission_id?: string
          _assessment?: string
          _encounter_id?: string
          _evaluation?: string
          _intervention?: string
          _note_text: string
          _note_type?: string
          _patient_id: string
        }
        Returns: {
          admission_id: string | null
          assessment: string | null
          author_id: string
          created_at: string
          encounter_id: string | null
          evaluation: string | null
          facility_id: string | null
          id: string
          intervention: string | null
          note_text: string
          note_type: string
          patient_id: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "nursing_notes"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_nursing_shift_handover: {
        Args: {
          _clinical_summary: string
          _escalation_required?: boolean
          _patient_id: string
          _pending_tasks?: string
          _safety_concerns?: string
          _shift_label: string
          _ward_id?: string
        }
        Returns: string
      }
      create_ophthalmology_exam: {
        Args: {
          _color_vision: string
          _fundus_notes: string
          _intraocular_pressure: number
          _keratometry: string
          _patient_id: string
          _refraction: string
          _visual_acuity: string
        }
        Returns: string
      }
      create_patient_admission: {
        Args: {
          _bed?: string
          _patient_id: string
          _reason: string
          _ward?: string
        }
        Returns: Json
      }
      create_patient_appointment: {
        Args: {
          _department?: string
          _patient_id: string
          _reason?: string
          _scheduled_at: string
        }
        Returns: Json
      }
      create_patient_document: {
        Args: {
          _document_type: string
          _file_url: string
          _notes?: string
          _patient_id: string
        }
        Returns: Json
      }
      create_patient_referral_workflow: {
        Args: {
          _clinical_summary?: string
          _destination: string
          _patient_id: string
          _reason?: string
          _specialty?: string
          _urgency?: string
        }
        Returns: Json
      }
      create_pharmacy_inventory_item: {
        Args: {
          _batch_number: string
          _brand_name: string
          _category?: string
          _drug_name: string
          _expiry_date: string
          _form: string
          _generic_name: string
          _reorder_level: number
          _stock_quantity: number
          _strength: string
          _supplier: string
          _unit_price: number
        }
        Returns: {
          active: boolean
          barcode: string | null
          batch_number: string | null
          brand_name: string | null
          catalogue_id: string | null
          created_at: string
          drug_name: string
          expiry_date: string | null
          facility_id: string | null
          form: string | null
          generic_name: string | null
          id: string
          nhis_claim_amount: number
          nhis_patient_price: number
          pack_size: number | null
          reorder_level: number | null
          stock_quantity: number
          strength: string | null
          supplier: string | null
          unit_price: number | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "pharmacy_inventory"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_pharmacy_pos_sale: {
        Args: { _inventory_id: string; _patient_id: string; _quantity: number }
        Returns: {
          created_at: string
          created_by: string | null
          dispensed_at: string | null
          dispensed_by: string | null
          facility_id: string | null
          id: string
          inventory_id: string | null
          medication: string
          patient_id: string | null
          quantity: number
          service_order_id: string | null
          status: string
          total_amount: number | null
          unit_price: number
        }
        SetofOptions: {
          from: "*"
          to: "pharmacy_pos_sales"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_procedure_note: {
        Args: {
          _charge_amount: number
          _complications: string
          _findings: string
          _indication: string
          _patient_id: string
          _post_op_plan: string
          _procedure_name: string
          _service_order_id: string
          _technique: string
          _template_used: string
        }
        Returns: string
      }
      create_reports_facility: {
        Args: {
          _dhims2_uid?: string
          _district?: string
          _facility_code?: string
          _facility_type?: string
          _name: string
          _region?: string
        }
        Returns: {
          created_at: string
          created_by: string | null
          dhims2_uid: string | null
          district: string | null
          facility_code: string | null
          facility_type: string
          id: string
          is_active: boolean
          name: string
          region: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "healthcare_facilities"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_service_catalogue_item: {
        Args: {
          _amount: number
          _currency?: string
          _department: string
          _service_code: string
          _service_name: string
          _unit: string
        }
        Returns: {
          active: boolean
          amount: number
          created_at: string
          currency: string
          department: string
          effective_from: string | null
          effective_to: string | null
          id: string
          is_session_package: boolean
          metadata: Json
          package_session_count: number | null
          service_code: string
          service_name: string
          source_standard: string | null
          specialty_category: string | null
          unit: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "service_tariffs"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_service_order: {
        Args: {
          _amount?: number
          _department?: string
          _encounter_id?: string
          _invoice_id?: string
          _invoice_item_id?: string
          _notes?: string
          _order_type?: string
          _patient_id: string
          _related_entity_id?: string
          _requested_by?: string
          _service_code?: string
          _service_name?: string
        }
        Returns: Json
      }
      create_staff_shift_assignment: {
        Args: {
          _department: string
          _ends_at: string
          _shift_label: string
          _starts_at: string
          _user_id: string
        }
        Returns: string
      }
      create_theatre_case: {
        Args: {
          _anesthetist_id?: string
          _encounter_id?: string
          _patient_id: string
          _procedure_name: string
          _scheduled_start?: string
          _surgeon_id?: string
          _theatre_name?: string
          _urgency?: string
        }
        Returns: string
      }
      create_transfusion_record: {
        Args: {
          _blood_group?: string
          _blood_product: string
          _consent_confirmed?: boolean
          _encounter_id?: string
          _patient_id: string
          _unit_identifier: string
        }
        Returns: string
      }
      create_treatment_template_workflow: {
        Args: {
          _description?: string
          _diagnosis?: string
          _name: string
          _prescriptions?: Json
        }
        Returns: {
          created_at: string
          created_by: string | null
          description: string | null
          diagnosis: string | null
          icd_code: string | null
          id: string
          is_ai_generated: boolean | null
          lab_orders: Json | null
          name: string
          notes: string | null
          prescriptions: Json | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "treatment_templates"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_walk_in_billable_service: {
        Args: {
          _notes?: string
          _patient_id: string
          _quantity?: number
          _service_code: string
        }
        Returns: string
      }
      create_ward_bed: {
        Args: { _bed_number: string; _ward_id: string }
        Returns: string
      }
      create_ward_unit:
        | {
            Args: {
              _code: string
              _gender_policy: string
              _name: string
              _specialty: string
            }
            Returns: string
          }
        | {
            Args: {
              _code: string
              _facility_id: string
              _gender_policy: string
              _name: string
              _specialty: string
            }
            Returns: string
          }
      create_workflow_notification: {
        Args: {
          _category?: string
          _link?: string
          _message?: string
          _metadata?: Json
          _recipient_role?: string
          _recipient_user_id?: string
          _related_entity_id?: string
          _related_patient_id?: string
          _severity?: string
          _title?: string
        }
        Returns: string
      }
      current_user_can_edit_patient_record: { Args: never; Returns: boolean }
      current_user_facility_id: { Args: never; Returns: string }
      current_user_has_catalogue_create_permission: {
        Args: { _permission: string }
        Returns: boolean
      }
      current_user_has_facility_access: {
        Args: { _facility_id: string }
        Returns: boolean
      }
      current_user_has_role: {
        Args: { _role: Database["public"]["Enums"]["app_role"] }
        Returns: boolean
      }
      current_user_is_clinical_staff: { Args: never; Returns: boolean }
      discharge_admission_workflow: {
        Args: { _admission_id: string; _summary?: string }
        Returns: Json
      }
      end_video_session: { Args: { _session_id: string }; Returns: boolean }
      enqueue_external_notification_channels: {
        Args: { _notification_id: string }
        Returns: number
      }
      enqueue_notification_v2: {
        Args: {
          _channels?: Json
          _event_name: string
          _facility_id?: string
          _idempotency_key?: string
          _locale?: string
          _payload: Json
          _priority?: string
          _scheduled_for?: string
          _template_key: string
          _tenant_id?: string
          _timezone?: string
          _user_id: string
        }
        Returns: string
      }
      ensure_encounter_facility_attribution: {
        Args: { _encounter_id: string }
        Returns: {
          admission_id: string | null
          appointment_id: string | null
          assessment: string | null
          chief_complaint: string | null
          clerking_notes: string | null
          completed_at: string | null
          created_at: string
          encounter_type: string | null
          facility_id: string | null
          follow_up_date: string | null
          history_of_present_illness: string | null
          id: string
          locked_at: string | null
          patient_id: string
          plan: string | null
          practitioner_id: string | null
          principal_diagnosis: string | null
          provider_id: string | null
          started_at: string | null
          status: string
          submitted_at: string | null
          submitted_by: string | null
          symptoms: string | null
          treatment_plan: string | null
          updated_at: string
          version_no: number
        }
        SetofOptions: {
          from: "*"
          to: "encounters"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      ensure_notification_preferences: {
        Args: { _user_id: string }
        Returns: {
          category_preferences: Json
          channel_preferences: Json
          consent_ip: unknown
          consent_version: string | null
          consented_at: string | null
          id: string
          locale: string
          pause_non_critical: boolean
          quiet_hours_end: string
          quiet_hours_start: string
          tenant_id: string | null
          timezone: string
          updated_at: string
          user_id: string
        }
        SetofOptions: {
          from: "*"
          to: "user_notification_preferences"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      enter_lab_result: {
        Args: {
          _interpretation?: string
          _is_abnormal?: boolean
          _lab_order_id: string
          _numeric_value?: number
          _result_text: string
        }
        Returns: string
      }
      enter_lab_result_structured: {
        Args: {
          _interpretation?: string
          _is_abnormal?: boolean
          _lab_order_id: string
          _parameter_results: Json
          _result_text?: string
        }
        Returns: string
      }
      erase_notification_history: {
        Args: { _user_id?: string }
        Returns: number
      }
      fail_ai_report_request: {
        Args: { _error?: string; _request_id: string }
        Returns: {
          completed_at: string | null
          content: string | null
          created_at: string
          error: string | null
          facility_id: string | null
          id: string
          patient_id: string
          report_type: string
          requested_by: string | null
          status: string
        }
        SetofOptions: {
          from: "*"
          to: "ai_report_requests"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      find_legacy_patient_candidates: {
        Args: { _record_id: string }
        Returns: {
          date_of_birth: string
          first_name: string
          last_name: string
          match_confidence: number
          match_method: string
          patient_code: string
          patient_id: string
        }[]
      }
      find_pharmacy_alternatives: {
        Args: { _medication: string; _strength?: string }
        Returns: {
          brand_name: string
          category: string
          drug_name: string
          form: string
          generic_name: string
          id: string
          stock_quantity: number
          strength: string
          supplier: string
          unit_price: number
        }[]
      }
      generate_invoice_number: { Args: never; Returns: string }
      generate_payroll_items: {
        Args: { _payroll_period_id: string }
        Returns: number
      }
      get_active_inpatient_billing_queue: {
        Args: { _limit?: number }
        Returns: {
          admission_id: string
          admitted_at: string
          bed: string
          discharged_at: string
          patient_id: string
          status: string
          ward: string
        }[]
      }
      get_admission_workspace: { Args: { _limit?: number }; Returns: Json }
      get_ai_case_memory_for_diagnosis: {
        Args: { _diagnosis: string; _limit?: number }
        Returns: {
          age_group: string
          created_at: string
          diagnosis: string
          gender: string
          icd_code: string
          id: string
          outcome: string
          outcome_notes: string
          prescriptions: Json
          symptoms: string
        }[]
      }
      get_ai_clinical_context: { Args: { _patient_id: string }; Returns: Json }
      get_ai_report_requests: {
        Args: { _limit?: number; _patient_id?: string }
        Returns: {
          completed_at: string
          content: string
          created_at: string
          error: string
          id: string
          patient_id: string
          report_type: string
          requested_by: string
          status: string
        }[]
      }
      get_appointment_clinician: {
        Args: never
        Returns: {
          clinician_role: string
          department: string
          first_name: string
          id: string
          last_name: string
          specialization: string
        }[]
      }
      get_appointment_clinicians: {
        Args: never
        Returns: {
          clinician_role: string
          department: string
          first_name: string
          id: string
          last_name: string
          specialization: string
        }[]
      }
      get_appointment_schedulable_patients: {
        Args: { _limit?: number }
        Returns: {
          first_name: string
          id: string
          last_name: string
          patient_code: string
        }[]
      }
      get_appointment_worklist: {
        Args: { _limit?: number }
        Returns: {
          attending_officer_id: string
          consultation_type: string
          department: string
          id: string
          patient_code: string
          patient_first_name: string
          patient_id: string
          patient_last_name: string
          practitioner_id: string
          practitioner_name: string
          reason: string
          scheduled_at: string
          status: string
          treatment_notes: string
          treatment_status: string
        }[]
      }
      get_attending_patient_history: {
        Args: { _current_encounter_id?: string; _patient_id: string }
        Returns: Json
      }
      get_billing_window: {
        Args: { _at?: string; _patient_id: string }
        Returns: Json
      }
      get_billing_workspace_summary: {
        Args: never
        Returns: {
          cash_collected_today: number
          currency: string
          nhis_pending_count: number
        }[]
      }
      get_bmi_category: { Args: { _bmi: number }; Returns: string }
      get_canteen_active_patient_orders: {
        Args: never
        Returns: {
          current_diagnoses: Json
          dietary_restrictions: string
          meal_type: string
          order_id: string
          order_status: string
          patient_code: string
          patient_id: string
          patient_name: string
          plan_type: string
          scheduled_for: string
          underlying_conditions: string
        }[]
      }
      get_clinician_imaging_results: {
        Args: { _limit?: number }
        Returns: Json
      }
      get_clinician_lab_results: { Args: { _limit?: number }; Returns: Json }
      get_current_facility_context: {
        Args: never
        Returns: {
          currency: string
          dhims2_uid: string
          district: string
          facility_code: string
          facility_id: string
          facility_name: string
          facility_type: string
          region: string
          timezone: string
        }[]
      }
      get_current_user_roles: {
        Args: never
        Returns: Database["public"]["Enums"]["app_role"][]
      }
      get_department_queue: {
        Args: { _department: string; _limit?: number }
        Returns: {
          amount: number
          department: string
          id: string
          patient_code: string
          patient_first_name: string
          patient_id: string
          patient_last_name: string
          queued_at: string
          service_name: string
          service_order_id: string
          service_order_status: string
          status: string
        }[]
      }
      get_emergency_workspace: { Args: { _limit?: number }; Returns: Json }
      get_encounter_clinical_context: {
        Args: { _encounter_id?: string; _patient_id: string }
        Returns: Json
      }
      get_encounter_workflow_workspace: {
        Args: never
        Returns: {
          admission_id: string
          created_at: string
          encounter_id: string
          patient_code: string
          patient_id: string
          patient_name: string
          status: string
          version_no: number
        }[]
      }
      get_encounter_worklist: {
        Args: { _limit?: number }
        Returns: {
          admission_id: string
          clerking_notes: string
          created_at: string
          encounter_type: string
          id: string
          patient_id: string
          practitioner_id: string
          principal_diagnosis: string
          status: string
          submitted_at: string
          symptoms: string
          treatment_plan: string
          updated_at: string
          version_no: number
        }[]
      }
      get_hms_test_runtime_status: {
        Args: never
        Returns: {
          enabled: boolean
          environment: string
          updated_at: string
        }[]
      }
      get_imaging_workspace: { Args: { _limit?: number }; Returns: Json }
      get_inpatient_discharge_bill: {
        Args: { _admission_id: string; _patient_id: string; _to?: string }
        Returns: {
          admission_id: string
          amount: number
          category: string
          created_at: string
          department: string
          description: string
          invoice_id: string
          invoice_item_id: string
          outstanding_amount: number
          paid_amount: number
          patient_id: string
          quantity: number
          service_order_id: string
          service_order_status: string
          source_id: string
          source_type: string
          unit_price: number
        }[]
      }
      get_insurance_claim_reconciliation_context: {
        Args: { _claim_ids?: string[] }
        Returns: {
          claim_id: string
          insurance_company_id: string
          insurer_code: string
          insurer_name: string
          invoice_id: string
          invoice_insurance_total: number
        }[]
      }
      get_it_support_system_logs: {
        Args: { _limit?: number; _module?: string; _severity?: string }
        Returns: {
          action: string
          created_at: string
          entity_type: string
          id: string
          module: string
          severity: string
        }[]
      }
      get_lab_result_attachments: {
        Args: { _lab_order_ids: string[] }
        Returns: Json
      }
      get_laboratory_specimens: { Args: { _limit?: number }; Returns: Json }
      get_laboratory_test_groups: {
        Args: { _include_inactive?: boolean }
        Returns: Json
      }
      get_laboratory_workspace: { Args: { _limit?: number }; Returns: Json }
      get_legacy_patient_candidates: {
        Args: { _row_id: string }
        Returns: Json
      }
      get_maternity_workspace: {
        Args: { _episode_id?: string; _limit?: number }
        Returns: Json
      }
      get_missing_billing_tariffs: {
        Args: { _patient_id?: string }
        Returns: {
          amount: number
          created_at: string
          department: string
          description: string
          invoice_id: string
          invoice_item_id: string
          patient_id: string
          quantity: number
          service_code: string
          service_order_id: string
          service_order_status: string
          unit_price: number
        }[]
      }
      get_my_permissions: {
        Args: never
        Returns: {
          permission_key: string
        }[]
      }
      get_operational_workspace: {
        Args: { _limit?: number; _module: string }
        Returns: Json
      }
      get_patient_admission_history: {
        Args: { _patient_id: string }
        Returns: Json
      }
      get_patient_appointments: {
        Args: { _limit?: number; _patient_id?: string }
        Returns: Json
      }
      get_patient_bmi_context: {
        Args: { _patient_id: string }
        Returns: {
          bmi: number
          category: string
          height_m: number
          recorded_at: string
          weight_kg: number
        }[]
      }
      get_patient_care_continuity: {
        Args: { _patient_id: string }
        Returns: Json
      }
      get_patient_current_treatment_snapshot: {
        Args: { _admission_id: string; _patient_id: string }
        Returns: Json
      }
      get_patient_directory: {
        Args: { _limit?: number; _query?: string }
        Returns: {
          first_name: string
          ghana_card_number: string
          id: string
          insurance_number: string
          insurance_provider: string
          last_name: string
          membership_expires_at: string
          membership_type: string
          patient_code: string
          phone: string
          status: string
        }[]
      }
      get_patient_directory_record: {
        Args: { _patient_id: string }
        Returns: {
          first_name: string
          ghana_card_number: string
          id: string
          insurance_number: string
          insurance_provider: string
          last_name: string
          patient_code: string
          phone: string
          status: string
        }[]
      }
      get_patient_hub_clinical_snapshot: {
        Args: { _patient_id: string }
        Returns: Json
      }
      get_patient_invoice_summary: { Args: { _limit?: number }; Returns: Json }
      get_patient_invoices: {
        Args: { _limit?: number; _patient_id: string }
        Returns: Json
      }
      get_patient_outside_lab_documents: {
        Args: { _limit?: number }
        Returns: Json
      }
      get_patient_portal_identity: {
        Args: never
        Returns: {
          date_of_birth: string
          email: string
          facility_id: string
          first_name: string
          id: string
          last_name: string
          patient_code: string
          phone: string
        }[]
      }
      get_patient_portal_meal_menus: {
        Args: { _service_date: string }
        Returns: Json
      }
      get_patient_portal_medical_record: {
        Args: { _patient_id: string }
        Returns: Json
      }
      get_patient_portal_video_sessions: {
        Args: { _limit?: number }
        Returns: Json
      }
      get_patient_profile_for_user: {
        Args: { _patient_id: string }
        Returns: {
          address: string
          allergies: string
          blood_group: string
          chronic_conditions: string
          city: string
          date_of_birth: string
          email: string
          emergency_contact_name: string
          emergency_contact_phone: string
          emergency_contact_relation: string
          first_name: string
          gender: string
          genotype: string
          ghana_card_number: string
          id: string
          insurance_company_id: string
          insurance_expiry: string
          insurance_group_number: string
          insurance_number: string
          insurance_provider: string
          last_name: string
          patient_code: string
          phone: string
          status: string
        }[]
      }
      get_patient_telemedicine_clinicians: {
        Args: { _scheduled_at?: string }
        Returns: {
          clinician_role: string
          department: string
          first_name: string
          id: string
          is_on_duty: boolean
          last_name: string
          specialization: string
        }[]
      }
      get_patient_telemedicine_clinicians_legacy: {
        Args: never
        Returns: {
          clinician_role: string
          department: string
          first_name: string
          id: string
          last_name: string
          specialization: string
        }[]
      }
      get_patient_triage_history: {
        Args: { _limit?: number; _patient_id: string }
        Returns: {
          bmi: number
          diastolic: number
          id: string
          oxygen_saturation: number
          patient_id: string
          recorded_at: string
          systolic: number
          temperature: number
        }[]
      }
      get_pending_review_appointments: { Args: never; Returns: Json }
      get_pending_specialist_referrals: { Args: never; Returns: Json }
      get_pharmacy_workspace: { Args: { _limit?: number }; Returns: Json }
      get_role_dashboard_summary: { Args: never; Returns: Json }
      get_role_dashboard_summary_for_role: {
        Args: { _requested_role?: string }
        Returns: Json
      }
      get_staff_signature_for_report: {
        Args: { _user_id: string }
        Returns: string
      }
      get_user_facilities: {
        Args: never
        Returns: {
          facility_code: string
          facility_id: string
          facility_name: string
          facility_type: string
          is_active: boolean
        }[]
      }
      get_ward_management_workspace: {
        Args: { _limit?: number }
        Returns: Json
      }
      get_workflow_notifications: {
        Args: { _limit?: number }
        Returns: {
          category: string
          created_at: string
          id: string
          is_read: boolean
          link: string
          message: string
          metadata: Json
          recipient_role: string
          recipient_user_id: string
          related_entity_id: string
          related_patient_id: string
          severity: string
          title: string
        }[]
      }
      grant_service_order_override: {
        Args: { _reason: string; _service_order_id: string }
        Returns: {
          approved_at: string | null
          approved_by: string
          created_at: string
          department: string
          facility_id: string | null
          id: string
          overridden_by: string
          patient_id: string
          reason: string
          related_entity_id: string | null
          service_order_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "billing_overrides"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      has_active_patient_visit_coverage: {
        Args: { _patient_id: string }
        Returns: boolean
      }
      has_facility_access: {
        Args: { _facility_id: string; _user_id: string }
        Returns: boolean
      }
      has_role: {
        Args: {
          _role: Database["public"]["Enums"]["app_role"]
          _user_id: string
        }
        Returns: boolean
      }
      hms_current_user_is_test_user: { Args: never; Returns: boolean }
      hms_test_facility_id: { Args: never; Returns: string }
      hms_test_mode_enabled: { Args: never; Returns: boolean }
      import_approved_diagnosis_batch: {
        Args: { p_batch_id: string }
        Returns: Json
      }
      import_legacy_ward: {
        Args: { _facility_id: string; _legacy_ward_id: string }
        Returns: string
      }
      import_service_tariffs: {
        Args: { _rows: Json; _source_standard: string }
        Returns: number
      }
      import_stg_diagnoses: {
        Args: { _rows: Json; _source_version: string; _standard_code: string }
        Returns: number
      }
      initialize_facility_notification_onboarding: {
        Args: { _facility_id: string }
        Returns: {
          branding: Json
          compliance_policy: Json
          consent_policy: Json
          created_at: string
          created_by: string | null
          default_locale: string
          default_timezone: string
          delivery_policy: Json
          deployment_secret_namespace: string | null
          enabled: boolean
          enabled_channels: Json
          environment: string
          facility_id: string
          id: string
          kill_switch: boolean
          onboarding_status: string
          operational_contacts: Json
          production_approved_at: string | null
          production_approved_by: string | null
          provider_config: Json
          provider_defaults: Json
          quiet_hours_end: string
          quiet_hours_start: string
          rollout_percent: number
          sender_config: Json
          updated_at: string
          updated_by: string | null
          verified_at: string | null
          verified_by: string | null
          webhook_config: Json
          webhook_policy: Json
        }
        SetofOptions: {
          from: "*"
          to: "facility_notification_config"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      is_clinical_staff: { Args: { _user_id: string }; Returns: boolean }
      list_facilities_for_superadmin_context: {
        Args: never
        Returns: {
          dhims2_uid: string
          district: string
          facility_code: string
          facility_type: string
          id: string
          is_active: boolean
          name: string
          region: string
        }[]
      }
      list_insurance_companies: {
        Args: { _include_inactive?: boolean }
        Returns: {
          active: boolean
          address: string | null
          code: string
          contact_person: string | null
          created_at: string
          created_by: string | null
          email: string | null
          id: string
          metadata: Json
          name: string
          phone: string | null
          short_name: string | null
          updated_at: string
        }[]
        SetofOptions: {
          from: "*"
          to: "insurance_companies"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      list_unresolved_clinical_facility_records: {
        Args: { _limit?: number }
        Returns: {
          created_at: string
          entity_id: string
          entity_type: string
          metadata: Json
          patient_id: string
        }[]
      }
      list_unresolved_remaining_clinical_facility_records: {
        Args: { _limit?: number }
        Returns: {
          created_at: string
          entity_id: string
          entity_type: string
          metadata: Json
          patient_id: string
        }[]
      }
      lock_overdue_medication_slots: { Args: never; Returns: number }
      mark_billing_items_billed: {
        Args: { _invoice_id: string; _item_ids: string[] }
        Returns: Json
      }
      mark_facility_notification_production_ready: {
        Args: { _facility_id: string }
        Returns: {
          branding: Json
          compliance_policy: Json
          consent_policy: Json
          created_at: string
          created_by: string | null
          default_locale: string
          default_timezone: string
          delivery_policy: Json
          deployment_secret_namespace: string | null
          enabled: boolean
          enabled_channels: Json
          environment: string
          facility_id: string
          id: string
          kill_switch: boolean
          onboarding_status: string
          operational_contacts: Json
          production_approved_at: string | null
          production_approved_by: string | null
          provider_config: Json
          provider_defaults: Json
          quiet_hours_end: string
          quiet_hours_start: string
          rollout_percent: number
          sender_config: Json
          updated_at: string
          updated_by: string | null
          verified_at: string | null
          verified_by: string | null
          webhook_config: Json
          webhook_policy: Json
        }
        SetofOptions: {
          from: "*"
          to: "facility_notification_config"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      mark_meal_order_delivered: {
        Args: { _order_id: string }
        Returns: {
          created_at: string
          delivered_at: string | null
          facility_id: string | null
          id: string
          meal_plan_id: string | null
          meal_type: string
          notes: string | null
          patient_id: string
          scheduled_for: string
          status: string
        }
        SetofOptions: {
          from: "*"
          to: "meal_orders"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      mark_notification_read: {
        Args: { _notification_id: string }
        Returns: boolean
      }
      mark_report_submissions_submitted: {
        Args: { _submission_ids: string[] }
        Returns: number
      }
      mark_service_order_in_progress: {
        Args: { _service_order_id: string }
        Returns: {
          amount: number
          approved_at: string | null
          approved_by: string | null
          cancelled_at: string | null
          completed_at: string | null
          created_at: string
          created_by: string | null
          department: string
          encounter_id: string | null
          facility_id: string | null
          id: string
          invoice_id: string | null
          invoice_item_id: string | null
          notes: string | null
          order_type: string
          patient_id: string
          payment_required: boolean
          quantity: number
          related_entity_id: string | null
          release_reason: string | null
          released_at: string | null
          released_by: string | null
          requested_by: string | null
          service_code: string | null
          service_name: string
          started_at: string | null
          status: string
          unit_price: number
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "service_orders"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      mark_video_session_paid: {
        Args: { _session_id: string }
        Returns: boolean
      }
      medication_frequency_interval: {
        Args: { _frequency: string }
        Returns: string
      }
      notification_feature_enabled: {
        Args: { _key: string; _user_id?: string }
        Returns: boolean
      }
      notify_due_medications: { Args: never; Returns: number }
      patient_can_read_meal_menus: { Args: never; Returns: boolean }
      patient_coverage_details: {
        Args: { _patient_id: string }
        Returns: {
          coverage_type: string
          payer_name: string
        }[]
      }
      patient_has_active_admission: { Args: never; Returns: boolean }
      pay_selected_invoice_items: {
        Args: {
          _invoice_id: string
          _item_ids: string[]
          _method: string
          _reference?: string
        }
        Returns: Json
      }
      platform_create_facility: {
        Args: {
          _dhims2_uid?: string
          _district?: string
          _facility_code?: string
          _facility_type?: string
          _name: string
          _region?: string
        }
        Returns: {
          created_at: string
          created_by: string | null
          dhims2_uid: string | null
          district: string | null
          facility_code: string | null
          facility_type: string
          id: string
          is_active: boolean
          name: string
          region: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "healthcare_facilities"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      platform_list_facilities: {
        Args: never
        Returns: {
          created_at: string
          district: string
          facility_code: string
          facility_type: string
          id: string
          is_active: boolean
          name: string
          region: string
        }[]
      }
      platform_list_facilitys: {
        Args: never
        Returns: {
          created_at: string
          district: string
          facility_code: string
          facility_type: string
          id: string
          is_active: boolean
          name: string
          region: string
        }[]
      }
      platform_list_user_facility_memberships: {
        Args: { _user_id: string }
        Returns: {
          access_scope: string
          facility_code: string
          facility_id: string
          facility_is_active: boolean
          facility_name: string
          is_active_context: boolean
          membership_is_active: boolean
        }[]
      }
      platform_set_facility_active: {
        Args: { _facility_id: string; _is_active: boolean }
        Returns: {
          created_at: string
          created_by: string | null
          dhims2_uid: string | null
          district: string | null
          facility_code: string | null
          facility_type: string
          id: string
          is_active: boolean
          name: string
          region: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "healthcare_facilities"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      platform_set_user_active_facility: {
        Args: { _facility_id: string; _user_id: string }
        Returns: Json
      }
      platform_set_user_facility_membership: {
        Args: {
          _access_scope?: string
          _facility_id: string
          _is_active?: boolean
          _user_id: string
        }
        Returns: Json
      }
      platform_set_user_role: {
        Args: {
          _role: Database["public"]["Enums"]["app_role"]
          _user_id: string
        }
        Returns: Json
      }
      platform_update_facility: {
        Args: {
          _dhims2_uid: string
          _district: string
          _facility_code: string
          _facility_id: string
          _facility_type: string
          _name: string
          _region: string
        }
        Returns: {
          created_at: string
          created_by: string | null
          dhims2_uid: string | null
          district: string | null
          facility_code: string | null
          facility_type: string
          id: string
          is_active: boolean
          name: string
          region: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "healthcare_facilities"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      prepare_patient_billable_items: {
        Args: { _from?: string; _patient_id: string; _to?: string }
        Returns: {
          amount: number
          category: string
          department: string
          description: string
          invoice_id: string
          invoice_item_id: string
          outstanding_amount: number
          paid_amount: number
          quantity: number
          service_order_id: string
          service_order_status: string
          source_id: string
          source_type: string
          unit_price: number
        }[]
      }
      prepare_pharmacy_dispensing: {
        Args: {
          _alternative_reason?: string
          _inventory_id: string
          _notes?: string
          _prescription_id: string
          _quantity: number
        }
        Returns: Json
      }
      prescription_duration_end: {
        Args: { _created_at: string; _duration: string }
        Returns: string
      }
      promote_legacy_migration_batch: {
        Args: { _batch_id: string }
        Returns: Json
      }
      reconcile_clinical_facility_record: {
        Args: {
          _entity_id: string
          _entity_type: string
          _reason: string
          _target_facility_id: string
        }
        Returns: Json
      }
      reconcile_discharge_billing: {
        Args: { _notification_id: string }
        Returns: Json
      }
      reconcile_extended_clinical_facility_record: {
        Args: {
          _entity_id: string
          _entity_type: string
          _reason: string
          _target_facility_id: string
        }
        Returns: Json
      }
      reconcile_insurance_claim_to_invoice: {
        Args: { _claim_id: string }
        Returns: {
          amount_approved: number | null
          amount_claimed: number
          amount_paid: number
          claim_number: string | null
          created_at: string
          facility_id: string | null
          id: string
          insurance_company_id: string | null
          invoice_id: string
          member_number: string | null
          notes: string | null
          patient_id: string
          payer_name: string
          policy_number: string | null
          provider: string
          rejection_reason: string | null
          resolved_at: string | null
          service_from: string | null
          service_to: string | null
          status: string
          submitted_at: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "insurance_claims"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      reconcile_legacy_migration_row: {
        Args: {
          _match_confidence?: number
          _match_method?: string
          _patient_id: string
          _row_id: string
        }
        Returns: Json
      }
      reconcile_legacy_record_patient: {
        Args: { _method?: string; _patient_id: string; _record_id: string }
        Returns: boolean
      }
      reconcile_remaining_clinical_facility_record: {
        Args: {
          _entity_id: string
          _entity_type: string
          _reason: string
          _target_facility_id: string
        }
        Returns: undefined
      }
      record_ai_clinical_event: {
        Args: { _event_type: string; _metadata?: Json; _session_id: string }
        Returns: string
      }
      record_fertility_monitoring_workflow: {
        Args: {
          _cycle_day?: number
          _cycle_id: string
          _endometrial_thickness?: number
          _estradiol?: number
          _follicle_count_left?: number
          _follicle_count_right?: number
          _fsh?: number
          _lh?: number
          _medication_adjustments?: string
          _progesterone?: number
          _visit_date: string
        }
        Returns: {
          created_at: string
          cycle_day: number | null
          cycle_id: string
          endometrial_thickness: number | null
          estradiol: number | null
          follicle_count_left: number | null
          follicle_count_right: number | null
          fsh: number | null
          id: string
          lh: number | null
          medication_adjustments: string | null
          notes: string | null
          progesterone: number | null
          recorded_by: string | null
          visit_date: string
        }
        SetofOptions: {
          from: "*"
          to: "fertility_monitoring"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      record_maternity_observation_workflow: {
        Args: {
          _blood_pressure?: string
          _cervical_dilation_cm?: number
          _contractions_per_10_min?: number
          _effacement_percent?: number
          _episode_id: string
          _fetal_heart_rate?: number
          _membrane_status?: string
          _notes?: string
          _pulse?: number
          _station?: string
          _temperature?: number
        }
        Returns: Json
      }
      record_notification_consent: {
        Args: {
          _category: string
          _channel: string
          _consent_ip?: unknown
          _consent_version: string
          _granted: boolean
          _user_agent?: string
        }
        Returns: string
      }
      record_patient_deposit: {
        Args: { _amount: number; _patient_id: string; _reference?: string }
        Returns: {
          amount: number
          created_at: string
          created_by: string
          entry_type: string
          facility_id: string | null
          id: string
          invoice_id: string | null
          notes: string | null
          patient_id: string
          payment_id: string | null
          reference: string | null
        }
        SetofOptions: {
          from: "*"
          to: "patient_account_credits"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      record_system_audit: {
        Args: {
          _action: string
          _entity_id?: string
          _entity_type?: string
          _metadata?: Json
          _module: string
          _severity?: string
        }
        Returns: string
      }
      record_transfusion_event: {
        Args: {
          _reaction_notes: string
          _reaction_observed: boolean
          _record_id: string
          _status: string
        }
        Returns: Json
      }
      record_triage_assessment: {
        Args: {
          _clinical_notes?: string
          _consciousness?: string
          _diastolic?: number
          _heart_rate?: number
          _height_m?: number
          _oxygen_saturation?: number
          _pain_score?: number
          _patient_id: string
          _presenting_complaint?: string
          _priority?: string
          _respiratory_rate?: number
          _systolic?: number
          _temperature?: number
          _weight_kg?: number
        }
        Returns: string
      }
      record_triage_assessment_offline: {
        Args: {
          _clinical_notes?: string
          _consciousness?: string
          _diastolic?: number
          _heart_rate?: number
          _height_m?: number
          _id: string
          _oxygen_saturation?: number
          _pain_score?: number
          _patient_id: string
          _presenting_complaint?: string
          _priority?: string
          _respiratory_rate?: number
          _systolic?: number
          _temperature?: number
          _weight_kg?: number
        }
        Returns: Json
      }
      recover_stale_report_run: {
        Args: { _run_id: string; _stale_after_minutes?: number }
        Returns: {
          bundle_manifest: Json
          completed_at: string | null
          created_at: string
          created_by: string | null
          facility_id: string
          failed_count: number
          frequency: string
          id: string
          parameters: Json
          period_end: string
          period_start: string
          reporting_period_end: string | null
          reporting_period_start: string | null
          started_at: string | null
          status: string
          success_count: number
          total_reports: number
          updated_at: string
          warning_count: number
        }
        SetofOptions: {
          from: "*"
          to: "report_generation_runs"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      register_notification_device: {
        Args: {
          _device_label?: string
          _platform: string
          _provider: string
          _token: string
        }
        Returns: string
      }
      register_outside_lab_document: {
        Args: {
          _document_type: string
          _mime_type?: string
          _patient_id: string
          _storage_path: string
          _title: string
        }
        Returns: {
          ai_analysis: string | null
          ai_analyzed_at: string | null
          created_at: string
          document_type: string
          facility_id: string | null
          id: string
          mime_type: string | null
          notes: string | null
          patient_id: string
          reviewed_at: string | null
          reviewed_by: string | null
          storage_path: string
          title: string | null
          uploaded_by: string | null
        }
        SetofOptions: {
          from: "*"
          to: "outside_lab_documents"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      register_patient_workflow: {
        Args: { _patient: Json }
        Returns: {
          address: string | null
          allergies: string | null
          blood_group: string | null
          chronic_conditions: string | null
          city: string | null
          created_at: string
          created_by: string | null
          date_of_birth: string | null
          email: string | null
          emergency_contact_name: string | null
          emergency_contact_phone: string | null
          emergency_contact_relation: string | null
          facility_id: string | null
          first_name: string
          gender: string | null
          genotype: string | null
          ghana_card_number: string | null
          id: string
          insurance_company_id: string | null
          insurance_expiry: string | null
          insurance_group_number: string | null
          insurance_number: string | null
          insurance_provider: string | null
          last_name: string
          membership_expires_at: string | null
          membership_type: string
          partner_company: string | null
          partner_member_number: string | null
          patient_code: string | null
          phone: string | null
          registration_reason: string | null
          status: string
          updated_at: string
          user_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "patients"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      reject_lab_specimen: {
        Args: { _reason: string; _specimen_id: string }
        Returns: Json
      }
      release_service_order: {
        Args: { _reason?: string; _service_order_id: string }
        Returns: {
          amount: number
          approved_at: string | null
          approved_by: string | null
          cancelled_at: string | null
          completed_at: string | null
          created_at: string
          created_by: string | null
          department: string
          encounter_id: string | null
          facility_id: string | null
          id: string
          invoice_id: string | null
          invoice_item_id: string | null
          notes: string | null
          order_type: string
          patient_id: string
          payment_required: boolean
          quantity: number
          related_entity_id: string | null
          release_reason: string | null
          released_at: string | null
          released_by: string | null
          requested_by: string | null
          service_code: string | null
          service_name: string
          started_at: string | null
          status: string
          unit_price: number
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "service_orders"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      release_ward_bed: {
        Args: { _bed_id: string; _notes?: string }
        Returns: Json
      }
      remove_encounter_diagnosis: {
        Args: { _diagnosis_id: string }
        Returns: undefined
      }
      reopen_medication_administration: {
        Args: { _reason: string; _record_id: string }
        Returns: boolean
      }
      reopen_own_document: {
        Args: { _entity_id: string; _entity_type: string }
        Returns: Json
      }
      replace_role_permissions: {
        Args: {
          _permission_keys: string[]
          _role: Database["public"]["Enums"]["app_role"]
        }
        Returns: boolean
      }
      request_ai_clinical_analysis: {
        Args: { _session_id: string }
        Returns: {
          created_at: string
          created_by: string
          facility_id: string | null
          id: string
          input_snapshot: Json
          model_name: string | null
          model_provider: string | null
          output_snapshot: Json | null
          patient_id: string
          provenance: Json
          review_status: string
          reviewed_at: string | null
          reviewed_by: string | null
          specialist: string
          status: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "ai_clinical_sessions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      request_patient_telemedicine_session: {
        Args: { _clinician_id: string; _reason: string; _scheduled_at: string }
        Returns: string
      }
      review_ophthalmology_exam: {
        Args: { _advisory?: Json; _exam_id: string }
        Returns: boolean
      }
      revoke_facility_data_sharing_agreement: {
        Args: { _agreement_id: string; _reason: string }
        Returns: undefined
      }
      revoke_notification_device: { Args: { _token: string }; Returns: boolean }
      save_canteen_menu: {
        Args: {
          _available_from?: string
          _available_until?: string
          _items?: Json
          _meal_period: string
          _notes?: string
          _publish?: boolean
          _service_date: string
        }
        Returns: Json
      }
      save_encounter_clerking: {
        Args: {
          _assessment?: string
          _chief_complaint?: string
          _clerking_notes?: string
          _encounter_id: string
          _follow_up_date?: string
          _history_of_present_illness?: string
          _plan?: string
          _symptoms?: string
          _treatment_plan?: string
        }
        Returns: {
          admission_id: string | null
          appointment_id: string | null
          assessment: string | null
          chief_complaint: string | null
          clerking_notes: string | null
          completed_at: string | null
          created_at: string
          encounter_type: string | null
          facility_id: string | null
          follow_up_date: string | null
          history_of_present_illness: string | null
          id: string
          locked_at: string | null
          patient_id: string
          plan: string | null
          practitioner_id: string | null
          principal_diagnosis: string | null
          provider_id: string | null
          started_at: string | null
          status: string
          submitted_at: string | null
          submitted_by: string | null
          symptoms: string | null
          treatment_plan: string | null
          updated_at: string
          version_no: number
        }
        SetofOptions: {
          from: "*"
          to: "encounters"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      save_encounter_draft: {
        Args: {
          _clerking_notes?: string
          _encounter_id: string
          _symptoms?: string
          _treatment_plan?: string
        }
        Returns: {
          admission_id: string | null
          appointment_id: string | null
          assessment: string | null
          chief_complaint: string | null
          clerking_notes: string | null
          completed_at: string | null
          created_at: string
          encounter_type: string | null
          facility_id: string | null
          follow_up_date: string | null
          history_of_present_illness: string | null
          id: string
          locked_at: string | null
          patient_id: string
          plan: string | null
          practitioner_id: string | null
          principal_diagnosis: string | null
          provider_id: string | null
          started_at: string | null
          status: string
          submitted_at: string | null
          submitted_by: string | null
          symptoms: string | null
          treatment_plan: string | null
          updated_at: string
          version_no: number
        }
        SetofOptions: {
          from: "*"
          to: "encounters"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      save_laboratory_test_group: {
        Args: {
          _default_charge: number
          _description: string
          _group_code: string
          _group_id: string
          _group_name: string
          _is_active?: boolean
          _test_ids: string[]
        }
        Returns: Json
      }
      save_my_profile: {
        Args: {
          _department?: string
          _first_name: string
          _last_name: string
          _phone?: string
          _specialization?: string
        }
        Returns: {
          avatar_url: string | null
          created_at: string
          department: string | null
          email: string | null
          first_name: string | null
          full_name: string | null
          id: string
          last_name: string | null
          phone: string | null
          specialization: string | null
          title: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "profiles"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      schedule_medication_administration: {
        Args: {
          _dose?: string
          _due_window_minutes?: number
          _medication_name: string
          _notes?: string
          _patient_id: string
          _route?: string
          _scheduled_at?: string
        }
        Returns: string
      }
      schedule_patient_referral_workflow: {
        Args: { _referral_id: string }
        Returns: Json
      }
      schedule_video_session: {
        Args: { _patient_id: string; _provider?: string; _scheduled_at: string }
        Returns: string
      }
      search_clinical_diagnoses: {
        Args: { _facility_id?: string; _limit?: number; _query: string }
        Returns: {
          code: string
          display_name: string
          icd10_code: string
          source: string
          standard_name: string
        }[]
      }
      search_patient_directory: {
        Args: { _limit?: number; _query?: string }
        Returns: {
          first_name: string
          ghana_card_number: string
          id: string
          insurance_number: string
          insurance_provider: string
          last_name: string
          patient_code: string
          phone: string
          status: string
        }[]
      }
      seed_facility_reports: {
        Args: { _facility_id: string }
        Returns: undefined
      }
      set_active_facility_context: {
        Args: { _facility_id: string }
        Returns: {
          created_at: string
          created_by: string | null
          dhims2_uid: string | null
          district: string | null
          facility_code: string | null
          facility_type: string
          id: string
          is_active: boolean
          name: string
          region: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "healthcare_facilities"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      set_facility_notification_provider: {
        Args: {
          _account_reference?: string
          _channel: string
          _environment?: string
          _facility_id: string
          _metadata?: Json
          _provider: string
          _secret_reference?: string
          _sender_identity?: string
        }
        Returns: {
          account_reference: string | null
          channel: string
          created_at: string
          created_by: string | null
          environment: string
          facility_id: string
          id: string
          is_primary: boolean
          last_error: string | null
          last_verified_at: string | null
          metadata: Json
          priority: number
          provider: string
          secret_reference: string | null
          sender_identity: string | null
          status: string
          updated_at: string
          updated_by: string | null
        }
        SetofOptions: {
          from: "*"
          to: "facility_notification_provider_connections"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      set_facility_routing_mode: {
        Args: { _mode: string }
        Returns: {
          admission_financial_override_enabled: boolean
          allow_clinical_emergency_override: boolean
          allow_treatment_before_deposit: boolean
          created_at: string
          facility_name: string
          id: string
          payment_flow: string
          require_accounts_release_after_deposit: boolean
          routing_mode: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "facility_settings"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      set_hms_test_runtime: {
        Args: { _enabled: boolean; _reason: string }
        Returns: {
          enabled: boolean
          environment: string
          updated_at: string
        }[]
      }
      set_my_active_facility: {
        Args: { _facility_id: string }
        Returns: {
          created_at: string
          created_by: string | null
          dhims2_uid: string | null
          district: string | null
          facility_code: string | null
          facility_type: string
          id: string
          is_active: boolean
          name: string
          region: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "healthcare_facilities"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      set_patient_insurance_company: {
        Args: { _insurance_company_id: string; _patient_id: string }
        Returns: {
          address: string | null
          allergies: string | null
          blood_group: string | null
          chronic_conditions: string | null
          city: string | null
          created_at: string
          created_by: string | null
          date_of_birth: string | null
          email: string | null
          emergency_contact_name: string | null
          emergency_contact_phone: string | null
          emergency_contact_relation: string | null
          facility_id: string | null
          first_name: string
          gender: string | null
          genotype: string | null
          ghana_card_number: string | null
          id: string
          insurance_company_id: string | null
          insurance_expiry: string | null
          insurance_group_number: string | null
          insurance_number: string | null
          insurance_provider: string | null
          last_name: string
          membership_expires_at: string | null
          membership_type: string
          partner_company: string | null
          partner_member_number: string | null
          patient_code: string | null
          phone: string | null
          registration_reason: string | null
          status: string
          updated_at: string
          user_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "patients"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      set_patient_referral_appointment_date: {
        Args: { _appointment_date: string; _referral_id: string }
        Returns: Json
      }
      set_principal_diagnosis: {
        Args: { _diagnosis_id: string; _encounter_id: string }
        Returns: {
          ai_suggested: boolean | null
          created_at: string
          diagnosis: string
          encounter_id: string
          facility_id: string | null
          icd_code: string | null
          id: string
          is_principal: boolean | null
          is_provisional: boolean | null
          notes: string | null
          patient_id: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "diagnoses"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      set_staff_shift_assignment_active: {
        Args: { _active: boolean; _assignment_id: string }
        Returns: boolean
      }
      set_user_facility_context: {
        Args: { _facility_id: string; _user_id: string }
        Returns: undefined
      }
      set_ward_bed_status: {
        Args: { _bed_id: string; _notes?: string; _status: string }
        Returns: Json
      }
      stage_data_migration_rows: {
        Args: { _batch_id: string; _rows: Json }
        Returns: number
      }
      start_appointment_encounter: {
        Args: {
          _appointment_id: string
          _clerking_notes?: string
          _symptoms?: string
        }
        Returns: string
      }
      start_imaging_order: {
        Args: { _imaging_order_id: string }
        Returns: {
          acknowledged_at: string | null
          acknowledged_by: string | null
          amount: number
          body_site: string | null
          clinical_indication: string | null
          completed_at: string | null
          created_at: string
          encounter_id: string | null
          facility_id: string | null
          id: string
          impression: string | null
          modality: string
          patient_id: string
          performed_by: string | null
          priority: string
          report: string | null
          requested_by: string | null
          service_order_id: string | null
          started_at: string | null
          status: string
          study_name: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "imaging_orders"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      start_video_session: {
        Args: { _session_id: string }
        Returns: {
          id: string
          provider: string
          room_name: string
        }[]
      }
      submit_encounter_workflow: {
        Args: {
          _appointment_date?: string
          _encounter_id: string
          _referral_reason?: string
          _specialty?: string
        }
        Returns: Json
      }
      sync_encounter_clerking_followups: {
        Args: { _encounter_id: string }
        Returns: Json
      }
      sync_overdue_report_submissions: {
        Args: {
          _facility_id: string
          _period_end: string
          _period_start: string
        }
        Returns: number
      }
      transfer_inpatient_bed: {
        Args: {
          _admission_id: string
          _summary?: string
          _target_bed_id: string
        }
        Returns: Json
      }
      transfer_patient_ward_bed_workflow: {
        Args: {
          _admission_id: string
          _destination_bed_id: string
          _notes?: string
          _patient_id: string
          _reason?: string
          _source_bed_id?: string
        }
        Returns: Json
      }
      transition_ai_protocol: {
        Args: { _protocol_id: string; _status: string }
        Returns: {
          approved_at: string | null
          approved_by: string | null
          case_count: number | null
          created_at: string
          diagnosis: string
          icd_code: string | null
          id: string
          protocol_text: string
          status: string
        }
        SetofOptions: {
          from: "*"
          to: "ai_protocols"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      transition_emergency_case: {
        Args: { _case_id: string; _disposition?: string; _status: string }
        Returns: Json
      }
      transition_fertility_cycle_workflow: {
        Args: { _cycle_id: string; _outcome?: string; _status: string }
        Returns: {
          assigned_specialist: string | null
          created_at: string
          cycle_number: number | null
          cycle_type: string
          expected_retrieval_date: string | null
          expected_transfer_date: string | null
          facility_id: string | null
          id: string
          notes: string | null
          outcome: string | null
          partner_name: string | null
          patient_id: string
          protocol: string | null
          start_date: string
          status: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "fertility_cycles"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      transition_insurance_claim_canonical: {
        Args: {
          _amount_approved?: number
          _amount_paid?: number
          _claim_id: string
          _notes?: string
          _rejection_reason?: string
          _status: string
        }
        Returns: Json
      }
      transition_medication_administration: {
        Args: {
          _notes?: string
          _reason?: string
          _record_id: string
          _status: string
          _witnessed_by?: string
        }
        Returns: Json
      }
      transition_theatre_case: {
        Args: {
          _cancellation_reason: string
          _case_id: string
          _status: string
        }
        Returns: Json
      }
      update_appointment_workflow: {
        Args: {
          _appointment_id: string
          _department: string
          _reason: string
          _scheduled_at: string
          _treatment_notes?: string
          _treatment_status: string
        }
        Returns: {
          appointment_date: string | null
          attending_officer_id: string | null
          claimed_at: string | null
          completed_at: string | null
          consultation_type: string
          created_at: string
          department: string | null
          duration_minutes: number | null
          facility_id: string | null
          id: string
          notes: string | null
          patient_id: string
          practitioner_id: string | null
          provider_id: string | null
          reason: string | null
          scheduled_at: string
          started_at: string | null
          status: string
          treatment_notes: string | null
          treatment_status: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "appointments"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      update_encounter_draft_workflow: {
        Args: {
          _clerking_notes?: string
          _encounter_id: string
          _symptoms?: string
          _treatment_plan?: string
        }
        Returns: {
          admission_id: string | null
          appointment_id: string | null
          assessment: string | null
          chief_complaint: string | null
          clerking_notes: string | null
          completed_at: string | null
          created_at: string
          encounter_type: string | null
          facility_id: string | null
          follow_up_date: string | null
          history_of_present_illness: string | null
          id: string
          locked_at: string | null
          patient_id: string
          plan: string | null
          practitioner_id: string | null
          principal_diagnosis: string | null
          provider_id: string | null
          started_at: string | null
          status: string
          submitted_at: string | null
          submitted_by: string | null
          symptoms: string | null
          treatment_plan: string | null
          updated_at: string
          version_no: number
        }
        SetofOptions: {
          from: "*"
          to: "encounters"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      update_facility_configuration_workflow: {
        Args: { _changes: Json; _configuration_id: string }
        Returns: {
          address: string | null
          admission_financial_override_enabled: boolean
          allow_clinical_emergency_override: boolean
          allow_treatment_before_deposit: boolean
          appointment_buffer_minutes: number
          country: string
          created_at: string
          currency: string
          email: string | null
          facility_code: string | null
          facility_name: string
          id: string
          inherit_inpatient_diagnoses: boolean
          maintenance_mode: boolean
          notification_sound_enabled: boolean
          phone: string | null
          require_accounts_release_after_deposit: boolean
          require_principal_diagnosis_for_final: boolean
          routing_mode: string
          timezone: string
          updated_at: string
          updated_by: string | null
        }
        SetofOptions: {
          from: "*"
          to: "facility_configuration"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      update_facility_notification_configuration: {
        Args: { _changes: Json; _facility_id: string }
        Returns: {
          branding: Json
          compliance_policy: Json
          consent_policy: Json
          created_at: string
          created_by: string | null
          default_locale: string
          default_timezone: string
          delivery_policy: Json
          deployment_secret_namespace: string | null
          enabled: boolean
          enabled_channels: Json
          environment: string
          facility_id: string
          id: string
          kill_switch: boolean
          onboarding_status: string
          operational_contacts: Json
          production_approved_at: string | null
          production_approved_by: string | null
          provider_config: Json
          provider_defaults: Json
          quiet_hours_end: string
          quiet_hours_start: string
          rollout_percent: number
          sender_config: Json
          updated_at: string
          updated_by: string | null
          verified_at: string | null
          verified_by: string | null
          webhook_config: Json
          webhook_policy: Json
        }
        SetofOptions: {
          from: "*"
          to: "facility_notification_config"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      update_insurance_case: {
        Args: {
          _approved_amount: number
          _authorization: string
          _claim_amount: number
          _claim_status: string
          _eligibility: string
          _id: string
          _rejection_reason: string
        }
        Returns: {
          approved_amount: number
          authorization_number: string | null
          checked_by: string | null
          claim_amount: number
          claim_status: string
          created_at: string
          eligibility_checked_at: string | null
          eligibility_status: string
          facility_id: string | null
          id: string
          insurance_company_id: string | null
          patient_id: string
          payer_name: string
          policy_number: string | null
          rejection_reason: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "insurance_cases"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      update_insurance_claim_financials: {
        Args: {
          _amount_approved?: number
          _amount_paid?: number
          _claim_id: string
          _claim_number?: string
          _rejection_reason?: string
        }
        Returns: {
          amount_approved: number | null
          amount_claimed: number
          amount_paid: number
          claim_number: string | null
          created_at: string
          facility_id: string | null
          id: string
          insurance_company_id: string | null
          invoice_id: string
          member_number: string | null
          notes: string | null
          patient_id: string
          payer_name: string
          policy_number: string | null
          provider: string
          rejection_reason: string | null
          resolved_at: string | null
          service_from: string | null
          service_to: string | null
          status: string
          submitted_at: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "insurance_claims"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      update_insurance_company: {
        Args: {
          _active?: boolean
          _address?: string
          _code: string
          _contact_person?: string
          _email?: string
          _id: string
          _name: string
          _phone?: string
          _short_name?: string
        }
        Returns: boolean
      }
      update_insurance_service_tariff: {
        Args: {
          _active?: boolean
          _base_charge: number
          _effective_from: string
          _effective_to?: string
          _id: string
          _insurance_charge: number
          _top_up: number
        }
        Returns: {
          active: boolean
          base_charge: number
          created_at: string
          created_by: string | null
          effective_from: string
          effective_to: string | null
          id: string
          insurance_charge: number
          insurance_company_id: string | null
          metadata: Json
          payer_name: string
          service_code: string
          service_name: string | null
          top_up: number
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "insurance_service_tariffs"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      update_patient_workflow: {
        Args: { _changes: Json; _patient_id: string }
        Returns: {
          address: string | null
          allergies: string | null
          blood_group: string | null
          chronic_conditions: string | null
          city: string | null
          created_at: string
          created_by: string | null
          date_of_birth: string | null
          email: string | null
          emergency_contact_name: string | null
          emergency_contact_phone: string | null
          emergency_contact_relation: string | null
          facility_id: string | null
          first_name: string
          gender: string | null
          genotype: string | null
          ghana_card_number: string | null
          id: string
          insurance_company_id: string | null
          insurance_expiry: string | null
          insurance_group_number: string | null
          insurance_number: string | null
          insurance_provider: string | null
          last_name: string
          membership_expires_at: string | null
          membership_type: string
          partner_company: string | null
          partner_member_number: string | null
          patient_code: string | null
          phone: string | null
          registration_reason: string | null
          status: string
          updated_at: string
          user_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "patients"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      update_pharmacy_inventory_item: {
        Args: {
          _barcode?: string
          _batch_number: string
          _brand_name: string
          _category?: string
          _drug_name: string
          _expiry_date: string
          _form: string
          _generic_name: string
          _item_id: string
          _nhis_claim_amount?: number
          _nhis_patient_price?: number
          _reorder_level: number
          _stock_quantity: number
          _strength: string
          _supplier: string
          _unit_price: number
        }
        Returns: {
          active: boolean
          barcode: string | null
          batch_number: string | null
          brand_name: string | null
          catalogue_id: string | null
          created_at: string
          drug_name: string
          expiry_date: string | null
          facility_id: string | null
          form: string | null
          generic_name: string | null
          id: string
          nhis_claim_amount: number
          nhis_patient_price: number
          pack_size: number | null
          reorder_level: number | null
          stock_quantity: number
          strength: string | null
          supplier: string | null
          unit_price: number | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "pharmacy_inventory"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      update_service_catalogue_item: {
        Args: {
          _active?: boolean
          _amount: number
          _currency?: string
          _department: string
          _id: string
          _service_code: string
          _service_name: string
          _unit: string
        }
        Returns: {
          active: boolean
          amount: number
          created_at: string
          currency: string
          department: string
          effective_from: string | null
          effective_to: string | null
          id: string
          is_session_package: boolean
          metadata: Json
          package_session_count: number | null
          service_code: string
          service_name: string
          source_standard: string | null
          specialty_category: string | null
          unit: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "service_tariffs"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      update_ward_unit: {
        Args: {
          _active?: boolean
          _code: string
          _gender_policy?: string
          _name: string
          _specialty?: string
          _ward_id: string
        }
        Returns: string
      }
      upload_patient_document_metadata: {
        Args: {
          _document_type: string
          _file_name: string
          _file_size?: number
          _mime_type?: string
          _notes?: string
          _patient_id: string
          _storage_path: string
        }
        Returns: Json
      }
      upsert_my_staff_signature: {
        Args: { _signature_data: string }
        Returns: {
          created_at: string
          facility_id: string | null
          id: string
          signature_data: string
          updated_at: string
          user_id: string
        }
        SetofOptions: {
          from: "*"
          to: "staff_signatures"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      upsert_report_submission_tracking: {
        Args: {
          _data_snapshot?: Json
          _due_date: string
          _facility_id: string
          _period_end: string
          _period_start: string
          _report_id: string
        }
        Returns: {
          created_at: string
          data_snapshot: Json
          due_date: string
          facility_id: string
          id: string
          period_end: string
          period_start: string
          report_definition_id: string | null
          report_id: string
          reporting_period_end: string | null
          reporting_period_start: string | null
          status: string
          submission_reference: string | null
          submitted_at: string | null
          submitted_by: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "report_submissions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      validate_diagnosis_import_batch: {
        Args: { p_batch_id: string }
        Returns: Json
      }
      validate_legacy_migration_batch: {
        Args: { _batch_id: string }
        Returns: Json
      }
      validate_legacy_record: { Args: { _record_id: string }; Returns: Json }
      verify_facility_notification_provider: {
        Args: {
          _channel: string
          _environment?: string
          _error?: string
          _facility_id: string
          _verified?: boolean
        }
        Returns: {
          account_reference: string | null
          channel: string
          created_at: string
          created_by: string | null
          environment: string
          facility_id: string
          id: string
          is_primary: boolean
          last_error: string | null
          last_verified_at: string | null
          metadata: Json
          priority: number
          provider: string
          secret_reference: string | null
          sender_identity: string | null
          status: string
          updated_at: string
          updated_by: string | null
        }
        SetofOptions: {
          from: "*"
          to: "facility_notification_provider_connections"
          isOneToOne: true
          isSetofReturn: false
        }
      }
    }
    Enums: {
      app_role:
        | "admin"
        | "practitioner"
        | "nurse"
        | "midwife"
        | "lab_technician"
        | "pharmacist"
        | "accountant"
        | "front_desk"
        | "canteen"
        | "patient"
        | "specialist_nurse"
        | "radiologist"
        | "it_admin"
        | "radiology_technician"
        | "system_superuser"
        | "physiotherapist"
        | "ophthalmologist"
        | "dentist"
        | "dietician"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      app_role: [
        "admin",
        "practitioner",
        "nurse",
        "midwife",
        "lab_technician",
        "pharmacist",
        "accountant",
        "front_desk",
        "canteen",
        "patient",
        "specialist_nurse",
        "radiologist",
        "it_admin",
        "radiology_technician",
        "system_superuser",
        "physiotherapist",
        "ophthalmologist",
        "dentist",
        "dietician",
      ],
    },
  },
} as const
