# Trusted ADMIN bootstrap instructions

The public signup API always creates `USER + Pending` and can **never** create an ADMIN. If an ADMIN already exists in the legacy database, it can be used after confirming its Authentication UID and profile role/status in staging.

For a new environment, provision initial ADMIN **using a privileged one-time operator script in your private infrastructure**:

1. Via Firebase Admin SDK create an Auth user with private email alias/password (store credentials only in secure manager).
2. Write `employees/{employeeId}` with `role=ADMIN`, `status=Approved`, `authUid=<new uid>`, name, branch, and 12-digit ID.
3. Write `auth_users/{uid}` with matching employeeId, role, status.
4. Write `login_index/{SHA256(employeeId)}` with `email` matching Auth user, `authUid`, and employeeId.
5. Restrict this script to trusted deployment personnel; never expose a bootstrap endpoint in the app.

After verification, disable bootstrap privileges and confirm that a USER cannot call ADMIN APIs.

This project also provides `bootstrap_admin.js` for new/test Firebase projects. Run **only** from trusted operator infrastructure with Application Default Credentials and environment variables set:

```
FIREBASE_PROJECT_ID=... ADMIN_EMPLOYEE_ID=000000000001 ADMIN_NAME='Primary Admin' ADMIN_PASSWORD='secure-12-plus-character-secret' npm run bootstrap
```

Do not include this password in committed scripts, shell history, screenshots or build logs. For production supply credentials via protected secret injection. The script refuses to change an existing employee.
