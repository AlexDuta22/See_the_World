import 'package:flutter_map/flutter_map.dart';

// Web: nu avem filesystem, deci nu cache-uim. open() intoarce null, iar pagina
// cade pe provider-ul de retea (harta merge doar cu internet pe web).
class TileCache {
  TileCache(this.baseDir);
  final String baseDir;

  static Future<TileCache?> open() async => null;

  TileProvider tileProvider() => NetworkTileProvider();

  Future<void> downloadRegion({
    required double minLat,
    required double minLng,
    required double maxLat,
    required double maxLng,
    int minZoom = 13,
    int maxZoom = 17,
    void Function(int done, int total)? onProgress,
  }) async {}
}
