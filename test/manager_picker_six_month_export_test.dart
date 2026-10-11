import 'package:flutter_test/flutter_test.dart';
import 'package:performance_tracker_flutter/models/entities.dart';
import 'package:performance_tracker_flutter/services/report_tables.dart';

void main() {
  const admin = Employee(employeeId: '123456789999', name: 'Admin',
    role: 'ADMIN', status: 'Approved');
  const manager = Employee(employeeId: '123456789111', name: 'Manager',
    role: 'Sales Manager', status: 'Approved');
  const first = Employee(employeeId: '123456789222', name: 'First Officer',
    role: 'USER', status: 'Approved', managerId: '123456789111',
    salesManager: 'Manager', branch: 'Station Road, Rangpur', zone: 'Others',
    monthlyTarget: 10, yearlyTarget: 100);
  const second = Employee(employeeId: '123456789333', name: 'Second Officer',
    role: 'USER', status: 'Approved', managerId: '123456789111',
    salesManager: 'Manager', branch: 'Khulna', zone: 'Others',
    monthlyTarget: 2, yearlyTarget: 30);
  final employees = [admin, manager, first, second];
  final records = [
    const CardRecord(id: 'a', employeeId: '123456789222', employeeName: 'First Officer',
      applicantName: 'A', accountNo: '1234-906-000001', limit: '100',
      reportingPeriod: '2026-01'),
    const CardRecord(id: 'duplicate', employeeId: '123456789222',
      employeeName: 'First Officer', applicantName: 'Same',
      accountNo: '1234-906-000001', limit: '100', reportingPeriod: '2026-01'),
    const CardRecord(id: 'b', employeeId: '123456789222', employeeName: 'First Officer',
      applicantName: 'B', accountNo: '1234-906-000002', limit: '100',
      reportingPeriod: '2026-06'),
    const CardRecord(id: 'not906', employeeId: '123456789222',
      employeeName: 'First Officer', applicantName: 'Other product',
      accountNo: '1234-379-000003', limit: '100', reportingPeriod: '2026-06'),
    const CardRecord(id: 'outOfRange', employeeId: '123456789222',
      employeeName: 'First Officer', applicantName: 'July',
      accountNo: '1234-906-000004', limit: '100', reportingPeriod: '2026-07'),
  ];

  test('January-June export aggregates six months and ignores duplicates / non906', () {
    final rows = buildReportTable(viewer: admin, employees: employees,
      records: records, reportType: 'Officer Performance (Target Summary)',
      selectedOfficer: '123456789222', year: 2026, month: 1,
      allMonths: false, includeZone: true, includeManager: true,
      fromMonth: 1, toMonth: 6);
    expect(rows.first, ['Branch', 'Branch Official', 'Sales Manager', 'Zone',
      'Total', 'Target', 'SHORT', 'Achievement']);
    expect(rows.length, 2);
    expect(rows[1][4], '2');
    expect(rows[1][5], '60');
    expect(rows[1][6], '58');
    expect(rows[1][7], '3.3%');
    expect(exportedCardCount(viewer: admin, employees: employees,
      records: records, selectedOfficer: '123456789222', year: 2026, month: 1,
      allMonths: false, fromMonth: 1, toMonth: 6), 2);
  });

  test('Sales Manager can export their team but not outsiders', () {
    final rows = buildReportTable(viewer: manager, employees: employees,
      records: records, reportType: 'Officer Performance (Target Summary)',
      selectedOfficer: 'ALL', year: 2026, month: 1,
      allMonths: false, includeZone: true, includeManager: false,
      fromMonth: 1, toMonth: 6);
    expect(rows.length, 3);
  });
}
