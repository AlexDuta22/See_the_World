# See the World

Aplicatie Flutter pentru descoperirea atractiilor din Timisoara si planificarea
unor trasee turistice, cu suport online si offline.

## Ce face aplicatia
- Afiseaza pe harta locuri turistice si detalii (descriere, poza, coordonate).
- Cauta locuri cu Google Places si permite pornirea navigatiei pe harta.
- Genereaza rute si afiseaza pasii de navigare.
- Permite salvarea locurilor favorite.
- Salveaza "memory photos" pentru locurile favorite.
- Ofera tururi offline (ex. Timisoara City Tour).
- Are profil de utilizator cu statistici (locuri vizitate, tururi finalizate).
- Login/Register cu email/parola + autentificare Google/Facebook.
- Tema light/dark si preferinte salvate local.

## Tehnologii folosite
- Flutter + Dart
- Firebase Auth, Firestore, Firebase Storage
- Google Maps, Google Places, Google Directions API
- Geolocator, Flutter Compass
- HTTP client pentru apeluri API
- Shared Preferences pentru stocare locala
- Image Picker + Path Provider pentru fotografii locale

## Structura pe scurt
- `lib/pages/home_page.dart`: harta, cautare, rute, top places.
- `lib/pages/offline_tours_page.dart`: tururi offline.
- `lib/pages/favorite_places_page.dart`: favorite si detalii.
- `lib/pages/profile_page.dart`: profil si setari.
- `lib/pages/login_page.dart` + `lib/pages/register_page.dart`: autentificare.
