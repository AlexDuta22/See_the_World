# Cloud Functions — proxy securizat pentru Gemini

Aceste funcții există ca să **scoată cheia API Gemini din aplicația client**.
Cheia stă exclusiv pe server, ca secret Firebase. Clientul cheamă funcția
`askGemini` autentificat (Firebase Auth), iar funcția vorbește cu Gemini.

## De ce e necesar

`String.fromEnvironment` / `--dart-define` doar ține cheia în afara git-ului —
**nu o face secretă**. Cheia ajunge compilată în binar și e trimisă ca
`?key=...` din telefon. Oricine decompilează APK-ul sau interceptează traficul
o extrage și consumă quota/banii. Proxy-ul rezolvă asta: cheia nu mai părăsește
niciodată serverul.

## Pași de deploy (rulezi o singură dată)

Necesită plan **Blaze** (Cloud Functions nu rulează pe Spark). Există free tier
generos, dar trebuie un card atașat.

```bash
# 1. Firebase CLI (dacă nu e instalat)
npm install -g firebase-tools

# 2. Autentificare
firebase login

# 3. Treci proiectul pe planul Blaze din consolă:
#    https://console.firebase.google.com/project/seetheworld-57efc/usage/details

# 4. Setează cheia Gemini ca secret (NU în cod). Vei lipi cheia la prompt:
firebase functions:secrets:set GEMINI_API_KEY

# 5. Deploy (CLI va activa automat API-urile necesare și va instala dependențele)
firebase deploy --only functions
```

După deploy, funcția e disponibilă în regiunea `europe-west1` și aplicația o
folosește automat — nu mai e nevoie de `GEMINI_API_KEY` în `dart_defines.json`.

## Important: rotește cheia veche

Cheia din `dart_defines.json` a fost (sau a putut fi) compilată în binare deja
distribuite, deci e considerată compromisă. Generează una nouă în
[Google AI Studio](https://aistudio.google.com/app/apikey), folosește-o la pasul
4 de mai sus, apoi **revocă cheia veche**.

## Opțional: Firebase App Check

Pentru a bloca apelurile care nu vin din aplicația ta reală (nu doar
neautentificate), configurează App Check în client și decomentează
`enforceAppCheck: true` din `index.js`.

## Test local (opțional)

```bash
cd functions
npm install
firebase emulators:start --only functions
```
