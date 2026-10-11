import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';

import 'api.dart';

/// Spark-compatible local JSON export. Does NOT export Firebase Authentication
/// passwords, login-index lookup documents or deleted Auth identities.
/// Do not upload the resulting file to a public repository.
class BackupService {
  BackupService(this.api);
  final ApiClient api;

  static const collections = <String>[
    'employees', 'auth_users', 'performance', 'targets', 'leaderboard',
  ];
  static const reportingCollections = <String>[
    'performance', 'targets', 'leaderboard',
  ];

  Future<void> _ensureAdmin() async {
    if (!(await api.me()).isAdmin) {
      throw const ApiException('Administrator access required.', 403);
    }
  }

  static Object? _jsonSafe(Object? value) {
    if (value is Timestamp) {
      return {'__type': 'firestore_timestamp', 'seconds': value.seconds,
        'nanoseconds': value.nanoseconds};
    }
    if (value is GeoPoint) {
      return {'__type': 'firestore_geopoint', 'latitude': value.latitude,
        'longitude': value.longitude};
    }
    if (value is DocumentReference) {
      return {'__type': 'firestore_reference', 'path': value.path};
    }
    if (value is Map) {
      return value.map<String, Object?>((key, entry) =>
          MapEntry(key.toString(), _jsonSafe(entry)));
    }
    if (value is Iterable) return value.map(_jsonSafe).toList();
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    return value.toString();
  }

  /// Read snapshots from the SERVER to avoid accidentally calling local stale
  /// cached data a complete backup. Firestore charges these document reads.
  Future<Map<String, dynamic>> createBackupData() async {
    await _ensureAdmin();
    final data = <String, dynamic>{};
    final counts = <String, int>{};
    for (final collectionName in collections) {
      final documents = await api.db.collection(collectionName)
          .get(const GetOptions(source: Source.server));
      final entries = <Map<String, dynamic>>[];
      for (final document in documents.docs) {
        entries.add({'_doc_id': document.id, 'data': _jsonSafe(document.data())});
      }
      data[collectionName] = entries;
      counts[collectionName] = entries.length;
    }
    return {
      'format': 'PerformanceTracker_Spark_JSON_v1',
      'generatedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'exportedByUid': api.auth.currentUser?.uid,
      'counts': counts,
      'collections': data,
      'notes': 'Contains private employee and applicant data. No passwords or sign-in accounts. '
          'Keep this file encrypted/private. Restore requires administrator review.',
    };
  }

  /// Returns null when user cancels Save As. Callers must not treat cancel as
  /// a saved backup or unlock Reset.
  Future<Uri?> saveBackup(Map<String, dynamic> data) async {
    final stamp = DateTime.now().toUtc().toIso8601String()
        .replaceAll(RegExp(r'[^0-9]'), '');
    final bytes = Uint8List.fromList(utf8.encode(
      const JsonEncoder.withIndent('  ').convert(data),
    ));
    return FilePicker.saveFile(
      dialogTitle: 'Save private Performance Tracker backup',
      fileName: 'PerformanceTracker_Backup_$stamp.json',
      bytes: bytes,
    );
  }

  Future<Map<String, int>> countReportingDocuments() async {
    await _ensureAdmin();
    final counts = <String, int>{};
    for (final name in reportingCollections) {
      final results = await api.db.collection(name)
          .count().get(source: AggregateSource.server);
      counts[name] = results.count ?? 0;
    }
    return counts;
  }

