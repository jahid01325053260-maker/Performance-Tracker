import 'dart:typed_data';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/entities.dart';
import '../core/submission_deadline.dart';

class ApiException implements Exception {
  final String message;
  final int status;
  const ApiException(this.message, this.status);
  @override
  String toString() => message;
}

/// No paid Cloud Functions, self-hosted API or service account in the client.
/// Access control MUST be enforced by firestore.rules, not by these checks.
class ApiClient {
  // Keep the existing public named arguments while using initializing formals.
  ApiClient({FirebaseFirestore? database, FirebaseAuth? authentication})
      : this._withDependencies(database, authentication);

  ApiClient._withDependencies(this._database, this._authentication);

  final FirebaseFirestore? _database;
  final FirebaseAuth? _authentication;
  FirebaseFirestore get db => _database ?? FirebaseFirestore.instance;
  FirebaseAuth get auth => _authentication ?? FirebaseAuth.instance;
  bool get isConfigured => Firebase.apps.isNotEmpty;
  String get _uid => auth.currentUser?.uid ?? (throw const ApiException('Please sign in.', 401));

  String _hash(String input) => sha256.convert(utf8.encode(input)).toString();
  String _alias(String employeeId) =>
      'pt-${_hash(employeeId).substring(0, 40)}@performance-tracker.invalid';

