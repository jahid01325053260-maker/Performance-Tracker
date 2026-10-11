import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart' as pdfrx;

/// A positioned text fragment. Coordinates are page-size-relative; x grows to
/// the right and y grows downward, regardless of native PDF coordinates.
class KpiTextFragment {
  const KpiTextFragment({required this.page, required this.x, required this.y,
    required this.text});
  final int page;
  final double x, y;
  final String text;
}

class KpiPdfRow {
  const KpiPdfRow({required this.serial, required this.accountNo,
    required this.accountTitle, required this.amount, required this.period,
    required this.periodStart, required this.periodEnd,
    required this.verify, required this.originatingBranch});
  final int serial;
  final String accountNo, accountTitle, amount, period, periodStart,
      periodEnd, verify, originatingBranch;

  Map<String, dynamic> toSubmission() => {
    'slNo': serial,
    'accountNo': accountNo,
    'applicantName': accountTitle,
    'limit': amount,
    'source': 'pdf',
    'kpiCategory': 'NEW LOAN ACCOUNT',
    'verify': verify,
    'periodStart': periodStart,
    'periodEnd': periodEnd,
    'originatingBranch': originatingBranch,
    'reportingPeriod': period,
  };
}

class KpiPdfIssue {
  const KpiPdfIssue(this.serial, this.message);
  final int serial;
  final String message;
}

class KpiPdfResult {
  const KpiPdfResult({required this.rows, required this.issues,
    required this.total, required this.non906, required this.duplicate});
  final List<KpiPdfRow> rows;
  final List<KpiPdfIssue> issues;
  final int total, non906, duplicate;
  Map<String, int> get monthlyCounts {
    final result = <String, int>{};
    for (final row in rows) {
      result.update(row.period, (count) => count + 1, ifAbsent: () => 1);
    }
    return Map.fromEntries(result.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key)));
  }
}

/// Extracts account records from Pubali Bank's Employee Wise KPI Register.
///
/// Supports the exact table structure supplied as the reference PDF, including
/// a row continued onto the following page. Other banks' PDFs may have a
/// different layout; their unrecognized rows MUST NOT be silently submitted.
class KpiPdfParser {
  KpiPdfParser._();

  static final _accountPattern = RegExp(r'\b(\d{4})[\s-]?(\d{3})[\s-]?(\d{6})\b');
  static final _datePattern = RegExp(r'\b\d{2}-\d{2}-\d{4}\b');
  static final _amountPattern = RegExp(r'\b\d{1,3}(?:,\d{3})+(?:\.\d{2})?\b|\b\d+\.\d{2}\b');

  /// Native text extraction happens locally; no sensitive applicant data is
  /// transmitted to a third-party PDF processing service.
  static Future<KpiPdfResult> parseBytes(Uint8List data) async {
    final document = await pdfrx.PdfDocument.openData(data);
    try {
      final fragments = <KpiTextFragment>[];
      for (var index = 0; index < document.pages.length; index++) {
        final page = document.pages[index];
        final text = await page.loadStructuredText();
        for (final fragment in text.fragments) {
          final content = fragment.text.trim();
          if (content.isEmpty) { continue; }
          final bounds = fragment.bounds;
          fragments.add(KpiTextFragment(page: index, x: bounds.left / page.width,
            y: (page.height - (bounds.top + bounds.bottom) / 2) / page.height,
            text: content));
        }
      }
      if (fragments.isEmpty) {
        throw const FormatException('This PDF has no selectable text. Image-only scanned PDFs require OCR.');
      }
      return parseFragments(fragments);
    } finally {
      await document.dispose();
    }
  }

