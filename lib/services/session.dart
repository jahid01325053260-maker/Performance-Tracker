import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/entities.dart';
import 'api.dart';

class Session extends ChangeNotifier {
  Session(this.api);
  final ApiClient api;
  Employee? user;
  bool busy = false;
  String? error;
  bool get loggedIn => user != null;

  Future<void> restore() async {
    if (FirebaseAuth.instance.currentUser == null) return;
    busy = true;
    notifyListeners();
    try {
      user = await api.me();
    } catch (e) {
      error = e.toString();
      await FirebaseAuth.instance.signOut();
      user = null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> login(String id, String password) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      user = await api.login(id, password);
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (FirebaseAuth.instance.currentUser == null) return;
    user = await api.me();
    notifyListeners();
  }

  void logout() {
    user = null;
    error = null;
    notifyListeners();
    FirebaseAuth.instance.signOut();
  }
}
