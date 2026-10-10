import 'dart:typed_data';

import 'package:gal/gal.dart';

enum SaveImageResult { saved, permissionDenied, notEnoughSpace, failed }

/// Saves PNG bytes to the device gallery / Photos, asking for permission first.
class GalleryService {
  static const album = 'Glasses Try-On';

  Future<SaveImageResult> savePng(Uint8List pngBytes) async {
    try {
      var hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        hasAccess = await Gal.requestAccess(toAlbum: true);
      }
      if (!hasAccess) return SaveImageResult.permissionDenied;

      await Gal.putImageBytes(
        pngBytes,
        album: album,
        name: 'tryon_${DateTime.now().millisecondsSinceEpoch}',
      );
      return SaveImageResult.saved;
    } on GalException catch (e) {
      // Unknown future exception types fall through to `failed`.
      if (e.type == GalExceptionType.accessDenied) return SaveImageResult.permissionDenied;
      if (e.type == GalExceptionType.notEnoughSpace) return SaveImageResult.notEnoughSpace;
      return SaveImageResult.failed;
    }
  }
}
