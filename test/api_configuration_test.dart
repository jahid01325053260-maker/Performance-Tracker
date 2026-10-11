import 'package:flutter_test/flutter_test.dart';
import 'package:performance_tracker_flutter/services/api.dart';

void main() {
  test('Spark API has no external base URL or Cloud Functions dependency', () {
    final api = ApiClient();
    expect(api.isConfigured, isFalse);
    expect(ApiException('Network error', 503).toString(), 'Network error');
  });
}
