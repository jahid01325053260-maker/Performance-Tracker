import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../core/theme.dart';
import '../../services/profile_photo_processor.dart';

class ProfilePhotoAdjustScreen extends StatefulWidget {
  const ProfilePhotoAdjustScreen({super.key, required this.source});

  final img.Image source;

  @override
  State<ProfilePhotoAdjustScreen> createState() => _ProfilePhotoAdjustScreenState();
}

class _ProfilePhotoAdjustScreenState extends State<ProfilePhotoAdjustScreen> {
  late final img.Image _previewSource;
  double _zoom = 1;
  double _horizontal = 0;
  double _vertical = 0;
  int _quarterTurns = 0;
  late Uint8List _previewBytes;

  ProfilePhotoAdjustment get _adjustment => ProfilePhotoAdjustment(
        zoom: _zoom,
        horizontal: _horizontal,
        vertical: _vertical,
        quarterTurns: _quarterTurns,
      );

  @override
  void initState() {
    super.initState();
    _previewSource = ProfilePhotoProcessor.createPreviewSource(widget.source);
    _renderPreview();
  }

  void _renderPreview() {
    _previewBytes = ProfilePhotoProcessor.previewBytes(
      _previewSource,
      _adjustment,
    );
  }

  void _change(VoidCallback update) {
    setState(() {
      update();
      _renderPreview();
    });
  }

  void _reset() {
    _change(() {
      _zoom = 1;
      _horizontal = 0;
      _vertical = 0;
      _quarterTurns = 0;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Adjust Profile Photo'),
          actions: [
            TextButton(onPressed: _reset, child: const Text('Reset')),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Adjust the square crop before upload',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Palette.muted),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 430),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Palette.pale,
                              border: Border.all(color: Palette.primary.withValues(alpha: .25)),
                            ),
                            child: Image.memory(
                              _previewBytes,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _slider(
                    label: 'Zoom',
                    value: _zoom,
                    min: 1,
                    max: 4,
                    onChanged: (value) => _change(() => _zoom = value),
                  ),
                  _slider(
                    label: 'Move left / right',
                    value: _horizontal,
                    min: -1,
                    max: 1,
                    onChanged: (value) => _change(() => _horizontal = value),
                  ),
                  _slider(
                    label: 'Move up / down',
                    value: _vertical,
                    min: -1,
                    max: 1,
                    onChanged: (value) => _change(() => _vertical = value),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _change(() => _quarterTurns = (_quarterTurns + 3) % 4),
                        icon: const Icon(Icons.rotate_left),
                        label: const Text('Rotate Left'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _change(() => _quarterTurns = (_quarterTurns + 1) % 4),
                        icon: const Icon(Icons.rotate_right),
                        label: const Text('Rotate Right'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('CANCEL'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(context, _adjustment),
                          icon: const Icon(Icons.check),
                          label: const Text('USE PHOTO'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Slider(value: value, min: min, max: max, onChanged: onChanged),
        ],
      );
}
