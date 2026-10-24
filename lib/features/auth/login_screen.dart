import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../services/session.dart';
import '../../services/api.dart';
import '../../services/remembered_login.dart';
import '../../services/update_service.dart';
import '../../models/entities.dart';
import '../employees/sales_manager_picker.dart';
import '../settings/updates_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.session});
  final Session session;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final id = TextEditingController();
  final password = TextEditingController();
  final vault = RememberedLogin();
  bool obscured = true;
  bool signingIn = false;
  bool loadingSaved = true;
  bool keepId = true;
  bool keepPassword = false;

  @override
  void initState() {
    super.initState();
    loadSaved();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkWindowsUpdate());
  }

  Future<void> _checkWindowsUpdate() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
    final updater = UpdateService();
    try {
      if (!await updater.autoCheckEnabled()) return;
      final result = await updater.checkForUpdate();
      if (!mounted || !result.updateAvailable) return;
      final open = await showUpdateAvailableDialog(context, result);
      if (!mounted || !open) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => UpdatesScreen(initialResult: result),
        ),
      );
    } catch (_) {
      // A failed update check must never block login. The user can retry from
      // Settings > Updates after signing in.
    } finally {
      updater.close();
    }
  }

  Future<void> loadSaved() async {
    try {
      final saved = await vault.read();
      if (!mounted) return;
      id.text = saved.id;
      password.text = saved.password;
      setState(() {
        keepId = saved.keepId;
        keepPassword = saved.keepPassword;
      });
    } catch (_) {
      if (mounted) {
        showMessage(context,
            'Saved login could not be unlocked on this device. Enter credentials again.');
      }
    } finally {
      if (mounted) setState(() => loadingSaved = false);
    }
  }

  @override
  void dispose() {
    id.dispose();
    password.dispose();
    super.dispose();
  }


  Future<void> signIn() async {
    final employeeId = id.text.trim();
    final secret = password.text;
    if (employeeId.isEmpty || secret.isEmpty) {
      showMessage(context, 'Enter your Employee ID or sign-in email and password.');
      return;
    }
    if (signingIn) return;
    setState(() => signingIn = true);
    try {
      await widget.session.login(employeeId, secret);
      // Android Autofill / Google Password Manager may offer to save credentials.
      // The system controls whether the prompt is shown.
      TextInput.finishAutofillContext(shouldSave: true);
      // Save ONLY after a successful login, and only with explicit consent.
      // Session may have already routed to Home; do not use context after login.
      try {
        await vault.save(
          employeeId: employeeId,
          password: secret,
          keepId: keepId,
          keepPassword: keepId && keepPassword,
        );
      } catch (_) {
        // Credential storage failure must not invalidate successful sign-in.
      }
    } catch (e) {
      if (mounted) showMessage(context, '$e');
    } finally {
      if (mounted) setState(() => signingIn = false);
    }
  }

  Future<void> forgotPassword() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ResetPasswordDialog(
        api: widget.session.api,
        initialValue: id.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Image.asset(
                    'assets/branding/performance_tracker_logo.png',
                    width: 88,
                    height: 88,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                    semanticLabel: 'Performance Tracker logo',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Performance Tracker', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold, color: Palette.dark)),
              const SizedBox(height: 8),
              const Text('Employee Performance Management', textAlign: TextAlign.center),
              const SizedBox(height: 24),
              AutofillGroup(child: SectionCard(child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Welcome back',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: id,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(
                      labelText: 'Employee ID / Sign-in email',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: password,
                    obscureText: obscured,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => signIn(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: 'Show/hide password',
                        onPressed: () => setState(() => obscured = !obscured),
                        icon: Icon(obscured ? Icons.visibility : Icons.visibility_off),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: keepId,
                    title: const Text('Remember ID on this device'),
                    onChanged: (v) => setState(() {
                      keepId = v ?? false;
                      if (!keepId) keepPassword = false;
                    }),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: signingIn || widget.session.busy || loadingSaved ? null : signIn,
                    icon: signingIn ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login),
                    label: const Text('LOGIN'),
                  ),
                  TextButton(onPressed: forgotPassword,
                      child: const Text('Forgot password?')),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => RegisterScreen(api: widget.session.api)),
                    ),
                    child: const Text('Register Now'),
                  ),
                ],
              ))),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ResetPasswordDialog extends StatefulWidget {
  const _ResetPasswordDialog({required this.api, required this.initialValue});
  final ApiClient api;
  final String initialValue;
  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  late final TextEditingController address =
      TextEditingController(text: widget.initialValue);
  bool busy = false;
  String? result;
  @override
  void dispose() { address.dispose(); super.dispose(); }

  Future<void> submit() async {
    if (busy) return;
    setState(() { busy = true; result = null; });
    try {
      await widget.api.requestPasswordReset(address.text.trim());
      if (mounted) {
        setState(() => result =
          'If this sign-in account exists, '
          'a password reset link has been requested. Check Inbox and Spam.');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => result = e.message);
    } catch (e) {
      if (mounted) setState(() => result = 'Unable to request reset: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Reset password'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Enter your Employee ID or your actual sign-in email.'),
          const SizedBox(height: 12),
          TextField(
            controller: address,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Employee ID / Sign-in email',
              prefixIcon: Icon(Icons.mail_outline),
            ),
            onSubmitted: (_) => submit(),
          ),
          const SizedBox(height: 10),
          const Text('Note: accounts using the internal .invalid login alias '
              'cannot receive reset emails. Contact your ADMIN for verified '
              'account recovery. A profile contact email is not automatically '
              'your sign-in email.',
              style: TextStyle(fontSize: 12, color: Palette.muted)),
          if (result != null) ...[
            const SizedBox(height: 12),
            SelectableText(result!),
          ],
        ],
      )),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE')),
      FilledButton(onPressed: busy ? null : submit,
          child: Text(busy ? 'Sending...' : 'SEND RESET LINK')),
    ],
  );
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key,required this.api}); final ApiClient api;
  @override State<RegisterScreen> createState()=>_RegisterScreenState();
}
class _RegisterScreenState extends State<RegisterScreen> {
  final formKey = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{
    for (final key in ['employeeId','name','mobile','email','officialNumber',
      'branch','zone','password']) key: TextEditingController(),
  };
  SalesManagerOption? manager;
  bool busy = false;
  @override
  void dispose() {
    for (final controller in fields.values) { controller.dispose(); }
    super.dispose();
  }
  Future<void> submit() async {
    if (busy || !(formKey.currentState?.validate() ?? false)) return;
    if (manager == null) {
      showMessage(context, 'Select a Sales Manager before registration.');
      return;
    }
    setState(() => busy = true);
    try {
      await widget.api.register({
        for (final field in fields.entries) field.key: field.value.text.trim(),
        'managerId': manager!.employeeId,
      });
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (dialog) => AlertDialog(
        title: const Text('Registration submitted'),
        content: const Text('Your account is Pending until ADMIN approval.\n'
          'The selected Sales Manager will be saved with your registration.'),
        actions: [TextButton(onPressed: () => Navigator.pop(dialog),
          child: const Text('OK'))],
      ));
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) showMessage(context, '$error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Employee Registration')),
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680),
      child: Form(key: formKey, child: ListView(
        padding: const EdgeInsets.all(16), children: [SectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final key in fields.keys) ...[
              if (key == 'password') ...[
                SalesManagerPicker(api: widget.api,
                  onChanged: (value) => setState(() => manager = value)),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: fields[key],
                keyboardType: ['employeeId','mobile','officialNumber'].contains(key)
                    ? TextInputType.number : key == 'email'
                    ? TextInputType.emailAddress : TextInputType.text,
                obscureText: key == 'password',
                decoration: InputDecoration(labelText: const {
                  'employeeId': 'Employee ID (12 digits)', 'name': 'Full Name',
                  'mobile': 'Mobile Number', 'email': 'Recovery Email',
                  'officialNumber': 'Official Number', 'branch': 'Branch',
                  'zone': 'Zone', 'password': 'Password (8+ characters)',
                }[key]),
                validator: (value) {
                  final v = value?.trim() ?? '';
                  if (v.isEmpty) return 'Required';
                  if (key == 'employeeId' && !RegExp(r'^\d{12}$').hasMatch(v)) {
                    return 'Exactly 12 digits';
                  }
                  if (key == 'email' && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
                    return 'Enter a valid recovery email';
                  }
                  if (key == 'password' && v.length < 8) return 'At least 8 characters';
                  return null;
                },
              ),
              const SizedBox(height: 12),
            ],
            FilledButton(onPressed: busy ? null : submit,
              child: Text(busy ? 'Submitting...' : 'Create account')),
            const SizedBox(height: 8),
            const Text('All new accounts start as Pending USER until admin approval.',
              textAlign: TextAlign.center),
          ]),
        )],
      )),
    )),
  );
}

void showMessage(BuildContext context,String msg) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(msg)));
}
