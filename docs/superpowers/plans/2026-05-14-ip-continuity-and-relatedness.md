# IP Continuity and Relatedness Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Turn Idea Foundry into an IP continuity system: track whether ideas are protected/registered, represent IP as durable assets, define posthumous/continuity forwarding rules, link ideas to external work/plans, support stronger voice+typing identity checks, and surface related ideas/facts/knowledge-base items.

**Architecture:** Add first-class Rails models around ideas instead of overloading `ideas.metadata`: `IpAsset`, `IdeaWorkLink`, `ContinuityPlan`, `ContinuityRecipient`, `ContinuityRule`, `IdeaRelationship`, and `IdeaFactLink`. Keep current `IdeaEntry` competitors/tools intact. Use background jobs/services for recommendations and relatedness so the core UI stays fast. Store sensitive continuity and voice identity data as derived hashes/templates only; never store raw passwords or raw voice audio as authentication secrets.

**Tech Stack:** Rails 8, ActiveRecord, ActionText, ActiveStorage, Solid Queue jobs, Minitest, existing typing fingerprint lock, existing workspace export/backup pipeline.

---

## Current App Findings

- `Idea` already has lifecycle state, score fields, topologies, lists, versions, notes, todo items, drawings, attachments, and `metadata` JSON.
- `IdeaEntry` currently covers only `tool`, `competitor`, and `potential_competitor`; it is not the right place for implementation-plan links or IP registrations.
- `Fact` exists as standalone user-owned knowledge-base snippets but has no association to ideas.
- Knowledge-base folder settings exist at `User#kb_folders`, but there is no indexed KB item model yet.
- Workspace export/backup already exists (`ExportJob`, `WorkspaceExportJob`, scheduled backup settings), but it exports only lists, ideas, versions, templates, and attachments. It does not include facts, notes, todo items, drawings, idea entries, continuity rules, recipients, or IP assets.
- Security already has typing fingerprint and TOTP authenticator support. Voice ID is not present.
- Idea detail has an always-visible Enrich tab and optional tabs controlled by `User::AVAILABLE_IDEA_TABS`, but `enrichment` is not part of `AVAILABLE_IDEA_TABS`.

---

## Feature Slices

### Slice 1: External Work / Plan Links

**User need:** “Add a link if the idea is worked on and plans are elsewhere (link).”

**Data model:**
- `idea_work_links`
  - `idea_id: references, null: false`
  - `label: string, null: false`
  - `url: string, null: false`
  - `kind: integer, null: false, default: 0` (`plan`, `repository`, `prototype`, `doc`, `task_board`, `other`)
  - `status: integer, null: false, default: 0` (`planned`, `active`, `paused`, `complete`, `abandoned`)
  - `notes: text`
  - `position: integer`

**Acceptance criteria:**
- Idea detail page shows an “External Work” tab/card with links.
- User can add, edit, delete, and reorder links on an idea.
- Links are included in idea history snapshots and workspace export.
- Invalid URLs are rejected.

### Slice 2: IP Asset Registry and Registration Loop Closure

**User need:** “Close the loop on idea as IP management, when they have been registered and if fully or partially.”

**Data model:**
- `ip_assets`
  - `idea_id: references, null: false`
  - `title: string, null: false`
  - `asset_type: integer, null: false` (`invention`, `copyright`, `trademark`, `trade_secret`, `domain`, `software`, `dataset`, `other`)
  - `protection_status: integer, null: false, default: 0` (`unregistered`, `drafting`, `filed`, `partially_registered`, `registered`, `rejected`, `expired`, `abandoned`)
  - `coverage_scope: integer, null: false, default: 0` (`none`, `partial`, `full`)
  - `jurisdiction: string`
  - `registration_number: string`
  - `filed_on: date`
  - `registered_on: date`
  - `expires_on: date`
  - `owner_name: string`
  - `chain_of_title_notes: text`
  - `public_disclosure_on: date`
  - `confidentiality_level: integer, null: false, default: 0` (`normal`, `confidential`, `secret`)
  - `metadata: text/json`

