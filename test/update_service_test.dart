import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:performance_tracker_flutter/services/update_service.dart';

void main() {
  group('UpdateService version comparison', () {
    test('newer semantic version wins', () {
      expect(UpdateService.compareVersions('1.3.0', '1.2.9'), greaterThan(0));
      expect(UpdateService.compareVersions('2.0.0', '1.99.99'), greaterThan(0));
    });

    test('v prefix, build suffix and missing patch are normalized', () {
      expect(UpdateService.compareVersions('v1.2.0', '1.2.0+7'), 0);
      expect(UpdateService.compareVersions('1.2', '1.2.0'), 0);
    });

    test('older release is not offered', () {
      expect(UpdateService.compareVersions('1.1.9', '1.2.0'), lessThan(0));
    });
  });

  test('GitHub release JSON is parsed into update metadata', () {
    final release = AppRelease.fromJson(<String, dynamic>{
      'tag_name': 'v1.3.0',
      'name': 'Performance Tracker 1.3.0',
      'body': 'New ranking and update features',
      'html_url': 'https://github.com/example/repo/releases/tag/v1.3.0',
      'published_at': '2026-10-24T00:00:00Z',
      'assets': <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'app-arm64-v8a-release.apk',
          'browser_download_url': 'https://example.invalid/app.apk',
          'size': 1234,
        },
      ],
    });

    expect(release.version, '1.3.0');
    expect(release.assets.single.name, 'app-arm64-v8a-release.apk');
  });
  test('Windows updater selects the setup EXE from release assets', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final release = AppRelease.fromJson(<String, dynamic>{
      'tag_name': 'V1.3',
      'assets': <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'PerformanceTracker-windows-x64-portable.zip',
          'browser_download_url': 'https://example.invalid/portable.zip',
          'size': 2000,
        },
        <String, dynamic>{
          'name': 'PerformanceTracker-windows-x64-setup.exe',
          'browser_download_url': 'https://example.invalid/setup.exe',
          'size': 3000,
        },
      ],
    });

    final service = UpdateService();
    addTearDown(service.close);
    final asset = service.compatibleWindowsInstaller(release);
    expect(asset?.name, 'PerformanceTracker-windows-x64-setup.exe');
  });
}
