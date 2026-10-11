import 'package:flutter_test/flutter_test.dart';
import 'package:performance_tracker_flutter/services/pdf_replacement_plan.dart';

void main() {
  test('replaces all periods, overwrites repeated IDs, leaves no old-only report', () {
    final plan = PdfReplacementPlan(
      {'2024-01-old', '2025-02-common', '2026-03-NIL'},
      {'2025-02-common', '2026-07-new'},
    );
    expect(plan.removedIds, {'2024-01-old', '2026-03-NIL'});
    expect(plan.overwrittenIds, {'2025-02-common'});
    expect(plan.insertedIds, {'2026-07-new'});
    expect(plan.resultingCount, 2);
    expect(plan.batchWriteCount, 7);
  });

  test('new import with no old records only creates new plus metadata', () {
    final plan = PdfReplacementPlan({}, {'a', 'b'});
    expect(plan.removedIds, isEmpty);
    expect(plan.insertedIds, {'a', 'b'});
    expect(plan.batchWriteCount, 5);
  });
}
