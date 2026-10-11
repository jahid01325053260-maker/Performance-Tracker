import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:performance_tracker_flutter/features/settings/settings_screen.dart';
import 'package:performance_tracker_flutter/models/entities.dart';
import 'package:performance_tracker_flutter/services/api.dart';
import 'package:performance_tracker_flutter/services/session.dart';

class _FakeApprovalsApi extends ApiClient {
  final pending = <Employee>[
    const Employee(
      employeeId: '123456789012',
      name: 'Test Employee',
      role: 'USER',
      status: 'Pending',
      branch: 'Demo Branch',
    ),
  ];

  int refreshCount = 0;
  String? decidedId;
  String? decidedRole;
  bool? approved;

  @override
  Future<List<Employee>> pendingApprovals() async {
    refreshCount++;
    return List<Employee>.of(pending);
  }

  @override
  Future<void> decideApproval(
    String id,
    bool approve, {
    String role = 'USER',
  }) async {
    decidedId = id;
    decidedRole = role;
    approved = approve;
    pending.removeWhere((employee) => employee.employeeId == id);
  }
}

void main() {
  testWidgets('Refresh and approve do not return a Future from setState', (
    tester,
  ) async {
    final api = _FakeApprovalsApi();
    await tester.pumpWidget(
      MaterialApp(home: ApprovalsScreen(session: Session(api))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test Employee'), findsOneWidget);
    expect(find.text('123456789012 • DEMO BRANCH'), findsOneWidget);

    await tester.tap(find.byTooltip('Refresh approvals'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(api.refreshCount, 2);

    await tester.tap(find.byTooltip('Approve'));
    await tester.pumpAndSettle();
    expect(find.text('Approve Test Employee?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(api.decidedId, '123456789012');
    expect(api.decidedRole, 'USER');
    expect(api.approved, isTrue);
    expect(find.text('No pending requests'), findsOneWidget);
  });

  testWidgets('Reject confirmation removes a pending request', (tester) async {
    final api = _FakeApprovalsApi();
    await tester.pumpWidget(
      MaterialApp(home: ApprovalsScreen(session: Session(api))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Reject'));
    await tester.pumpAndSettle();
    expect(find.text('Reject Test Employee?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(api.approved, isFalse);
    expect(find.text('No pending requests'), findsOneWidget);
  });
}
