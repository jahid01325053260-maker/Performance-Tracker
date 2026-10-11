import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:performance_tracker_flutter/main.dart';

void main() {
  testWidgets('Performance Tracker shows its login screen', (tester) async {
    // The initial screen does not require Firebase or a running API server.
    // Having a real test here also prevents `flutter create` in CI from
    // generating its default counter-app test (which references `MyApp`).
    await tester.pumpWidget(const PerformanceTrackerApp());

    expect(find.text('Performance Tracker'), findsOneWidget);
    expect(find.text('LOGIN'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });
}