import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:performance_tracker_flutter/features/settings/settings_screen.dart';
import 'package:performance_tracker_flutter/models/entities.dart';
import 'package:performance_tracker_flutter/services/api.dart';
import 'package:performance_tracker_flutter/services/session.dart';

void main() {
  test('Legacy approved statuses remain visible, unapproved do not', () {
    for (final value in ['Approved', 'APPROVED', 'approved', '']) {
      expect(ApiClient.isDirectoryApproved(value), isTrue, reason: value);
    }
    for (final value in ['Pending', 'Rejected', 'Disabled', 'PENDING']) {
      expect(ApiClient.isDirectoryApproved(value), isFalse, reason: value);
    }
    final legacy = Employee.fromJson({
      'employeeId': '123456789012', 'name': 'Legacy officer',
      'role': '', 'status': '',
    });
    expect(legacy.isOfficer, isTrue);
  });

  testWidgets('Help & Support shows reference contact details', (tester) async {
    final session = Session(ApiClient());
    session.user = const Employee(employeeId: '123456789012',
      name: 'Admin', role: 'ADMIN', status: 'Approved');
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(session: session)));
    // The administrator section pushes Help & Support below the viewport on
    // smaller test devices. ListView lazily builds off-screen children, so
    // ensureVisible cannot find the tile until it has been scrolled into view.
    final helpTile = find.widgetWithText(ListTile, 'Help & Support');
    await tester.scrollUntilVisible(
      helpTile,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(helpTile);
    await tester.pumpAndSettle();
    expect(find.text('Help & Support'), findsWidgets);
    expect(find.text('+880 1686-556444'), findsOneWidget);
    expect(find.text('jahid2177@gmail.com'), findsOneWidget);
    expect(find.text('• Created By: Md. Jahidul Islam, CBD'), findsOneWidget);
    expect(find.text('https://wa.me/qr/UYHZCG4FYNYYC1'), findsOneWidget);
    expect(find.text('OPEN WHATSAPP'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'OK'));
    await tester.pumpAndSettle();
    session.dispose();
  });

  testWidgets('Admin gets new user and backup actions', (tester) async {
    final session = Session(ApiClient());
    session.user = const Employee(employeeId: '123456789012',
      name: 'Admin', role: 'ADMIN', status: 'Approved');
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(session: session)));
    expect(find.text('Create New User / Management ID'), findsOneWidget);
    expect(find.text('Backup / Reset'), findsOneWidget);
    session.dispose();
  });
}
