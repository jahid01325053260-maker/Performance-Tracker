import 'dart:io';

void _copy(String from, String to) {
  final source = File(from);
  if (!source.existsSync()) {
    stderr.writeln('Branding source missing: $from');
    exitCode = 2;
    return;
  }
  final target = File(to);
  target.parent.createSync(recursive: true);
  source.copySync(to);
  stdout.writeln('Applied branding: $to');
}

void main(List<String> args) {
  final target = args.isEmpty ? 'all' : args.first.toLowerCase();

  if (target == 'all' || target == 'android') {
    const densities = <String>[
      'mipmap-mdpi',
      'mipmap-hdpi',
      'mipmap-xhdpi',
      'mipmap-xxhdpi',
      'mipmap-xxxhdpi',
    ];
    for (final density in densities) {
      _copy(
        'assets/branding/native/android/$density/ic_launcher.png',
        'android/app/src/main/res/$density/ic_launcher.png',
      );
    }
  }

  if (target == 'all' || target == 'windows') {
    _copy(
      'assets/branding/native/windows/app_icon.ico',
      'windows/runner/resources/app_icon.ico',
    );
  }

  // Linux/macOS builds are intentionally left unchanged here. The product's
  // primary branded distributables are Android APKs and the Windows installer.
}
