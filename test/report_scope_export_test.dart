import 'package:flutter_test/flutter_test.dart';
import 'package:performance_tracker_flutter/models/entities.dart';
import 'package:performance_tracker_flutter/services/calculations.dart';
import 'package:performance_tracker_flutter/services/report_scope.dart';
import 'package:performance_tracker_flutter/services/report_tables.dart';

void main() {
  const manager = Employee(employeeId: '000000000111', name: 'Team Manager',
      role: 'Sales Manager', status: 'Approved');
  const mine = Employee(employeeId: '000000000222', name: 'My Officer',
      role: 'USER', status: 'Approved', managerId: '000000000111',
      monthlyTarget: 8, yearlyTarget: 75);
  const other = Employee(employeeId: '000000000333', name: 'Other Officer',
      role: 'USER', status: 'Approved', managerId: '000000000999',
      monthlyTarget: 10, yearlyTarget: 120);
  const unlinked = Employee(employeeId: '000000000444', name: 'Legacy Officer',
      role: 'USER', status: 'Approved', salesManager: 'Team Manager');
  const admin = Employee(employeeId: '000000000999', name: 'Admin',
      role: 'ADMIN', status: 'Approved');

  final records = <CardRecord>[
    const CardRecord(id: 'r1', employeeId: '000000000222', employeeName: 'My Officer',
      applicantName: 'A', accountNo: '1234-906-000001', limit: '1000',
      reportingPeriod: '2026-01', managerId: '000000000111'),
    const CardRecord(id: 'r2', employeeId: '000000000222', employeeName: 'My Officer',
      applicantName: 'A duplicate', accountNo: '1234-906-000001', limit: '1000',
      reportingPeriod: '2026-01', managerId: '000000000111'),
    const CardRecord(id: 'r3', employeeId: '000000000222', employeeName: 'My Officer',
      applicantName: 'B', accountNo: '1234-906-000001', limit: '1000',
      reportingPeriod: '2026-02', managerId: '000000000111'),
    const CardRecord(id: 'r4', employeeId: '000000000333', employeeName: 'Other Officer',
      applicantName: 'Secret', accountNo: '1234-906-000099', limit: '1000',
      reportingPeriod: '2026-01', managerId: '000000000999'),
  ];
  final people = <Employee>[manager, mine, other, unlinked, admin];

  test('Manager reports are scoped to stable manager ID, not a display name', () {
    final view = permittedReportOfficers(manager, people);
    expect(view.map((e) => e.employeeId), ['000000000222']);
    expect(canReadOfficerReports(manager, other), isFalse);
    expect(canReadOfficerReports(manager, unlinked), isFalse);
    expect(canReadOfficerReports(admin, other), isTrue);
    expect(canReadOfficerReports(mine, mine), isTrue);
    expect(canReadOfficerReports(mine, other), isFalse);
  });

  test('AGM and DGM can view all officer performance; Sales Manager only team', () {
    const agm = Employee(employeeId: '000000000777', name: 'AGM',
        role: 'AGM', status: 'Approved');
    const dgm = Employee(employeeId: '000000000888', name: 'DGM',
        role: 'DGM', status: 'Approved');
    expect(permittedReportOfficers(agm, people).length, 3);
    expect(permittedReportOfficers(dgm, people).length, 3);
    expect(permittedReportOfficers(manager, people).length, 1);
    expect(canReadOfficerReports(agm, other), isTrue);
    expect(canReadOfficerReports(dgm, other), isTrue);
    expect(canReadOfficerReports(manager, other), isFalse);
  });

  test('Monthly vs annual exports use two independent assigned targets', () {
    final january = buildReportTable(viewer: manager, employees: people,
      records: records, reportType: 'Officer Performance (Target Summary)',
      selectedOfficer: 'ALL', year: 2026, month: 1,
      allMonths: false, includeZone: false, includeManager: false);
    expect(january.length, 2);
    expect(january[1][2], '1'); // Jan duplicates count as one
    expect(january[1][3], '8');

    final annual = buildReportTable(viewer: manager, employees: people,
      records: records, reportType: 'Officer Performance (Target Summary)',
      selectedOfficer: 'ALL', year: 2026, month: 1,
      allMonths: true, includeZone: false, includeManager: false);
    expect(annual[1][2], '2'); // Same account in two months counts in both
    expect(annual[1][3], '75'); // Not monthlyTarget * 12
    expect(countCardsForYear(records, mine.employeeId, 2026), 2);
    expect(exportedCardCount(viewer: manager, employees: people,
      records: records, selectedOfficer: 'ALL', year: 2026, month: 1,
      allMonths: true), 2);
  });

  test('Non-team applicants do not appear in manager Excel/PDF detail data', () {
    final table = buildReportTable(viewer: manager, employees: people,
      records: records, reportType: 'Card Application Details',
      selectedOfficer: 'ALL', year: 2026, month: 1,
      allMonths: true, includeZone: true, includeManager: true);
    expect(table.length, 3); // header and two month-specific valid accounts
    expect(table.toString().contains('Secret'), isFalse);
    final managerRows = buildReportTable(viewer: manager, employees: people,
      records: records, reportType: 'Sales Manager Performance',
      selectedOfficer: 'ALL', year: 2026, month: 1,
      allMonths: true, includeZone: false, includeManager: false);
    expect(managerRows[1][0], 'Team Manager');
    expect(managerRows[1][2], '2');
  });
}
