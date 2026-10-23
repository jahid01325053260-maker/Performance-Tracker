import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/update_service.dart';
import '../auth/login_screen.dart' show showMessage;

Future<bool> showUpdateAvailableDialog(
  BuildContext context,
  UpdateCheckResult result,
) async {
  final release = result.latestRelease;
  if (release == null || !result.updateAvailable) return false;
  return await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          icon: const CircleAvatar(
            radius: 34,
            backgroundColor: Palette.pale,
            child: Icon(Icons.auto_awesome, size: 34, color: Palette.primary),
          ),
          title: const Text('Update Available', textAlign: TextAlign.center),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'A newer build of Performance Tracker is ready to download & install.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(child: _VersionBox(label: 'Installed', version: result.installedVersion)),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Icon(Icons.arrow_forward, color: Palette.primary),
                    ),
                    Expanded(child: _VersionBox(label: 'Latest', version: release.version, highlight: true)),
                  ],
                ),
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(dialog, true),
                icon: const Icon(Icons.arrow_forward),
                label: const Text('View Update'),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('Later'),
              ),
            ),
          ],
        ),
      ) ??
      false;
}

class UpdatesScreen extends StatefulWidget {
  const UpdatesScreen({super.key, this.initialResult});
  final UpdateCheckResult? initialResult;

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> {
  late final UpdateService service;
  UpdateCheckResult? result;
  bool loading = true;
  bool autoCheck = true;
  String? pageError;

  @override
  void initState() {
    super.initState();
    service = UpdateService();
    result = widget.initialResult;
    _load();
  }

  @override
  void dispose() {
    service.close();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() {
      loading = result == null;
      pageError = null;
    });
    try {
      final enabled = await service.autoCheckEnabled();
      final checked = result ?? await service.checkForUpdate();
      if (!mounted) return;
      setState(() {
        autoCheck = enabled;
        result = checked;
        loading = false;
        pageError = checked.error;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        pageError = '$e';
      });
    }
  }

  Future<void> _refresh() async {
    setState(() {
      loading = true;
      pageError = null;
    });
    final checked = await service.checkForUpdate();
    if (!mounted) return;
    setState(() {
      result = checked;
      loading = false;
      pageError = checked.error;
    });
  }

  Future<void> _downloadAndInstall() async {
    final current = result;
    final release = current?.latestRelease;
    if (current == null || release == null) return;

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      try {
        await service.openReleasePage(release);
      } catch (e) {
        if (mounted) showMessage(context, 'Unable to open release page: $e');
      }
      return;
    }

