import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/backup_service.dart';
import '../../services/session.dart';
import '../auth/login_screen.dart';

class BackupResetScreen extends StatefulWidget {
  const BackupResetScreen({super.key, required this.session});
  final Session session;

  @override
  State<BackupResetScreen> createState() => _BackupResetScreenState();
}

class _BackupResetScreenState extends State<BackupResetScreen> {
  bool busy = false;
  bool backupSaved = false;
  String? savedDestination;
  late final BackupService service = BackupService(widget.session.api);

  Future<void> makeBackup() async {
    if (busy) { return; }
    setState(() { busy = true; backupSaved = false; savedDestination = null; });
    try {
      final data = await service.createBackupData();
      final saved = await service.saveBackup(data);
      if (!mounted) return;
      if (saved == null) {
        showMessage(context, 'Backup cancelled. Reset remains locked.');
        return;
      }
      setState(() { backupSaved = true; savedDestination = saved.toString(); });
      showMessage(context, 'JSON backup saved. Keep this file private.');
    } catch (e) {
      if (mounted) showMessage(context, 'Backup failed: $e');
    } finally {
      if (mounted) { setState(() => busy = false); }
    }
  }

  Future<void> uploadJsonBackup() async {
    if (busy) { return; }
    setState(() => busy = true);
    try {
      // Parse and validate the COMPLETE file before requesting credentials.
      final plan = await service.chooseJsonFile();
      if (plan == null || !mounted) { return; }
      final phrase = TextEditingController();
      final password = TextEditingController();
      bool proceed = false;
      try {
        proceed = await showDialog<bool>(context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Upload JSON Backup'),
            content: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Validated reporting data from a PerformanceTracker backup:'),
                for (final entry in plan.collectionCounts.entries)
                  Text('${entry.key}: ${entry.value} documents'),
                const SizedBox(height: 12),
                const Text('Only missing performance, targets and leaderboard '
                  'documents will be restored. Existing records are NEVER '
                  'overwritten. Employee IDs, roles, passwords and accounts '
                  'are NEVER restored. A network failure may leave partial import.',
                  style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 14),
                TextField(controller: phrase, decoration: const InputDecoration(
                  labelText: 'Type RESTORE REPORTS')),
                const SizedBox(height: 10),
                TextField(controller: password, obscureText: true,
                  decoration: const InputDecoration(labelText: 'Admin password')),
              ],
            )),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx,
                phrase.text.trim() == 'RESTORE REPORTS' &&
                  password.text.isNotEmpty),
                child: const Text('Confirm Restore')),
            ],
          ),
        ) ?? false;
        if (!proceed) {
          if (mounted) { showMessage(context, 'JSON upload cancelled.'); }
          return;
        }
        final admin = FirebaseAuth.instance.currentUser;
        if (admin?.email == null) {
          throw StateError('Admin session expired. Sign in again.');
        }
        await admin!.reauthenticateWithCredential(
          EmailAuthProvider.credential(
            email: admin.email!, password: password.text,
          ),
        );
        final result = await service.restoreMissing(plan);
        if (mounted) { showMessage(context,
          'JSON upload completed: ${result.restored} restored, '
          '${result.skipped} already existed.'); }
      } finally {
        phrase.dispose();
        password.dispose();
      }
    } catch (e) {
      if (mounted) { showMessage(context, 'JSON upload failed: $e'); }
    } finally {
      if (mounted) { setState(() => busy = false); }
    }
  }

  Future<void> resetReporting() async {
    if (busy || !backupSaved) {
      showMessage(context, 'Save a backup first.');
      return;
    }
    Map<String, int> counts;
    try {
      counts = await service.countReportingDocuments();
    } catch (e) {
      if (mounted) showMessage(context, 'Unable to check reporting data: $e');
      return;
    }
    if (!mounted) return;
    final count = counts.values.fold<int>(0, (a, b) => a + b);
    final confirmation = TextEditingController();
    final password = TextEditingController();
    bool confirmed = false;
    try {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Reset reporting data?'),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('This permanently deletes $count performance records, targets '
                  'and leaderboard summaries.'),
              const SizedBox(height: 12),
              const Text('Employee profiles, login accounts, approvals and '
                  'Sign-in accounts will NOT be deleted.',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('You saved a JSON backup. Automated restore is not '
                  'provided. A failed batch may leave partial deletion.'),
              const SizedBox(height: 16),
              TextField(controller: confirmation,
                decoration: const InputDecoration(labelText: 'Type RESET REPORTS')),
              const SizedBox(height: 10),
              TextField(controller: password, obscureText: true,
                decoration: const InputDecoration(labelText: 'Your admin password')),
            ],
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext,
                    confirmation.text.trim() == 'RESET REPORTS' && password.text.isNotEmpty),
              child: const Text('Confirm Reset')),
          ],
        ),
      ) ?? false;
      if (!confirmed) {
        if (mounted) showMessage(context, 'Reset cancelled. Check phrase/password.');
        return;
      }
      setState(() => busy = true);
      final admin = FirebaseAuth.instance.currentUser;
      if (admin == null || admin.email == null) {
        throw StateError('Admin session expired. Please sign in again.');
      }
      await admin.reauthenticateWithCredential(EmailAuthProvider.credential(
        email: admin.email!, password: password.text,
      ));
      final removed = await service.resetReportingData();
      if (!mounted) return;
      setState(() { backupSaved = false; savedDestination = null; });
      showMessage(context, 'Reset finished: $removed reporting documents removed.');
    } catch (e) {
      if (mounted) showMessage(context, 'Reset failed: $e');
    } finally {
      confirmation.dispose();
      password.dispose();
      if (mounted) { setState(() => busy = false); }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Backup / Reset')),
    body: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        SectionCard(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ListTile(leading: Icon(Icons.cloud_download_outlined),
              title: Text('Backup App Data'),
              subtitle: Text('Save employees, linked identities, performance, '
                  'targets and leaderboard as a local JSON file.')),
            const SizedBox(height: 8),
            const Text('The backup contains private employee and applicant data. '
                'Keep it secure. Sign-in passwords are never exported.'),
            const SizedBox(height: 14),
            FilledButton.icon(onPressed: busy ? null : makeBackup,
              icon: const Icon(Icons.save_alt),
              label: Text(busy ? 'Please wait...' : 'Create & Save Backup')),
            if (savedDestination != null) ...[
              const SizedBox(height: 8),
              SelectableText('Saved: $savedDestination'),
            ],
          ],
        )),
        const SizedBox(height: 16),
        SectionCard(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ListTile(
              leading: Icon(Icons.upload_file_outlined),
              title: Text('Upload JSON File'),
              subtitle: Text('Restore missing reporting data from a private '
                  'PerformanceTracker backup. Preview before confirming.'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: busy ? null : uploadJsonBackup,
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('UPLOAD JSON FILE'),
            ),
            const SizedBox(height: 8),
            const Text('Restore is admin-only and cannot overwrite existing '
              'data or restore employee accounts. Back up first.'),
          ],
        )),
        const SizedBox(height: 16),
        SectionCard(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ListTile(leading: Icon(Icons.warning_amber, color: Colors.red),
              title: Text('Reset Reports and Targets'),
              subtitle: Text('Admin only • destructive • preserves employee logins')),
            const Text('Reset is only available after you save a backup '
                'in this screen and verify your admin password. This is not '
                'a full account reset.'),
            const SizedBox(height: 14),
            OutlinedButton.icon(onPressed: busy || !backupSaved ? null : resetReporting,
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              label: const Text('Reset Reporting Data')),
          ],
        )),
        if (busy) const Padding(padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator())),
      ]),
    )),
  );
}
