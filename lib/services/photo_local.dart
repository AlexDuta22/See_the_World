// Pe mobil/desktop lucrăm cu fișiere locale; pe web nu avem sistem de fișiere,
// așa că folosim o implementare "no-op" care lasă totul pe cloud.
export 'photo_local_io.dart'
    if (dart.library.js_interop) 'photo_local_web.dart';
