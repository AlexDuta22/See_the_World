# 🌍 See the World

Aplicație de călătorie făcută în **Flutter**, pentru **Android**. Combină descoperirea de locuri pe hartă, un jurnal de călătorie personal și un asistent AI care oferă recomandări — totul funcționând atât **online**, cât și **offline**.

Exemplul folosit pentru partea de descoperire este orașul **Timișoara** (locuri, tururi, rute), dar codul nu este legat de un oraș anume și poate fi folosit oriunde.

---

## 📑 Cuprins

- [Ce face aplicația](#-ce-face-aplicația)
- [Tehnologii folosite](#-tehnologii-folosite)
- [Structura proiectului](#-structura-proiectului)
- [Configurare și rulare](#-configurare-și-rulare)
- [Build APK și instalare](#-build-apk-și-instalare)
- [Asistentul AI (Cloud Function)](#-asistentul-ai-cloud-function)
- [Teste](#-teste)

---

## ✨ Ce face aplicația

### 🗺️ Descoperire și rute
- Hartă cu locuri de vizitat, fiecare cu descriere, poză și coordonate
- Căutare prin **Google Places**
- Navigație pas cu pas
- Tururi offline (ex. *Timișoara City Tour*) pentru momentele fără internet

### 📔 Jurnal de călătorie
- Locuri favorite
- Poze atașate locurilor vizitate ("memory photos")
- Profil personal cu statistici

### 🤖 Asistent cu recomandări
- Chat scris **sau vocal**
- Recomandări bazate pe favorite și pe locurile deja vizitate
- Cheia Gemini **nu stă în aplicație**, ci pe server, într-o Cloud Function (`askGemini`) — astfel nu poate fi extrasă din client

### 🔧 În plus, peste tot
- Login cu email/parolă sau Google/Facebook
- Temă light/dark
- Preferințe salvate local

---

## 🛠️ Tehnologii folosite

| Categorie | Tehnologii |
|---|---|
| Framework | Flutter + Dart |
| Backend | Firebase (Auth, Firestore, Storage, Cloud Functions) |
| Hărți & locații | Google Maps, Places API, Directions API |
| AI | Google Gemini (apelat de pe server, prin Cloud Function) |
| Voce | Speech-to-Text și Text-to-Speech |
| Offline | Geolocator, Flutter Compass, flutter_map + OpenStreetMap |

---

## 📁 Structura proiectului

```
lib/
  components/   widget-uri refolosite (buton, câmp text, buton social)
  pages/        ecranele app-ului (home, login, register, profil, favorite,
                tururi offline, asistent AI)
  services/     logica și integrările (Discover, profil de gust, cache de dale,
                poze locale, teme, preferințe)
  widgets/      bara de navigație și dialogurile comune
functions/      Cloud Function askGemini (vorbește ea cu Gemini)
test/           teste pentru ranking, profil de gust și componente
```

---

## ⚙️ Configurare și rulare

### De ce ai nevoie

- **Flutter SDK** (canal stable) — verifici cu `flutter doctor`
- Aplicația e făcută pentru **Android**: `lib/firebase_options.dart` și `android/app/google-services.json` sunt incluse și reale pentru Android. Pentru iOS/web ar mai trebui completată configurația Firebase pentru platformele respective.
- O cheie **Google Cloud** cu: Maps SDK for Android, Places API, Geocoding API, Directions API

### Cheile (nu sunt în git)

Cheile se pun în două locuri:

- **`google_maps_api.xml`** — obligatoriu, de acolo își ia harta nativă cheia
- **`dart_defines.json`** — pentru apelurile din cod (Places, Geocoding, Directions), folosit de configurațiile din `.vscode/launch.json`; dacă lipsește, apelurile astea cad tot pe cheia nativă

**`android/app/src/main/res/values/google_maps_api.xml`:**

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="google_maps_api_key">CHEIA_TA</string>
    <string name="google_directions_api_key">CHEIA_TA</string>
    <string name="google_places_api_key">CHEIA_TA</string>
</resources>
```

**`dart_defines.json`** (în rădăcina proiectului, fără cheia Gemini — aia stă pe server):

```json
{
  "GOOGLE_MAPS_API_KEY": "...",
  "GOOGLE_DIRECTIONS_API_KEY": "...",
  "GOOGLE_PLACES_API_KEY": "..."
}
```

### Rulare

```bash
flutter pub get
flutter run --dart-define-from-file=dart_defines.json
```

---

## 📦 Build APK și instalare

Build de release (semnat cu cheia de debug, deci se instalează direct — vezi `android/app/build.gradle.kts`):

```bash
flutter build apk --release --dart-define-from-file=dart_defines.json
```

APK-ul iese în `build/app/outputs/flutter-apk/app-release.apk`. Îl instalezi pe un telefon sau emulator Android conectat:

```bash
flutter install
# sau direct:
adb install build/app/outputs/flutter-apk/app-release.apk
```

Apoi deschizi aplicația din iconiță. Sau, alternativ:

```bash
flutter run --release
```

care face build, instalare și pornire dintr-o dată.

---

## 🧠 Asistentul AI (Cloud Function)

Cheia Gemini stă doar pe server, ca secret Firebase, niciodată în client. Se pune o singură dată și are nevoie de planul **Blaze**:

```bash
npm install -g firebase-tools
firebase login
firebase functions:secrets:set GEMINI_API_KEY
firebase deploy --only functions
```

Funcția `askGemini` rulează în regiunea `europe-west1`.

> Pași mai detaliați (activare Blaze, schimbarea cheii vechi, emulator local) sunt în [`functions/README.md`](functions/README.md).

---

## ✅ Teste

```bash
flutter test
```

Testele acoperă:
- ranking-ul din Discover
- înclinarea recomandărilor după profilul de gust
- componenta de buton principal
