import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../models/entities.dart';
import '../../services/session.dart';
import '../../services/remembered_login.dart';
import '../auth/login_screen.dart';
import '../employees/directory_screen.dart';
import '../employees/sales_manager_picker.dart';
import 'backup_reset_screen.dart';
import 'updates_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.session});
  final Session session;

  Future<void> confirmLogout(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Exit / Logout'),
        content: const Text('Are you sure you want to log out and exit the application?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
            child: const Text('CANCEL')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
            child: const Text('LOGOUT')),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    session.logout();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    // Build the short Settings menu eagerly so action tiles remain discoverable
    // on small screens, while the page itself stays scrollable.
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('ACCOUNT & PROFILE',
            style: TextStyle(color: Palette.primary, fontWeight: FontWeight.bold)),
          _item(Icons.person_outline, 'My Profile', () => Navigator.push(context,
            MaterialPageRoute<void>(builder: (_) => EmployeeProfileScreen(
              session: session, id: session.user!.employeeId)))),
          _item(Icons.key_outlined, 'Change Password', () =>
            showDialog<void>(context: context,
              builder: (_) => _ChangePasswordDialog(session: session))),
          if (session.user!.isAdmin) ...[
            const SizedBox(height: 16),
            const Text('MANAGEMENT & ADMINISTRATION',
              style: TextStyle(color: Palette.primary, fontWeight: FontWeight.bold)),
            _item(Icons.checklist_outlined, 'Pending Approvals', () =>
              Navigator.push(context, MaterialPageRoute<void>(
                builder: (_) => ApprovalsScreen(session: session))),
              // Live dots require an initialized database connection. Widget
              // tests, or an app awaiting initialization, have no default app.
              attention: session.api.isConfigured
                ? session.api.db.collection('employees')
                    .where('status', isEqualTo: 'Pending').snapshots()
                    .map((event) => event.docs.isNotEmpty)
                : null),
            _item(Icons.manage_accounts_outlined, 'Sales Manager Change Requests', () =>
              Navigator.push(context, MaterialPageRoute<void>(
                builder: (_) => ManagerChangeRequestsScreen(session: session))),
              attention: session.api.isConfigured
                ? session.api.db.collection('manager_change_requests')
                    .where('status', isEqualTo: 'Pending').snapshots()
                    .map((event) => event.docs.isNotEmpty)
                : null),
            _item(Icons.person_add_outlined, 'Create New User / Management ID', () =>
              Navigator.push(context, MaterialPageRoute<void>(
                builder: (_) => CreateManagementScreen(session: session)))),
            _item(Icons.groups_outlined, 'Officer List', () =>
              Navigator.push(context, MaterialPageRoute<void>(
                builder: (_) => DirectoryScreen(session: session)))),
            _item(Icons.backup_outlined, 'Backup / Reset', () =>
              Navigator.push(context, MaterialPageRoute<void>(
                builder: (_) => BackupResetScreen(session: session)))),
          ],
          const SizedBox(height: 16),
          const Text('SYSTEM & SUPPORT',
            style: TextStyle(color: Palette.primary, fontWeight: FontWeight.bold)),
          _item(Icons.system_update_alt, 'Updates', () =>
            Navigator.push(context, MaterialPageRoute<void>(
              builder: (_) => const UpdatesScreen()))),
          _item(Icons.info_outline, 'About', () => showDialog<void>(
            context: context, builder: (dialog) => const _AboutDialog())),
          _item(Icons.help_outline, 'Help & Support', () =>
            showDialog<void>(context: context, builder: (_) => const _SupportDialog())),
          const SizedBox(height: 16),
          const Text('SESSION & EXIT',
            style: TextStyle(color: Palette.primary, fontWeight: FontWeight.bold)),
          _item(Icons.logout, 'Exit Application / Logout', () => confirmLogout(context)),
          const SizedBox(height: 24),
          const Center(child: Text('Performance Tracker\n'
            'Use Updates to check the installed and latest version\nAll rights reserved',
            textAlign: TextAlign.center, style: TextStyle(color: Palette.muted))),
        ],
      ),
    ),
  );

  Widget _item(IconData icon, String label, VoidCallback action,
      {Stream<bool>? attention}) {
    Widget tile(bool hasPending) => Card(child: ListTile(
      leading: Icon(icon, color: Palette.primary),
      title: Text(label),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (hasPending) const _SmallPendingDot(),
        if (hasPending) const SizedBox(width: 10),
        const Icon(Icons.chevron_right),
      ]),
      onTap: action));
    if (attention == null) return tile(false);
    return StreamBuilder<bool>(
      stream: attention,
      builder: (context, snapshot) => tile(snapshot.data ?? false),
    );
  }
}