**Acceptance criteria:**
- Idea detail shows IP status summary: unprotected / partial / registered / needs renewal.
- “Close the loop” checklist: owner identified, disclosure risk checked, registration evidence attached, renewal date known, continuity recipient selected.
- Partial registrations can record exactly what is protected vs still unprotected.
- Expiring assets appear in recommendations.

### Slice 3: Built-in IP Recommendations

**User need:** “IP management (built-in), with recommendations, etc.”

**Service:** `IpRecommendationService`

**Inputs:** idea state, description, topologies, scores, IP assets, public disclosure dates, external work links, facts.

**Outputs:** structured recommendations:
- `protect_before_public_launch`
- `add_owner_or_chain_of_title`
- `renewal_due`
- `consider_trade_secret`
- `consider_copyright_notice`
- `consider_trademark_search`
- `needs_external_plan_link`
- `missing_continuity_recipient`

**Acceptance criteria:**
- Recommendations are deterministic initially; no LLM dependency required.
- Each recommendation has severity, rationale, and action link.
- Recommendations are visible on idea detail and an IP dashboard.

### Slice 4: IP as Assets with Continuity

**User need:** “IP as assets with continuity.”

**Data model additions:**
- `ip_asset_events`
  - `ip_asset_id`
  - `event_type` (`created`, `filed`, `registered`, `renewed`, `assigned`, `licensed`, `disclosed`, `expired`, `abandoned`)
  - `event_date`
  - `notes`
  - optional attachment evidence

**Acceptance criteria:**
- Each IP asset has an audit/event timeline.
- Assignment/license/ownership changes are evented, not just overwritten.
- Workspace export includes asset timeline and evidence attachments.

### Slice 5: “What Happens When You Die” Continuity Forwarding

**User need:** “What happens when you die, setup forwarding of this database. With rules and a charter.”

**Data model:**
- `continuity_plans`
  - `user_id`
  - `enabled: boolean`
  - `charter: text`
  - `check_in_frequency_days: integer`
  - `last_check_in_at: datetime`
  - `dead_man_switch_after_days: integer`
  - `status: integer` (`draft`, `active`, `paused`, `triggered`, `revoked`)
- `continuity_recipients`
  - `continuity_plan_id`
  - `name`, `email`, `role` (`executor`, `beneficiary`, `advisor`, `archive_custodian`)
  - `verification_notes`
  - `priority`
- `continuity_rules`
  - `continuity_plan_id`
  - `scope_type` (`all_database`, `idea`, `ip_asset`, `topology`, `list`)
  - `scope_id`
  - `recipient_id`
  - `action` (`notify`, `share_export`, `transfer_stewardship`, `archive_only`, `exclude`)
  - `conditions: json/text`

**Important safety note:** Build this as an export-and-notification system first, not legal transfer automation. The charter should clearly state it is operational continuity metadata, not legal advice.

**Acceptance criteria:**
- Settings page has “Continuity” section with charter editor, recipients, and rules.
- User can run a dry-run showing who receives what.
- Trigger path creates an export package plus `CONTINUITY_CHARTER.md` and `RULES.json`.
- No continuity package sends automatically until an explicit active plan and validated check-in policy exist.

### Slice 6: Voice ID + Typing + Voice Challenge

**User need:** “Add Voice id (my voice is my password) + typing + voice.”

**Approach:** Extend security settings with `VoiceIdentity` templates and a combined challenge flow:
- Existing typing fingerprint remains factor one.
- Voice ID becomes factor two or an unlock supplement.
- Prefer passphrase + voiceprint features; do not store raw passphrase as password.

**Data model:**
- `voice_identity_profiles`
  - `user_id`
  - `enabled: boolean`
  - `phrase_digest: string`
  - `voice_template: text/json` (provider-neutral feature vector, encrypted if possible)
  - `sample_count: integer`
  - `last_enrolled_at`
  - `last_verified_at`

