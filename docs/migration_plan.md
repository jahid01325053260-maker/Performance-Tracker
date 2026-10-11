# Legacy data migration and safety plan

**This ZIP does not modify the live Firebase project.** It only contains client code and proposed Firestore Rules. The same original Firebase project is retained; no new project is necessary.

1. Before deploy: preserve or safely back up `employees`, `performance`, `targets`, `login_index`, `auth_users` and Firebase Auth user records using trusted export mechanisms. Spark does not include the paid Firestore managed backup/PITR feature.
2. Use Firebase Emulator or a test project to verify role-based rules, Login, Registration and Approval. The old Android client's migration behavior may fail under the new rules. Plan cutover; don't deploy the new rules blindly.
3. The old app may use `login_index/{sha256(ID)}` to resolve its Firebase Authentication email. The new app can read that single index entry for legacy accounts. For new accounts, it derives the private login alias from ID and creates only `auth_users` + `employees` in one Firestore batch.
4. Old Firestore-plaintext-password records are NOT automatically migrated. Such users must have verified Firebase Auth accounts and matching `auth_users/{uid}`, `employees/{id}.authUid` before the new Login works. Never copy plaintext passwords into the new client.
5. Before approving anybody as ADMIN, verify the person's identity and use existing trusted Firebase Admin tooling / console account mapping. New user registration ALWAYS creates `USER / Pending`; existing Approved ADMIN approves and can select USER/Sales Manager/AGM/DGM.
6. Old performance records may lack `year`, `reportingPeriod`, `managerId`, or normalized account keys. Review dates before migration. Sales Manager scoped reports require `managerId` in record data, otherwise legacy records won't be queryable by manager.
7. New target documents use the year-aware ID `{employeeId}_{YYYY-MM}`; legacy `{employeeId}_{MONTH}` documents remain untouched and can still be read, but require review before matching an annual period.
8. Admin publishes the aggregate leaderboard after record changes. This allows employees to see verified ranking without access to private applicant records but can lag real-time changes.
9. Test normal and management users, monthly/yearly targets, nil, export, admin approval, denied cross-user applicant queries, old-client compatibility and duplicate submission in the emulator before rollout. Keep a rollback copy of the old rules.

Read [Spark Free Setup](spark_free_setup_bn.md) and [Security Model](security_model.md).
