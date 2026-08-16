# Age verification validation — 2026-08-15

## Exact Firestore Rules rollback

- Previous Rules SHA-256: `96de3204401f11f2c4a6e3f607c7709245e77ed3c4bb4f6f86792f215d89cf90`.
- Candidate Rules SHA-256 before the navigation hardening audit: `497fa33cc677df5067f79a2eb72fd1f7903f42eab242bfd4512d953facb45933`.
- The previous file is the repository `HEAD` version: `git show HEAD:firestore.rules`.
- `docs/age-verification-firestore-rules-rollback.patch` is the reverse patch for only the age-verification Rules changes.

Before any future Rules deployment, export the active production Rules and
compare their SHA-256 with the expected previous hash. If it differs, stop;
do not assume repository `HEAD` is the live rollback source.

Rollback procedure after approval:

1. Restore the exported production Rules (preferred), or apply the reverse patch.
2. Run the complete emulator Rules suite against the restored file.
3. Deploy only `firestore.rules` after explicit authorization.
4. Verify login, own-user read, messages, groups, events, presence and deletion.

No deploy was performed during this validation.