**Implementation caution:** Browser-side microphone capture + server-side voice verification is non-trivial and security-sensitive. Start with enrollment/recording UX behind a feature flag, then plug in a verification adapter. Never market voice ID alone as high-security authentication; use it with typing/TOTP.

**Acceptance criteria:**
- User can enroll voice phrase samples.
- Unlock can require typing only, typing+TOTP, or typing+voice.
- Failed voice attempts respect the same cooldown pattern as typing lock.
- Tests cover missing microphone payloads, malformed samples, and disabled voice ID.

### Slice 7: Related Ideas, Clusters, Facts, and Knowledge Base

**User need:** “find related (ideas -> then cluster), facts to the ideas, things in the knowledge base to the ideas, etc.”

**Data model:**
- `idea_relationships`
  - `source_idea_id`, `target_idea_id`
  - `relationship_type` (`similar`, `depends_on`, `overlaps`, `competes`, `supersedes`, `derived_from`)
  - `score: decimal`
  - `explanation: text`
  - `accepted: boolean`
- `idea_fact_links`
  - `idea_id`, `fact_id`
  - `score`, `explanation`, `accepted`
- optional later: `knowledge_base_items`
  - `user_id`, `source_path`, `title`, `body`, `checksum`, `indexed_at`

**Services:**
- `RelatedIdeaService` — deterministic text similarity first (`title`, description plain text, topologies, facts), later embeddings.
- `IdeaClusteringService` — cluster related ideas into topologies or suggested lists.
- `KnowledgeBaseIndexer` — turns configured KB folders into searchable items.

**Acceptance criteria:**
- Idea detail has “Related” tab with related ideas, facts, and KB items.
- User can accept/reject suggested relationships.
- Accepted idea relationships can create topology/list membership suggestions.
- Relatedness works without external APIs; embeddings can be an adapter later.

---

## Suggested Implementation Order

1. **External Work Links** — smallest/high-value; establishes pattern for idea-owned records.
2. **IP Assets basic registry** — core “ideas as IP” loop closure.
3. **IP Recommendations** — deterministic rules using new registry data.
4. **Export/Backup coverage update** — include all new continuity/IP/link/relation records plus existing omitted records.
5. **Continuity plan, recipients, rules, charter, dry-run** — safe non-automatic continuity layer.
6. **Relatedness: facts + ideas** — link facts and similar ideas before full KB indexing.
7. **KB indexing + clustering** — larger background-processing piece.
8. **Voice ID** — defer until security model and adapter are chosen.

---

## First PR Proposal: External Work Links + Export Coverage Prep

**Objective:** Ship the “plans are elsewhere” link feature and prepare export serialization conventions for new records.

**Files:**
- Create migration: `db/migrate/*_create_idea_work_links.rb`
- Create model: `app/models/idea_work_link.rb`
- Modify: `app/models/idea.rb`
- Create controller: `app/controllers/idea_work_links_controller.rb`
- Modify routes: `config/routes.rb`
- Create partial: `app/views/ideas/_work_links.html.erb`
- Modify: `app/views/ideas/show.html.erb`
- Modify: `app/jobs/workspace_export_job.rb`
- Tests: `test/models/idea_work_link_test.rb`, `test/controllers/idea_work_links_controller_test.rb`

**Verification commands:**

```bash
bin/rails test test/models/idea_work_link_test.rb test/controllers/idea_work_links_controller_test.rb
bin/rails test test/jobs/workspace_export_job_test.rb
```

---

## Open Product Decisions

- Should continuity recipients receive the full database export, only selected IP assets, or both?
- Should IP evidence files be stored as normal idea attachments, dedicated `IpAsset` attachments, or both?
- Do you want “registration” to mean formal legal registration only, or also internal private proof-of-conception records?
- Should relatedness auto-create topology clusters, or only suggest clusters until accepted?
- For Voice ID: local-only verification, third-party voice biometrics API, or feature-flagged placeholder until provider decision?