  /// Intentionally limited to reporting data. Firebase Auth, identities and
  /// employee profiles must NEVER be mass-deleted from a public Spark client.
  /// A failed batch may leave partial progress; an exported backup is required.
  Future<int> resetReportingData() async {
    await _ensureAdmin();
    var deleted = 0;
    for (final collectionName in reportingCollections) {
      while (true) {
        final docs = await api.db.collection(collectionName).limit(300)
            .get(const GetOptions(source: Source.server));
        if (docs.docs.isEmpty) break;
        final batch = api.db.batch();
        for (final doc in docs.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        deleted += docs.docs.length;
      }
    }
    try {
      await api.auditExport('ADMIN_RESET_REPORTING_DATA');
    } catch (_) {
      // Reporting documents have already been deleted: never claim the
      // destructive operation failed solely because its log write failed.
    }
    return deleted;
  }
}

/// A validated, NON-DESTRUCTIVE import plan for reporting collections only.
/// Employee identities, Auth users and login indexes are never restored by an
/// Android client. Existing documents are skipped rather than overwritten.
class ReportingRestorePlan {
  const ReportingRestorePlan(this.documents);
  final Map<String, Map<String, Map<String, dynamic>>> documents;
  int get count => documents.values.fold(0, (total, collection) => total + collection.length);
  Map<String, int> get collectionCounts =>
      {for (final e in documents.entries) e.key: e.value.length};
}

extension ReportingJsonRestore on BackupService {
  Future<ReportingRestorePlan?> chooseJsonFile() async {
    await _ensureAdminForRestore();
    final picked = await FilePicker.pickFiles(
      type: FileType.custom, allowedExtensions: ['json'],
    );
    if (picked.isEmpty) { return null; }
    final file = picked.single;
    if (await file.length() > 25 * 1024 * 1024) {
      throw const FormatException('JSON backup exceeds 25 MB. Use a trusted PC restore.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > 25 * 1024 * 1024) {
      throw const FormatException('JSON backup exceeds 25 MB.');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map ||
        decoded['format'] != 'PerformanceTracker_Spark_JSON_v1' ||
        decoded['collections'] is! Map) {
      throw const FormatException('Not a supported PerformanceTracker JSON backup.');
    }
    final collections = decoded['collections'] as Map;
    const allowed = ['performance', 'targets', 'leaderboard'];
    final plan = <String, Map<String, Map<String, dynamic>>>{};
    for (final name in allowed) {
      final rows = collections[name];
      if (rows is! List) {
        throw FormatException('Backup is missing reporting collection: $name');
      }
      final documents = <String, Map<String, dynamic>>{};
      for (final entry in rows) {
        if (entry is! Map || entry['_doc_id'] is! String ||
            entry['data'] is! Map) {
          throw FormatException('Invalid $name document in backup.');
        }
        final id = entry['_doc_id'] as String;
        if (id.isEmpty || id.contains('/') || id == '.' || id == '..' ||
            documents.containsKey(id)) {
          throw FormatException('Invalid or duplicated $name document ID.');
        }
        final value = Map<String, dynamic>.from(entry['data'] as Map);
        if (!_restoreValidRow(name, id, value)) {
          throw FormatException('Unsupported legacy $name document: $id. '
              'No data has been uploaded. Migrate old schemas on a trusted PC.');
        }
        documents[id] = _decodeRestoreValues(value);
      }
      plan[name] = documents;
    }
    final result = ReportingRestorePlan(plan);
    if (result.count > 10000) {
      throw const FormatException('Over 10,000 documents; use a trusted PC restore.');
    }
    return result;
  }

  Future<void> _ensureAdminForRestore() async {
    if (!(await api.me()).isAdmin) {
      throw const ApiException('ADMIN access required.', 403);
    }
  }

  bool _restoreValidRow(String collection, String id, Map<String, dynamic> row) {
    if (collection == 'performance') {
      final employeeId = '${row['employeeId'] ?? ''}';
      final period = '${row['reportingPeriod'] ?? ''}';
      final account = '${row['accountNo'] ?? ''}';
      final limit = '${row['limit'] ?? ''}';
      return RegExp(r'^\d{12}$').hasMatch(employeeId) &&
          RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(period) &&
          ['confirmed', 'deleted'].contains(row['status']) &&
          (limit == 'NIL' || RegExp(r'^\d{4}-?906-?\d{6}$').hasMatch(account));
    }
    if (collection == 'targets') {
      final employeeId = '${row['employeeId'] ?? ''}';
      final period = '${row['reportingPeriod'] ?? ''}';
      return RegExp(r'^\d{12}$').hasMatch(employeeId) &&
          RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(period) &&
          id == '${employeeId}_$period' &&
          row['targetCards'] is int && (row['targetCards'] as int) >= 0 &&
          row['yearlyTargetCards'] is int &&
          (row['yearlyTargetCards'] as int) >= 0;
    }
    final count = row['cards'];
    return RegExp(r'^\d{12}$').hasMatch(id) &&
        row['employeeId'] == id && count is int && count >= 0;
  }

  Map<String, dynamic> _decodeRestoreValues(Map<String, dynamic> input) {
    Object? decode(Object? value) {
      if (value is List) { return value.map(decode).toList(); }
      if (value is Map) {
        if (value['__type'] == 'firestore_timestamp') {
          return Timestamp(value['seconds'] as int, value['nanoseconds'] as int);
        }
        if (value['__type'] == 'firestore_geopoint') {
          return GeoPoint((value['latitude'] as num).toDouble(),
              (value['longitude'] as num).toDouble());
        }
        // Do not reconstruct arbitrary Firestore paths from untrusted JSON.
        if (value.containsKey('__type')) {
          throw const FormatException('Unsupported backup value type.');
        }
        return value.map<String, dynamic>((key, child) =>
            MapEntry(key.toString(), decode(child)));
      }
      return value;
    }
    return Map<String, dynamic>.from(decode(input) as Map);
  }

  /// Restore only absent report/target/leaderboard docs. Does not delete or
  /// overwrite any existing data. A disconnect can leave partial progress;
  /// the same backup can be safely retried. Firestore rules enforce ADMIN.
  Future<({int restored, int skipped})> restoreMissing(
      ReportingRestorePlan plan) async {
    await _ensureAdminForRestore();
    var restored = 0;
    var skipped = 0;
    // Commit each document only after confirming absence on server.
    // This is intentionally conservative for a destructive-data recovery tool.
    for (final group in plan.documents.entries) {
      for (final entry in group.value.entries) {
        final reference = api.db.collection(group.key).doc(entry.key);
        final written = await api.db.runTransaction((transaction) async {
          final existing = await transaction.get(reference);
          if (existing.exists) { return false; }
          transaction.set(reference, entry.value);
          return true;
        });
        if (written) {
          restored++;
        } else {
          skipped++;
        }
      }
    }
    await api.db.waitForPendingWrites();
    try {
      await api.auditExport('ADMIN_JSON_RESTORE');
    } catch (_) {
      // Do not misreport an otherwise successful restore due to audit transport.
    }
    return (restored: restored, skipped: skipped);
  }
}
