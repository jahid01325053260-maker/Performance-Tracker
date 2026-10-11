import 'package:flutter_test/flutter_test.dart';
import 'package:performance_tracker_flutter/models/entities.dart';
import 'package:performance_tracker_flutter/services/calculations.dart';

void main() {
  const manager = Employee(employeeId: '000000000100', name: 'SALES MANAGER',
    role: 'Sales Manager', status: 'Approved');
  const officer = Employee(employeeId: '000000000101', name: 'Officer',
    role: 'USER', status: 'Approved', salesManager: 'sales manager', monthlyTarget: 20,
    yearlyTarget: 240);
  const indexedOfficer = Employee(employeeId: '000000000102', name: 'Officer 2',
    role: 'USER', status: 'Approved', managerId: '000000000100');
  test('Native manager team: ID and case-insensitive name fallback', () {
    expect(belongsToManager(officer, manager), isTrue);
    expect(belongsToManager(indexedOfficer, manager), isTrue);
    expect(belongsToManager(manager, manager), isFalse);
  });
  test('Unsubmitted approved officers appear with zero cards in ranking', () {
    final result = calculateRanking([officer, indexedOfficer, manager], []);
    expect(result.length, 2);
    expect(result.map((r) => r.cards), everyElement(0));
  });
  test('Monthly and yearly target defaults persist across reporting periods', () {
    expect(officer.monthlyTarget, 20);
    expect(officer.yearlyTarget, 240);
    expect(Achievement(10, officer.monthlyTarget).below50, isFalse);
  });
}
