"use strict";

// Proxy securizat pentru Gemini.
//
// De ce există acest fișier: cheia API Gemini NU trebuie să ajungă niciodată în
// aplicația client. Dacă o trimitem din telefon (ex. ?key=... prin dart-define),
// oricine decompilează APK-ul sau interceptează traficul o extrage și ne
// consumă quota. Soluția: cheia stă DOAR aici, pe server, ca secret Firebase.
// Clientul cheamă această funcție autentificat, iar funcția vorbește cu Gemini.

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const logger = require("firebase-functions/logger");

// Secret gestionat de Firebase/Google Secret Manager. Se setează o singură dată
// din terminal (vezi README), nu apare niciodată în cod sau în repo:
//   firebase functions:secrets:set GEMINI_API_KEY
const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");

const MODEL = "gemini-2.5-flash";
const REGION = "europe-west1";

exports.askGemini = onCall(
  {
    region: REGION,
    secrets: [GEMINI_API_KEY],
    // Activează enforceAppCheck: true după ce configurezi App Check în client,
    // ca să blochezi apelurile care nu vin din aplicația ta reală.
    // enforceAppCheck: true,
  },
  async (request) => {
    // 1. Doar utilizatori autentificați pot folosi asistentul.
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Trebuie să fii autentificat ca să folosești asistentul.",
      );
    }

    // 2. Validare input.
    const data = request.data || {};
    const systemInstruction =
      typeof data.systemInstruction === "string" ? data.systemInstruction : "";
    const contents = data.contents;
    if (!Array.isArray(contents) || contents.length === 0) {
      throw new HttpsError(
        "invalid-argument",
        "Lipsește istoricul conversației (contents).",
      );
    }

    // 3. Apel către Gemini cu cheia care stă pe server (Node 20 are fetch global).
    const url =
      "https://generativelanguage.googleapis.com/v1beta/models/" +
      `${MODEL}:generateContent?key=${GEMINI_API_KEY.value()}`;

    let response;
    try {
      response = await fetch(url, {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({
          system_instruction: {parts: [{text: systemInstruction}]},
          contents,
          generationConfig: {maxOutputTokens: 1024},
        }),
      });
    } catch (err) {
      logger.error("Eroare de rețea către Gemini", err);
      throw new HttpsError("unavailable", "Nu am putut contacta Gemini.");
    }

    if (!response.ok) {
      const body = await response.text();
      logger.error(`Gemini a răspuns ${response.status}`, body);
      // Nu propagăm corpul brut către client (poate conține detalii interne).
      throw new HttpsError("internal", `Gemini a răspuns ${response.status}.`);
    }

    const json = await response.json();
    const text =
      json &&
      json.candidates &&
      json.candidates[0] &&
      json.candidates[0].content &&
      json.candidates[0].content.parts &&
      json.candidates[0].content.parts[0] &&
      json.candidates[0].content.parts[0].text;

    if (!text) {
      logger.error("Răspuns gol de la Gemini", JSON.stringify(json));
      throw new HttpsError("internal", "Răspuns gol de la Gemini.");
    }

    return {text};
  },
);
