import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:performance_tracker_flutter/features/dashboard/month_view_screen.dart';
import 'package:performance_tracker_flutter/features/employees/directory_screen.dart';
import 'package:performance_tracker_flutter/models/entities.dart';
import 'package:performance_tracker_flutter/services/api.dart';
import 'package:performance_tracker_flutter/services/calculations.dart';
import 'package:performance_tracker_flutter/services/session.dart';

class _FakeApi extends ApiClient {
  String? updatedRole;

  // Month View listens to this realtime stream. Keep widget tests independent
  // of an initialized Firebase app, while exercising the real counting UI.
  @override
  Stream<Map<String, int>> watchRankingCounts() =>
      const Stream<Map<String, int>>.empty();
  @override
  Future<List<CardRecord>> records({String? employeeId, String? period}) async => [
    CardRecord(
      id: 'r1', employeeId: '000000000001', employeeName: 'Demo Officer',
      applicantName: 'Applicant', accountNo: '1234-906-123456', limit: '1000',
      reportingPeriod: '${DateTime.now().year}-01', branch: 'TEST', zone: 'NORTH',
    ),
    CardRecord(
      id: 'r2', employeeId: '000000000001', employeeName: 'Demo Officer',
      applicantName: 'Applicant Duplicate', accountNo: '1234-906-123456',
      limit: '1000', reportingPeriod: '${DateTime.now().year}-01',
      branch: 'TEST', zone: 'NORTH',
    ),
  ];

  @override
  Future<List<Employee>> employees({String search = '', String role = 'All'}) async => [
    const Employee(employeeId: '000000000001', name: 'Demo Officer',
      role: 'USER', status: 'Approved', branch: 'TEST', zone: 'NORTH'),
  ];

  @override
  Future<List<EmployeeTarget>> targets({String? period}) async => [];

  @override
  Future<void> changeEmployeeRole(String employeeId, String newRole) async {
    updatedRole = newRole;
  }
}

void main() {
  test('Card counting deduplicates per officer and reporting month', () async {
    final rows = await _FakeApi().records();
    final january = '${DateTime.now().year}-01';
    expect(countCards(rows), 1);
    expect(countCards(rows, reportingPeriod: january), 1);
    expect(countCards(rows, employeeId: '000000000001'), 1);
    expect(countCards(rows, reportingPeriod: '${DateTime.now().year}-02'), 0);
  });

  testWidgets('Month View groups duplicate cards only once', (tester) async {
    final api = _FakeApi();
    final session = Session(api);
    session.user = const Employee(employeeId: '000000000000',
        name: 'Admin', role: 'ADMIN', status: 'Approved');
    await tester.pumpWidget(MaterialApp(
        home: MonthViewScreen(session: session)));
    await tester.pumpAndSettle();
    expect(find.text('Month View'), findsOneWidget);
    expect(find.text('Performance overview'), findsOneWidget);
    expect(find.text('REPORT FILTERS'), findsOneWidget);

    // Two Firestore rows with the same employee, month and account number
    // must display as ONE verified card and ONE monthly report group.
    final verifiedCard = find.ancestor(
      of: find.text('906 cards'),
      matching: find.byType(Card),
    );
    expect(verifiedCard, findsOneWidget);
    expect(
      find.descendant(of: verifiedCard, matching: find.text('1')),
      findsOneWidget,
    );
    final reportGroupCard = find.ancestor(
      of: find.text('Report groups'),
      matching: find.byType(Card),
    );
    expect(reportGroupCard, findsOneWidget);
    expect(
      find.descendant(of: reportGroupCard, matching: find.text('1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });

  testWidgets('Admin can review and confirm a role change', (tester) async {
    final api = _FakeApi();
    final session = Session(api);
    session.user = const Employee(employeeId: '000000000000',
        name: 'Admin', role: 'ADMIN', status: 'Approved');
    final employee = (await api.employees()).first;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => showAdminRoleEditor(context, session, employee),
        child: const Text('Edit'),
      ),
    ))));
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sales Manager').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('REVIEW CHANGE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONFIRM'));
    await tester.pumpAndSettle();
    expect(api.updatedRole, 'Sales Manager');
    expect(tester.takeException(), isNull);
    session.dispose();
  });
}
