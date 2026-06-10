# Attachment System Design

**Date:** 2026-05-19

## Problem

- Show page renders attachments without position ordering; no inline open
- Form attachment items are static after upload (no viewer)
- `purge_later` is unreliable for precious files (lost on restart)
- No rename or replace capability

## Goals

- Attachments render on show page in position order, clickable to open inline
- Upload works in form (already works via draft auto-create), items appear in list
- Clicking any attachment in the form opens a modal: preview, rename, replace, delete
- Delete is synchronous (`purge`), never fire-and-forget
- Replace preserves position in list

## Out of Scope

- Attachment editing on the show page (read-only there)
- Bulk operations

---

## Architecture

### Routes

Add `:update` to `idea_attachments` resources:

```ruby
resources :attachments, only: [:create, :destroy, :update], controller: :idea_attachments do
  collection { patch :reorder }
  member do
    post :ocr
    patch :update
  end
end
```

### Controller: `IdeaAttachmentsController`

**`update` action** — handles rename and/or file replace:
1. Find attachment by id within idea's attachments
2. If `params[:filename]` present → `attachment.blob.update!(filename: params[:filename])`
3. If `params[:file]` present → save position, `attachment.purge`, attach new file, set position on new attachment
4. Return rendered `_item.html.erb` partial as JSON

**`destroy` action** — change `purge_later` → `purge` (synchronous)

### Views

**`show.html.erb`**
- Replace `@idea.attachments.each` with `@idea.ordered_attachments.each`
- Each item: thumbnail/icon + name + size + link to open inline (new tab, `disposition: "inline"`)

**`_form.html.erb` attachment items**
- Each `_item.html.erb` gets a `data-action="click->attachment-viewer#open"` and data attributes: id, filename, url, content-type, destroy-url, update-url

**`idea_attachments/_item.html.erb`**
- Add data attributes for viewer: `data-attachment-viewer-*`
- Rename the destroy button's action to `attachment-viewer#openDelete` (so delete goes through modal)
- Remove old `attachment-reorder#destroyItem` action from the ×-button; keep drag/reorder actions

**Modal** — added once to the form layout or at bottom of `_form.html.erb`:
```html
<dialog data-controller="attachment-viewer" ...>
  <img/embed/icon preview area>
  <input type="text" for filename rename>
  <input type="file" for replace>
  <button delete>
  <button close>
</dialog>
```

### Stimulus: `attachment-viewer` controller

Targets: `dialog`, `preview`, `filenameInput`, `fileInput`, `deleteBtn`
Values: `updateUrl` (String), `destroyUrl` (String), `contentType` (String), `attachmentId` (Number)

**`open(event)`**: populate modal from `event.currentTarget.dataset`, show dialog
**`save()`**: PATCH with filename (and/or file), replace list item with returned HTML, close
**`confirmDelete()`**: DELETE request, remove list item, close
**`close()`**: `this.dialogTarget.close()`

### Data flow: Replace file

1. User picks new file in modal → `save()` called with `file` param
2. PATCH `/ideas/:id/attachments/:attachment_id`
3. Controller: saves `position`, calls `attachment.purge` (sync), attaches new file, sets position
4. Returns new `_item.html.erb` HTML
5. JS replaces the old `<li>` with the new one, closes modal

---

## Key Invariants

- Files are only deleted when the user explicitly confirms deletion
- `purge` (not `purge_later`) used everywhere to ensure immediate, reliable removal
- Position is preserved across renames and replacements
- Show page is read-only (no delete/edit controls there)
