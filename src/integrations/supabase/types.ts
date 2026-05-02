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
          created_at: string
          diagnosis: string
          encounter_id: string
          icd_code: string | null
          id: string
          is_principal: boolean | null
        }
        Insert: {
          created_at?: string
          diagnosis: string
          encounter_id: string
          icd_code?: string | null
          id?: string
          is_principal?: boolean | null
        }
        Update: {
          created_at?: string
          diagnosis?: string
          encounter_id?: string
          icd_code?: string | null
          id?: string
          is_principal?: boolean | null
        }
        Relationships: [
          {
            foreignKeyName: "diagnoses_encounter_id_fkey"
            columns: ["encounter_id"]
            isOneToOne: false
            referencedRelation: "encounters"
            referencedColumns: ["id"]
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
          patient_code: string | null
          phone: string | null
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
          patient_code?: string | null
          phone?: string | null
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
          patient_code?: string | null
          phone?: string | null
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
      [_ in never]: never
    }
    Functions: {
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
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
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
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
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
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
      ],
    },
  },
} as const
