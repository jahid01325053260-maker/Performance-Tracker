import '../models/entities.dart';
import 'calculations.dart';
import 'report_scope.dart';

/// Shared report aggregation for PDF, Excel and on-screen preview.
/// For a manager, private details and totals can only come from team-scoped
/// Firestore queries AND managerId-authorized employee selections.
List<List<String>> buildReportTable({
  required Employee viewer,
  required Iterable<Employee> employees,
  required Iterable<CardRecord> records,
  required String reportType,
  required String selectedOfficer,
  required int year,
  required int month,
  required bool allMonths,
  required bool includeZone,
  required bool includeManager,
  int? fromMonth,
  int? toMonth,
}) {
  final permitted = permittedReportOfficers(viewer, employees);
  final officers = selectedOfficer == 'ALL' ? permitted :
      permitted.where((e) => e.employeeId == selectedOfficer).toList();
  final scopedIds = officers.map((e) => e.employeeId).toSet();
  // Only use a custom range when both endpoints have been provided.
  var isRange = false;
  int lowerMonth = month;
  int upperMonth = month;
  if (!allMonths && fromMonth != null && toMonth != null) {
    isRange = true;
    lowerMonth = fromMonth;
    upperMonth = toMonth;
  }
  final selectedMonths = isRange && lowerMonth <= upperMonth
      ? upperMonth - lowerMonth + 1 : 1;
  final scopedRecords = records.where((r) {
    if (!scopedIds.contains(r.employeeId) || !r.reportingPeriod.startsWith('$year-')) {
      return false;
    }
    if (allMonths) return true;
    final recordMonth = int.tryParse(r.reportingPeriod.split('-').last);
    return recordMonth != null &&
        recordMonth >= lowerMonth && recordMonth <= upperMonth;
  }).toList();
  int assignedTarget(Employee e) => allMonths ? e.yearlyTarget :
      e.monthlyTarget * selectedMonths;
  if (reportType == 'Card Application Details') {
    final seen = <String>{};
    final output = <List<String>>[
      ['Employee', 'Branch', 'Applicant Name', 'A/C No', 'Limit', 'Month'],
    ];
    for (final record in scopedRecords) {
      if (!record.valid) continue;
      final key = '${record.employeeId}|${record.reportingPeriod}|${accountKey(record.accountNo)}';
      if (!seen.add(key)) continue;
      output.add([record.employeeName, upper(record.branch),
          record.applicantName, record.accountNo, record.limit,
          record.reportingPeriod]);
    }
    return output;
  }

  if (reportType == 'Sales Manager Performance') {
    final managers = {
      for (final m in employees.where((e) =>
          e.role.trim().toLowerCase() == 'sales manager')) m.employeeId: m.name,
    };
    final groups = <String, List<Employee>>{};
    for (final e in officers) {
      (groups[e.managerId] ??= <Employee>[]).add(e);
    }
    final rows = <List<String>>[
      ['Sales Manager', 'Officers', if (includeZone) 'Zones',
        'Total', 'Target', 'SHORT', 'Achievement'],
    ];
    for (final entry in groups.entries) {
      final eligible = entry.value;
      final cards = eligible.fold<int>(0, (sum, e) => sum +
          countCards(scopedRecords, employeeId: e.employeeId));
      final target = eligible.fold<int>(0, (sum, e) => sum +
          assignedTarget(e));
      final achievement = Achievement(cards, target);
      rows.add([managers[entry.key] ?? (entry.key.isEmpty
          ? 'UNASSIGNED' : entry.key), '${eligible.length}',
        if (includeZone) eligible.map((e) => e.displayZone).toSet().join(', '),
        '$cards', '$target', '${achievement.shortfall}', achievement.label]);
    }
    return rows;
  }

  final output = <List<String>>[
    ['Branch', 'Branch Official', if (includeManager) 'Sales Manager',
      if (includeZone) 'Zone', 'Total', 'Target', 'SHORT', 'Achievement'],
  ];
  final sortedOfficers = [...officers]..sort((a, b) {
    final aTarget = assignedTarget(a), bTarget = assignedTarget(b);
    final aCards = countCards(scopedRecords, employeeId: a.employeeId);
    final bCards = countCards(scopedRecords, employeeId: b.employeeId);
    final aPercent = aTarget > 0 ? aCards / aTarget : -1.0;
    final bPercent = bTarget > 0 ? bCards / bTarget : -1.0;
    final byPercent = bPercent.compareTo(aPercent);
    return byPercent != 0 ? byPercent : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  for (final e in sortedOfficers) {
    final total = countCards(scopedRecords, employeeId: e.employeeId);
    final target = assignedTarget(e);
    final achievement = Achievement(total, target);
    output.add([e.displayBranch, e.name,
      if (includeManager) e.salesManager,
      if (includeZone) e.displayZone,
      '$total', '$target', '${achievement.shortfall}', achievement.label]);
  }
  return output;
}

/// Counts exported eligible 906 records, distinct per employee/month/account,
/// even when a summary report includes only one row per officer.
int exportedCardCount({required Employee viewer,
  required Iterable<Employee> employees,
  required Iterable<CardRecord> records,
  required String selectedOfficer,
  required int year, required int month, required bool allMonths,
  int? fromMonth, int? toMonth}) {
  final permitted = permittedReportOfficers(viewer, employees);
  final ids = permitted.where((e) => selectedOfficer == 'ALL' ||
      selectedOfficer == e.employeeId).map((e) => e.employeeId).toSet();
  return countCards(records.where((r) {
    if (!ids.contains(r.employeeId) || !r.reportingPeriod.startsWith('$year-')) {
      return false;
    }
    if (allMonths) return true;
    final recordMonth = int.tryParse(r.reportingPeriod.split('-').last);
    return recordMonth != null &&
        recordMonth >= (fromMonth ?? month) && recordMonth <= (toMonth ?? month);
  }));
}
