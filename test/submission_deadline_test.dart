import 'package:flutter_test/flutter_test.dart';
import 'package:performance_tracker_flutter/core/submission_deadline.dart';

void main() {
  test('deadline for September report is October 10', () {
    expect(submissionDueDate(2026, 9), DateTime(2026, 10, 10));
    expect(reminderIsDue('2026-09', DateTime(2026, 10, 9)), false);
    expect(reminderIsDue('2026-09', DateTime(2026, 10, 10)), true);
  });
  test('December report deadline rolls into next year', () {
    expect(submissionDueDate(2032, 12), DateTime(2033, 1, 10));
    expect(reminderIsDue('2032-12', DateTime(2033, 1, 10)), true);
  });
}
