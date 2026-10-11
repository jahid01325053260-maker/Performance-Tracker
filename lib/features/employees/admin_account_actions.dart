import 'package:flutter/material.dart';
import '../../models/entities.dart';
import '../../services/session.dart';

/// No privileged Firebase Admin SDK operation runs on the phone.
Future<void> adminPasswordResetAction(
    BuildContext context, Session session, Employee employee) async {
  if (session.user?.isAdmin != true) { return; }
  final choice = await showDialog<bool>(context: context, builder: (dialog) =>
    AlertDialog(
      title: const Text('Password recovery'),
      content: Text('Employee: ${employee.name}\nID: ${employee.employeeId}\n\n'
        'If the sign-in account uses a real email address, send a password '
        'reset link to that address. Legacy accounts with a .invalid login '
        'alias require a verified administrator to use the PC reset utility. '
        'Do not send a password to an unverified person.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('CANCEL')),
        FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('SEND RESET EMAIL')),
      ],
    ));
  if (choice != true) { return; }
  try {
    await session.api.sendAdminPasswordResetEmail(employee.employeeId);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('If the sign-in email is registered, a reset link was requested.')));
    }
  } catch (e) {
    if (context.mounted) {
      await showDialog<void>(context: context, builder: (dialog) =>
      AlertDialog(title: const Text('Admin recovery required'),
        content: Text('$e\n\nRun backend/scripts/reset_employee_password.js '
          'on a trusted PC with private Admin SDK credentials. Repair missing UID first.'),
        actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('OK'))]));
    }
  }
}

/// Double-confirm and disable login access immediately. Actual irreversible
/// Firebase Auth deletion is done only by a trusted Admin SDK operator.
Future<bool> adminDeleteAction(
    BuildContext context, Session session, Employee employee) async {
  if (session.user?.isAdmin != true ||
      session.user!.employeeId == employee.employeeId) { return false; }
  final agreed = await showDialog<bool>(context: context, builder: (dialog) =>
    AlertDialog(
      title: const Text('Warning: Disable employee ID?'),
      content: Text('Employee: ${employee.name}\nID: ${employee.employeeId}\n\n'
        'The account will be disabled immediately and placed in the '
        'administrator deletion queue. The linked sign-in identity is '
        'permanently deleted later by a trusted PC operator. Historic '
        'performance records are retained for audit.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('CANCEL')),
        FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('CONTINUE')),
      ],
    ));
  if (agreed != true || !context.mounted) { return false; }
  final controller = TextEditingController();
  try {
    final confirmed = await showDialog<bool>(context: context, builder: (dialog) =>
      StatefulBuilder(builder: (dialog, refresh) => AlertDialog(
        title: const Text('Final confirmation'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Type Employee ID ${employee.employeeId} to continue.'),
          TextField(controller: controller, keyboardType: TextInputType.number,
            onChanged: (_) => refresh(() {}),
            decoration: const InputDecoration(labelText: 'Confirm Employee ID')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('CANCEL')),
          FilledButton(onPressed: controller.text.trim() == employee.employeeId
            ? () => Navigator.pop(dialog, true) : null, child: const Text('DISABLE ID')),
        ],
      )));
    if (confirmed != true) { return false; }
    await session.api.requestAccountDeletion(employee.employeeId);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ID disabled. Trusted PC must finalize account cleanup.')));
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not disable ID: $e')));
    }
    return false;
  } finally {
    controller.dispose();
  }
}
