# File Storage

Idea Foundry treats uploaded files as application data, not cache. Local files
must stay co-located with the SQLite databases so the app can load them quickly
and so a single storage backup captures the whole workspace.

## Storage Location

- Active Storage uses the Rails disk service rooted at `storage/`.
- SQLite databases also live in `storage/`.
- Docker and Podman deployments mount `./storage:/rails/storage`.

Keep `storage/` on durable local disk. Do not put it on ephemeral container
storage, tmpfs, or a remote mount with high latency.

## Backup Contract

Backups must include both:

- The SQLite databases: `production.sqlite3` and `queue.sqlite3`.
- Active Storage blob files under the hashed subdirectories in `storage/`.

`bin/backup` snapshots the databases with `VACUUM INTO` and archives the local
Active Storage files into `active_storage_<timestamp>.tar.gz`. This makes the
manual backup path safe to run while the app is live and keeps uploaded files in
the same backup set as database records.

Scheduled in-app backups use `WorkspaceExportJob`, which exports every
user-owned Active Storage attachment, including idea media, drawing renders,
submission files, backlog images, and rich-text embeds.

## Restore Notes

Restore the database snapshots and Active Storage archive together. Database
rows reference blobs by Active Storage key, so restoring only the databases or
only the files can leave records pointing at missing data.
