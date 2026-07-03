# Licensing CRM + Idea Detail UI — Design

Date: 2026-07-04
Status: Approved

## Goal
1. UI polish on `/ideas/:id`: equal-size action buttons; hero image blends seamlessly into the tabbed-content card; general Dark Forge refinement.
2. Per-idea "for licensing" flag. When set, hide Tools + Notes tabs, show a **Potential Licensors** tab.
3. A Twenty-style CRM at `/licensing/crm` aggregating every for-licensing idea's licensors: records table + kanban board + slide-over record panel with a dated contact log. Tracks who was contacted, when, and at what stage.

## Data model
- `ideas.for_licensing` — boolean, default false, not null.
- **Licensor** `belongs_to :idea`, `has_many :contacts (LicensorContact)`:
  - `company` (required), `contact_name`, `contact_email`, `contact_url`, `notes`, `next_action`
  - `stage` enum: `identified, contacted, meeting, negotiating, closed_won, closed_lost`
  - `last_contacted_at` (datetime), `position` (int, kanban order within stage)
- **LicensorContact** `belongs_to :licensor`:
  - `occurred_at` (datetime), `channel` enum (`email, call, meeting, note, other`), `summary` (text)
  - `after_create` → set parent `last_contacted_at = max(occurred_at)`.
- Idea `has_many :licensors, dependent: :destroy`. Permit `:for_licensing`.

All access scoped through `@user.ideas` → licensors → contacts (security boundary; no cross-user access).

## Idea show page
- `for_licensing?` true → omit `tool` and `notes` tab buttons/panels; render **Potential Licensors** tab.
- Tab: add-licensor form + list. Each row: company, contact, stage pill, last-contacted relative time, "Log contact" + edit/delete. Mirrors `idea_entries` turbo-stream patterns.

## /licensing/crm (Twenty-style, app dark theme via existing CSS vars)
- Header: title, **Board / Table** toggle, per-stage count chips, filter-by-idea.
- **Board**: column per stage; card = company + idea badge + last-contacted. Drag card → PATCH stage + position.
- **Table**: rows — Company · Idea · Stage · Contact · Last contacted · Next action; sortable.
- **Slide-over record panel** (Turbo frame): licensor fields + contact-log timeline + "Log contact" form; edit stage/fields inline.

## Routes
```
resources :ideas do resources :licensors, only: [:create] end
resources :licensors, only: [:show, :update, :destroy] do
  resources :contacts, only: [:create, :destroy], controller: :licensor_contacts
end
namespace :licensing do get 'crm', to: 'crm#index' end
```
Controllers: `LicensorsController`, `LicensorContactsController`, `Licensing::CrmController`.

## UI polish
- `.header-actions .btn` uniform min-width + height (equal-size row).
- Unify hero image + `.idea-main-content`: hero caps the card, top corners rounded, squared seam into `.tabs-nav`, panel bottom rounded.
- Spacing/hierarchy refinement.
- Nav entry linking to `/licensing/crm`.

## Skipped (v1)
Configurable stages · separate Company/People entities · CRM full-text search · bulk actions.

## Tests
Model: Licensor validations + stage enum, LicensorContact bumps last_contacted_at, idea for_licensing scope. Controller: licensor CRUD scoped to user, CRM index, contact create/destroy. Full suite + migrations must pass.
