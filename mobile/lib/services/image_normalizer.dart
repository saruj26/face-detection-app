import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Re-encodes a photo so that its pixels are upright (EXIF orientation baked
/// in), it is at most [maxDimension] pixels on the long side, and optionally
/// mirrored. Face detection, on-screen display and the saved composite then
/// all use exactly the same pixel coordinates.
///
/// The photo is written to the app's temporary directory only; nothing is
/// uploaded. Call [deleteNormalizedPhoto] when done.
Future<File> normalizePhoto(String sourcePath, {bool mirror = false, int maxDimension = 1600}) async {
  final bytes = await File(sourcePath).readAsBytes();
  final out = await compute(_normalize, _NormalizeArgs(bytes, mirror, maxDimension));
  if (out == null) {
    throw const FormatException('This image format is not supported.');
  }
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/tryon_${DateTime.now().microsecondsSinceEpoch}.jpg');
  await file.writeAsBytes(out, flush: true);
  return file;
}

Future<void> deleteNormalizedPhoto(File? file) async {
  if (file == null) return;
  try {
    if (await file.exists()) await file.delete();
  } on FileSystemException {
    // Temporary file; the OS will clean it up eventually.
  }
}

class _NormalizeArgs {
  const _NormalizeArgs(this.bytes, this.mirror, this.maxDimension);
  final Uint8List bytes;
  final bool mirror;
  final int maxDimension;
}

Uint8List? _normalize(_NormalizeArgs args) {
  final decoded = img.decodeImage(args.bytes);
  if (decoded == null) return null;
  var image = img.bakeOrientation(decoded);
  final longSide = image.width > image.height ? image.width : image.height;
  if (longSide > args.maxDimension) {
    image = image.width >= image.height
        ? img.copyResize(image, width: args.maxDimension, interpolation: img.Interpolation.average)
        : img.copyResize(image, height: args.maxDimension, interpolation: img.Interpolation.average);
  }
  if (args.mirror) image = img.flipHorizontal(image);
  return img.encodeJpg(image, quality: 92);
}
