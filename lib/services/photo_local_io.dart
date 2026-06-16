import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

// Varianta pentru mobil/desktop: ține copia locală a pozei și o pune în galerie.
class PhotoLocal {
  static bool get supportsLocalFiles => true;

  // Copiez poza aleasă în directorul aplicației și întorc calea locală.
  static Future<String?> persist(XFile picked, String prefix) async {
    final dir = await getApplicationDocumentsDirectory();
    final target =
        '${dir.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final file = await File(picked.path).copy(target);
    return file.path;
  }

  // Pun poza și în galeria telefonului, într-un album dedicat. Best-effort.
  static Future<void> saveToGallery(String path, String album) async {
    try {
      if (!await Gal.hasAccess(toAlbum: true)) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) return;
      }
      await Gal.putImage(path, album: album);
    } catch (_) {}
  }

  static bool existsSync(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  static Future<void> delete(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  // Widget cu poza locală, sau null dacă nu există (caller-ul cade pe network).
  static Widget? localImage(
    String path, {
    BoxFit? fit,
    double? width,
    double? height,
    Widget Function()? errorPlaceholder,
  }) {
    final file = File(path);
    if (!file.existsSync()) return null;
    return Image.file(
      file,
      fit: fit,
      width: width,
      height: height,
      errorBuilder: errorPlaceholder == null
          ? null
          : (_, _, _) => errorPlaceholder(),
    );
  }
}
