# See the World

Aplicatie companion de calatorie construita in Flutter, organizata in trei
module: descoperire locala si rutare, jurnal personal de calatorie si un
asistent conversational care ofera recomandari personalizate pe baza
istoricului utilizatorului. Functioneaza atat online, cat si offline.

Orasul Timisoara este folosit ca proof of concept pentru modulul de descoperire
locala (date despre locuri, tururi, rute). Arhitectura nu este insa legata de un
singur oras si poate fi extinsa la orice locatie.

## Module

### 1. Descoperire locala si rutare (studiu de caz: Timisoara)
- Afiseaza pe harta locuri turistice si detalii (descriere, poza, coordonate).
- Cauta locuri cu Google Places si porneste navigatia pe harta.
- Genereaza rute si afiseaza pasii de navigare pas cu pas.
- Ofera tururi offline (ex. Timisoara City Tour) cand nu exista conexiune.

### 2. Jurnal personal de calatorie
- Salveaza locuri favorite, oriunde in lume.
- Ataseaza "memory photos" locurilor vizitate.
- Profil cu statistici (locuri vizitate, tururi finalizate).

### 3. Asistent conversational personalizat
- Chat (text sau voce) care recomanda destinatii din Romania si Europa.
- Fundamenteaza recomandarile pe favoritele si locurile vizitate de utilizator.
- Cheia Gemini sta exclusiv pe server, intr-o Cloud Function autentificata
  (`askGemini`); clientul nu o contine niciodata.

## Functionalitati transversale
- Login/Register cu email/parola + autentificare Google/Facebook.
- Tema light/dark si preferinte salvate local.

## Tehnologii folosite
- Flutter + Dart
- Firebase Auth, Firestore, Firebase Storage, Cloud Functions
- Google Maps, Google Places, Google Directions API
- Google Gemini (prin proxy securizat pe Cloud Functions)
- Speech-to-Text si Text-to-Speech pentru asistentul vocal
- Geolocator, Flutter Compass
- Shared Preferences pentru stocare locala
- Image Picker + Path Provider pentru fotografii locale

## Structura
- `lib/pages/home_page.dart`: harta, cautare, rute, top places.
- `lib/pages/offline_tours_page.dart`: tururi offline.
- `lib/pages/favorite_places_page.dart`: favorite si detalii.
- `lib/pages/ai_assistant_page.dart`: asistentul conversational.
- `lib/pages/profile_page.dart`: profil si setari.
- `lib/pages/login_page.dart` + `lib/pages/register_page.dart`: autentificare.
- `functions/`: Cloud Function `askGemini` (proxy securizat catre Gemini).
