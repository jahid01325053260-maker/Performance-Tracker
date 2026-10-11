import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Password storage is opt-in. Flutter secure storage uses Android Keystore /
/// Apple Keychain (and equivalent protected stores on desktop).
/// Never put passwords in SharedPreferences, Firestore or analytics events.
class RememberedLogin {
  RememberedLogin({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _idKey = 'pt_remembered_employee_id';
  static const _keepIdKey = 'pt_remember_id_enabled';
  static const _passwordKey = 'pt_remembered_password';
  static const _keepPasswordKey = 'pt_remember_password_enabled';

  Future<SavedLogin> read() async {
    final keepId = await _storage.read(key: _keepIdKey) != 'false';
    final id = keepId ? await _storage.read(key: _idKey) ?? '' : '';
    final keepPassword =
        await _storage.read(key: _keepPasswordKey) == 'true';
    final password = keepPassword
        ? await _storage.read(key: _passwordKey) ?? ''
        : '';
    return SavedLogin(id: id, password: password,
        keepId: keepId, keepPassword: keepPassword);
  }

  Future<void> save({
    required String employeeId,
    required String password,
    required bool keepId,
    required bool keepPassword,
  }) async {
    if (!keepId) {
      await clear();
      return;
    }
    await _storage.write(key: _keepIdKey, value: 'true');
    await _storage.write(key: _idKey, value: employeeId.trim());
    await _storage.write(
        key: _keepPasswordKey, value: keepPassword.toString());
    if (keepPassword) {
      await _storage.write(key: _passwordKey, value: password);
    } else {
      await _storage.delete(key: _passwordKey);
    }
  }

  Future<void> clearPassword() async {
    await _storage.delete(key: _passwordKey);
    await _storage.write(key: _keepPasswordKey, value: 'false');
  }

  Future<void> clear() async {
    await _storage.delete(key: _idKey);
    await _storage.delete(key: _passwordKey);
    await _storage.delete(key: _keepPasswordKey);
    await _storage.write(key: _keepIdKey, value: 'false');
  }
}

class SavedLogin {
  const SavedLogin({
    required this.id,
    required this.password,
    required this.keepId,
    required this.keepPassword,
  });
  final String id;
  final String password;
  final bool keepId;
  final bool keepPassword;
}
