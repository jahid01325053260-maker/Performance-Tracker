import 'package:flutter_test/flutter_test.dart';
import 'package:performance_tracker_flutter/models/entities.dart';
import 'package:performance_tracker_flutter/services/report_scope.dart';

void main() {
  const admin = Employee(employeeId: '100000000001', name: 'Admin', role: 'ADMIN', status: 'Approved');
  const agm = Employee(employeeId: '100000000002', name: 'AGM', role: 'AGM', status: 'Approved');
  const dgm = Employee(employeeId: '100000000003', name: 'DGM', role: 'DGM', status: 'Approved');
  const manager = Employee(employeeId: '100000000004', name: 'Manager', role: 'Sales Manager', status: 'Approved');
  const team = Employee(employeeId: '100000000005', name: 'Team officer', role: 'USER', status: 'Approved', managerId: '100000000004');
  const outside = Employee(employeeId: '100000000006', name: 'Outside officer', role: 'USER', status: 'Approved', managerId: '100000000099');
  const legacyUnlinked = Employee(employeeId: '100000000007', name: 'Unlinked officer', role: 'USER', status: 'Approved', salesManager: 'Manager');

  test('Individual View and Export scope follow management permissions', () {
    final users = [admin, agm, dgm, manager, team, outside, legacyUnlinked];
    expect(permittedReportOfficers(admin, users).length, 3);
    expect(permittedReportOfficers(agm, users).length, 3);
    expect(permittedReportOfficers(dgm, users).length, 3);
    expect(permittedReportOfficers(manager, users).map((e) => e.employeeId),
        ['100000000005']);
    expect(canReadOfficerReports(manager, outside), isFalse);
    expect(canReadOfficerReports(manager, legacyUnlinked), isFalse);
    expect(canReadOfficerReports(agm, outside), isTrue);
    expect(canReadOfficerReports(dgm, outside), isTrue);
  });
}
