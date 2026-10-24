import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class ProfilePhotoAdjustment {
  const ProfilePhotoAdjustment({
    this.zoom = 1,
    this.horizontal = 0,
    this.vertical = 0,
    this.quarterTurns = 0,
  });

  final double zoom;
  final double horizontal;
  final double vertical;
  final int quarterTurns;
}

class ProfilePhotoProcessor {
  static const int targetBytes = 5 * 1024;

  static img.Image applyAdjustment(
    img.Image source,
    ProfilePhotoAdjustment adjustment,
  ) {
    var working = source;
    final turns = adjustment.quarterTurns % 4;
    if (turns != 0) {
      working = img.copyRotate(working, angle: turns * 90);
    }

    final minSide = math.min(working.width, working.height);
    final zoom = adjustment.zoom.clamp(1.0, 4.0);
    final cropSide = (minSide / zoom).round().clamp(32, minSide).toInt();
    final maxX = math.max(0, working.width - cropSide);
    final maxY = math.max(0, working.height - cropSide);
    final horizontal = adjustment.horizontal.clamp(-1.0, 1.0);
    final vertical = adjustment.vertical.clamp(-1.0, 1.0);
    final x = ((horizontal + 1) * maxX / 2).round().clamp(0, maxX).toInt();
    final y = ((vertical + 1) * maxY / 2).round().clamp(0, maxY).toInt();

    return img.copyCrop(
      working,
      x: x,
      y: y,
      width: cropSide,
      height: cropSide,
    );
  }

  static Uint8List previewBytes(
    img.Image source,
    ProfilePhotoAdjustment adjustment, {
    int size = 360,
  }) {
    final cropped = applyAdjustment(source, adjustment);
    final resized = img.copyResize(cropped, width: size, height: size);
    return Uint8List.fromList(img.encodeJpg(resized, quality: 82));
  }

  /// Returns the highest practical JPEG quality that fits within [maxBytes].
  /// The dimensions are reduced only when lowering JPEG quality is not enough.
  static Uint8List compressToTarget(
    img.Image squareImage, {
    int maxBytes = targetBytes,
  }) {
    if (maxBytes < 1024) {
      throw ArgumentError.value(maxBytes, 'maxBytes', 'Must be at least 1 KB');
    }

    const dimensions = <int>[256, 224, 192, 176, 160, 144, 128, 112, 96, 80, 64, 48, 32];
    Uint8List? smallest;

    for (final dimension in dimensions) {
      final resized = img.copyResize(
        squareImage,
        width: dimension,
        height: dimension,
      );

      var low = 5;
      var high = 90;
      Uint8List? bestAtThisSize;
      while (low <= high) {
        final quality = (low + high) ~/ 2;
        final candidate = Uint8List.fromList(
          img.encodeJpg(resized, quality: quality),
        );
        if (smallest == null || candidate.length < smallest.length) {
          smallest = candidate;
        }
        if (candidate.length <= maxBytes) {
          bestAtThisSize = candidate;
          low = quality + 1;
        } else {
          high = quality - 1;
        }
      }

      if (bestAtThisSize != null) {
        return bestAtThisSize;
      }
    }

    if (smallest != null && smallest.length <= maxBytes) {
      return smallest;
    }
    throw const FormatException('Could not compress profile photo to 5 KB.');
  }

  static img.Image createPreviewSource(img.Image source, {int maxDimension = 900}) {
    final largest = math.max(source.width, source.height);
    if (largest <= maxDimension) {
      return source;
    }
    final scale = maxDimension / largest;
    return img.copyResize(
      source,
      width: math.max(1, (source.width * scale).round()).toInt(),
      height: math.max(1, (source.height * scale).round()).toInt(),
    );
  }
}
