# Draft Rules notes — events date organization (LOCAL ONLY)

Do **not** deploy without authorization.

## Current (mobile)
- `events` create: denied (CF/Admin only)
- `events` update: admin permission only
- Organizers already cannot client-write `archived` / `deleted`

## Additions to enforce after Functions land
1. Keep client create/update denied for event docs.
2. Document that `archived`, `archivedAt`, `deleted`, `permanentlyDeletedAt`, counters, `attendeesUids`, `status`, `isActive` are server-owned.
3. Optional: deny client writes to `events/{id}/attendees` if not already (join/leave via CF).

## Canonical modeling proposal (if composite queries struggle)
Server-owned boolean `publicListed` (or enum `visibility`) written only by CF on approve / cancel / archive / delete.
- Never trust client to set it.
- Date buckets (upcoming/live/past) still computed from `startAt`/`endAt` UTC — no minute cron.
- After authorized backfill: set `archived:false`, `deleted:false`, `endAt`, `eventTimeZone` on legacies with explicit per-case proposal (no blanket +24h).
