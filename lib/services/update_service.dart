import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
  });

  final String name;
  final String downloadUrl;
  final int size;

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) => ReleaseAsset(
        name: '${json['name'] ?? ''}',
        downloadUrl: '${json['browser_download_url'] ?? ''}',
        size: _asInt(json['size']),
      );
}

class AppRelease {
  const AppRelease({
    required this.tagName,
    required this.version,
    required this.title,
    required this.notes,
    required this.htmlUrl,
    required this.publishedAt,
    required this.assets,
  });

  final String tagName;
  final String version;
  final String title;
  final String notes;
  final String htmlUrl;
  final DateTime? publishedAt;
  final List<ReleaseAsset> assets;

  factory AppRelease.fromJson(Map<String, dynamic> json) {
    final tag = '${json['tag_name'] ?? ''}'.trim();
    final rawAssets = json['assets'];
    return AppRelease(
      tagName: tag,
      version: UpdateService.cleanVersion(tag),
      title: '${json['name'] ?? ''}'.trim(),
      notes: '${json['body'] ?? ''}'.trim(),
      htmlUrl: '${json['html_url'] ?? ''}'.trim(),
      publishedAt: DateTime.tryParse('${json['published_at'] ?? ''}'),
      assets: rawAssets is List
          ? rawAssets
              .whereType<Map>()
              .map((e) => ReleaseAsset.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const <ReleaseAsset>[],
    );
  }
}

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.installedVersion,
    required this.installedBuild,
    required this.repositoryConfigured,
    this.latestRelease,
    this.error,
  });

  final String installedVersion;
  final String installedBuild;
  final bool repositoryConfigured;
  final AppRelease? latestRelease;
  final String? error;

  bool get updateAvailable => latestRelease != null &&
      UpdateService.compareVersions(latestRelease!.version, installedVersion) > 0;
}

class UpdateService {
  UpdateService({http.Client? client, FlutterSecureStorage? storage})
      : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  static const _repository = String.fromEnvironment(
    'UPDATE_GITHUB_REPOSITORY',
    defaultValue: '',
  );
  static const _autoCheckKey = 'pt_auto_check_updates';
  static const _githubAccept = 'application/vnd.github+json';

  final http.Client _client;
  final FlutterSecureStorage _storage;

  String get repository => _repository.trim();
  bool get isRepositoryConfigured => repository.contains('/');

  Future<bool> autoCheckEnabled() async =>
      await _storage.read(key: _autoCheckKey) != 'false';

  Future<void> setAutoCheckEnabled(bool value) =>
      _storage.write(key: _autoCheckKey, value: value.toString());

  Future<PackageInfo> packageInfo() => PackageInfo.fromPlatform();

  Future<UpdateCheckResult> checkForUpdate() async {
    final info = await packageInfo();
    if (!isRepositoryConfigured) {
      return UpdateCheckResult(
        installedVersion: info.version,
        installedBuild: info.buildNumber,
        repositoryConfigured: false,
        error: 'Update source is not configured in this build.',
      );
    }

    try {
      final uri = Uri.https('api.github.com', '/repos/$repository/releases/latest');
      final response = await _client.get(uri, headers: _githubHeaders);
      if (response.statusCode != 200) {
        throw HttpException(
          'GitHub returned HTTP ${response.statusCode}.',
          uri: uri,
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException('Invalid release response.');
      }
      final release = AppRelease.fromJson(Map<String, dynamic>.from(decoded));
      if (release.version.isEmpty) {
        throw const FormatException('Latest release has no valid version tag.');
      }
      return UpdateCheckResult(
        installedVersion: info.version,
        installedBuild: info.buildNumber,
        repositoryConfigured: true,
        latestRelease: release,
      );
    } catch (e) {
      return UpdateCheckResult(
        installedVersion: info.version,
        installedBuild: info.buildNumber,
        repositoryConfigured: true,
        error: '$e',
      );
    }
  }

  Future<List<AppRelease>> releaseHistory({int limit = 20}) async {
    if (!isRepositoryConfigured) return const <AppRelease>[];
    final uri = Uri.https(
      'api.github.com',
      '/repos/$repository/releases',
      <String, String>{'per_page': '$limit'},
    );
    final response = await _client.get(uri, headers: _githubHeaders);
    if (response.statusCode != 200) {
      throw HttpException('GitHub returned HTTP ${response.statusCode}.', uri: uri);
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) throw const FormatException('Invalid release list.');
    return decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => e['draft'] != true && e['prerelease'] != true)
        .map(AppRelease.fromJson)
        .toList(growable: false);
  }

