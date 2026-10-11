# Direct Firestore security model — Spark Free

**Authoritative access policy** is `backend/firestore.rules` (not Flutter widget role checks).

- New user registers as `USER/Pending` in `employees/{id}` and `auth_users/{uid}` using one Firestore batch after Firebase Auth creation. Neither side can self-create ADMIN or self-change role/approval.
- An existing Approved ADMIN must approve accounts, in one batch updating role/status in both docs.
- Accepted `performance` writes require a verified and approved officer and deterministic per-employee per-period account doc ID. Other officers cannot read individual applicant records. ADMIN may read all records, Sales Manager scoped to `managerId` fields.
- Approved directory is visible to other approved employees and may contain personal contact details. Limit fields on UI and review internal data privacy before production.
- A `login_index/{sha256(ID)}` direct `get` is publicly readable to preserve old Android account login. **This has an employee-enumeration/email-disclosure risk** for known IDs; no collection listing allowed, and new aliases do not create index records. A future trusted ID-resolution service or managed account-email migration should eliminate this risk.
- Published `leaderboard/` is admin-owned. It is stale between publishes; normal employees do not get cross-user Applicant details.
- Firebase Authentication does not itself know company roles; all Firestore reads require verified matching `auth_users` and `employees` records.
- Spark-only rules are incompatible with portions of the old Kotlin app's registration/migration writes. Stage and test before deploying on production.
- Firestore rules are static and have limits: they cannot enforce all cross-record monthly NIL/card uniqueness guarantees or replace a trusted administrator for creating Firebase Auth accounts, backups and credential resets.
