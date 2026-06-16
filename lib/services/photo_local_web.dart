import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

// Varianta web: nu avem fișiere locale, totul merge prin cloud (Storage).
// Metodele sunt no-op, iar afișarea cade pe imaginea din rețea.
class PhotoLocal {
  static bool get supportsLocalFiles => false;

  static Future<String?> persist(XFile picked, String prefix) async => null;

  static Future<void> saveToGallery(String path, String album) async {}

  static bool existsSync(String path) => false;

  static Future<void> delete(String path) async {}

  static Widget? localImage(
    String path, {
    BoxFit? fit,
    double? width,
    double? height,
    Widget Function()? errorPlaceholder,
  }) =>
      null;
}