    final asset = service.compatibleAndroidApk(release);
    if (asset == null) {
      final open = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Compatible APK not found'),
          content: const Text(
            'This release does not contain an APK matching this device architecture. '
            'You can open the GitHub release page and install a compatible file manually.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('CANCEL')),
            FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('OPEN RELEASE')),
          ],
        ),
      );
      if (open == true) {
        try {
          await service.openReleasePage(release);
        } catch (e) {
          if (mounted) showMessage(context, 'Unable to open release page: $e');
        }
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        icon: const CircleAvatar(
          radius: 28,
          backgroundColor: Palette.pale,
          child: Icon(Icons.download_for_offline_outlined, color: Palette.primary, size: 30),
        ),
        title: const Text('Download Update?'),
        content: Text(
          'Performance Tracker v${release.version} is available '
          '(you have v${current.installedVersion}). The APK will be downloaded and the Android installer will open.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Not Now')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Download')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final progress = ValueNotifier<_DownloadState>(const _DownloadState(0, 0));
    var progressDialogOpen = true;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DownloadProgressDialog(version: release.version, progress: progress),
    ));

    try {
      final path = await service.downloadApk(
        asset,
        onProgress: (received, total) {
          progress.value = _DownloadState(received, total);
        },
      );
      if (!mounted) return;
      if (progressDialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        progressDialogOpen = false;
      }
      await service.installDownloadedApk(path);
      if (mounted) {
        showMessage(
          context,
          'Android installer opened. If asked, allow installation from this source. '
          'Do not uninstall the current app; install the new APK over it.',
        );
      }
    } catch (e) {
      if (mounted && progressDialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        progressDialogOpen = false;
      }
      if (mounted) {
        final open = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('Update could not be installed'),
            content: Text('$e\n\nYou can open the release page and download the APK manually.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('CLOSE')),
              FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('OPEN RELEASE')),
            ],
          ),
        );
        if (open == true) {
          try {
            await service.openReleasePage(release);
          } catch (openError) {
            if (mounted) showMessage(context, 'Unable to open release page: $openError');
          }
        }
      }
    } finally {
      progress.dispose();
    }
  }

  Future<void> _compareReleaseNotes() async {
    final current = result;
    final latest = current?.latestRelease;
    if (current == null || latest == null) return;
    try {
      final releases = await service.releaseHistory();
      AppRelease? installed;
      for (final release in releases) {
        if (UpdateService.compareVersions(
              release.version, current.installedVersion) == 0) {
          installed = release;
          break;
        }
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Compare Release Notes'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680, maxHeight: 620),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Installed v${current.installedVersion}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(_releaseText(installed?.notes ??
                      'Release notes for the installed version are not available on GitHub.')),
                  const Divider(height: 32),
                  Text('Latest v${latest.version}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(_releaseText(latest.notes)),
                ],
              ),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('CLOSE'))],
        ),
      );
    } catch (e) {
      if (mounted) showMessage(context, 'Unable to compare release notes: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = result;
    final release = current?.latestRelease;
    final hasUpdate = current?.updateAvailable == true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Updates'),
        actions: [IconButton(onPressed: loading ? null : _refresh, icon: const Icon(Icons.refresh), tooltip: 'Check again')],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (loading && current == null)
              const SizedBox(height: 280, child: Center(child: CircularProgressIndicator()))
            else ...[
              _UpdateHero(
                hasUpdate: hasUpdate,
                latestVersion: release?.version ?? current?.installedVersion ?? '—',
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _InfoCard(
                    icon: Icons.phone_android_outlined,
                    title: 'v${current?.installedVersion ?? '—'}',
                    subtitle: 'Installed',
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: _InfoCard(
                    icon: Icons.cloud_download_outlined,
                    title: 'v${release?.version ?? '—'}',
                    subtitle: release == null ? 'Latest unavailable' : 'Latest Release',
                    highlighted: hasUpdate,
                  )),
                ],
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: release == null ? _refresh : (hasUpdate ? _downloadAndInstall : null),
                icon: Icon(hasUpdate ? Icons.download : Icons.check_circle_outline),
                label: Text(hasUpdate
                    ? (defaultTargetPlatform == TargetPlatform.android
                        ? 'Download & Install v${release!.version}'
                        : 'Open Release v${release!.version}')
                    : release == null
                        ? 'Check For Updates'
                        : 'You Are Up To Date'),
              ),
              if (pageError != null) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      pageError!,
                      style: const TextStyle(color: Palette.red),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const Text("WHAT'S NEW", style: TextStyle(fontWeight: FontWeight.bold, color: Palette.primary)),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Palette.pale,
                            child: Icon(Icons.auto_awesome, color: Palette.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  release == null ? 'No release loaded' : 'v${release.version}',
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  release?.title.isNotEmpty == true ? release!.title : 'Latest Release',
                                  style: const TextStyle(color: Palette.muted),
                                ),
                              ],
                            ),
                          ),
                          if (release?.publishedAt != null)
                            Text(
                              _dateLabel(release!.publishedAt!),
                              style: const TextStyle(color: Palette.muted),
                            ),
                        ],
                      ),
                      const Divider(height: 28),
                      SelectableText(_releaseText(release?.notes ??
                          'Release notes will appear here after the GitHub Release is published.')),
                    ],
                  ),
                ),
              ),
              if (release != null) ...[
                const SizedBox(height: 14),
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Palette.pale,
                      child: Icon(Icons.difference_outlined, color: Palette.primary),
                    ),
                    title: const Text('Compare Release Notes'),
                    subtitle: Text('Compare installed v${current!.installedVersion} with v${release.version}'),
                    trailing: const Icon(Icons.arrow_forward),
                    onTap: _compareReleaseNotes,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const Text('OPTIONS', style: TextStyle(fontWeight: FontWeight.bold, color: Palette.primary)),
              const SizedBox(height: 10),
              Card(
                child: SwitchListTile(
                  secondary: const CircleAvatar(
                    backgroundColor: Palette.pale,
                    child: Icon(Icons.sync, color: Palette.primary),
                  ),
                  title: const Text('Auto Check For Updates'),
                  subtitle: const Text('Automatically check for new releases when the app opens'),
                  value: autoCheck,
                  onChanged: (value) async {
                    setState(() => autoCheck = value);
                    await service.setAutoCheckEnabled(value);
                  },
                ),
              ),
              if (current?.repositoryConfigured == false) ...[
                const SizedBox(height: 14),
                const Text(
                  'Developer setup: build with UPDATE_GITHUB_REPOSITORY=owner/repository. '
                  'The included GitHub release workflow sets this automatically.',
                  style: TextStyle(color: Palette.muted),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _UpdateHero extends StatelessWidget {
  const _UpdateHero({required this.hasUpdate, required this.latestVersion});
  final bool hasUpdate;
  final String latestVersion;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: hasUpdate ? Palette.dark : Palette.primary,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 30,
              backgroundColor: Color(0x33FFFFFF),
              child: Icon(Icons.new_releases_outlined, size: 34, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PERFORMANCE TRACKER', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                  Text(
                    hasUpdate ? 'Update Available!' : 'You’re Up To Date',
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    hasUpdate ? 'Version v$latestVersion is ready to download' : 'Latest version v$latestVersion is installed',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.highlighted = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => Card(
        color: highlighted ? Palette.pale : Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Palette.primary),
              const SizedBox(height: 18),
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Text(subtitle, style: const TextStyle(color: Palette.muted)),
            ],
          ),
        ),
      );
}