class _AboutDialog extends StatelessWidget {
  const _AboutDialog();

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Performance Tracker'),
    content: FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        final version = info == null ? 'Loading version…'
            : 'Version ${info.version} • Build ${info.buildNumber}';
        return Text('Flutter edition\n$version');
      },
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
    ],
  );
}

class _SmallPendingDot extends StatelessWidget {
  const _SmallPendingDot();
  @override
  Widget build(BuildContext context) => const Tooltip(
    message: 'New request requires attention',
    child: SizedBox(width: 10, height: 10,
      child: DecoratedBox(decoration: BoxDecoration(
        color: Palette.red, shape: BoxShape.circle))));
}

class _SupportDialog extends StatelessWidget {
  const _SupportDialog();
  static const whatsappUrl = 'https://wa.me/qr/UYHZCG4FYNYYC1';

  Future<void> open(BuildContext context, String url) async {
    try {
      if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
        if (context.mounted) showMessage(context, 'Cannot open this link.');
      }
    } catch (e) {
      if (context.mounted) showMessage(context, 'Unable to open link: $e');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Help & Support'),
    content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520),
      child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('For system assistance, approval requests, or technical '
              'issues, please contact your System Administrator or IT Support:'),
          const SizedBox(height: 18),
          _linkRow(context, '• Helpline:', '+880 1686-556444', 'tel:+8801686556444'),
          _linkRow(context, '• Official Support:', 'jahid2177@gmail.com',
              'mailto:jahid2177@gmail.com'),
          const Text('• Created By: Md. Jahidul Islam, CBD'),
          const SizedBox(height: 4),
          const Text('• Contact on WhatsApp:'),
          InkWell(onTap: () => open(context, whatsappUrl),
            child: const Padding(padding: EdgeInsets.only(top: 4),
              child: Text(whatsappUrl,
                style: TextStyle(color: Palette.primary,
                  decoration: TextDecoration.underline))),),
        ],
      )),
    ),
    actions: [
      TextButton(onPressed: () => open(context, whatsappUrl),
        child: const Text('OPEN WHATSAPP')),
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
    ],
  );

  Widget _linkRow(BuildContext context, String title, String value, String url) =>
    Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text('$title '),
      InkWell(onTap: () => open(context, url),
        child: Text(value, style: const TextStyle(color: Palette.primary,
          decoration: TextDecoration.underline))),
    ]);
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.session});
  final Session session;
  @override State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}
class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final old = TextEditingController(), newer = TextEditingController(),
      again = TextEditingController();
  bool busy = false;
  @override void dispose() { old.dispose(); newer.dispose(); again.dispose(); super.dispose(); }
  Future<void> save() async {
    if (newer.text != again.text) {
      showMessage(context, 'Passwords do not match.'); return;
    }
    setState(() => busy = true);
    try {
      await widget.session.api.changePassword(old.text, newer.text);
      // Never leave the previous password auto-filled after a password change.
      try { await RememberedLogin().clearPassword(); } catch (_) { /* no cached secret */ }
      if (!mounted) return;
      showMessage(context, 'Password changed. Previously saved password cleared.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showMessage(context, 'Change password failed: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
  @override Widget build(BuildContext context) => AlertDialog(
    title: const Text('Change Password'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
      children: [
        TextField(controller: old, obscureText: true,
          decoration: const InputDecoration(labelText: 'Current Password')),
        const SizedBox(height: 12),
        TextField(controller: newer, obscureText: true,
          decoration: const InputDecoration(labelText: 'New Password (8+ characters)')),
        const SizedBox(height: 12),
        TextField(controller: again, obscureText: true,
          decoration: const InputDecoration(labelText: 'Confirm New Password')),
      ],)),
    actions: [
      TextButton(onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('CANCEL')),
      FilledButton(onPressed: busy ? null : save,
        child: Text(busy ? 'Updating...' : 'UPDATE')),
    ],
  );
}

class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key, required this.session});
  final Session session;
  @override State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}
