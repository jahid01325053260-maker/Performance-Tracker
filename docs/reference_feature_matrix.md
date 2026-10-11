# Native Android to Flutter: implementation tracking

Legacy inspection based on uploaded `PerformanceTracker(1)(1).zip` and its XML/Kotlin source.
This is the state of THIS new deliverable, not a promise that all prompt features are finished.

| Old native feature | New Flutter status | Current limitation |
|---|---|---|
| Login with employee ID | Implemented API + UI | Firebase credentials/deployment needed; token refresh not implemented |
| Pending employee registration (email optional) | Implemented API + UI | No photo at registration; password reset is an admin process |
| Admin approval/reject | Implemented API + UI | No Firebase Auth disable on reject (API blocks login) |
| Create Sales Manager, AGM, DGM | Implemented API + UI | Requires a provisioned approved ADMIN |
| User Dashboard | Implemented | Summary and cards, responsive |
| Admin/management dashboard | Partial | Month view, directory, target, export, trend; no full legacy filter set |
| Manual cards and NIL | Implemented | Internet required; batch/retry uses deterministic IDs |
| KPI PDF import | Partial | Server conservatively extracts 906 numbers, review required; no scanned OCR |
| Profile and photos | Partial | Displays existing photos; permitted profile photo update via Base64 (resize/compress), signup photo omitted |
| Employee directory and role chips | Implemented | Scoped roster for managers, regular users see approved directory |
| Officer ranking with podium | Implemented | All-time scope only, no individual selected-period search filters |
| Monthly targets, below-50 warnings | Implemented | New targets are year-aware; existing legacy ambiguous targets need migration |
| My Reports, details and edit/delete | Implemented | Account-number replacement requires delete + submit |
| Not Submitted | Implemented | Authenticated report scope, NIL counts as submitted |
| 12-month trends | Basic | Bar-like progression, not interactive line chart |
| Export CSV, PDF, XLSX | Implemented initial versions | Basic A4 PDF and single-sheet XLSX; Bangla PDF font bundling pending |
| Report preview | Implemented | Table preview only, not exact PDF page preview |
| Offline SQLite/outbox | Not implemented | Read/write operations require API connectivity |
| Biometric unlock | Not implemented | Password sign-in only |
| Backup / destructive reset | Deliberately disabled | Security-sensitive feature needs verified recovery/ops procedure |
| Automatic update check | Not implemented | Use signed OS distribution mechanism |
| Android, iOS, Windows, macOS, Linux | Flutter code + generation script + CI | SDK/platform-specific runners needed; Apple signing for installable IPA |
