import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:pdfrx/pdfrx.dart';
import 'core/theme.dart';
import 'services/api.dart';
import 'services/session.dart';
import 'features/auth/login_screen.dart';
import 'features/dashboard/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();
  try {
    await Firebase.initializeApp();
    runApp(const PerformanceTrackerApp());
  } catch (error) {
    runApp(MaterialApp(home: Scaffold(body: Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text('App service initialization failed. Please verify the application setup and try again.\n$error',
          textAlign: TextAlign.center),
    )))));
  }
}
class PerformanceTrackerApp extends StatefulWidget {
  const PerformanceTrackerApp({super.key});
  @override State<PerformanceTrackerApp> createState() => _PerformanceTrackerAppState();
}
class _PerformanceTrackerAppState extends State<PerformanceTrackerApp> {
  late final Session session = Session(ApiClient())..addListener(_changed);
  @override void initState() { super.initState();
    if (Firebase.apps.isNotEmpty) session.restore();
  }
  void _changed() { if(mounted) setState(() {}); }
  @override void dispose() { session.removeListener(_changed); session.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'Performance Tracker', debugShowCheckedModeBanner: false, theme: buildTheme(),
    // Android 15/16 edge-to-edge navigation must never obscure page controls.
    builder: (context, child) => SafeArea(
      top: false, left: false, right: false, bottom: true,
      child: child ?? const SizedBox.shrink(),
    ),
    home: session.busy && !session.loggedIn
      ? const Scaffold(body: Center(child: CircularProgressIndicator()))
      : session.loggedIn ? HomeScreen(session: session) : LoginScreen(session:session),
  );
}
