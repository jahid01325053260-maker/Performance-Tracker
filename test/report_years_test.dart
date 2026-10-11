import 'package:flutter_test/flutter_test.dart';
import 'package:performance_tracker_flutter/core/report_years.dart';

void main() {
  test('Report years include 2032 and remain ordered', () {
    expect(reportYears.first, 2020);
    expect(reportYears.last, 2032);
    expect(reportYears.contains(2027), true);
    expect(reportYears.length, 13);
  });
}
