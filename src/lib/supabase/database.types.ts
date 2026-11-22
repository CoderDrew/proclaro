
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
            "addenda": {
                  Row: {
                    "checker_id": string | null,"created_at": string,"created_by": string,"data": NonNullable<Json>,"id": string,"latest_submitted_at": string | null,"narrative": string,"number": number,"published_version": number | null,"reviewer_id": string | null,"single_reviewer": boolean,"solicitation_id": string,"state": Database["public"]['Enums']["addendum_state"],"withdrawn_reason": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "checker_id"?: string | null,"created_at"?: string,"created_by": string,"data": NonNullable<Json>,"id"?: string,"latest_submitted_at"?: string | null,"narrative"?: string,"number": number,"published_version"?: number | null,"reviewer_id"?: string | null,"single_reviewer"?: boolean,"solicitation_id": string,"state"?: Database["public"]['Enums']["addendum_state"],"withdrawn_reason"?: string | null
                  }
                  Update: {
                    "checker_id"?: string | null,"created_at"?: string,"created_by"?: string,"data"?: NonNullable<Json>,"id"?: string,"latest_submitted_at"?: string | null,"narrative"?: string,"number"?: number,"published_version"?: number | null,"reviewer_id"?: string | null,"single_reviewer"?: boolean,"solicitation_id"?: string,"state"?: Database["public"]['Enums']["addendum_state"],"withdrawn_reason"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "addenda_checker_id_fkey"
      columns: ["checker_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "addenda_created_by_fkey"
      columns: ["created_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "addenda_reviewer_id_fkey"
      columns: ["reviewer_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "addenda_solicitation_id_fkey"
      columns: ["solicitation_id"]
isOneToOne: false
      referencedRelation: "solicitations"
      referencedColumns: ["id"]
    }
                  ]
                },"addendum_answers": {
                  Row: {
                    "addendum_id": string,"answer": string,"published_question": string,"question_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "addendum_id": string,"answer": string,"published_question": string,"question_id": string
                  }
                  Update: {
                    "addendum_id"?: string,"answer"?: string,"published_question"?: string,"question_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "addendum_answers_addendum_id_fkey"
      columns: ["addendum_id"]
isOneToOne: false
      referencedRelation: "addenda"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "addendum_answers_question_id_fkey"
      columns: ["question_id"]
isOneToOne: false
      referencedRelation: "questions"
      referencedColumns: ["id"]
    }
                  ]
                },"addendum_comments": {
                  Row: {
                    "addendum_id": string,"author_id": string,"body": string,"created_at": string,"field": string | null,"id": string,"kind": Database["public"]['Enums']["comment_kind"]
                  }
                  ComputedFields: never
                  Insert: {
                    "addendum_id": string,"author_id": string,"body": string,"created_at"?: string,"field"?: string | null,"id"?: string,"kind": Database["public"]['Enums']["comment_kind"]
                  }
                  Update: {
                    "addendum_id"?: string,"author_id"?: string,"body"?: string,"created_at"?: string,"field"?: string | null,"id"?: string,"kind"?: Database["public"]['Enums']["comment_kind"]
                  }
                  Relationships: [
                    {
      foreignKeyName: "addendum_comments_addendum_id_fkey"
      columns: ["addendum_id"]
isOneToOne: false
      referencedRelation: "addenda"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "addendum_comments_author_id_fkey"
      columns: ["author_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    }
                  ]
                },"audit_log": {
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
                },"award_picks": {
                  Row: {
                    "bid_id": string,"id": string,"picked_at": string,"picked_by": string,"reason": string | null,"solicitation_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "bid_id": string,"id"?: string,"picked_at"?: string,"picked_by": string,"reason"?: string | null,"solicitation_id": string
                  }
                  Update: {
                    "bid_id"?: string,"id"?: string,"picked_at"?: string,"picked_by"?: string,"reason"?: string | null,"solicitation_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "award_picks_bid_id_fkey"
      columns: ["bid_id"]
isOneToOne: false
      referencedRelation: "bids"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "award_picks_picked_by_fkey"
      columns: ["picked_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "award_picks_solicitation_id_fkey"
      columns: ["solicitation_id"]
isOneToOne: false
      referencedRelation: "solicitations"
      referencedColumns: ["id"]
    }
                  ]
                },"awards": {
                  Row: {
                    "bid_id": string,"checked_by": string | null,"pick_id": string,"posted_at": string,"prepared_by": string,"single_reviewer": boolean,"snapshot": NonNullable<Json>,"solicitation_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "bid_id": string,"checked_by"?: string | null,"pick_id": string,"posted_at"?: string,"prepared_by": string,"single_reviewer": boolean,"snapshot": NonNullable<Json>,"solicitation_id": string
                  }
                  Update: {
                    "bid_id"?: string,"checked_by"?: string | null,"pick_id"?: string,"posted_at"?: string,"prepared_by"?: string,"single_reviewer"?: boolean,"snapshot"?: NonNullable<Json>,"solicitation_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "awards_bid_id_fkey"
      columns: ["bid_id"]
isOneToOne: false
      referencedRelation: "bids"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "awards_checked_by_fkey"
      columns: ["checked_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "awards_pick_id_fkey"
      columns: ["pick_id"]
isOneToOne: false
      referencedRelation: "award_picks"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "awards_prepared_by_fkey"
      columns: ["prepared_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "awards_solicitation_id_fkey"
      columns: ["solicitation_id"]
isOneToOne: true
      referencedRelation: "solicitations"
      referencedColumns: ["id"]
    }
                  ]
                },"bid_acknowledgments": {
                  Row: {
                    "acknowledged_at": string,"acknowledged_by": string,"addendum_number": number,"bid_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "acknowledged_at"?: string,"acknowledged_by": string,"addendum_number": number,"bid_id": string
                  }
                  Update: {
                    "acknowledged_at"?: string,"acknowledged_by"?: string,"addendum_number"?: number,"bid_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "bid_acknowledgments_acknowledged_by_fkey"
      columns: ["acknowledged_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "bid_acknowledgments_bid_id_fkey"
      columns: ["bid_id"]
isOneToOne: false
      referencedRelation: "bids"
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
                },"bid_cure_files": {
                  Row: {
                    "bid_id": string,"file_name": string,"id": string,"object_etag": string | null,"object_id": string | null,"object_size": number | null,"path": string,"uploaded_at": string,"uploaded_by": string,"version": number
                  }
                  ComputedFields: never
                  Insert: {
                    "bid_id": string,"file_name": string,"id"?: string,"object_etag"?: string | null,"object_id"?: string | null,"object_size"?: number | null,"path": string,"uploaded_at": string,"uploaded_by": string,"version": number
                  }
                  Update: {
                    "bid_id"?: string,"file_name"?: string,"id"?: string,"object_etag"?: string | null,"object_id"?: string | null,"object_size"?: number | null,"path"?: string,"uploaded_at"?: string,"uploaded_by"?: string,"version"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "bid_cure_files_bid_id_fkey"
      columns: ["bid_id"]
isOneToOne: false
      referencedRelation: "bids"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "bid_cure_files_bid_id_version_fkey"
      columns: ["bid_id","version"]
isOneToOne: false
      referencedRelation: "bid_versions"
      referencedColumns: ["bid_id","version"]
    },{
      foreignKeyName: "bid_cure_files_uploaded_by_fkey"
      columns: ["uploaded_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
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
                    "alternate_cents": (number)[],"apprentice_commitment": boolean | null,"bid_bond_choice": Database["public"]['Enums']["bid_bond_choice"] | null,"bid_id": string,"item_cents": (number)[],"solicitation_version": number,"updated_at": string,"version": number
                  }
                  ComputedFields: never
                  Insert: {
                    "alternate_cents"?: (number)[],"apprentice_commitment"?: boolean | null,"bid_bond_choice"?: Database["public"]['Enums']["bid_bond_choice"] | null,"bid_id": string,"item_cents"?: (number)[],"solicitation_version"?: number,"updated_at"?: string,"version": number
                  }
                  Update: {
                    "alternate_cents"?: (number)[],"apprentice_commitment"?: boolean | null,"bid_bond_choice"?: Database["public"]['Enums']["bid_bond_choice"] | null,"bid_id"?: string,"item_cents"?: (number)[],"solicitation_version"?: number,"updated_at"?: string,"version"?: number
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
                },"bid_outcomes": {
                  Row: {
                    "bid_id": string,"ground": Database["public"]['Enums']["non_responsive_ground"] | null,"id": string,"note": string,"outcome": Database["public"]['Enums']["bid_outcome"],"set_at": string,"set_by": string,"solicitation_id": string,"version": number
                  }
                  ComputedFields: never
                  Insert: {
                    "bid_id": string,"ground"?: Database["public"]['Enums']["non_responsive_ground"] | null,"id"?: string,"note": string,"outcome": Database["public"]['Enums']["bid_outcome"],"set_at"?: string,"set_by": string,"solicitation_id": string,"version": number
                  }
                  Update: {
                    "bid_id"?: string,"ground"?: Database["public"]['Enums']["non_responsive_ground"] | null,"id"?: string,"note"?: string,"outcome"?: Database["public"]['Enums']["bid_outcome"],"set_at"?: string,"set_by"?: string,"solicitation_id"?: string,"version"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "bid_outcomes_bid_id_fkey"
      columns: ["bid_id"]
isOneToOne: false
      referencedRelation: "bids"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "bid_outcomes_bid_id_version_fkey"
      columns: ["bid_id","version"]
isOneToOne: false
      referencedRelation: "bid_versions"
      referencedColumns: ["bid_id","version"]
    },{
      foreignKeyName: "bid_outcomes_bid_solicitation_fkey"
      columns: ["bid_id","solicitation_id"]
isOneToOne: false
      referencedRelation: "bids"
      referencedColumns: ["id","solicitation_id"]
    },{
      foreignKeyName: "bid_outcomes_set_by_fkey"
      columns: ["set_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "bid_outcomes_solicitation_id_fkey"
      columns: ["solicitation_id"]
isOneToOne: false
      referencedRelation: "solicitations"
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
                    "alternate_cents": (number)[],"apprentice_commitment": boolean | null,"bid_bond_choice": Database["public"]['Enums']["bid_bond_choice"] | null,"bid_id": string,"bidder_legal_name": string,"id": string,"item_cents": (number)[],"solicitation_version": number,"submitted_at": string,"submitted_by": string,"version": number
                  }
                  ComputedFields: never
                  Insert: {
                    "alternate_cents": (number)[],"apprentice_commitment"?: boolean | null,"bid_bond_choice"?: Database["public"]['Enums']["bid_bond_choice"] | null,"bid_id": string,"bidder_legal_name": string,"id"?: string,"item_cents": (number)[],"solicitation_version"?: number,"submitted_at"?: string,"submitted_by": string,"version": number
                  }
                  Update: {
                    "alternate_cents"?: (number)[],"apprentice_commitment"?: boolean | null,"bid_bond_choice"?: Database["public"]['Enums']["bid_bond_choice"] | null,"bid_id"?: string,"bidder_legal_name"?: string,"id"?: string,"item_cents"?: (number)[],"solicitation_version"?: number,"submitted_at"?: string,"submitted_by"?: string,"version"?: number
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
                },"cure_deadlines": {
                  Row: {
                    "bid_due_at": string,"cure_due_at": string,"frozen_at": string,"solicitation_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "bid_due_at": string,"cure_due_at": string,"frozen_at"?: string,"solicitation_id": string
                  }
                  Update: {
                    "bid_due_at"?: string,"cure_due_at"?: string,"frozen_at"?: string,"solicitation_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "cure_deadlines_solicitation_id_fkey"
      columns: ["solicitation_id"]
isOneToOne: true
      referencedRelation: "solicitations"
      referencedColumns: ["id"]
    }
                  ]
                },"evaluations": {
                  Row: {
                    "award_disagreed_at": string | null,"award_preparer_id": string | null,"flags_released_at": string | null,"recap_draft": Json | null,"recap_preparer_id": string | null,"solicitation_id": string,"stage": Database["public"]['Enums']["evaluation_stage"],"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "award_disagreed_at"?: string | null,"award_preparer_id"?: string | null,"flags_released_at"?: string | null,"recap_draft"?: Json | null,"recap_preparer_id"?: string | null,"solicitation_id": string,"stage"?: Database["public"]['Enums']["evaluation_stage"],"updated_at"?: string
                  }
                  Update: {
                    "award_disagreed_at"?: string | null,"award_preparer_id"?: string | null,"flags_released_at"?: string | null,"recap_draft"?: Json | null,"recap_preparer_id"?: string | null,"solicitation_id"?: string,"stage"?: Database["public"]['Enums']["evaluation_stage"],"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "evaluations_award_preparer_id_fkey"
      columns: ["award_preparer_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "evaluations_recap_preparer_id_fkey"
      columns: ["recap_preparer_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "evaluations_solicitation_id_fkey"
      columns: ["solicitation_id"]
isOneToOne: true
      referencedRelation: "solicitations"
      referencedColumns: ["id"]
    }
                  ]
                },"flagged_decisions": {
                  Row: {
                    "bid_id": string,"decided_at": string,"decided_by": string,"decision": Database["public"]['Enums']["flag_decision"],"id": string,"outcome_id": string,"reason": string,"solicitation_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "bid_id": string,"decided_at"?: string,"decided_by": string,"decision": Database["public"]['Enums']["flag_decision"],"id"?: string,"outcome_id": string,"reason": string,"solicitation_id": string
                  }
                  Update: {
                    "bid_id"?: string,"decided_at"?: string,"decided_by"?: string,"decision"?: Database["public"]['Enums']["flag_decision"],"id"?: string,"outcome_id"?: string,"reason"?: string,"solicitation_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "flagged_decisions_bid_id_fkey"
      columns: ["bid_id"]
isOneToOne: false
      referencedRelation: "bids"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "flagged_decisions_decided_by_fkey"
      columns: ["decided_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "flagged_decisions_outcome_id_fkey"
      columns: ["outcome_id"]
isOneToOne: false
      referencedRelation: "bid_outcomes"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "flagged_decisions_outcome_match_fkey"
      columns: ["outcome_id","bid_id","solicitation_id"]
isOneToOne: false
      referencedRelation: "bid_outcomes"
      referencedColumns: ["id","bid_id","solicitation_id"]
    },{
      foreignKeyName: "flagged_decisions_solicitation_id_fkey"
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
                },"questions": {
                  Row: {
                    "answered_in": string | null,"asked_at": string,"asked_by": string,"body": string,"close_reason": Database["public"]['Enums']["question_close_reason"] | null,"closed_at": string | null,"closed_by": string | null,"id": string,"org_id": string,"reference": string,"solicitation_id": string,"status": Database["public"]['Enums']["question_status"]
                  }
                  ComputedFields: never
                  Insert: {
                    "answered_in"?: string | null,"asked_at"?: string,"asked_by": string,"body": string,"close_reason"?: Database["public"]['Enums']["question_close_reason"] | null,"closed_at"?: string | null,"closed_by"?: string | null,"id"?: string,"org_id": string,"reference"?: string,"solicitation_id": string,"status"?: Database["public"]['Enums']["question_status"]
                  }
                  Update: {
                    "answered_in"?: string | null,"asked_at"?: string,"asked_by"?: string,"body"?: string,"close_reason"?: Database["public"]['Enums']["question_close_reason"] | null,"closed_at"?: string | null,"closed_by"?: string | null,"id"?: string,"org_id"?: string,"reference"?: string,"solicitation_id"?: string,"status"?: Database["public"]['Enums']["question_status"]
                  }
                  Relationships: [
                    {
      foreignKeyName: "questions_answered_in_fkey"
      columns: ["answered_in"]
isOneToOne: false
      referencedRelation: "addenda"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "questions_asked_by_fkey"
      columns: ["asked_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "questions_closed_by_fkey"
      columns: ["closed_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "questions_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "questions_solicitation_id_fkey"
      columns: ["solicitation_id"]
isOneToOne: false
      referencedRelation: "solicitations"
      referencedColumns: ["id"]
    }
                  ]
                },"recaps": {
                  Row: {
                    "checked_by": string | null,"kind": Database["public"]['Enums']["recap_kind"],"posted_at": string,"prepared_by": string,"single_reviewer": boolean,"snapshot": NonNullable<Json>,"solicitation_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "checked_by"?: string | null,"kind": Database["public"]['Enums']["recap_kind"],"posted_at"?: string,"prepared_by": string,"single_reviewer": boolean,"snapshot": NonNullable<Json>,"solicitation_id": string
                  }
                  Update: {
                    "checked_by"?: string | null,"kind"?: Database["public"]['Enums']["recap_kind"],"posted_at"?: string,"prepared_by"?: string,"single_reviewer"?: boolean,"snapshot"?: NonNullable<Json>,"solicitation_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "recaps_checked_by_fkey"
      columns: ["checked_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "recaps_prepared_by_fkey"
      columns: ["prepared_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "recaps_solicitation_id_fkey"
      columns: ["solicitation_id"]
isOneToOne: true
      referencedRelation: "solicitations"
      referencedColumns: ["id"]
    }
                  ]
                },"resident_verifications": {
                  Row: {
                    "bid_id": string,"certificate": string,"id": string,"note": string,"solicitation_id": string,"verified": boolean,"verified_at": string,"verified_by": string
                  }
                  ComputedFields: never
                  Insert: {
                    "bid_id": string,"certificate": string,"id"?: string,"note": string,"solicitation_id": string,"verified": boolean,"verified_at"?: string,"verified_by": string
                  }
                  Update: {
                    "bid_id"?: string,"certificate"?: string,"id"?: string,"note"?: string,"solicitation_id"?: string,"verified"?: boolean,"verified_at"?: string,"verified_by"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "resident_verifications_bid_id_fkey"
      columns: ["bid_id"]
isOneToOne: false
      referencedRelation: "bids"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "resident_verifications_solicitation_id_fkey"
      columns: ["solicitation_id"]
isOneToOne: false
      referencedRelation: "solicitations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "resident_verifications_verified_by_fkey"
      columns: ["verified_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
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
                },"solicitation_funding": {
                  Row: {
                    "frozen_at": string,"funding_cents": number,"solicitation_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "frozen_at"?: string,"funding_cents": number,"solicitation_id": string
                  }
                  Update: {
                    "frozen_at"?: string,"funding_cents"?: number,"solicitation_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "solicitation_funding_solicitation_id_fkey"
      columns: ["solicitation_id"]
isOneToOne: true
      referencedRelation: "solicitations"
      referencedColumns: ["id"]
    }
                  ]
                },"solicitation_funding_changes": {
                  Row: {
                    "frozen_at": string,"funding_cents": number,"solicitation_id": string,"version": number
                  }
                  ComputedFields: never
                  Insert: {
                    "frozen_at"?: string,"funding_cents": number,"solicitation_id": string,"version": number
                  }
                  Update: {
                    "frozen_at"?: string,"funding_cents"?: number,"solicitation_id"?: string,"version"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "solicitation_funding_changes_solicitation_id_version_fkey"
      columns: ["solicitation_id","version"]
isOneToOne: true
      referencedRelation: "solicitation_versions"
      referencedColumns: ["solicitation_id","version"]
    }
                  ]
                },"solicitation_versions": {
                  Row: {
                    "addendum_path": string | null,"bid_due_at": string,"bid_form_path": string,"published_at": string,"published_by": string | null,"rfb_path": string,"schedule_changed": boolean,"snapshot": NonNullable<Json>,"solicitation_id": string,"version": number
                  }
                  ComputedFields: never
                  Insert: {
                    "addendum_path"?: string | null,"bid_due_at": string,"bid_form_path": string,"published_at"?: string,"published_by"?: string | null,"rfb_path": string,"schedule_changed"?: boolean,"snapshot": NonNullable<Json>,"solicitation_id": string,"version": number
                  }
                  Update: {
                    "addendum_path"?: string | null,"bid_due_at"?: string,"bid_form_path"?: string,"published_at"?: string,"published_by"?: string | null,"rfb_path"?: string,"schedule_changed"?: boolean,"snapshot"?: NonNullable<Json>,"solicitation_id"?: string,"version"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "solicitation_versions_published_by_fkey"
      columns: ["published_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "solicitation_versions_solicitation_id_fkey"
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
            "acknowledge_addendum":
{ Args: { "p_addendum_number": number,"p_bid_id": string }; Returns: undefined
                           },
"acknowledge_warning":
{ Args: { "p_code": string,"p_field": string,"p_id": string }; Returns: undefined
                           },
"addendum_answers_draft":
{ Args: { "p_addendum_id": string }; Returns: {
              "answer": string,"published_question": string,"question_id": string
            }[]
                           },
"addendum_review_info":
{ Args: { "p_addendum_id": string }; Returns: {
              "after_answers_due": boolean,"can_approve": boolean,"can_approve_alone": boolean,"can_disagree": boolean,"can_publish": boolean,"can_reopen": boolean,"can_return": boolean,"can_send": boolean,"can_start": boolean,"can_withdraw": boolean,"checker_id": string,"effective_state": Database["public"]['Enums']["addendum_state"],"reviewer_id": string,"state": Database["public"]['Enums']["addendum_state"]
            }[]
                           },
"agency_flagged_bids":
{ Args: { "p_solicitation_id": string }; Returns: {
              "base_total_cents": number,"decided_at": string,"decision": Database["public"]['Enums']["flag_decision"],"decision_reason": string,"note": string,"outcome_id": string,"reference": string
            }[]
                           },
"agency_questions":
{ Args: { "p_solicitation_id": string }; Returns: {
              "answered_in_number": number,"asked_at": string,"body": string,"id": string,"in_draft": boolean,"reference": string,"status": Database["public"]['Enums']["question_status"]
            }[]
                           },
"approve_addendum_alone":
{ Args: { "p_addendum_id": string }; Returns: undefined
                           },
"approve_addendum_check":
{ Args: { "p_addendum_id": string }; Returns: undefined
                           },
"approve_alone":
{ Args: { "p_id": string }; Returns: undefined
                           },
"approve_check":
{ Args: { "p_id": string }; Returns: undefined
                           },
"ask_question":
{ Args: { "p_body": string,"p_reference": string,"p_solicitation_id": string }; Returns: string
                           },
"award_check_info":
{ Args: { "p_solicitation_id": string }; Returns: {
              "can_check": boolean,"needs_new_pick": boolean,"prepared_by": string
            }[]
                           },
"bidding_state":
{ Args: { "p_solicitation_id": string }; Returns: string
                           },
"close_question":
{ Args: { "p_question_id": string,"p_reason": Database["public"]['Enums']["question_close_reason"] }; Returns: undefined
                           },
"current_award_pick":
{ Args: { "p_solicitation_id": string }; Returns: {
              "bid_id": string,"differs_from_expected": boolean,"picked_at": string,"reason": string,"reference": string
            }[]
                           },
"decide_flagged_bid":
{ Args: { "p_decision": Database["public"]['Enums']["flag_decision"],"p_outcome_id": string,"p_reason": string }; Returns: string
                           },
"disagree":
{ Args: { "p_comment": string,"p_field": string,"p_id": string }; Returns: undefined
                           },
"disagree_addendum":
{ Args: { "p_addendum_id": string,"p_comment": string }; Returns: undefined
                           },
"disagree_award":
{ Args: { "p_comment": string,"p_solicitation_id": string }; Returns: undefined
                           },
"disagree_recap":
{ Args: { "p_comment": string,"p_solicitation_id": string }; Returns: undefined
                           },
"log_bid_original":
{ Args: { "p_item": Database["public"]['Enums']["original_item"],"p_received_at"?: string,"p_reference": string,"p_solicitation_id": string,"p_version": number }; Returns: string
                           },
"my_bid_acknowledgments":
{ Args: { "p_bid_id": string }; Returns: {
              "acknowledged_at": string,"addendum_number": number,"published_at": string
            }[]
                           },
"my_bid_cure":
{ Args: { "p_bid_id": string }; Returns: {
              "due_at": string,"status": string
            }[]
                           },
"my_bid_outcome":
{ Args: { "p_bid_id": string }; Returns: {
              "reason": string,"recap_kind": Database["public"]['Enums']["recap_kind"],"status": string
            }[]
                           },
"my_bid_receipts":
{ Args: { "p_bid_id": string }; Returns: {
              "is_current": boolean,"reference": string,"submitted_at": string,"version": number,"withdrawn_at": string
            }[]
                           },
"my_bid_status_addenda":
{ Args: { "p_bid_id": string }; Returns: {
              "draft_cleared_by": number,"resubmit_required": boolean,"schedule_changed_in": number
            }[]
                           },
"my_questions":
{ Args: { "p_solicitation_id": string }; Returns: {
              "answered_in_number": number,"asked_at": string,"body": string,"close_reason": Database["public"]['Enums']["question_close_reason"],"id": string,"reference": string,"status": Database["public"]['Enums']["question_status"]
            }[]
                           },
"office_bid_index":
{ Args: { "p_solicitation_id": string }; Returns: {
              "reference": string,"status": string,"version": number
            }[]
                           },
"office_questions":
{ Args: { "p_solicitation_id": string }; Returns: {
              "answered_in_number": number,"asked_at": string,"asker_name": string,"body": string,"close_reason": Database["public"]['Enums']["question_close_reason"],"id": string,"org_name": string,"reference": string,"status": Database["public"]['Enums']["question_status"]
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
"pick_award":
{ Args: { "p_bid_id": string,"p_reason": string,"p_solicitation_id": string }; Returns: string
                           },
"post_award":
{ Args: { "p_solicitation_id": string }; Returns: undefined
                           },
"post_award_alone":
{ Args: { "p_solicitation_id": string }; Returns: undefined
                           },
"post_recap":
{ Args: { "p_solicitation_id": string }; Returns: undefined
                           },
"post_recap_alone":
{ Args: { "p_solicitation_id": string }; Returns: undefined
                           },
"preview_recap":
{ Args: { "p_solicitation_id": string }; Returns: Json
                           },
"publish_addendum":
{ Args: { "p_addendum_id": string,"p_addendum_path": string,"p_bid_due_at": string,"p_bid_form_path": string,"p_funding_cents": number,"p_rfb_path": string,"p_snapshot": Json }; Returns: number
                           },
"publish_solicitation":
{ Args: { "p_bid_due_at": string,"p_bid_form_path": string,"p_funding_cents": number,"p_id": string,"p_rfb_path": string,"p_snapshot": Json }; Returns: undefined
                           },
"published_answers":
{ Args: { "p_solicitation_id": string }; Returns: {
              "addendum_number": number,"answer": string,"published_question": string
            }[]
                           },
"reassign_addendum_review":
{ Args: { "p_addendum_id": string,"p_user": string }; Returns: undefined
                           },
"reassign_review":
{ Args: { "p_id": string,"p_user": string }; Returns: undefined
                           },
"recall_award":
{ Args: { "p_solicitation_id": string }; Returns: undefined
                           },
"recall_recap":
{ Args: { "p_solicitation_id": string }; Returns: undefined
                           },
"recap_draft":
{ Args: { "p_solicitation_id": string }; Returns: Json
                           },
"register_bidder":
{ Args: { "p_address": string,"p_contact_email": string,"p_contact_name": string,"p_contact_phone": string,"p_legal_name": string,"p_resident_certificate": string,"p_resident_claimed": boolean }; Returns: string
                           },
"remove_addendum_answer":
{ Args: { "p_addendum_id": string,"p_question_id": string }; Returns: undefined
                           },
"reopen_addendum_review":
{ Args: { "p_addendum_id": string,"p_reason": string }; Returns: undefined
                           },
"reopen_review":
{ Args: { "p_id": string,"p_reason": string }; Returns: undefined
                           },
"replace_bid":
{ Args: { "p_bid_id": string }; Returns: undefined
                           },
"resident_claims":
{ Args: { "p_solicitation_id": string }; Returns: {
              "bid_id": string,"certificate": string,"note": string,"reference": string,"verified": boolean,"verified_at": string
            }[]
                           },
"return_addendum":
{ Args: { "p_addendum_id": string,"p_comments": Json }; Returns: undefined
                           },
"return_to_agency":
{ Args: { "p_comments": Json,"p_id": string }; Returns: undefined
                           },
"review_bids":
{ Args: { "p_solicitation_id": string }; Returns: {
              "alternate_cents": (number)[],"apprentice_commitment": boolean,"base_total_cents": number,"bid_id": string,"bidder_name": string,"bidder_org_id": string,"cure_due_at": string,"cure_status": string,"ground": Database["public"]['Enums']["non_responsive_ground"],"missing_addenda": (number)[],"note": string,"outcome": Database["public"]['Enums']["bid_outcome"],"outcome_id": string,"reference": string,"status": string,"status_reason": string,"version": number
            }[]
                           },
"save_addendum":
{ Args: { "p_addendum_id": string,"p_data": Json,"p_narrative": string }; Returns: undefined
                           },
"save_addendum_answer":
{ Args: { "p_addendum_id": string,"p_answer": string,"p_published_question": string,"p_question_id": string }; Returns: undefined
                           },
"send_addendum_to_check":
{ Args: { "p_addendum_id": string }; Returns: undefined
                           },
"send_award_to_check":
{ Args: { "p_solicitation_id": string }; Returns: undefined
                           },
"send_flags_to_agency":
{ Args: { "p_solicitation_id": string }; Returns: undefined
                           },
"send_recap_to_check":
{ Args: { "p_solicitation_id": string }; Returns: undefined
                           },
"send_to_check":
{ Args: { "p_id": string }; Returns: undefined
                           },
"set_bid_outcome":
{ Args: { "p_bid_id": string,"p_ground": Database["public"]['Enums']["non_responsive_ground"],"p_note": string,"p_outcome": Database["public"]['Enums']["bid_outcome"] }; Returns: string
                           },
"solicitation_addenda":
{ Args: { "p_solicitation_id": string }; Returns: {
              "effective_state": Database["public"]['Enums']["addendum_state"],"id": string,"number": number,"published_at": string,"published_version": number,"state": Database["public"]['Enums']["addendum_state"]
            }[]
                           },
"solicitation_version_list":
{ Args: { "p_solicitation_id": string }; Returns: {
              "addendum_path": string,"bid_form_path": string,"is_current": boolean,"published_at": string,"rfb_path": string,"version": number
            }[]
                           },
"stale_bids":
{ Args: { "p_solicitation_id": string }; Returns: {
              "bid_id": string,"bidder_legal_name": string,"reference": string,"solicitation_version": number,"version": number
            }[]
                           },
"start_addendum":
{ Args: { "p_solicitation_id": string }; Returns: string
                           },
"start_addendum_review":
{ Args: { "p_addendum_id": string }; Returns: undefined
                           },
"start_bid":
{ Args: { "p_solicitation_id": string }; Returns: string
                           },
"start_review":
{ Args: { "p_id": string }; Returns: undefined
                           },
"submit_addendum":
{ Args: { "p_addendum_id": string }; Returns: undefined
                           },
"submit_bid":
{ Args: { "p_bid_id": string }; Returns: {
              "reference": string,"submitted_at": string,"version": number
            }[]
                           },
"submit_cure_bond":
{ Args: { "p_bid_id": string,"p_file_name": string,"p_path": string }; Returns: string
                           },
"submit_solicitation":
{ Args: { "p_id": string }; Returns: undefined
                           },
"verify_resident":
{ Args: { "p_bid_id": string,"p_note": string,"p_verified": boolean }; Returns: string
                           },
"void_bid_original":
{ Args: { "p_entry_id": string,"p_reason": string }; Returns: string
                           },
"withdraw_addendum":
{ Args: { "p_addendum_id": string,"p_reason": string }; Returns: undefined
                           },
"withdraw_bid":
{ Args: { "p_bid_id": string }; Returns: undefined
                           }
          }
          Enums: {
            "addendum_state": "draft"|"submitted"|"in_review"|"in_check"|"approved"|"published"|"withdrawn","bid_bond_choice": "electronic"|"paper","bid_outcome": "accepted"|"accepted_flagged"|"non_responsive","bid_upload_slot": "insurance"|"qualifications"|"references"|"current_work"|"bid_bond","comment_kind": "return"|"disagree"|"note","evaluation_stage": "bid_review"|"recap_check"|"recap_posted"|"award_check"|"awarded"|"all_rejected","flag_decision": "accept"|"reject","non_responsive_ground": "late_upload"|"wrong_form"|"missing_signature","org_kind": "agency"|"office"|"bidder","original_item": "signed_form"|"bid_bond","question_close_reason": "duplicate"|"out_of_scope","question_status": "open"|"answered"|"closed","recap_kind": "recap"|"all_rejected","solicitation_state": "draft"|"submitted"|"in_review"|"in_check"|"approved"|"published"
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
            "addendum_state": ["draft", "submitted", "in_review", "in_check", "approved", "published", "withdrawn"],"bid_bond_choice": ["electronic", "paper"],"bid_outcome": ["accepted", "accepted_flagged", "non_responsive"],"bid_upload_slot": ["insurance", "qualifications", "references", "current_work", "bid_bond"],"comment_kind": ["return", "disagree", "note"],"evaluation_stage": ["bid_review", "recap_check", "recap_posted", "award_check", "awarded", "all_rejected"],"flag_decision": ["accept", "reject"],"non_responsive_ground": ["late_upload", "wrong_form", "missing_signature"],"org_kind": ["agency", "office", "bidder"],"original_item": ["signed_form", "bid_bond"],"question_close_reason": ["duplicate", "out_of_scope"],"question_status": ["open", "answered", "closed"],"recap_kind": ["recap", "all_rejected"],"solicitation_state": ["draft", "submitted", "in_review", "in_check", "approved", "published"]
          }
        }
} as const