class _ApprovalsScreenState extends State<ApprovalsScreen> {
  late Future<List<Employee>> future;
  String? processingEmployeeId;
  @override void initState() { super.initState(); reload(); }
  void reload() { future = widget.session.api.pendingApprovals(); }

  Future<void> decide(Employee employee, bool approve) async {
    if (processingEmployeeId != null) return;
    String chosenRole = 'USER';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(builder: (dialog, update) => AlertDialog(
        title: Text('${approve ? 'Approve' : 'Reject'} ${employee.name}?'),
        content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Employee ID: ${employee.employeeId}'),
          Text('Branch: ${employee.displayBranch}'),
          if (approve) ...[
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(initialValue: chosenRole,
              decoration: const InputDecoration(labelText: 'Approved role'),
              isExpanded: true,
              items: ['USER', 'Sales Manager', 'AGM', 'DGM'].map((role) =>
                DropdownMenuItem(value: role, child: Text(role))).toList(),
              onChanged: (role) => update(() => chosenRole = role ?? 'USER')),
          ] else const Text('This employee will not be able to sign in.'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
            child: Text(approve ? 'Approve' : 'Reject')),
        ],
      )),
    );
    if (confirmed != true || !mounted) return;
    setState(() => processingEmployeeId = employee.employeeId);
    try {
      await widget.session.api.decideApproval(employee.employeeId, approve, role: chosenRole);
      if (!mounted) return;
      setState(reload);
      showMessage(context,
        '${employee.name} ${approve ? 'approved as $chosenRole' : 'rejected'} successfully.');
    } catch (e) {
      if (mounted) showMessage(context, 'Unable to update approval: $e');
    } finally {
      if (mounted) setState(() => processingEmployeeId = null);
    }
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pending Approvals'), actions: [
      IconButton(tooltip: 'Refresh approvals',
        onPressed: processingEmployeeId == null ? () => setState(reload) : null,
        icon: const Icon(Icons.refresh)),
    ]),
    body: FutureBuilder<List<Employee>>(future: future, builder: (context, snapshot) {
      if (snapshot.hasError) {
        return LoadError(message: '${snapshot.error}',
          retry: () => setState(reload));
      }
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final pending = snapshot.data!;
      if (pending.isEmpty) return const Center(child: Text('No pending requests'));
      return ListView.builder(padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: pending.length, itemBuilder: (context, index) {
        final employee = pending[index];
        final processing = processingEmployeeId == employee.employeeId;
        return Card(margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: ListTile(
            title: Text(employee.name),
            subtitle: Text('${employee.employeeId} • ${employee.displayBranch}'),
            trailing: processing
              ? const SizedBox(width: 44, height: 44,
                  child: Padding(padding: EdgeInsets.all(9),
                    child: CircularProgressIndicator(strokeWidth: 2)))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(tooltip: 'Reject',
                    onPressed: processingEmployeeId == null
                      ? () => decide(employee, false) : null,
                    icon: const Icon(Icons.close, color: Palette.red)),
                  IconButton(tooltip: 'Approve',
                    onPressed: processingEmployeeId == null
                      ? () => decide(employee, true) : null,
                    icon: const Icon(Icons.check, color: Palette.primary)),
                ]),
          ),
        );
      });
    }),
  );
}

