import 'package:flutter_test/flutter_test.dart';
import 'package:performance_tracker_flutter/services/kpi_pdf_parser.dart';

void main() {
  KpiTextFragment fragment(int page, double x, double y, String text) =>
    KpiTextFragment(page: page, x: x, y: y, text: text);

  test('906-only multi-month, N verification, blank amount, cross-page continuation', () {
    final parts = <KpiTextFragment>[
      fragment(0, .065, .30, '1'),
      fragment(0, .24, .28, '0573-906-000765'),
      fragment(0, .24, .30, 'AL TOUFIQ'),
      fragment(0, .24, .32, 'BILLAH'),
      fragment(0, .42, .30, '200,000.00 MIRERDANGA'),
      fragment(0, .76, .30, 'Y'),
      fragment(0, .79, .28, '01-01-2026'),
      fragment(0, .79, .30, '31-01-2026'),
      // Non-906: exclude even if it is verified.
      fragment(0, .065, .50, '2'),
      fragment(0, .24, .48, '0573-379-000151'),
      fragment(0, .24, .50, 'OTHER LOAN'),
      fragment(0, .79, .48, '01-06-2026'),
      fragment(0, .79, .50, '30-06-2026'),
      // Account on last page is continued on the following page.
      fragment(0, .065, .92, '3'),
      fragment(0, .24, .90, '0573-906-001073'),
      fragment(0, .24, .92, 'CROSS PAGE NAME'),
      fragment(0, .76, .92, 'N'),
      fragment(0, .79, .90, '01-02-2026'),
      fragment(1, .79, .05, '28-02-2026'),
      fragment(1, .065, .18, '4'),
      fragment(1, .24, .16, '0650-906-000819'),
      fragment(1, .24, .18, 'NO AMOUNT ACCOUNT'),
      fragment(1, .79, .16, '01-03-2026'),
      fragment(1, .79, .18, '31-03-2026'),
      // Same account and period is a duplicate, not a new card.
      fragment(1, .065, .38, '5'),
      fragment(1, .24, .36, '0573-906-000765'),
      fragment(1, .24, .38, 'DUPLICATE'),
      fragment(1, .79, .36, '01-01-2026'),
      fragment(1, .79, .38, '31-01-2026'),
      // Conflicting years in the PDF period must not be guessed.
      fragment(1, .065, .58, '6'),
      fragment(1, .24, .56, '0573-906-001198'),
      fragment(1, .24, .58, 'INVALID PERIOD'),
      fragment(1, .79, .56, '01-01-2026'),
      fragment(1, .79, .58, '31-01-2016'),
    ];
    final result = KpiPdfParser.parseFragments(parts);
    expect(result.total, 6);
    expect(result.non906, 1);
    expect(result.duplicate, 1);
    expect(result.issues.length, 1);
    expect(result.rows.length, 3);
    expect(result.monthlyCounts, {'2026-01': 1, '2026-02': 1, '2026-03': 1});
    expect(result.rows.first.accountTitle, 'AL TOUFIQ BILLAH');
    expect(result.rows[1].verify, 'N');
    expect(result.rows[1].periodEnd, '28-02-2026');
    expect(result.rows[2].amount, '');
    expect(result.rows[0].toSubmission()['source'], 'pdf');
  });
}
