// Pe mobil/desktop cache-uim dalele de hartă pe disc; pe web nu avem sistem de
// fișiere, așa că folosim direct provider-ul de rețea (fără cache offline).
export 'tile_cache_io.dart'
    if (dart.library.js_interop) 'tile_cache_web.dart';
