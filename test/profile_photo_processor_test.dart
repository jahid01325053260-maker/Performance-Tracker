import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:performance_tracker_flutter/services/profile_photo_processor.dart';

void main() {
  test('profile photo is square and compressed to five KB or less', () {
    final source = img.Image(width: 640, height: 420);
    for (var y = 0; y < source.height; y += 1) {
      for (var x = 0; x < source.width; x += 1) {
        source.setPixelRgb(x, y, (x * 17 + y * 3) % 256,
          (x * 7 + y * 11) % 256, (x * 5 + y * 19) % 256);
      }
    }

    final crop = ProfilePhotoProcessor.applyAdjustment(
      source,
      const ProfilePhotoAdjustment(zoom: 1.7, horizontal: .35, vertical: -.25),
    );
    final bytes = ProfilePhotoProcessor.compressToTarget(crop);
    final decoded = img.decodeJpg(bytes);

    expect(bytes.length, lessThanOrEqualTo(ProfilePhotoProcessor.targetBytes));
    expect(decoded, isNotNull);
    expect(decoded!.width, decoded.height);
  });
}