  /// Public pure-Dart parser for test fixtures and alternate PDF text engines.
  /// All dimensions are normalized to 0..1 (top-left origin).
  static KpiPdfResult parseFragments(List<KpiTextFragment> fragments) {
    final pages = <int, List<KpiTextFragment>>{};
    for (final span in fragments) {
      (pages[span.page] ??= []).add(span);
    }
    final serialRows = <int, List<KpiTextFragment>>{};
    for (final pageNumber in pages.keys.toList()..sort()) {
      final pageSpans = pages[pageNumber]!;
      // Serial-number column: less than 9% of the table page width.
      final anchors = <_KpiAnchor>[];
      for (final span in pageSpans) {
        if (span.x >= .09) { continue; }
        final match = RegExp(r'^\d{1,4}$').firstMatch(span.text.trim());
        if (match == null) { continue; }
        final serial = int.tryParse(match.group(0)!);
        if (serial == null || serial < 1 || serial > 9999) { continue; }
        anchors.add(_KpiAnchor(serial, span.y));
      }
      anchors.sort((a, b) => a.y.compareTo(b.y));
      if (anchors.isEmpty) { continue; }
      for (final anchor in anchors) {
        serialRows.putIfAbsent(anchor.serial, () => <KpiTextFragment>[]);
      }
      for (final span in pageSpans) {
        final closest = anchors.reduce((a, b) =>
          (a.y - span.y).abs() <= (b.y - span.y).abs() ? a : b);
        var serial = closest.serial;
        // A continuation at the beginning of page N belongs to the last row
        // on page N-1, not the first new serial in page N.
        if (pageNumber > 0 && span.y < anchors.first.y - .045) {
          final previous = serialRows.keys.where((n) => n < anchors.first.serial);
          if (previous.isNotEmpty) { serial = previous.reduce(math.max); }
        } else if (pageNumber == 0 && span.y < anchors.first.y - .045) {
          // Do not attach the page-1 heading/table column names to SL 1.
          continue;
        }
        serialRows.putIfAbsent(serial, () => <KpiTextFragment>[]).add(span);
      }
    }
    if (serialRows.isEmpty) {
      throw const FormatException('No KPI serial-number rows found. The PDF layout is not supported.');
    }
    final accepted = <KpiPdfRow>[];
    final issues = <KpiPdfIssue>[];
    final seen = <String>{};
    var non906 = 0;
    var duplicates = 0;
    final ordered = serialRows.keys.toList()..sort();
    for (final serial in ordered) {
      final cells = serialRows[serial]!;
      final acctCell = _column(cells, .21, .405);
      final account = _accountPattern.firstMatch(acctCell);
      if (account == null) {
        issues.add(KpiPdfIssue(serial, 'Account number could not be read.'));
        continue;
      }
      if (account.group(2) != '906') {
        non906++;
        continue;
      }
      final accountNo = '${account.group(1)}-906-${account.group(3)}';
      final dates = _datePattern.allMatches(_column(cells, .785, .91))
          .map((m) => m.group(0)!).toList();
      if (dates.length != 2) {
        issues.add(KpiPdfIssue(serial, 'Expected both Period start and end dates.'));
        continue;
      }
      final from = _parseDate(dates[0]);
      final until = _parseDate(dates[1]);
      if (from == null || until == null || from.year != until.year ||
          from.month != until.month || from.day != 1 ||
          until.day != DateTime(until.year, until.month + 1, 0).day) {
        issues.add(KpiPdfIssue(serial, 'Invalid or mismatched Period ${dates.join(' to ')}.'));
        continue;
      }
      final month = '${from.year}-${from.month.toString().padLeft(2, '0')}';
      final key = '$month|$accountNo';
      if (!seen.add(key)) {
        duplicates++;
        continue;
      }
      var title = acctCell.replaceFirst(account.group(0)!, '').trim();
      title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (title.isEmpty) {
        issues.add(KpiPdfIssue(serial, 'Account title missing.'));
        continue;
      }
      final amountAndBranch = _column(cells, .405, .655);
      final amountMatch = _amountPattern.firstMatch(amountAndBranch);
      final amount = amountMatch?.group(0) ?? '';
      final branch = amountMatch == null ? amountAndBranch.trim()
          : amountAndBranch.replaceFirst(amountMatch.group(0)!, '').trim();
      final verifyCell = _column(cells, .74, .785).trim().toUpperCase();
      final verify = RegExp(r'\b[YN]\b').firstMatch(verifyCell)?.group(0) ?? '';
      accepted.add(KpiPdfRow(serial: serial, accountNo: accountNo,
        accountTitle: title, amount: amount, period: month,
        periodStart: dates[0], periodEnd: dates[1], verify: verify,
        originatingBranch: branch));
    }
    return KpiPdfResult(rows: accepted, issues: issues,
      total: ordered.length, non906: non906, duplicate: duplicates);
  }

  static String _column(List<KpiTextFragment> cells, double lower, double upper) {
    final parts = cells.where((c) => c.x >= lower && c.x < upper).toList()
      ..sort((a, b) {
        final page = a.page.compareTo(b.page);
        if (page != 0) { return page; }
        final diff = a.y - b.y;
        return diff.abs() < .004 ? a.x.compareTo(b.x) : diff < 0 ? -1 : 1;
      });
    return parts.map((s) => s.text).join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static DateTime? _parseDate(String value) {
    final p = value.split('-');
    if (p.length != 3) { return null; }
    final day = int.tryParse(p[0]);
    final month = int.tryParse(p[1]);
    final year = int.tryParse(p[2]);
    if (day == null ||
        month == null ||
        year == null ||
        year < 2000 ||
        year > 2100 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31) {
      return null;
    }
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day ? date : null;
  }
}

class _KpiAnchor {
  const _KpiAnchor(this.serial, this.y);
  final int serial;
  final double y;
}