class _VersionBox extends StatelessWidget {
  const _VersionBox({required this.label, required this.version, this.highlight = false});
  final String label;
  final String version;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: highlight ? Palette.pale : Palette.background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(color: Palette.muted)),
            Text('v$version', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      );
}

class _DownloadState {
  const _DownloadState(this.received, this.total);
  final int received;
  final int total;

  double? get fraction => total > 0 ? (received / total).clamp(0.0, 1.0).toDouble() : null;
  int? get percent => fraction == null ? null : (fraction! * 100).round();
}

class _DownloadProgressDialog extends StatelessWidget {
  const _DownloadProgressDialog({required this.version, required this.progress});
  final String version;
  final ValueListenable<_DownloadState> progress;

  @override
  Widget build(BuildContext context) => AlertDialog(
        icon: const CircleAvatar(
          radius: 28,
          backgroundColor: Palette.pale,
          child: Icon(Icons.downloading_outlined, color: Palette.primary, size: 30),
        ),
        title: Text('Downloading v$version'),
        content: ValueListenableBuilder<_DownloadState>(
          valueListenable: progress,
          builder: (_, state, __) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: state.fraction),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(state.percent == null ? 'Downloading…' : '${state.percent}%'),
                  const Spacer(),
                  const Text('Installing when ready…', style: TextStyle(color: Palette.muted)),
                ],
              ),
            ],
          ),
        ),
      );
}

String _dateLabel(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _releaseText(String text) {
  if (text.trim().isEmpty) return 'No release notes were provided for this version.';
  return text
      .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
      .replaceAll(RegExp(r'\[([^\]]+)\]\([^\)]+\)'), r'$1')
      .replaceAll('**', '')
      .replaceAll('__', '')
      .trim();
}