  ReleaseAsset? compatibleAndroidApk(AppRelease release) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    final apks = release.assets
        .where((asset) => asset.name.toLowerCase().endsWith('.apk'))
        .where((asset) => !asset.name.toLowerCase().contains('debug'))
        .toList(growable: false);
    if (apks.isEmpty) return null;

    String needle;
    switch (Abi.current()) {
      case Abi.androidArm64:
        needle = 'arm64-v8a';
        break;
      case Abi.androidArm:
        needle = 'armeabi-v7a';
        break;
      case Abi.androidX64:
        needle = 'x86_64';
        break;
      case Abi.androidIA32:
        needle = 'x86';
        break;
      default:
        needle = '';
        break;
    }
    if (needle.isNotEmpty) {
      for (final asset in apks) {
        if (asset.name.toLowerCase().contains(needle)) return asset;
      }
    }
    for (final asset in apks) {
      final lower = asset.name.toLowerCase();
      if (lower == 'app-release.apk' || lower.contains('universal')) return asset;
    }
    return apks.length == 1 ? apks.single : null;
  }

  Future<String> downloadApk(
    ReleaseAsset asset, {
    required void Function(int received, int total) onProgress,
  }) async {
    final uri = Uri.parse(asset.downloadUrl);
    final request = http.Request('GET', uri)..headers.addAll(_githubHeaders);
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw HttpException('Download failed with HTTP ${response.statusCode}.', uri: uri);
    }

    final baseDir = await _safeDownloadDirectory();
    final safeName = asset.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File('${baseDir.path}${Platform.pathSeparator}$safeName');
    if (await file.exists()) await file.delete();
    final sink = file.openWrite();
    var received = 0;
    final total = response.contentLength ?? asset.size;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (received == 0) throw const FileSystemException('Downloaded APK is empty.');
    return file.path;
  }

  Future<void> installDownloadedApk(String path) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('Direct APK installation is available on Android only.');
    }
    final result = await OpenFilex.open(
      path,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) {
      throw StateError(result.message);
    }
  }

  Future<void> openReleasePage(AppRelease release) async {
    final uri = Uri.tryParse(release.htmlUrl);
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('Could not open the release page.');
    }
  }

  Future<Directory> _safeDownloadDirectory() async {
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        await downloads.create(recursive: true);
        final probe = File('${downloads.path}${Platform.pathSeparator}.pt-write-test');
        await probe.writeAsString('ok', flush: true);
        await probe.delete();
        return downloads;
      }
    } catch (_) {
      // Scoped storage or platform restrictions can reject the public Downloads
      // folder. Falling back to app cache still allows FileProvider installation.
    }
    return getTemporaryDirectory();
  }

  Map<String, String> get _githubHeaders => const <String, String>{
        'Accept': _githubAccept,
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'Performance-Tracker-Updater',
      };

  void close() => _client.close();

  static String cleanVersion(String value) {
    var result = value.trim();
    if (result.toLowerCase().startsWith('v')) result = result.substring(1);
    return result.split('+').first.split('-').first.trim();
  }

  static int compareVersions(String a, String b) {
    final left = _versionParts(cleanVersion(a));
    final right = _versionParts(cleanVersion(b));
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final x = i < left.length ? left[i] : 0;
      final y = i < right.length ? right[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  static List<int> _versionParts(String version) => version
      .split('.')
      .map((part) => int.tryParse(RegExp(r'^\d+').stringMatch(part) ?? '') ?? 0)
      .toList(growable: false);
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}
