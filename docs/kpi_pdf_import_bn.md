# PerformanceTracker — Employee KPI PDF Import (Spark Free)

## What is implemented

In **User → New Submission → Import Multi-Month KPI PDF**, select a text-based "Employee Wise KPI Register Details" PDF. The app processes text locally through the MIT-licensed `pdfrx`/PDFium library. No Cloud Function or paid Firebase backend is needed.

The parser extracts **SL / Account No / Account Title / Achievement Amount / Period**, plus originating branch and Verify Y/N when available. It also joins records spread over successive pages.

- Only account numbers matching `####-906-######` are accepted.
- The `Period` column, **not** the Maker Date, Checker Date, printed date or currently selected New Submission month, determines `YYYY-MM`.
- Period must start on the first day and end on the last day of **the same calendar month and year**. Mismatch is flagged for correction; the app never silently changes 2016 to 2026.
- This policy includes both `Verify Y` and `Verify N`, because this specification filters **only** by 906. The Verify status is kept in Firestore. If the business later requires Verified-only counting, it must be a separate rule.
- Missing Achievement Amount remains empty, **not zero**, and the valid account still counts as one card.
- A duplicate `(employee, YYYY-MM, canonical account)` is not counted twice, including after re-import.
- Preview shows monthly totals and errors. The user must press **Submit all ... accounts to their months** before any Firestore writing occurs.
- Sensitive customer records are not embedded in the project/CI fixtures and are not uploaded to a third-party parsing API.

## Sample file acceptance criteria (the supplied 10-page KPI PDF)

Expected PDF raw account total: **90**; Non-906: **1** (`0573-379-000151`, SL 76); eligible 906: **89**. This is based solely on the product-code requirement; Verify N rows are included.

| Period | Number of 906 accounts |
|---|---:|
| 2026-01 | 12 |
| 2026-02 | 5 |
| 2026-03 | 3 |
| 2026-04 | 17 |
| 2026-05 | 13 |
| 2026-06 | 3 |
| 2026-07 | 22 |
| 2026-08 | 6 |
| 2026-09 | 7 |
| 2026-10 | 1 |
| **TOTAL** | **89** |

Rows SL 17, 48, 79, 89 and others are split at page boundaries. Their data must be joined; otherwise their Period or Account Title will be lost. SL 17 and 79 are legitimate 906 accounts with empty Achievement Amount. No real bank/customer PDF is stored in this source archive.

## Deployment & tests

Use **Flutter 3.47+ (Dart 3.13+)** because `pdfrx 2.6.5` requires those versions. Install dependencies, then test:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

Run on an Android device and import the provided actual PDF to verify the full 90/89 count. There is no Firebase Rules change: Firestore writes still require a logged-in approved `USER` and are guarded by existing Rules. Existing documents will not be overwritten on import.

### Limitations

The parser is tailored to the given bank's table format and expects selectable PDF text. Scanned/image-only or password-protected PDFs need a separately implemented OCR/decryption workflow. The PDFium native dependency can increase APK size and must be verified under the project's GitHub Actions Flutter/NDK versions. If an unknown PDF format cannot be parsed safely, show a failure/review state instead of submitting inferred entries.