  String _period(String value) {
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(value)) {
      throw const ApiException('Choose a valid year and month.', 400);
    }
    return value;
  }

  Future<void> checkHealth() async {
    if (!isConfigured) throw const ApiException('The app service is not configured.', 0);
    try {
      // Identity-independent connectivity probe. This does NOT require
      // any unrestricted Firestore collection or deployed Cloud Function.
      await db.collection('login_index').doc(_hash('000000000000'))
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));
    } on FirebaseAuthException catch (e) {
      if (e.code == 'network-request-failed') {
        throw const ApiException('No network connection.', 503);
      }
    } catch (_) {
      throw const ApiException('Cannot reach the service. Check internet access.', 503);
    }
  }

  Future<Employee> login(String employeeId, String password) async {
    final id = employeeId.trim();
    // Real Firebase sign-in emails can be used by migrated accounts; legacy
    // Employee ID login and deterministic aliases remain fully supported.
    if (id.contains('@')) {
      try {
        await auth.signInWithEmailAndPassword(
            email: id.toLowerCase(), password: password);
        return await me();
      } on FirebaseAuthException catch (e) {
        throw ApiException(e.message ?? 'Invalid sign-in email or password.', 401);
      } catch (_) {
        await auth.signOut();
        rethrow;
      }
    }
    if (!RegExp(r'^\d{12}$').hasMatch(id)) {
      throw const ApiException('Employee ID must contain 12 digits.', 400);
    }
    // Existing Android app uses login_index/sha256(id) with an auth email.
    // New accounts use a deterministic private alias. The public single-doc
    // lookup is a legacy compatibility trade-off (see security_model.md).
    String loginEmail = _alias(id);
    try {
      final index = await db.collection('login_index').doc(_hash(id)).get();
      final legacyEmail = index.data()?['email'];
      if (legacyEmail is String && legacyEmail.trim().isNotEmpty) {
        loginEmail = legacyEmail.trim().toLowerCase();
      }
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable') {
        throw const ApiException('No internet connection.', 503);
      }
      // Alias remains valid when the old login index is not yet available.
    }
    try {
      await auth.signInWithEmailAndPassword(email: loginEmail, password: password);
      final employee = await me();
      if (employee.employeeId != id) {
        await auth.signOut();
        throw const ApiException('Employee ID does not match the linked account.', 403);
      }
      return employee;
    } on FirebaseAuthException catch (e) {
      throw ApiException(
        e.code == 'invalid-credential' || e.code == 'wrong-password' || e.code == 'user-not-found'
            ? 'Incorrect Employee ID or password. Contact admin if your account still needs sign-in setup.'
            : (e.message ?? 'Sign-in failed.'), 401);
    } on ApiException {
      await auth.signOut();
      rethrow;
    } on FirebaseException catch (e) {
      await auth.signOut();
      throw ApiException('Cannot load account: ${e.message ?? e.code}. Contact admin.', 403);
    }
  }

  /// Password reset can ONLY be emailed to an actual Firebase Auth sign-in
  /// email. Profile contact emails and deterministic .invalid aliases are not
  /// deliverable. Avoid pretending a link was sent to a contact-only address.
  Future<void> requestPasswordReset(String employeeIdOrEmail) async {
    final input = employeeIdOrEmail.trim();
    var email = input.toLowerCase();
    if (RegExp(r'^\d{12}$').hasMatch(input)) {
      try {
        final index = await db.collection('login_index')
            .doc(_hash(input)).get(const GetOptions(source: Source.server));
        email = '${index.data()?['email'] ?? ''}'.trim().toLowerCase();
        final employeeDoc = await db.collection('employees').doc(input)
            .get(const GetOptions(source: Source.server));
        final linkedUid = '${employeeDoc.data()?['authUid'] ?? ''}'.trim();
        final indexedUid = '${index.data()?['authUid'] ?? ''}'.trim();
        if (linkedUid.isEmpty || indexedUid.isEmpty || indexedUid != linkedUid) {
          throw const ApiException(
              'Unlinked/conflicting UID. Run trusted PC UID repair before reset.', 409);
        }
      } on FirebaseException catch (e) {
        throw ApiException('Unable to resolve the ID: ${e.message ?? e.code}', 503);
      }
      if (email.isEmpty || email.endsWith('.invalid')) {
        throw const ApiException(
          'This Employee ID uses an internal sign-in alias and cannot '
          'receive a reset email. Contact your ADMIN for identity-verified '
          'recovery; your profile email alone may not be your sign-in email.', 400);
      }
    } else if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      throw const ApiException('Enter a valid sign-in email or 12-digit Employee ID.', 400);
    }
    if (email.endsWith('.invalid')) {
      throw const ApiException(
        'Internal .invalid login aliases cannot receive email. Contact ADMIN '
        'for verified recovery.', 400);
    }
    try {
      await auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'too-many-requests') {
        throw const ApiException('Too many attempts. Please try again later.', 429);
      }
      if (e.code == 'network-request-failed') {
        throw const ApiException('No internet connection.', 503);
      }
      // Do not disclose whether an address has an Auth account.
      if (e.code != 'user-not-found' && e.code != 'invalid-credential') {
        throw ApiException(e.message ?? 'Password reset could not be requested.', 400);
      }
    }
  }

  Future<Employee> me() async {
    final uid = _uid;
    final identity = await db.collection('auth_users').doc(uid).get();
    final data = identity.data();
    final id = '${data?['employeeId'] ?? ''}';
    if (!RegExp(r'^\d{12}$').hasMatch(id)) {
      throw const ApiException('Account not linked to an Employee ID. Contact admin.', 403);
    }
    final snap = await db.collection('employees').doc(id).get();
    if (!snap.exists) throw const ApiException('Employee profile not found.', 403);
    final emp = Employee.fromJson({...snap.data()!, 'employeeId': id});
    if ('${snap.data()?['authUid'] ?? ''}' != uid ||
        '${data?['role'] ?? ''}'.trim().toLowerCase() != emp.role.trim().toLowerCase() ||
        '${data?['status'] ?? ''}'.trim().toLowerCase() != emp.status.trim().toLowerCase()) {
      throw const ApiException('Account identity/role mismatch. Contact admin.', 403);
    }
    if (emp.status.trim().toLowerCase() != 'approved') {
      throw ApiException('Account is ${emp.status}. Wait for administrator approval.', 403);
    }
    return emp;
  }

  /// Minimal public directory: employee IDs and names of approved Sales Managers
  /// only. Keep phone numbers, emails, applicant data and auth mappings private.
  Future<List<SalesManagerOption>> salesManagers() async {
    final snapshot = await db.collection('sales_manager_directory').get();
    final managers = snapshot.docs.map((doc) => SalesManagerOption(
      employeeId: doc.id, name: '${doc.data()['name'] ?? ''}',
    )).where((entry) => entry.employeeId.isNotEmpty && entry.name.isNotEmpty).toList();
    managers.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return managers;
  }

  /// A request does NOT move report permissions. ADMIN must confirm first and
  /// re-link older private report documents using assignSalesManager().
  Future<void> requestSalesManagerChange(String managerId) async {
    final current = await me();
    if (!current.isOfficer) throw const ApiException('Only officers can request a manager change.', 403);
    final choices = await salesManagers();
    final matches = choices.where((manager) => manager.employeeId == managerId).toList();
    if (matches.isEmpty) throw const ApiException('Choose an approved Sales Manager.', 400);
    await db.collection('manager_change_requests').doc(current.employeeId).set({
      'employeeId': current.employeeId,
      'authUid': auth.currentUser!.uid,
      'managerId': managerId,
      'managerName': matches.single.name,
      'status': 'Pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await db.waitForPendingWrites();
  }

  Future<List<Map<String, dynamic>>> managerChangeRequests() async {
    if (!(await me()).isAdmin) throw const ApiException('Admin only.', 403);
    final snapshot = await db.collection('manager_change_requests').get();
    return snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id})
        .where((data) => data['status'] == 'Pending').toList();
  }

  Future<void> decideManagerChange(String employeeId, bool approve) async {
    if (!(await me()).isAdmin) throw const ApiException('Admin only.', 403);
    final ref = db.collection('manager_change_requests').doc(employeeId);
    final request = await ref.get();
    if (!request.exists || request.data()?['status'] != 'Pending') {
      throw const ApiException('Manager change request not found.', 404);
    }
    if (approve) {
      final employee = await profile(employeeId);
      final manager = await profile('${request.data()!['managerId']}');
      if (!employee.isOfficer || manager.role != 'Sales Manager' ||
          manager.status.toLowerCase() != 'approved') {
        throw const ApiException('Officer or manager account is no longer eligible.', 409);
      }
      await assignSalesManager(employee, manager);
    }
    await ref.delete();
  }

  /// One-time legacy migration for the restricted public manager picker.
  /// Only publishes names and IDs; never personal contact information.
  Future<int> syncSalesManagerDirectory() async {
    if (!(await me()).isAdmin) throw const ApiException('Admin only.', 403);
    final all = await employees();
    final eligible = all.where((e) => e.role.toLowerCase() == 'sales manager' &&
        e.status.toLowerCase() == 'approved').toList();
    final existing = await db.collection('sales_manager_directory').get();
    final wanted = eligible.map((e) => e.employeeId).toSet();
    final operations = <void Function(WriteBatch)>[
      for (final e in eligible) (batch) => batch.set(
        db.collection('sales_manager_directory').doc(e.employeeId),
        {'employeeId': e.employeeId, 'name': e.name}),
      for (final d in existing.docs.where((d) => !wanted.contains(d.id)))
        (batch) => batch.delete(d.reference),
    ];
    for (var start = 0; start < operations.length; start += 200) {
      final batch = db.batch();
      for (final operation in operations.skip(start).take(200)) { operation(batch); }
      await batch.commit();
    }
    return eligible.length;
  }

  Future<void> register(Map<String, dynamic> payload) async {
    final id = '${payload['employeeId'] ?? ''}'.trim();
    final pass = '${payload['password'] ?? ''}';
    if (!RegExp(r'^\d{12}$').hasMatch(id) || pass.length < 8) {
      throw const ApiException('A 12-digit ID and password (8+ chars) are required.', 400);
    }
    for (final field in ['name', 'mobile', 'email', 'officialNumber', 'branch', 'zone', 'managerId']) {
      if ('${payload[field] ?? ''}'.trim().isEmpty) {
        throw ApiException('$field is required for registration.', 400);
      }
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch('${payload['email']}')) {
      throw const ApiException('Enter a valid recovery email.', 400);
    }
    // Resolve the selected public manager, never trust a typed display name.
    final managerId = '${payload['managerId'] ?? ''}'.trim();
    final managers = await salesManagers();
    final managerOptions = managers.where((e) => e.employeeId == managerId).toList();
    if (managerOptions.isEmpty) {
      throw const ApiException('Select an approved Sales Manager from the list.', 400);
    }
    final managerName = managerOptions.single.name;
    // Never accept client-provided role, status, uid or permissions.
    // Do not read employee profiles before authentication. Email/Password
    // alias uniqueness is enforced by Firebase Auth, and Firestore create rules
    // prevent overwriting an existing employee document.
    final emailAlias = _alias(id);
    UserCredential credential;
    try {
      credential = await auth.createUserWithEmailAndPassword(email: emailAlias, password: pass);
    } on FirebaseAuthException catch (e) {
      throw ApiException(e.message ?? 'Registration failed.', 400);
    }
    try {
      final uid = credential.user!.uid;
      final recovery = '${payload['email'] ?? ''}'.trim().toLowerCase();
      final batch = db.batch();
      batch.set(db.collection('employees').doc(id), {
        'employeeId': id,
        'authUid': uid,
        'name': '${payload['name'] ?? ''}'.trim(),
        'mobile': '${payload['mobile'] ?? ''}'.trim(),
        'email': recovery,
        'officialNumber': '${payload['officialNumber'] ?? ''}'.trim(),
        'branch': upper('${payload['branch'] ?? ''}'),
        'zone': upper('${payload['zone'] ?? ''}'),
        'salesManager': managerName, 'managerId': managerId,
        'role': 'USER', 'status': 'Pending',
        'monthlyTarget': 0, 'yearlyTarget': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(db.collection('auth_users').doc(uid), {
        'employeeId': id, 'role': 'USER', 'status': 'Pending',
      });
      // New IDs use a deterministic auth alias; no public login_index write.
      await batch.commit();
    } catch (e) {
      // If Firestore rules reject the batch, do not leave signed-in as a
      // half-registered user. Orphaned Auth users require admin cleanup.
      await auth.signOut();
      throw ApiException('Profile creation failed: $e. Contact admin if ID is reserved.', 403);
    }
    await auth.signOut();
  }

  /// Legacy Android accepted several forms of Approved, including blank.
  /// Keep Pending/Rejected/Disabled out of the public directory.
  static bool isDirectoryApproved(String? status) {
    final value = (status ?? '').trim().toLowerCase();
    return value.isEmpty || value == 'approved';
  }

  Future<List<Employee>> employees({String search = '', String role = 'All'}) async {
    final viewer = await me();
    // Firestore rules are NOT query-time filters. Non-admins must explicitly
    // constrain the query to approved-compatible values in the security rules.
    // Admin can inspect legacy records that omit status altogether.
    final snapshot = viewer.isAdmin
        ? await db.collection('employees').get()
        : await db.collection('employees').where('status', whereIn: [
            'Approved', 'APPROVED', 'approved', '',
          ]).get();
    final q = search.trim().toLowerCase();
    final output = <Employee>[];
    for (final document in snapshot.docs) {
      if (!isDirectoryApproved(document.data()['status']?.toString())) continue;
      final e = Employee.fromJson({...document.data(), 'employeeId': document.id});
      if (role != 'All' && e.role.toLowerCase() != role.toLowerCase()) continue;
      if ([e.name, e.employeeId, e.branch, e.zone, e.salesManager, e.department]
          .any((field) => field.toLowerCase().contains(q))) {
        output.add(e);
      }
    }
    output.sort((a, b) {
      const order = {'USER': 0, 'Sales Manager': 1, 'AGM': 2, 'DGM': 3, 'ADMIN': 4};
      final byRole = (order[a.role] ?? 5).compareTo(order[b.role] ?? 5);
      return byRole != 0 ? byRole : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return output;
  }

  Stream<List<Employee>> watchDirectory() async* {
    final viewer = await me();
    final query = viewer.isAdmin
      ? db.collection('employees')
      : db.collection('employees').where('status', whereIn:
          ['Approved','APPROVED','approved','']);
    yield* query.snapshots().map((snapshot) {
      final all = snapshot.docs
        .where((d) => isDirectoryApproved(d.data()['status']?.toString()))
        .map((d) => Employee.fromJson({...d.data(), 'employeeId': d.id}))
        .toList();
      return all;
    });
  }

  Future<Employee> profile(String id) async {
    final s = await db.collection('employees').doc(id).get();
    if (!s.exists) throw const ApiException('Employee not found.', 404);
    return Employee.fromJson({...s.data()!, 'employeeId': id});
  }

  Future<void> editProfile(String id, Map<String, dynamic> changes) async {
    // Field allowlists must also exist in Firestore rules.
    const selfFields = {'name', 'email', 'mobile', 'officialNumber', 'profileImage'};
    const adminFields = {...selfFields, 'branch', 'zone', 'department', 'salesManager', 'managerId'};
    final isAdmin = (await me()).isAdmin;
    final allowed = isAdmin ? adminFields : selfFields;
    if (!isAdmin && (await me()).employeeId != id) throw const ApiException('Access denied.', 403);
    if (changes.keys.any((k) => !allowed.contains(k))) throw const ApiException('Field cannot be edited.', 400);
    // Keep the restricted public picker in sync with ADMIN manager-name edits.
    if (isAdmin && changes.containsKey('name')) {
      final existing = await profile(id);
      if (existing.role.toLowerCase() == 'sales manager' &&
          existing.status.toLowerCase() == 'approved') {
        final batch = db.batch();
        batch.update(db.collection('employees').doc(id), changes);
        batch.set(db.collection('sales_manager_directory').doc(id), {
          'employeeId': id, 'name': '${changes['name']}',
        });
        await batch.commit();
        return;
      }
    }
    await db.collection('employees').doc(id).update(changes);
  }

  /// Explicit ADMIN team assignment. Membership is stored on the officer and
  /// existing reports, so server-side managerId-only rules stay enforceable.
  /// For very large histories, use the backup-first migration tool instead.
  Future<int> assignSalesManager(Employee officer, Employee? manager) async {
    if (!(await me()).isAdmin) throw const ApiException('Admin only.', 403);
    if (!officer.isOfficer) throw const ApiException('Select an officer.', 400);
    if (manager != null && manager.role.toLowerCase() != 'sales manager') {
      throw const ApiException('The selected employee is not a Sales Manager.', 400);
    }
    final managerId = manager?.employeeId ?? '';
    final managerName = manager?.name ?? '';
    final docs = await db.collection('performance')
        .where('employeeId', isEqualTo: officer.employeeId).get();
    // Set profile first; if a later batch fails, retrying the action is safe.
    await db.collection('employees').doc(officer.employeeId).update({
      'managerId': managerId, 'salesManager': managerName,
    });
    for (var start=0; start<docs.docs.length; start+=350) {
      final batch = db.batch();
      for (final doc in docs.docs.skip(start).take(350)) {
        batch.update(doc.reference, {
          'managerId': managerId, 'salesManager': managerName,
        });
      }
      await batch.commit();
    }
    await db.waitForPendingWrites();
    return docs.docs.length;
  }

  Future<List<CardRecord>> records({String? employeeId, String? period}) async {
    final own = await me();
    Query<Map<String, dynamic>> ref = db.collection('performance');
    if (employeeId != null) {
      ref = ref.where('employeeId', isEqualTo: employeeId);
    }
    if (own.role.trim().toLowerCase() == 'sales manager') {
      ref = ref.where('managerId', isEqualTo: own.employeeId);
    } else if (!(own.isAdmin || {'agm', 'dgm'}.contains(own.role.trim().toLowerCase()))) {
      if (employeeId != null && employeeId != own.employeeId) {
        throw const ApiException('You can view only your own records.', 403);
      }
      ref = ref.where('employeeId', isEqualTo: own.employeeId);
    }
    final docs = await ref.get();
    return docs.docs.map((s) => CardRecord.fromJson({...s.data(), 'id': s.id}))
        .where((record) => period == null || record.reportingPeriod == period).toList();
  }

  Future<void> submit(String period, List<Map<String, dynamic>> rows, {bool nil = false}) async {
    _period(period);
    final employee = await me();
    if (!employee.isOfficer) throw const ApiException('Only officers can submit accounts.', 403);
    if (rows.length > 100) throw const ApiException('Maximum 100 rows per submission.', 400);
    if (nil && rows.isNotEmpty) throw const ApiException('NIL cannot contain real accounts.', 400);
    final docNil = db.collection('performance').doc('${employee.employeeId}_${period}_NIL');
    final newRecords = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final account = '${row['accountNo'] ?? ''}'.trim();
      final key = accountKey(account);
      if (!RegExp(r'^\d{4}906\d{6}$').hasMatch(key) || '${row['applicantName'] ?? ''}'.trim().isEmpty) {
        throw const ApiException('Enter applicant and valid 906 account number.', 400);
      }
      final isPdf = row['source'] == 'pdf';
      newRecords['${employee.employeeId}_${period}_$key'] = {
        'employeeId': employee.employeeId, 'employeeName': employee.name,
        'branch': employee.branch, 'zone': employee.zone,
        'managerId': employee.managerId, 'salesManager': employee.salesManager,
        'reportingPeriod': period, 'year': int.parse(period.substring(0, 4)),
        'month': monthNames[int.parse(period.substring(5)) - 1],
        'applicantName': '${row['applicantName']}'.trim(),
        'accountNo': account, 'normalizedAccountNo': key,
        'limit': '${row['limit'] ?? ''}'.trim(),
        'status': 'confirmed', 'source': isPdf ? 'pdf' : 'manual',
        if (isPdf) ...{
          'slNo': row['slNo'] is int ? row['slNo'] : 0,
          'kpiCategory': '${row['kpiCategory'] ?? 'NEW LOAN ACCOUNT'}',
          'originatingBranch': '${row['originatingBranch'] ?? ''}',
          'periodStart': '${row['periodStart'] ?? ''}',
          'periodEnd': '${row['periodEnd'] ?? ''}',
          'verify': '${row['verify'] ?? ''}',
        },
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
    }
    if (nil) {
      // Query cannot be part of a Firestore transaction. An existing submission
      // check here is advisory; Rules cannot guarantee cross-document NIL
      // invariants without a server or a per-month lock document.
      final existing = await records(employeeId: employee.employeeId, period: period);
      if (existing.any((r) => r.valid)) {
        throw const ApiException('This month already has cards. NIL cannot be submitted.', 409);
      }
    }
    if (nil) {
      await db.runTransaction((t) async {
        final nilOld = await t.get(docNil);
        if (!nilOld.exists) {
          t.set(docNil, {
            'employeeId': employee.employeeId, 'employeeName': employee.name,
            'reportingPeriod': period, 'year': int.parse(period.substring(0, 4)),
            'month': monthNames[int.parse(period.substring(5)) - 1],
            'accountNo': 'N/A', 'normalizedAccountNo': 'NIL',
            'applicantName': '', 'limit': 'NIL', 'status': 'confirmed',
            'branch': employee.branch, 'zone': employee.zone,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
        }
      });
    } else {
      // One immutable account + its public counter update per transaction.
      // The Firestore rules verify both sides using getAfter(), so an officer
      // cannot invent a score without creating an actual 906 record.
      // Sequential imports are retry-safe, including after partial failures.
      final scoreRef = db.collection('leaderboard').doc(employee.employeeId);
      for (final entry in newRecords.entries) {
        final random = Random.secure();
        final proofId = base64UrlEncode(
          List<int>.generate(18, (_) => random.nextInt(256))).replaceAll('=', '');
        final proofRef = db.collection('ranking_proofs').doc(proofId);
        final accountRef = db.collection('performance').doc(entry.key);
        await db.runTransaction((t) async {
          final before = await t.get(accountRef);
          final score = await t.get(scoreRef);
          final oldNil = await t.get(docNil);
          if (before.exists) { return; } // Same period + same account => no duplicate.
          final count = asInt(score.data()?['cards']);
          t.set(accountRef, entry.value);
          t.set(proofRef, {'employeeId': employee.employeeId, 'recordId': entry.key});
          if (oldNil.exists) { t.delete(docNil); }
          t.set(scoreRef, {
            'employeeId': employee.employeeId,
            'cards': count + 1,
            'lastProofId': proofId,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        });
      }
    }
    // Wait for server acknowledgement; don't report success for offline cache.
    await db.waitForPendingWrites();
  }

  Future<void> updateRecord(String id, Map<String, dynamic> changes) async {
    if (!(await me()).isAdmin) {
      throw const ApiException('Submitted reports are read-only for officers.', 403);
    }
    const allowed = {'applicantName', 'accountNo', 'limit'};
    if (changes.keys.any((k) => !allowed.contains(k))) throw const ApiException('Unsupported field.', 400);
    // Keep IDs/account normalization immutable to avoid duplicate cards.
    if (changes.containsKey('accountNo')) throw const ApiException('Account number cannot be changed. Delete then submit a new account.', 400);
    await db.collection('performance').doc(id).update(changes);
  }

  Future<void> deleteRecord(String id) async {
    if (!(await me()).isAdmin) {
      throw const ApiException('Only ADMIN can delete submitted reports.', 403);
    }
    final record = db.collection('performance').doc(id);
    await db.runTransaction((t) async {
      final snap = await t.get(record);
      if (!snap.exists || snap.data()?['status'] == 'deleted') { return; }
      final data = snap.data()!;
      final scoreRef = db.collection('leaderboard').doc('${data['employeeId']}');
      final score = await t.get(scoreRef);
      t.update(record, {'status': 'deleted'});
      if (score.exists && data['accountNo'] != 'N/A') {
        t.update(scoreRef, {'cards': (asInt(score.data()?['cards']) - 1).clamp(0, 999999999),
          'updatedAt': FieldValue.serverTimestamp()});
      }
    });
  }

  Future<List<EmployeeTarget>> targets({String? period}) async {
    final docs = await db.collection('targets').get();
    return docs.docs.map((s) => EmployeeTarget.fromJson(s.data()))
        .where((t) => period == null || t.reportingPeriod == period).toList();
  }

  /// Set once for every calendar month and every future year. Overrides held
  /// in historical targets documents are not deleted, but new dashboards use
  /// these canonical employee defaults consistently.
  Future<void> setTarget(String id, String period, int cards, int yearly) async {
    _period(period);
    if (!(await me()).isAdmin) throw const ApiException('Admin only.', 403);
    if (cards < 0 || yearly < 0) throw const ApiException('Target cannot be negative.', 400);
    await db.collection('employees').doc(id).update({
      'monthlyTarget': cards, 'yearlyTarget': yearly,
    });
    await db.waitForPendingWrites();
  }

  /// Distinct approved officers, including those with zero cards.
  Stream<Map<String, int>> watchRankingCounts() =>
      db.collection('leaderboard').snapshots().map((snapshot) => {
        for (final doc in snapshot.docs) doc.id: asInt(doc.data()['cards']),
      });

  Stream<void> watchHomeChanges() => db.collection('leaderboard')
      .snapshots().map((_) {});

  Future<List<Employee>> pendingApprovals() async {
    if (!(await me()).isAdmin) throw const ApiException('Admin only.', 403);
    // Old Android versions used inconsistent status capitalization.
    // Admin reads all registrations and filters them locally so none disappear.
    final snapshot = await db.collection('employees').get();
    return snapshot.docs
        .where((doc) => (doc.data()['status']?.toString().trim().toLowerCase() ?? '') == 'pending')
        .map((doc) => Employee.fromJson({...doc.data(), 'employeeId': doc.id}))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<void> decideApproval(String id, bool approve, {String role = 'USER'}) async {
    if (!(await me()).isAdmin) throw const ApiException('Admin only.', 403);
    if (!{'USER', 'Sales Manager', 'AGM', 'DGM'}.contains(role)) {
      throw const ApiException('Invalid role.', 400);
    }
    final ref = db.collection('employees').doc(id);
    final snap = await ref.get();
    final data = snap.data();
    if (data == null || '${data['status']}'.trim().toLowerCase() != 'pending') {
      throw const ApiException('Pending registration not found.', 404);
    }
    if (approve && role == 'USER' && '${data['managerId'] ?? ''}'.trim().isEmpty) {
      throw const ApiException('Select an approved Sales Manager before approving an officer.', 400);
    }
    final authUid = '${data['authUid'] ?? ''}';
    if (authUid.isEmpty) throw const ApiException('Linked sign-in identity missing.', 409);
    final status = approve ? 'Approved' : 'Rejected';
    final chosenRole = approve ? role : 'USER';
    final batch = db.batch();
    batch.update(ref, {'role': chosenRole, 'status': status});
    batch.update(db.collection('auth_users').doc(authUid), {'role': chosenRole, 'status': status});
    if (approve && chosenRole == 'Sales Manager') {
      batch.set(db.collection('sales_manager_directory').doc(id), {
        'employeeId': id, 'name': '${data['name'] ?? ''}',
      });
    }
    await batch.commit();
  }

  /// Atomically change BOTH linked role documents, preserving the account's
  /// UID/employee ID and preventing an ADMIN from demoting themselves.
  /// Firestore rules must enforce the same constraints and audit permission.
  Future<void> changeEmployeeRole(String employeeId, String newRole) async {
    if (!{'USER', 'Sales Manager', 'AGM', 'DGM', 'ADMIN'}.contains(newRole)) {
      throw const ApiException('Unsupported role.', 400);
    }
    final currentAdmin = await me();
    if (!currentAdmin.isAdmin) throw const ApiException('Admin only.', 403);
    if (employeeId == currentAdmin.employeeId) {
      throw const ApiException('You cannot change your own ADMIN role.', 400);
    }
    final employeeRef = db.collection('employees').doc(employeeId);
    await db.runTransaction((transaction) async {
      final employeeSnap = await transaction.get(employeeRef);
      final data = employeeSnap.data();
      if (data == null) throw const ApiException('Employee not found.', 404);
      if ('${data['status'] ?? ''}' != 'Approved') {
        throw const ApiException('Approve this employee before changing the role.', 400);
      }
      final uid = '${data['authUid'] ?? ''}';
      if (uid.isEmpty) throw const ApiException('Missing linked UID. Run admin UID repair on a trusted PC; do not guess an ID.', 409);
      final identityRef = db.collection('auth_users').doc(uid);
      final identity = await transaction.get(identityRef);
      final identityData = identity.data();
      if (identityData == null || identityData['employeeId'] != employeeId ||
          identityData['status'] != data['status'] ||
          identityData['role'] != data['role']) {
        throw const ApiException('Employee/Auth role mapping is inconsistent.', 409);
      }
      final oldRole = '${data['role']}';
      if (oldRole == newRole) return;
      transaction.update(employeeRef, {'role': newRole});
      transaction.update(identityRef, {'role': newRole});
      final catalogRef = db.collection('sales_manager_directory').doc(employeeId);
      if (newRole == 'Sales Manager') {
        transaction.set(catalogRef, {'employeeId': employeeId, 'name': '${data['name'] ?? ''}'});
      } else if (oldRole == 'Sales Manager') {
        transaction.delete(catalogRef);
      }
      transaction.set(db.collection('role_change_logs').doc(), {
        'actorUid': auth.currentUser!.uid,
        'targetEmployeeId': employeeId,
        'oldRole': oldRole,
        'newRole': newRole,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Sensitive admin operations must never be implemented by embedding
  /// Firebase Admin SDK service-account credentials in the mobile APK.
  /// Only the active admin can disable an account and enqueue deletion.
  /// A trusted operator completes Firebase Auth deletion from a PC.
  Future<void> requestAccountDeletion(String employeeId) async {
    final operator = await me();
    if (!operator.isAdmin) { throw const ApiException('ADMIN only.', 403); }
    if (operator.employeeId == employeeId) {
      throw const ApiException('An administrator cannot delete their own account.', 400);
    }
    final employeeRef = db.collection('employees').doc(employeeId);
    final snapshot = await employeeRef.get(const GetOptions(source: Source.server));
    final employee = snapshot.data();
    if (employee == null) { throw const ApiException('Employee not found.', 404); }
    final uid = '${employee['authUid'] ?? ''}'.trim();
    if (uid.isEmpty) {
      throw const ApiException('Missing linked UID. Run the verified PC UID repair first.', 409);
    }
    final identityRef = db.collection('auth_users').doc(uid);
    final identity = await identityRef.get(const GetOptions(source: Source.server));
    if (!identity.exists || identity.data()?['employeeId'] != employeeId) {
      throw const ApiException('Conflicting linked identity. Run PC UID repair first.', 409);
    }
    final requestRef = db.collection('account_deletion_requests').doc(employeeId);
    final existing = await requestRef.get(const GetOptions(source: Source.server));
    if (existing.exists) { throw const ApiException('Deletion already requested.', 409); }
    final batch = db.batch();
    batch.update(employeeRef, {'status': 'Disabled'});
    batch.update(identityRef, {'status': 'Disabled'});
    if ('${employee['role'] ?? ''}'.trim().toLowerCase() == 'sales manager') {
      batch.delete(db.collection('sales_manager_directory').doc(employeeId));
    }
    batch.set(requestRef, {
      'employeeId': employeeId, 'authUid': uid,
      'requestedBy': auth.currentUser!.uid,
      'status': 'Pending', 'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// Reset links are possible only for a genuine Firebase Auth sign-in email.
  /// The recovery email stored on an employee profile is not necessarily the
  /// sign-in email, especially for legacy .invalid aliases.
  Future<void> sendAdminPasswordResetEmail(String employeeId) async {
    if (!(await me()).isAdmin) { throw const ApiException('ADMIN only.', 403); }
    final index = await db.collection('login_index').doc(_hash(employeeId)).get();
    final email = '${index.data()?['email'] ?? ''}'.trim().toLowerCase();
    final linkedUid = '${(await db.collection('employees').doc(employeeId).get()).data()?['authUid'] ?? ''}';
    final indexedUid = '${index.data()?['authUid'] ?? ''}';
    if (linkedUid.isEmpty || indexedUid.isEmpty || indexedUid != linkedUid) {
      throw const ApiException('Unlinked/conflicting UID. Run trusted PC UID repair before reset.', 409);
    }
    if (email.isEmpty || email.endsWith('.invalid')) {
      throw const ApiException('This ID uses a private sign-in alias. Use the trusted PC password-reset utility after verifying the employee.', 409);
    }
    await auth.sendPasswordResetEmail(email: email);
  }

  // Old manually published leaderboard docs remain readable during migration.
  Future<Map<String, int>> rankingCounts() async {
    final snapshot = await db.collection('leaderboard').get();
    return {for (final doc in snapshot.docs) doc.id: asInt(doc.data()['cards'])};
  }

  /// Creates a new Auth account in a SECONDARY Firebase app so the current
  /// ADMIN stays signed in. Firebase Auth itself allows public email sign-up;
  /// Firestore rules force all registrations to USER + Pending. Only the
  /// approved admin's separate primary Auth session can assign privileges.
  /// No service account, Cloud Function, or paid Blaze project is required.
  Future<void> createManagement(Map<String, dynamic> payload) async {
    if (!(await me()).isAdmin) throw const ApiException('Admin only.', 403);
    final id = '${payload['employeeId'] ?? ''}'.trim();
    final password = '${payload['password'] ?? ''}';
    final role = '${payload['role'] ?? ''}';
    if (!RegExp(r'^\d{12}$').hasMatch(id) || password.length < 8) {
      throw const ApiException('Enter a 12-digit ID and a password of 8+ characters.', 400);
    }
    if (!{'USER', 'Sales Manager', 'AGM', 'DGM'}.contains(role)) {
      throw const ApiException('Choose a valid employee role.', 400);
    }
    final required = <String>['name', 'mobile', 'email', 'officialNumber', 'branch'];
    if (role == 'USER' || role == 'Sales Manager') required.add('zone');
    if (role == 'USER') required.add('managerId');
    for (final field in required) {
      if ('${payload[field] ?? ''}'.trim().isEmpty) {
        throw ApiException('$field is required for $role.', 400);
      }
    }
    final recoveryEmail = '${payload['email']}'.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(recoveryEmail)) {
      throw const ApiException('Enter a valid recovery email.', 400);
    }
    String managerId = '';
    String managerName = '';
    if (role == 'USER') {
      managerId = '${payload['managerId']}'.trim();
      final found = (await salesManagers()).where((e) => e.employeeId == managerId).toList();
      if (found.isEmpty) throw const ApiException('Choose an approved Sales Manager.', 400);
      managerName = found.single.name;
    }
    final mainApp = Firebase.app();
    FirebaseApp secondary;
    try {
      secondary = Firebase.app('pt_admin_creator');
    } on FirebaseException {
      secondary = await Firebase.initializeApp(
        name: 'pt_admin_creator', options: mainApp.options,
      );
    }
    final secondaryAuth = FirebaseAuth.instanceFor(app: secondary);
    final secondaryDb = FirebaseFirestore.instanceFor(app: secondary);
    // A previous attempt might have left a temporary user in this app.
    await secondaryAuth.signOut();
    User? createdUser;
    bool profileCreated = false;
    try {
      final emailAlias = _alias(id);
      final credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: emailAlias, password: password,
      );
      createdUser = credential.user;
      final uid = createdUser?.uid;
      if (uid == null) throw const ApiException('The account could not be created.', 500);
      final batch = secondaryDb.batch();
      batch.set(secondaryDb.collection('employees').doc(id), {
        'employeeId': id, 'authUid': uid,
        'name': '${payload['name'] ?? ''}'.trim(),
        'mobile': '${payload['mobile'] ?? ''}'.trim(),
        'email': '${payload['email'] ?? ''}'.trim().toLowerCase(),
        'officialNumber': '${payload['officialNumber'] ?? ''}'.trim(),
        'branch': upper('${payload['branch'] ?? ''}'),
        'zone': upper('${payload['zone'] ?? ''}'),
        'salesManager': managerName, 'managerId': managerId,
        'role': 'USER', 'status': 'Pending',
        'monthlyTarget': 0, 'yearlyTarget': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(secondaryDb.collection('auth_users').doc(uid), {
        'employeeId': id, 'role': 'USER', 'status': 'Pending',
      });
      await batch.commit();
      profileCreated = true;
    } on FirebaseAuthException catch (e) {
      throw ApiException(e.message ?? 'Cannot create account.', 400);
    } finally {
      if (!profileCreated && createdUser != null) {
        // Best effort cleanup, since Auth and Firestore have no joint transaction.
        try { await createdUser.delete(); } catch (_) { /* manual admin cleanup */ }
      }
      await secondaryAuth.signOut();
    }
    // The primary ADMIN user alone performs this server-rule-protected batch.
    // If it fails, the new user remains Pending (never elevated).
    await decideApproval(id, true, role: role);
  }

  /// Requires the existing password; protects a temporary password issued
  /// during admin-led account creation without client-side password storage.
  Future<void> changePassword(String currentPassword, String newPassword) async {
    final user = auth.currentUser;
    if (user == null || user.email == null) {
      throw const ApiException('Sign in again to change password.', 401);
    }
    if (newPassword.length < 8) {
      throw const ApiException('New password must have at least 8 characters.', 400);
    }
    await user.reauthenticateWithCredential(EmailAuthProvider.credential(
      email: user.email!, password: currentPassword,
    ));
    await user.updatePassword(newPassword);
  }

  Stream<List<Map<String, dynamic>>> watchOwnAlerts() {
    final id = auth.currentUser == null ? '' : auth.currentUser!.uid;
    // Use current session identity, not arbitrary employeeId provided by caller.
    return db.collection('auth_users').doc(id).snapshots().asyncExpand((identity) {
      final employeeId = '${identity.data()?['employeeId'] ?? ''}';
      if (!RegExp(r'^\d{12}$').hasMatch(employeeId)) {
        return Stream<List<Map<String, dynamic>>>.value([]);
      }
      return db.collection('user_notifications').doc(employeeId)
          .collection('messages').orderBy('createdAt', descending: true)
          .limit(30).snapshots().map((snapshot) => snapshot.docs
            .map((document) => {'id': document.id, ...document.data()}).toList());
    });
  }

  Future<int> alertNotSubmitted(String period) async {
    if (!(await me()).isAdmin) throw const ApiException('ADMIN only.', 403);
    final p = _period(period);
    if (!reminderIsDue(p, DateTime.now())) {
      throw const ApiException('Reminder is available from the 10th of the month following the report period.', 400);
    }
    // Fetch from SERVER, not pending device-local cache, before alert delivery.
    final userDocs = await db.collection('employees')
      .get(const GetOptions(source: Source.server));
    final recordDocs = await db.collection('performance')
      .get(const GetOptions(source: Source.server));
    final eligible = userDocs.docs.where((d) {
      final data = d.data();
      return '${data['role'] ?? ''}'.trim().toUpperCase() == 'USER' &&
        '${data['status'] ?? ''}'.toLowerCase() == 'approved';
    });
    final submitted = recordDocs.docs.where((d) {
      final data = d.data();
      return data['reportingPeriod'] == p &&
        data['status'] != 'deleted' && data['status'] != 'rejected';
    }).map((d) => '${d.data()['employeeId']}').toSet();
    final missing = eligible.where((d) => !submitted.contains(d.id)).toList();
    // Each administrator-confirmed send produces a fresh message. Reusing one
    // document per period made later Alert taps appear successful but delivered
    // nothing new to a device that had already seen the first snapshot.
    var sent = 0;
    for (var offset = 0; offset < missing.length; offset += 400) {
      final chunk = missing.skip(offset).take(400).toList();
      final batch = db.batch();
      for (final employee in chunk) {
        final doc = db.collection('user_notifications').doc(employee.id)
            .collection('messages').doc();
        batch.set(doc, {
          'title': 'Monthly report reminder',
          'body': 'Your $p performance report has not been submitted. Please submit your report.',
          'period': p, 'kind': 'NOT_SUBMITTED',
          'createdAt': FieldValue.serverTimestamp(),
          'sentBy': auth.currentUser!.uid,
        });
      }
      // Count only confirmed committed messages, not attempted writes.
      await batch.commit();
      sent += chunk.length;
    }
    return sent;
  }

  Future<void> auditExport(String type) async {
    // Keep a scoped, append-only activity event without requiring any server.
    await db.collection('export_logs').add({
      'actorUid': _uid, 'type': type, 'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<Map<String, dynamic>>> extractPdf(Uint8List bytes, String filename) async {
    throw const ApiException('PDF KPI text extraction required the old Cloud Function and is not yet available offline. Please submit records manually; no PDF data was uploaded.', 501);
  }
}