class CreateManagementScreen extends StatefulWidget {
  const CreateManagementScreen({super.key, required this.session});
  final Session session;
  @override State<CreateManagementScreen> createState() => _CreateManagementScreenState();
}
class _CreateManagementScreenState extends State<CreateManagementScreen> {
  final formKey = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{
    for (final field in ['employeeId', 'name', 'mobile', 'email', 'officialNumber',
      'branch', 'zone', 'password', 'confirmPassword'])
      field: TextEditingController(),
  };
  String role = 'USER';
  SalesManagerOption? selectedManager;
  int managerDirectoryRevision = 0;
  List<String> get displayedFields => role == 'USER'
      ? ['employeeId','name','mobile','email','officialNumber','branch',
          'zone','managerId','password','confirmPassword']
      : role == 'Sales Manager'
      ? ['employeeId','name','mobile','email','officialNumber','branch',
          'zone','password','confirmPassword']
      : ['employeeId','name','mobile','email','officialNumber','branch',
          'password','confirmPassword'];
  bool busy = false;

  @override void dispose() {
    for (final controller in fields.values) { controller.dispose(); }
    super.dispose();
  }

  Future<void> create() async {
    if (busy || !(formKey.currentState?.validate() ?? false)) return;
    if (role == 'USER' && selectedManager == null) {
      showMessage(context, 'Select a Sales Manager for the USER role.');
      return;
    }
    setState(() => busy = true);
    try {
      await widget.session.api.createManagement({
        for (final key in displayedFields.where((key) => key != 'managerId'))
          key: fields[key]!.text.trim(),
        'managerId': role == 'USER' ? selectedManager!.employeeId : '',
        'role': role,
      });
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (dialog) => AlertDialog(
        title: const Text('Account created'),
        content: Text('New $role ID ${fields['employeeId']!.text.trim()} '
          'created and approved. Give the password privately to the employee. '
          'Ask them to change it after first login.'),
        actions: [TextButton(onPressed: () => Navigator.pop(dialog),
          child: const Text('OK'))],
      ));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        showMessage(context, 'Could not complete account creation: $e. '
            'If an ID was created as Pending, check Pending Approvals.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Create User / Manager ID')),
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 700),
      child: Form(key: formKey, child: ListView(padding: const EdgeInsets.all(16),
        children: [SectionCard(child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Admin can create USER, Sales Manager, AGM and DGM IDs '
                'without changing their own active session.'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: busy ? null : () async {
                try {
                  final count = await widget.session.api.syncSalesManagerDirectory();
                  if (mounted) {
                    setState(() => managerDirectoryRevision++);
                    showMessage(context,
                      '$count approved Sales Managers are available to registration and profiles.');
                  }
                } catch (e) {
                  if (mounted) showMessage(context, 'Cannot sync Sales Managers: $e');
                }
              },
              icon: const Icon(Icons.sync), label: const Text('Sync Approved Sales Managers'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(initialValue: role,
              decoration: const InputDecoration(labelText: 'Account Role'),
              items: ['USER', 'Sales Manager', 'AGM', 'DGM']
                  .map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
              onChanged: busy ? null : (value) => setState(() {
                role = value ?? 'USER';
                selectedManager = null;
              })),
            const SizedBox(height: 14),
            for (final key in displayedFields) ...[
              if (key == 'managerId') ...[
                SalesManagerPicker(key: ValueKey('create_${role}_${managerDirectoryRevision}_manager'),
                  api: widget.session.api,
                  onChanged: (value) => setState(() => selectedManager = value)),
                const SizedBox(height: 12),
              ] else TextFormField(controller: fields[key],
                obscureText: key.toLowerCase().contains('password'),
                keyboardType: ['employeeId', 'mobile', 'officialNumber'].contains(key)
                  ? TextInputType.number : TextInputType.text,
                decoration: InputDecoration(labelText: const {
                  'employeeId': 'Employee ID (12 digits)', 'name': 'Full Name',
                  'mobile': 'Mobile Number', 'email': 'Recovery Email (required)',
                  'officialNumber': 'Official Number (required)',
                  'branch': 'Branch', 'zone': 'Zone',
                                    'password': 'Temporary Password (8+ characters)',
                  'confirmPassword': 'Confirm Password',
                }[key]),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) {
                    return 'Required';
                  }
                  if (key == 'employeeId' && !RegExp(r'^\d{12}$').hasMatch(text)) {
                    return 'Exactly 12 digits';
                  }
                  if (['mobile','officialNumber'].contains(key) && !RegExp(r'^[0-9+() -]{7,20}$').hasMatch(text)) {
                    return 'Enter a valid contact number';
                  }
                  if (key == 'password' && text.length < 8) {
                    return 'At least 8 characters';
                  }
                  if (key == 'confirmPassword' && text != fields['password']!.text) {
                    return 'Passwords do not match';
                  }
                  if (key == 'email' &&
                    !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)) {
                    return 'Invalid email';
                  }
                  return null;
                }),
              const SizedBox(height: 12),
            ],
            const Text('Only fields required for the selected role are shown.\nThe new linked identity starts as Pending USER. '
                'Only your ADMIN session approves the selected role. '
                'Never share temporary passwords in public messages.'),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: busy ? null : create,
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(busy ? 'Creating...' : 'Create and Approve ID')),
          ],
        ))],
      )),
    )),
  );
}


