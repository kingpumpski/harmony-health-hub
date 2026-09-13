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
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      admissions: {
        Row: {
          admitted_at: string
          admitted_by: string | null
          bed: string | null
          created_at: string
          discharge_summary: string | null
          discharged_at: string | null
          encounter_id: string | null
          id: string
          patient_id: string
          reason: string | null
          status: string
          updated_at: string
          ward: string | null
        }
        Insert: {
          admitted_at?: string
          admitted_by?: string | null
          bed?: string | null
          created_at?: string
          discharge_summary?: string | null
          discharged_at?: string | null
          encounter_id?: string | null
          id?: string
          patient_id: string
          reason?: string | null
          status?: string
          updated_at?: string
          ward?: string | null
        }
        Update: {
          admitted_at?: string
          admitted_by?: string | null
          bed?: string | null
          created_at?: string
          discharge_summary?: string | null
          discharged_at?: string | null
          encounter_id?: string | null
          id?: string
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
          gender?: string | null
          icd_code?: string | null
          id?: string
          outcome?: string | null
          outcome_notes?: string | null
          patient_id?: string | null
          prescriptions?: Json | null
          symptoms?: string | null
        }
        Relationships: []
      }
      ai_diagnosis_suggestions: {
        Row: {
          accepted: boolean | null
          created_at: string | null
          encounter_id: string | null
          id: string
          model_version: string | null
          reasoning: string | null
          suggested_icd: string | null
        }
        Insert: {
          accepted?: boolean | null
          created_at?: string | null
          encounter_id?: string | null
          id?: string
          model_version?: string | null
          reasoning?: string | null
          suggested_icd?: string | null
        }
        Update: {
          accepted?: boolean | null
          created_at?: string | null
          encounter_id?: string | null
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
          id?: string
          patient_id?: string
          report_type?: string
          requested_by?: string | null
          status?: string
        }
        Relationships: []
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
          fasting_status?: string | null
          id?: string
          medications?: string | null
          patient_id?: string
          questionnaire?: Json | null
          respiratory?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      appointments: {
        Row: {
          created_at: string
          department: string | null
          duration_minutes: number | null
          id: string
          notes: string | null
          patient_id: string
          practitioner_id: string | null
          reason: string | null
          scheduled_at: string
          status: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          department?: string | null
          duration_minutes?: number | null
          id?: string
          notes?: string | null
          patient_id: string
          practitioner_id?: string | null
          reason?: string | null
          scheduled_at: string
          status?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          department?: string | null
          duration_minutes?: number | null
          id?: string
          notes?: string | null
          patient_id?: string
          practitioner_id?: string | null
          reason?: string | null
          scheduled_at?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
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
      billing_overrides: {
        Row: {
          created_at: string
          department: string
          id: string
          overridden_by: string
          patient_id: string
          reason: string
          related_entity_id: string | null
        }
        Insert: {
          created_at?: string
          department: string
          id?: string
          overridden_by: string
          patient_id: string
          reason: string
          related_entity_id?: string | null
        }
        Update: {
          created_at?: string
          department?: string
          id?: string
          overridden_by?: string
          patient_id?: string
          reason?: string
          related_entity_id?: string | null
        }
        Relationships: []
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
      dental_records: {
        Row: {
          created_at: string
          encounter_id: string | null
          examination: string | null
          id: string
          patient_id: string
          performed_by: string | null
          procedures_performed: string | null
          tooth_chart: Json | null
          treatment_plan: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          encounter_id?: string | null
          examination?: string | null
          id?: string
          patient_id: string
          performed_by?: string | null
          procedures_performed?: string | null
          tooth_chart?: Json | null
          treatment_plan?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          encounter_id?: string | null
          examination?: string | null
          id?: string
          patient_id?: string
          performed_by?: string | null
          procedures_performed?: string | null
          tooth_chart?: Json | null
          treatment_plan?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      department_queues: {
        Row: {
          assigned_to: string | null
          completed_at: string | null
          created_at: string
          created_by: string | null
          department: string
          id: string
          patient_id: string
          payment_required: boolean
          payment_satisfied: boolean
          priority: string
          reason: string | null
          related_encounter_id: string | null
          related_invoice_id: string | null
          status: string
          updated_at: string
        }
        Insert: {
          assigned_to?: string | null
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          department: string
          id?: string
          patient_id: string
          payment_required?: boolean
          payment_satisfied?: boolean
          priority?: string
          reason?: string | null
          related_encounter_id?: string | null
          related_invoice_id?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          assigned_to?: string | null
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          department?: string
          id?: string
          patient_id?: string
          payment_required?: boolean
          payment_satisfied?: boolean
          priority?: string
          reason?: string | null
          related_encounter_id?: string | null
          related_invoice_id?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      diagnoses: {
        Row: {
          ai_suggested: boolean | null
          created_at: string
          diagnosis: string
          encounter_id: string
          icd_code: string | null
          id: string
          is_principal: boolean | null
          is_provisional: boolean | null
          notes: string | null
        }
        Insert: {
          ai_suggested?: boolean | null
          created_at?: string
          diagnosis: string
          encounter_id: string
          icd_code?: string | null
          id?: string
          is_principal?: boolean | null
          is_provisional?: boolean | null
          notes?: string | null
        }
        Update: {
          ai_suggested?: boolean | null
          created_at?: string
          diagnosis?: string
          encounter_id?: string
          icd_code?: string | null
          id?: string
          is_principal?: boolean | null
          is_provisional?: boolean | null
          notes?: string | null
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
            foreignKeyName: "fk_diagnoses_icd"
            columns: ["icd_code"]
            isOneToOne: false
            referencedRelation: "icd_codes"
            referencedColumns: ["code"]
          },
        ]
      }
      encounters: {
        Row: {
          appointment_id: string | null
          clerking_notes: string | null
          completed_at: string | null
          created_at: string
          encounter_type: string | null
          follow_up_date: string | null
          id: string
          patient_id: string
          practitioner_id: string | null
          principal_diagnosis: string | null
          status: string
          symptoms: string | null
          treatment_plan: string | null
          updated_at: string
        }
        Insert: {
          appointment_id?: string | null
          clerking_notes?: string | null
          completed_at?: string | null
          created_at?: string
          encounter_type?: string | null
          follow_up_date?: string | null
          id?: string
          patient_id: string
          practitioner_id?: string | null
          principal_diagnosis?: string | null
          status?: string
          symptoms?: string | null
          treatment_plan?: string | null
          updated_at?: string
        }
        Update: {
          appointment_id?: string | null
          clerking_notes?: string | null
          completed_at?: string | null
          created_at?: string
          encounter_type?: string | null
          follow_up_date?: string | null
          id?: string
          patient_id?: string
          practitioner_id?: string | null
          principal_diagnosis?: string | null
          status?: string
          symptoms?: string | null
          treatment_plan?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "encounters_appointment_id_fkey"
            columns: ["appointment_id"]
            isOneToOne: false
            referencedRelation: "appointments"
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
      facility_settings: {
        Row: {
          created_at: string
          facility_name: string
          id: string
          payment_flow: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          facility_name?: string
          id?: string
          payment_flow?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          facility_name?: string
          id?: string
          payment_flow?: string
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
      inpatient_reviews: {
        Row: {
          admission_id: string
          created_at: string
          findings: string | null
          id: string
          patient_id: string
          plan: string | null
          review_type: string
          reviewed_by: string | null
          reviewer_name: string | null
          reviewer_role: string | null
        }
        Insert: {
          admission_id: string
          created_at?: string
          findings?: string | null
          id?: string
          patient_id: string
          plan?: string | null
          review_type?: string
          reviewed_by?: string | null
          reviewer_name?: string | null
          reviewer_role?: string | null
        }
        Update: {
          admission_id?: string
          created_at?: string
          findings?: string | null
          id?: string
          patient_id?: string
          plan?: string | null
          review_type?: string
          reviewed_by?: string | null
          reviewer_name?: string | null
          reviewer_role?: string | null
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
            foreignKeyName: "inpatient_reviews_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      insurance_claims: {
        Row: {
          amount_approved: number | null
          amount_claimed: number
          id: string
          invoice_id: string
          notes: string | null
          patient_id: string
          policy_number: string | null
          provider: string
          resolved_at: string | null
          status: string
          submitted_at: string
        }
        Insert: {
          amount_approved?: number | null
          amount_claimed: number
          id?: string
          invoice_id: string
          notes?: string | null
          patient_id: string
          policy_number?: string | null
          provider: string
          resolved_at?: string | null
          status?: string
          submitted_at?: string
        }
        Update: {
          amount_approved?: number | null
          amount_claimed?: number
          id?: string
          invoice_id?: string
          notes?: string | null
          patient_id?: string
          policy_number?: string | null
          provider?: string
          resolved_at?: string | null
          status?: string
          submitted_at?: string
        }
        Relationships: [
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
      invoice_items: {
        Row: {
          amount: number
          category: string | null
          created_at: string
          description: string
          id: string
          invoice_id: string
          quantity: number
          unit_price: number
        }
        Insert: {
          amount: number
          category?: string | null
          created_at?: string
          description: string
          id?: string
          invoice_id: string
          quantity?: number
          unit_price: number
        }
        Update: {
          amount?: number
          category?: string | null
          created_at?: string
          description?: string
          id?: string
          invoice_id?: string
          quantity?: number
          unit_price?: number
        }
        Relationships: [
          {
            foreignKeyName: "invoice_items_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
        ]
      }
      invoices: {
        Row: {
          created_at: string
          created_by: string | null
          encounter_id: string | null
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
          id?: string
          insurance_covered?: number | null
          invoice_number: string
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
          id: string
          ordered_by: string | null
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
          id?: string
          ordered_by?: string | null
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
          id?: string
          ordered_by?: string | null
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
            foreignKeyName: "lab_orders_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      lab_results: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          created_at: string
          entered_at: string
          entered_by: string | null
          id: string
          interpretation: string | null
          is_abnormal: boolean | null
          lab_order_id: string
          notes: string | null
          result_data: Json
          status: string
          updated_at: string
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          entered_at?: string
          entered_by?: string | null
          id?: string
          interpretation?: string | null
          is_abnormal?: boolean | null
          lab_order_id: string
          notes?: string | null
          result_data?: Json
          status?: string
          updated_at?: string
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          entered_at?: string
          entered_by?: string | null
          id?: string
          interpretation?: string | null
          is_abnormal?: boolean | null
          lab_order_id?: string
          notes?: string | null
          result_data?: Json
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "lab_results_lab_order_id_fkey"
            columns: ["lab_order_id"]
            isOneToOne: false
            referencedRelation: "lab_orders"
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
      meal_orders: {
        Row: {
          created_at: string
          delivered_at: string | null
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
          id?: string
          meal_plan_id?: string | null
          meal_type?: string
          notes?: string | null
          patient_id?: string
          scheduled_for?: string
          status?: string
        }
        Relationships: []
      }
      meal_plans: {
        Row: {
          active: boolean | null
          ai_recommendations: string | null
          created_at: string
          created_by: string | null
          description: string | null
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
          id?: string
          meals_per_day?: number | null
          patient_id?: string
          plan_type?: string
          restrictions?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      medication_administrations: {
        Row: {
          administered_at: string
          administered_by: string | null
          created_at: string
          dose: string | null
          drug_name: string
          id: string
          inventory_id: string | null
          notes: string | null
          patient_id: string
          prescription_id: string
          quantity_dispensed: number
        }
        Insert: {
          administered_at?: string
          administered_by?: string | null
          created_at?: string
          dose?: string | null
          drug_name: string
          id?: string
          inventory_id?: string | null
          notes?: string | null
          patient_id: string
          prescription_id: string
          quantity_dispensed?: number
        }
        Update: {
          administered_at?: string
          administered_by?: string | null
          created_at?: string
          dose?: string | null
          drug_name?: string
          id?: string
          inventory_id?: string | null
          notes?: string | null
          patient_id?: string
          prescription_id?: string
          quantity_dispensed?: number
        }
        Relationships: []
      }
      notification_queue: {
        Row: {
          attempts: number
          channel: string
          created_at: string
          delivered_at: string | null
          id: string
          last_error: string | null
          max_attempts: number
          next_attempt_at: string
          payload: Json
          status: string
          updated_at: string
        }
        Insert: {
          attempts?: number
          channel?: string
          created_at?: string
          delivered_at?: string | null
          id?: string
          last_error?: string | null
          max_attempts?: number
          next_attempt_at?: string
          payload: Json
          status?: string
          updated_at?: string
        }
        Update: {
          attempts?: number
          channel?: string
          created_at?: string
          delivered_at?: string | null
          id?: string
          last_error?: string | null
          max_attempts?: number
          next_attempt_at?: string
          payload?: Json
          status?: string
          updated_at?: string
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
          recipient_role: Database["public"]["Enums"]["app_role"] | null
          recipient_user_id: string | null
          related_entity_id: string | null
          related_patient_id: string | null
          severity: string
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
          recipient_role?: Database["public"]["Enums"]["app_role"] | null
          recipient_user_id?: string | null
          related_entity_id?: string | null
          related_patient_id?: string | null
          severity?: string
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
          recipient_role?: Database["public"]["Enums"]["app_role"] | null
          recipient_user_id?: string | null
          related_entity_id?: string | null
          related_patient_id?: string | null
          severity?: string
          title?: string
        }
        Relationships: []
      }
      outside_lab_documents: {
        Row: {
          ai_analysis: string | null
          ai_analyzed_at: string | null
          created_at: string
          document_type: string
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
        Relationships: []
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
          first_name: string
          gender: string | null
          genotype: string | null
          ghana_card_number: string | null
          id: string
          insurance_expiry: string | null
          insurance_group_number: string | null
          insurance_number: string | null
          insurance_provider: string | null
          last_name: string
          membership_expires_at: string | null
          membership_type: string
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
          first_name: string
          gender?: string | null
          genotype?: string | null
          ghana_card_number?: string | null
          id?: string
          insurance_expiry?: string | null
          insurance_group_number?: string | null
          insurance_number?: string | null
          insurance_provider?: string | null
          last_name: string
          membership_expires_at?: string | null
          membership_type?: string
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
          first_name?: string
          gender?: string | null
          genotype?: string | null
          ghana_card_number?: string | null
          id?: string
          insurance_expiry?: string | null
          insurance_group_number?: string | null
          insurance_number?: string | null
          insurance_provider?: string | null
          last_name?: string
          membership_expires_at?: string | null
          membership_type?: string
          patient_code?: string | null
          phone?: string | null
          registration_reason?: string | null
          status?: string
          updated_at?: string
          user_id?: string | null
        }
        Relationships: []
      }
      payments: {
        Row: {
          amount: number
          created_at: string
          id: string
          invoice_id: string | null
          method: string | null
          notes: string | null
          patient_id: string
          received_by: string | null
          reference: string | null
        }
        Insert: {
          amount: number
          created_at?: string
          id?: string
          invoice_id?: string | null
          method?: string | null
          notes?: string | null
          patient_id: string
          received_by?: string | null
          reference?: string | null
        }
        Update: {
          amount?: number
          created_at?: string
          id?: string
          invoice_id?: string | null
          method?: string | null
          notes?: string | null
          patient_id?: string
          received_by?: string | null
          reference?: string | null
        }
        Relationships: [
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
        Relationships: []
      }
      pharmacy_inventory: {
        Row: {
          created_at: string
          drug_name: string
          expiry_date: string | null
          form: string | null
          generic_name: string | null
          id: string
          reorder_level: number | null
          stock_quantity: number
          strength: string | null
          supplier: string | null
          unit_price: number | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          drug_name: string
          expiry_date?: string | null
          form?: string | null
          generic_name?: string | null
          id?: string
          reorder_level?: number | null
          stock_quantity?: number
          strength?: string | null
          supplier?: string | null
          unit_price?: number | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          drug_name?: string
          expiry_date?: string | null
          form?: string | null
          generic_name?: string | null
          id?: string
          reorder_level?: number | null
          stock_quantity?: number
          strength?: string | null
          supplier?: string | null
          unit_price?: number | null
          updated_at?: string
        }
        Relationships: []
      }
      prescriptions: {
        Row: {
          created_at: string
          dispensed_at: string | null
          dispensed_by: string | null
          dosage: string | null
          duration: string | null
          encounter_id: string | null
          frequency: string | null
          id: string
          instructions: string | null
          medication: string
          patient_id: string
          prescribed_by: string | null
          status: string
        }
        Insert: {
          created_at?: string
          dispensed_at?: string | null
          dispensed_by?: string | null
          dosage?: string | null
          duration?: string | null
          encounter_id?: string | null
          frequency?: string | null
          id?: string
          instructions?: string | null
          medication: string
          patient_id: string
          prescribed_by?: string | null
          status?: string
        }
        Update: {
          created_at?: string
          dispensed_at?: string | null
          dispensed_by?: string | null
          dosage?: string | null
          duration?: string | null
          encounter_id?: string | null
          frequency?: string | null
          id?: string
          instructions?: string | null
          medication?: string
          patient_id?: string
          prescribed_by?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "prescriptions_encounter_id_fkey"
            columns: ["encounter_id"]
            isOneToOne: false
            referencedRelation: "encounters"
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
          complications: string | null
          created_at: string
          encounter_id: string | null
          findings: string | null
          id: string
          indication: string | null
          patient_id: string
          performed_at: string | null
          performed_by: string | null
          post_op_plan: string | null
          procedure_code: string | null
          procedure_name: string
          status: string
          technique: string | null
          template_used: string | null
          updated_at: string
        }
        Insert: {
          assistants?: string | null
          complications?: string | null
          created_at?: string
          encounter_id?: string | null
          findings?: string | null
          id?: string
          indication?: string | null
          patient_id: string
          performed_at?: string | null
          performed_by?: string | null
          post_op_plan?: string | null
          procedure_code?: string | null
          procedure_name: string
          status?: string
          technique?: string | null
          template_used?: string | null
          updated_at?: string
        }
        Update: {
          assistants?: string | null
          complications?: string | null
          created_at?: string
          encounter_id?: string | null
          findings?: string | null
          id?: string
          indication?: string | null
          patient_id?: string
          performed_at?: string | null
          performed_by?: string | null
          post_op_plan?: string | null
          procedure_code?: string | null
          procedure_name?: string
          status?: string
          technique?: string | null
          template_used?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      profiles: {
        Row: {
          avatar_url: string | null
          created_at: string
          department: string | null
          email: string | null
          first_name: string | null
          id: string
          last_name: string | null
          phone: string | null
          specialization: string | null
          updated_at: string
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string
          department?: string | null
          email?: string | null
          first_name?: string | null
          id: string
          last_name?: string | null
          phone?: string | null
          specialization?: string | null
          updated_at?: string
        }
        Update: {
          avatar_url?: string | null
          created_at?: string
          department?: string | null
          email?: string | null
          first_name?: string | null
          id?: string
          last_name?: string | null
          phone?: string | null
          specialization?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      service_orders: {
        Row: {
          amount: number
          approved_at: string | null
          approved_by: string | null
          completed_at: string | null
          created_at: string
          department: string
          encounter_id: string | null
          id: string
          invoice_id: string | null
          notes: string | null
          patient_id: string
          related_entity_id: string | null
          requested_by: string | null
          service_name: string
          status: string
          updated_at: string
        }
        Insert: {
          amount?: number
          approved_at?: string | null
          approved_by?: string | null
          completed_at?: string | null
          created_at?: string
          department: string
          encounter_id?: string | null
          id?: string
          invoice_id?: string | null
          notes?: string | null
          patient_id: string
          related_entity_id?: string | null
          requested_by?: string | null
          service_name: string
          status?: string
          updated_at?: string
        }
        Update: {
          amount?: number
          approved_at?: string | null
          approved_by?: string | null
          completed_at?: string | null
          created_at?: string
          department?: string
          encounter_id?: string | null
          id?: string
          invoice_id?: string | null
          notes?: string | null
          patient_id?: string
          related_entity_id?: string | null
          requested_by?: string | null
          service_name?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "service_orders_encounter_id_fkey"
            columns: ["encounter_id"]
            isOneToOne: false
            referencedRelation: "encounters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_orders_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
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
        Relationships: [
          {
            foreignKeyName: "fk_stg_icd"
            columns: ["icd_code"]
            isOneToOne: false
            referencedRelation: "icd_codes"
            referencedColumns: ["code"]
          },
        ]
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
          started_at: string | null
          status: string
        }
        Insert: {
          appointment_id?: string | null
          created_at?: string
          ended_at?: string | null
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
          started_at?: string | null
          status?: string
        }
        Update: {
          appointment_id?: string | null
          created_at?: string
          ended_at?: string | null
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
            foreignKeyName: "video_sessions_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
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
          id?: string
          patient_id?: string
          severity?: string
          vital_signs_id?: string | null
        }
        Relationships: []
      }
      vital_signs: {
        Row: {
          appointment_id: string | null
          bmi: number | null
          diastolic: number | null
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
          weight_kg: number | null
        }
        Insert: {
          appointment_id?: string | null
          bmi?: number | null
          diastolic?: number | null
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
          weight_kg?: number | null
        }
        Update: {
          appointment_id?: string | null
          bmi?: number | null
          diastolic?: number | null
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
            foreignKeyName: "vital_signs_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      v_ai_clinical_decision: {
        Row: {
          description: string | null
          diagnosis: string | null
          encounter_id: string | null
          icd_code: string | null
          medications: Json | null
          recommended_action: string | null
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
            foreignKeyName: "fk_diagnoses_icd"
            columns: ["icd_code"]
            isOneToOne: false
            referencedRelation: "icd_codes"
            referencedColumns: ["code"]
          },
        ]
      }
      v_patient_diagnosis_full: {
        Row: {
          category: string | null
          diagnosis: string | null
          diagnosis_id: string | null
          encounter_id: string | null
          icd_code: string | null
          icd_description: string | null
          medications: Json | null
          recommended_action: string | null
          stg_summary: string | null
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
            foreignKeyName: "fk_diagnoses_icd"
            columns: ["icd_code"]
            isOneToOne: false
            referencedRelation: "icd_codes"
            referencedColumns: ["code"]
          },
        ]
      }
    }
    Functions: {
      enqueue_notification: {
        Args: { _channel?: string; _payload: Json }
        Returns: string
      }
      has_role: {
        Args: {
          _role: Database["public"]["Enums"]["app_role"]
          _user_id: string
        }
        Returns: boolean
      }
      is_clinical_staff: { Args: { _user_id: string }; Returns: boolean }
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
      ],
    },
  },
} as const
