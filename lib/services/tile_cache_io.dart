import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

// OSM cere un User-Agent care identifica aplicatia (politica de utilizare).
const String _userAgent =
    'SeeTheWorld/1.0 (licenta PoC; alexandruduta@yahoo.com)';
const String _tileBase = 'https://tile.openstreetmap.org';

// Cache de dale OSM pe disc. Dalele stau sub <docs>/osm_tiles/z/x/y.png.
class TileCache {
  TileCache(this.baseDir);
  final String baseDir;

  static Future<TileCache?> open() async {
    final dir = await getApplicationDocumentsDirectory();
    return TileCache('${dir.path}/osm_tiles');
  }

  File _fileFor(int z, int x, int y) => File('$baseDir/$z/$x/$y.png');

  TileProvider tileProvider() => _CachedTileProvider(this);

  // slippy map tile math
  static int _lonToX(double lon, int z) =>
      ((lon + 180) / 360 * (1 << z)).floor();
  static int _latToY(double lat, int z) {
    final r = lat * pi / 180;
    return ((1 - log(tan(r) + 1 / cos(r)) / pi) / 2 * (1 << z)).floor();
  }

  // Pre-descarca toate dalele care acopera dreptunghiul, pe zoom-urile cerute.
  // Best-effort: o dala care pica e sarita, restul turului ramane utilizabil.
  Future<void> downloadRegion({
    required double minLat,
    required double minLng,
    required double maxLat,
    required double maxLng,
    int minZoom = 13,
    int maxZoom = 17,
    void Function(int done, int total)? onProgress,
  }) async {
    final tiles = <(int, int, int)>[];
    for (var z = minZoom; z <= maxZoom; z++) {
      final x0 = _lonToX(minLng, z), x1 = _lonToX(maxLng, z);
      final y0 = _latToY(maxLat, z), y1 = _latToY(minLat, z); // lat e invers
      for (var x = x0; x <= x1; x++) {
        for (var y = y0; y <= y1; y++) {
          tiles.add((z, x, y));
        }
      }
    }
    var done = 0;
    for (final (z, x, y) in tiles) {
      final f = _fileFor(z, x, y);
      if (!await f.exists()) {
        try {
          final res = await http.get(
            Uri.parse('$_tileBase/$z/$x/$y.png'),
            headers: const {'User-Agent': _userAgent},
          );
          if (res.statusCode == 200) {
            await f.parent.create(recursive: true);
            await f.writeAsBytes(res.bodyBytes);
          }
        } catch (_) {
          // sari peste dala care pica
        }
      }
      onProgress?.call(++done, tiles.length);
    }
  }
}

// Serveste dala din cache daca exista (offline), altfel din retea.
class _CachedTileProvider extends TileProvider {
  _CachedTileProvider(this._cache);
  final TileCache _cache;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final f = _cache._fileFor(coordinates.z, coordinates.x, coordinates.y);
    if (f.existsSync()) return FileImage(f);
    return NetworkImage(
      '$_tileBase/${coordinates.z}/${coordinates.x}/${coordinates.y}.png',
      headers: const {'User-Agent': _userAgent},
    );
  }
}
