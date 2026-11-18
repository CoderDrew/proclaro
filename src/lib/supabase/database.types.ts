
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  
  "graphql_public": {
          Tables: {
            [_ in never]: never
          }
          Views: {
            [_ in never]: never
          }
          Functions: {
            "graphql":
{ Args: { "extensions"?: Json,"operationName"?: string,"query"?: string,"variables"?: Json }; Returns: Json
                           }
          }
          Enums: {
            [_ in never]: never
          }
          CompositeTypes: {
            [_ in never]: never
          }
        },"public": {
          Tables: {
            "audit_log": {
                  Row: {
                    "action": string,"actor_id": string | null,"created_at": string,"detail": NonNullable<Json>,"id": number,"solicitation_id": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "action": string,"actor_id"?: string | null,"created_at"?: string,"detail"?: NonNullable<Json>,"id"?: number,"solicitation_id"?: string | null
                  }
                  Update: {
                    "action"?: string,"actor_id"?: string | null,"created_at"?: string,"detail"?: NonNullable<Json>,"id"?: number,"solicitation_id"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "audit_log_actor_id_fkey"
      columns: ["actor_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "audit_log_solicitation_id_fkey"
      columns: ["solicitation_id"]
isOneToOne: false
      referencedRelation: "solicitations"
      referencedColumns: ["id"]
    }
                  ]
                },"bid_audit_log": {
                  Row: {
                    "action": string,"actor_id": string | null,"bid_id": string | null,"created_at": string,"detail": NonNullable<Json>,"id": number,"solicitation_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "action": string,"actor_id"?: string | null,"bid_id"?: string | null,"created_at"?: string,"detail"?: NonNullable<Json>,"id"?: number,"solicitation_id": string
                  }
                  Update: {
                    "action"?: string,"actor_id"?: string | null,"bid_id"?: string | null,"created_at"?: string,"detail"?: NonNullable<Json>,"id"?: number,"solicitation_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "bid_audit_log_actor_id_fkey"
      columns: ["actor_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "bid_audit_log_bid_id_fkey"
      columns: ["bid_id"]
isOneToOne: false
      referencedRelation: "bids"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "bid_audit_log_solicitation_id_fkey"
      columns: ["solicitation_id"]
isOneToOne: false
      referencedRelation: "solicitations"
      referencedColumns: ["id"]
    }
                  ]
                },"bid_draft_files": {
                  Row: {
                    "bid_id": string,"file_name": string,"path": string,"slot": Database["public"]['Enums']["bid_upload_slot"]
                  }
                  ComputedFields: never
                  Insert: {
                    "bid_id": string,"file_name": string,"path": string,"slot": Database["public"]['Enums']["bid_upload_slot"]
                  }
                  Update: {
                    "bid_id"?: string,"file_name"?: string,"path"?: string,"slot"?: Database["public"]['Enums']["bid_upload_slot"]
                  }
                  Relationships: [
                    {
      foreignKeyName: "bid_draft_files_bid_id_fkey"
      columns: ["bid_id"]
isOneToOne: false
      referencedRelation: "bid_drafts"
      referencedColumns: ["bid_id"]
    }
                  ]
                },"bid_drafts": {
                  Row: {
                    "alternate_cents": (number)[],"bid_bond_choice": Database["public"]['Enums']["bid_bond_choice"] | null,"bid_id": string,"item_cents": (number)[],"updated_at": string,"version": number
                  }
                  ComputedFields: never
                  Insert: {
                    "alternate_cents"?: (number)[],"bid_bond_choice"?: Database["public"]['Enums']["bid_bond_choice"] | null,"bid_id": string,"item_cents"?: (number)[],"updated_at"?: string,"version": number
                  }
                  Update: {
                    "alternate_cents"?: (number)[],"bid_bond_choice"?: Database["public"]['Enums']["bid_bond_choice"] | null,"bid_id"?: string,"item_cents"?: (number)[],"updated_at"?: string,"version"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "bid_drafts_bid_id_fkey"
      columns: ["bid_id"]
isOneToOne: true
      referencedRelation: "bids"
      referencedColumns: ["id"]
    }
                  ]
                },"bid_original_log": {
                  Row: {
                    "bid_id": string,"id": string,"item": Database["public"]['Enums']["original_item"],"logged_at": string,"logged_by": string,"reason": string | null,"received_at": string | null,"reference": string,"solicitation_id": string,"version": number,"voids_entry_id": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "bid_id": string,"id"?: string,"item": Database["public"]['Enums']["original_item"],"logged_at"?: string,"logged_by": string,"reason"?: string | null,"received_at"?: string | null,"reference": string,"solicitation_id": string,"version": number,"voids_entry_id"?: string | null
                  }
                  Update: {
                    "bid_id"?: string,"id"?: string,"item"?: Database["public"]['Enums']["original_item"],"logged_at"?: string,"logged_by"?: string,"reason"?: string | null,"received_at"?: string | null,"reference"?: string,"solicitation_id"?: string,"version"?: number,"voids_entry_id"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "bid_original_log_bid_id_fkey"
      columns: ["bid_id"]
isOneToOne: false
      referencedRelation: "bids"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "bid_original_log_bid_id_version_fkey"
      columns: ["bid_id","version"]
isOneToOne: false
      referencedRelation: "bid_versions"
      referencedColumns: ["bid_id","version"]
    },{
      foreignKeyName: "bid_original_log_logged_by_fkey"
      columns: ["logged_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "bid_original_log_solicitation_id_fkey"
      columns: ["solicitation_id"]
isOneToOne: false
      referencedRelation: "solicitations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "bid_original_log_voids_entry_id_fkey"
      columns: ["voids_entry_id"]
isOneToOne: true
      referencedRelation: "bid_original_log"
      referencedColumns: ["id"]
    }
                  ]
                },"bid_version_files": {
                  Row: {
                    "file_name": string,"object_etag": string | null,"object_id": string | null,"object_size": number | null,"path": string,"slot": Database["public"]['Enums']["bid_upload_slot"],"version_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "file_name": string,"object_etag"?: string | null,"object_id"?: string | null,"object_size"?: number | null,"path": string,"slot": Database["public"]['Enums']["bid_upload_slot"],"version_id": string
                  }
                  Update: {
                    "file_name"?: string,"object_etag"?: string | null,"object_id"?: string | null,"object_size"?: number | null,"path"?: string,"slot"?: Database["public"]['Enums']["bid_upload_slot"],"version_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "bid_version_files_version_id_fkey"
      columns: ["version_id"]
isOneToOne: false
      referencedRelation: "bid_versions"
      referencedColumns: ["id"]
    }
                  ]
                },"bid_versions": {
                  Row: {
                    "alternate_cents": (number)[],"bid_bond_choice": Database["public"]['Enums']["bid_bond_choice"] | null,"bid_id": string,"bidder_legal_name": string,"id": string,"item_cents": (number)[],"submitted_at": string,"submitted_by": string,"version": number
                  }
                  ComputedFields: never
                  Insert: {
                    "alternate_cents": (number)[],"bid_bond_choice"?: Database["public"]['Enums']["bid_bond_choice"] | null,"bid_id": string,"bidder_legal_name": string,"id"?: string,"item_cents": (number)[],"submitted_at"?: string,"submitted_by": string,"version": number
                  }
                  Update: {
                    "alternate_cents"?: (number)[],"bid_bond_choice"?: Database["public"]['Enums']["bid_bond_choice"] | null,"bid_id"?: string,"bidder_legal_name"?: string,"id"?: string,"item_cents"?: (number)[],"submitted_at"?: string,"submitted_by"?: string,"version"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "bid_versions_bid_id_fkey"
      columns: ["bid_id"]
isOneToOne: false
      referencedRelation: "bids"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "bid_versions_submitted_by_fkey"
      columns: ["submitted_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    }
                  ]
                },"bid_withdrawals": {
                  Row: {
                    "bid_id": string,"version": number,"withdrawn_at": string,"withdrawn_by": string
                  }
                  ComputedFields: never
                  Insert: {
                    "bid_id": string,"version": number,"withdrawn_at"?: string,"withdrawn_by": string
                  }
                  Update: {
                    "bid_id"?: string,"version"?: number,"withdrawn_at"?: string,"withdrawn_by"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "bid_withdrawals_bid_id_version_fkey"
      columns: ["bid_id","version"]
isOneToOne: true
      referencedRelation: "bid_versions"
      referencedColumns: ["bid_id","version"]
    },{
      foreignKeyName: "bid_withdrawals_withdrawn_by_fkey"
      columns: ["withdrawn_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    }
                  ]
                },"bidder_companies": {
                  Row: {
                    "address": string,"contact_email": string,"contact_name": string,"contact_phone": string,"created_at": string,"org_id": string,"resident_certificate": string | null,"resident_claimed": boolean
                  }
                  ComputedFields: never
                  Insert: {
                    "address": string,"contact_email": string,"contact_name": string,"contact_phone": string,"created_at"?: string,"org_id": string,"resident_certificate"?: string | null,"resident_claimed"?: boolean
                  }
                  Update: {
                    "address"?: string,"contact_email"?: string,"contact_name"?: string,"contact_phone"?: string,"created_at"?: string,"org_id"?: string,"resident_certificate"?: string | null,"resident_claimed"?: boolean
                  }
                  Relationships: [
                    {
      foreignKeyName: "bidder_companies_org_id_fkey"
      columns: ["org_id"]
isOneToOne: true
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    }
                  ]
                },"bids": {
                  Row: {
                    "bidder_org_id": string,"created_at": string,"created_by": string,"id": string,"reference": string,"solicitation_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "bidder_org_id": string,"created_at"?: string,"created_by": string,"id"?: string,"reference": string,"solicitation_id": string
                  }
                  Update: {
                    "bidder_org_id"?: string,"created_at"?: string,"created_by"?: string,"id"?: string,"reference"?: string,"solicitation_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "bids_bidder_org_id_fkey"
      columns: ["bidder_org_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "bids_created_by_fkey"
      columns: ["created_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "bids_solicitation_id_fkey"
      columns: ["solicitation_id"]
isOneToOne: false
      referencedRelation: "solicitations"
      referencedColumns: ["id"]
    }
                  ]
                },"clauses": {
                  Row: {
                    "body": string,"created_at": string,"created_by": string | null,"key": string,"version": number
                  }
                  ComputedFields: never
                  Insert: {
                    "body": string,"created_at"?: string,"created_by"?: string | null,"key": string,"version": number
                  }
                  Update: {
                    "body"?: string,"created_at"?: string,"created_by"?: string | null,"key"?: string,"version"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "clauses_created_by_fkey"
      columns: ["created_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    }
                  ]
                },"comments": {
                  Row: {
                    "author_id": string,"body": string,"created_at": string,"field": string | null,"id": string,"kind": Database["public"]['Enums']["comment_kind"],"solicitation_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "author_id": string,"body": string,"created_at"?: string,"field"?: string | null,"id"?: string,"kind": Database["public"]['Enums']["comment_kind"],"solicitation_id": string
                  }
                  Update: {
                    "author_id"?: string,"body"?: string,"created_at"?: string,"field"?: string | null,"id"?: string,"kind"?: Database["public"]['Enums']["comment_kind"],"solicitation_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "comments_author_id_fkey"
      columns: ["author_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "comments_solicitation_id_fkey"
      columns: ["solicitation_id"]
isOneToOne: false
      referencedRelation: "solicitations"
      referencedColumns: ["id"]
    }
                  ]
                },"holidays": {
                  Row: {
                    "day": string,"name": string
                  }
                  ComputedFields: never
                  Insert: {
                    "day": string,"name": string
                  }
                  Update: {
                    "day"?: string,"name"?: string
                  }
                  Relationships: [
                    
                  ]
                },"number_sequences": {
                  Row: {
                    "fiscal_year": number,"last_seq": number
                  }
                  ComputedFields: never
                  Insert: {
                    "fiscal_year": number,"last_seq"?: number
                  }
                  Update: {
                    "fiscal_year"?: number,"last_seq"?: number
                  }
                  Relationships: [
                    
                  ]
                },"organizations": {
                  Row: {
                    "id": string,"kind": Database["public"]['Enums']["org_kind"],"name": string
                  }
                  ComputedFields: never
                  Insert: {
                    "id"?: string,"kind": Database["public"]['Enums']["org_kind"],"name": string
                  }
                  Update: {
                    "id"?: string,"kind"?: Database["public"]['Enums']["org_kind"],"name"?: string
                  }
                  Relationships: [
                    
                  ]
                },"profiles": {
                  Row: {
                    "display_name": string,"is_admin": boolean,"org_id": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "display_name": string,"is_admin"?: boolean,"org_id": string,"user_id": string
                  }
                  Update: {
                    "display_name"?: string,"is_admin"?: boolean,"org_id"?: string,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "profiles_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    }
                  ]
                },"settings": {
                  Row: {
                    "fiscal_year_start_month": number,"id": number,"office_name": string,"state_name": string,"timezone": string
                  }
                  ComputedFields: never
                  Insert: {
                    "fiscal_year_start_month"?: number,"id"?: number,"office_name": string,"state_name": string,"timezone"?: string
                  }
                  Update: {
                    "fiscal_year_start_month"?: number,"id"?: number,"office_name"?: string,"state_name"?: string,"timezone"?: string
                  }
                  Relationships: [
                    
                  ]
                },"solicitation_clause_locks": {
                  Row: {
                    "clause_key": string,"clause_version": number,"solicitation_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "clause_key": string,"clause_version": number,"solicitation_id": string
                  }
                  Update: {
                    "clause_key"?: string,"clause_version"?: number,"solicitation_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "solicitation_clause_locks_clause_key_clause_version_fkey"
      columns: ["clause_key","clause_version"]
isOneToOne: false
      referencedRelation: "clauses"
      referencedColumns: ["key","version"]
    },{
      foreignKeyName: "solicitation_clause_locks_solicitation_id_fkey"
      columns: ["solicitation_id"]
isOneToOne: false
      referencedRelation: "solicitations"
      referencedColumns: ["id"]
    }
                  ]
                },"solicitations": {
                  Row: {
                    "agency_id": string,"bid_due_at": string | null,"bid_form_path": string | null,"checker_id": string | null,"created_at": string,"created_by": string,"data": NonNullable<Json>,"fallback_approved": boolean,"fiscal_year": number | null,"id": string,"latest_submitted_at": string | null,"number": string | null,"published_at": string | null,"published_snapshot": Json | null,"release_date": string | null,"reviewer_id": string | null,"rfb_path": string | null,"state": Database["public"]['Enums']["solicitation_state"],"version": number | null
                  }
                  ComputedFields: never
                  Insert: {
                    "agency_id": string,"bid_due_at"?: string | null,"bid_form_path"?: string | null,"checker_id"?: string | null,"created_at"?: string,"created_by": string,"data"?: NonNullable<Json>,"fallback_approved"?: boolean,"fiscal_year"?: number | null,"id"?: string,"latest_submitted_at"?: string | null,"number"?: string | null,"published_at"?: string | null,"published_snapshot"?: Json | null,"release_date"?: string | null,"reviewer_id"?: string | null,"rfb_path"?: string | null,"state"?: Database["public"]['Enums']["solicitation_state"],"version"?: number | null
                  }
                  Update: {
                    "agency_id"?: string,"bid_due_at"?: string | null,"bid_form_path"?: string | null,"checker_id"?: string | null,"created_at"?: string,"created_by"?: string,"data"?: NonNullable<Json>,"fallback_approved"?: boolean,"fiscal_year"?: number | null,"id"?: string,"latest_submitted_at"?: string | null,"number"?: string | null,"published_at"?: string | null,"published_snapshot"?: Json | null,"release_date"?: string | null,"reviewer_id"?: string | null,"rfb_path"?: string | null,"state"?: Database["public"]['Enums']["solicitation_state"],"version"?: number | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "solicitations_agency_id_fkey"
      columns: ["agency_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "solicitations_checker_id_fkey"
      columns: ["checker_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "solicitations_created_by_fkey"
      columns: ["created_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "solicitations_reviewer_id_fkey"
      columns: ["reviewer_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    }
                  ]
                },"warning_acks": {
                  Row: {
                    "acked_at": string,"acked_by": string,"code": string,"field": string | null,"solicitation_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "acked_at"?: string,"acked_by": string,"code": string,"field"?: string | null,"solicitation_id": string
                  }
                  Update: {
                    "acked_at"?: string,"acked_by"?: string,"code"?: string,"field"?: string | null,"solicitation_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "warning_acks_acked_by_fkey"
      columns: ["acked_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "warning_acks_solicitation_id_fkey"
      columns: ["solicitation_id"]
isOneToOne: false
      referencedRelation: "solicitations"
      referencedColumns: ["id"]
    }
                  ]
                }
          }
          Views: {
            [_ in never]: never
          }
          Functions: {
            "acknowledge_warning":
{ Args: { "p_code": string,"p_field": string,"p_id": string }; Returns: undefined
                           },
"approve_alone":
{ Args: { "p_id": string }; Returns: undefined
                           },
"approve_check":
{ Args: { "p_id": string }; Returns: undefined
                           },
"bidding_state":
{ Args: { "p_solicitation_id": string }; Returns: string
                           },
"disagree":
{ Args: { "p_comment": string,"p_field": string,"p_id": string }; Returns: undefined
                           },
"log_bid_original":
{ Args: { "p_item": Database["public"]['Enums']["original_item"],"p_received_at"?: string,"p_reference": string,"p_solicitation_id": string,"p_version": number }; Returns: string
                           },
"my_bid_receipts":
{ Args: { "p_bid_id": string }; Returns: {
              "is_current": boolean,"reference": string,"submitted_at": string,"version": number,"withdrawn_at": string
            }[]
                           },
"office_bid_index":
{ Args: { "p_solicitation_id": string }; Returns: {
              "reference": string,"status": string,"version": number
            }[]
                           },
"office_update_data":
{ Args: { "p_data": Json,"p_id": string,"p_reason": string }; Returns: undefined
                           },
"opened_bid_files":
{ Args: { "p_solicitation_id": string }; Returns: {
              "bid_id": string,"file_name": string,"file_status": string,"path": string,"slot": Database["public"]['Enums']["bid_upload_slot"]
            }[]
                           },
"opened_bids":
{ Args: { "p_solicitation_id": string }; Returns: {
              "alternate_cents": (number)[],"base_total_cents": number,"bid_bond_choice": Database["public"]['Enums']["bid_bond_choice"],"bid_id": string,"bidder_name": string,"bidder_org_id": string,"bond_original_received": boolean,"item_cents": (number)[],"non_responsive_reason": string,"original_received": boolean,"reference": string,"submitted_at": string,"version": number
            }[]
                           },
"publish_solicitation":
{ Args: { "p_bid_due_at": string,"p_bid_form_path": string,"p_id": string,"p_rfb_path": string,"p_snapshot": Json }; Returns: undefined
                           },
"reassign_review":
{ Args: { "p_id": string,"p_user": string }; Returns: undefined
                           },
"register_bidder":
{ Args: { "p_address": string,"p_contact_email": string,"p_contact_name": string,"p_contact_phone": string,"p_legal_name": string,"p_resident_certificate": string,"p_resident_claimed": boolean }; Returns: string
                           },
"reopen_review":
{ Args: { "p_id": string,"p_reason": string }; Returns: undefined
                           },
"replace_bid":
{ Args: { "p_bid_id": string }; Returns: undefined
                           },
"return_to_agency":
{ Args: { "p_comments": Json,"p_id": string }; Returns: undefined
                           },
"send_to_check":
{ Args: { "p_id": string }; Returns: undefined
                           },
"start_bid":
{ Args: { "p_solicitation_id": string }; Returns: string
                           },
"start_review":
{ Args: { "p_id": string }; Returns: undefined
                           },
"submit_bid":
{ Args: { "p_bid_id": string }; Returns: {
              "reference": string,"submitted_at": string,"version": number
            }[]
                           },
"submit_solicitation":
{ Args: { "p_id": string }; Returns: undefined
                           },
"void_bid_original":
{ Args: { "p_entry_id": string,"p_reason": string }; Returns: string
                           },
"withdraw_bid":
{ Args: { "p_bid_id": string }; Returns: undefined
                           }
          }
          Enums: {
            "bid_bond_choice": "electronic"|"paper","bid_upload_slot": "insurance"|"qualifications"|"references"|"current_work"|"bid_bond","comment_kind": "return"|"disagree"|"note","org_kind": "agency"|"office"|"bidder","original_item": "signed_form"|"bid_bond","solicitation_state": "draft"|"submitted"|"in_review"|"in_check"|"approved"|"published"
          }
          CompositeTypes: {
            [_ in never]: never
          }
        }
}

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>

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
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
  ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
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
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
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
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
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
    : never = never
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
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
    : never = never
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
  ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
  : never

export const Constants = {
  "graphql_public": {
          Enums: {
            
          }
        },"public": {
          Enums: {
            "bid_bond_choice": ["electronic", "paper"],"bid_upload_slot": ["insurance", "qualifications", "references", "current_work", "bid_bond"],"comment_kind": ["return", "disagree", "note"],"org_kind": ["agency", "office", "bidder"],"original_item": ["signed_form", "bid_bond"],"solicitation_state": ["draft", "submitted", "in_review", "in_check", "approved", "published"]
          }
        }
} as const