/// Administration queue for officer-initiated manager reassignment.
class ManagerChangeRequestsScreen extends StatefulWidget {
  const ManagerChangeRequestsScreen({super.key, required this.session});
  final Session session;
  @override
  State<ManagerChangeRequestsScreen> createState() => _ManagerChangeRequestsScreenState();
}

class _ManagerChangeRequestsScreenState extends State<ManagerChangeRequestsScreen> {
  late Future<List<Map<String, dynamic>>> requests;
  String? busy;
  @override
  void initState() { super.initState(); refresh(); }
  void refresh() { requests = widget.session.api.managerChangeRequests(); }

  Future<void> decision(Map<String, dynamic> request, bool approve) async {
    final id = '${request['employeeId'] ?? ''}';
    final employeeName = '${request['employeeName'] ?? ''}'.trim();
    if (busy != null) return;
    final confirmed = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'Approve manager reassignment?' : 'Reject manager change?'),
        content: Text('Officer: ${employeeName.isEmpty ? id : '$employeeName ($id)'}\n'
          'New manager: ${request['managerName']}\n'
          'Approving will also update historical private report team ownership.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('CONFIRM')),
        ],
      ));
    if (confirmed != true || !mounted) return;
    setState(() => busy = id);
    try {
      await widget.session.api.decideManagerChange(id, approve);
      if (mounted) {
        setState(refresh);
        showMessage(context, approve ? 'Manager changed successfully' : 'Request rejected');
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Cannot update manager: $e');
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  String _requestTitle(Map<String, dynamic> item) {
    final id = '${item['employeeId'] ?? ''}'.trim();
    final name = '${item['employeeName'] ?? ''}'.trim();
    return name.isEmpty ? 'Officer $id' : '$name • $id';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sales Manager Change Requests'),
      actions: [IconButton(onPressed: () => setState(refresh),
        icon: const Icon(Icons.refresh))]),
    body: FutureBuilder<List<Map<String, dynamic>>>(future: requests,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (snapshot.data!.isEmpty) return const Center(child: Text('No pending manager changes'));
        return ListView(children: [for (final item in snapshot.data!) Card(
          child: ListTile(
            title: Text(_requestTitle(item)),
            subtitle: Text('Requested Sales Manager: ${item['managerName']}'),
            trailing: busy == item['employeeId']
              ? const CircularProgressIndicator()
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(onPressed: () => decision(item, false),
                    icon: const Icon(Icons.close)),
                  IconButton(onPressed: () => decision(item, true),
                    icon: const Icon(Icons.check)),
                ]),
          ),
        )]);
      }),
  );
}
