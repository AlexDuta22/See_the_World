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
const admin = require("firebase-admin");

// Admin SDK pentru contorul de rate limit. Îl inițializăm o singură dată; el
// ocolește regulile Firestore, deci contorul nu are nevoie de firestore.rules.
if (!admin.apps.length) admin.initializeApp();

// Secret gestionat de Firebase/Google Secret Manager. Se setează o singură dată
// din terminal (vezi README), nu apare niciodată în cod sau în repo:
//   firebase functions:secrets:set GEMINI_API_KEY
const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");

const MODEL = "gemini-2.5-flash";
const REGION = "europe-west1";

// Câte întrebări poate trimite un utilizator pe zi. Peste limită refuzăm
// înainte de apelul (costisitor) către Gemini, ca să nu ne consume quota.
const DAILY_LIMIT = 50;

const RESPONSE_SCHEMA = {
  type: "OBJECT",
  properties: {
    answer: {type: "STRING"},
    places: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          name: {type: "STRING"},
          area: {type: "STRING"},
          // optional, doar cand se cere reordonarea unei liste; chatul il ignora
          why: {type: "STRING"},
          // categorie de tip Google Places (museum, park, restaurant...),
          // folosita doar pentru analiza experimentului; chatul o ignora
          category: {type: "STRING"},
        },
        required: ["name"],
      },
    },
  },
  required: ["answer", "places"],
};

const FORMAT_INSTRUCTION =
  " Raspunde strict in format JSON conform schemei. In 'answer' pui raspunsul " +
  "tau COMPLET si detaliat, in aceeasi limba ca utilizatorul, exact ca un " +
  "raspuns normal (intro plus cate o descriere scurta cu activitati pentru " +
  "fiecare recomandare). In 'places' pui locurile concrete, reale si " +
  "localizabile pe care le recomanzi, fiecare cu 'name' si 'area' " +
  "(oras/regiune/tara); 'places' este DOAR o lista suplimentara pentru harta " +
  "si NU inlocuieste descrierile din 'answer'. Daca nu recomanzi locuri anume, " +
  "pune 'places' lista goala. Daca utilizatorul iti da o lista fixa de locuri " +
  "si iti cere sa o reordonezi/clasifici, NU inventa locuri noi: pune in " +
  "'places' exact acele locuri, in ordinea recomandata (cel mai potrivit " +
  "primul), fiecare cu un camp 'why' = un singur rand scurt cu motivul." +
  " Pentru fiecare loc din 'places' include si un camp 'category' = o singura " +
  "categorie de tip Google Places reprezentativa pentru acel loc " +
  "(ex. museum, park, restaurant, church, art_gallery, natural_feature, " +
  "tourist_attraction).";

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

    // 2b. Rate limit zilnic per utilizator. Verificăm și incrementăm contorul
    // ÎNAINTE de apelul către Gemini, ca depășirea limitei să oprească cererea
    // costisitoare. Transaction-ul ține numărătoarea corectă la apeluri paralele.
    const today = new Date().toISOString().slice(0, 10);
    const quotaRef = admin
      .firestore()
      .collection("ai_quota")
      .doc(request.auth.uid);
    await admin.firestore().runTransaction(async (tx) => {
      const snap = await tx.get(quotaRef);
      const data = snap.data() || {};
      const count = data.date === today ? data.count || 0 : 0;
      if (count >= DAILY_LIMIT) {
        throw new HttpsError(
          "resource-exhausted",
          "Ai atins limita zilnică de întrebări pentru asistent. " +
            "Încearcă din nou mâine.",
        );
      }
      tx.set(quotaRef, {date: today, count: count + 1});
    });

    // 3. Apel către Gemini cu cheia care stă pe server (Node 20 are fetch global).
    const url =
      "https://generativelanguage.googleapis.com/v1beta/models/" +
      `${MODEL}:generateContent?key=${GEMINI_API_KEY.value()}`;

    // Cronometrăm DOAR apelul Gemini (fără overhead-ul contorului de mai sus),
    // ca metrica să reflecte latența pură a modelului.
    let response;
    let geminiLatencyMs = null;
    const t0 = Date.now();
    try {
      response = await fetch(url, {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({
          system_instruction: {
            parts: [{text: systemInstruction + FORMAT_INSTRUCTION}],
          },
          contents,
          generationConfig: {
            maxOutputTokens: 2048,
            thinkingConfig: {thinkingBudget: 0},
            responseMimeType: "application/json",
            responseSchema: RESPONSE_SCHEMA,
          },
        }),
      });
      geminiLatencyMs = Date.now() - t0;
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
    const raw = json?.candidates?.[0]?.content?.parts?.[0]?.text;

    if (!raw) {
      logger.error("Răspuns gol de la Gemini", JSON.stringify(json));
      throw new HttpsError("internal", "Răspuns gol de la Gemini.");
    }

    let answer = raw;
    let places = [];
    try {
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed.answer === "string") {
        answer = parsed.answer;
      }
      if (parsed && Array.isArray(parsed.places)) {
        places = parsed.places
          .filter((p) => p && typeof p.name === "string" && p.name.trim())
          .map((p) => ({
            name: p.name.trim(),
            area: typeof p.area === "string" ? p.area.trim() : "",
            why: typeof p.why === "string" ? p.why.trim() : "",
            category: typeof p.category === "string" ? p.category.trim() : "",
          }))
          .slice(0, 8);
      }
    } catch (e) {
      logger.warn("Răspuns Gemini non-JSON, returnez textul brut.");
    }

    // Token-ii vin din usageMetadata-ul Gemini; ii trimitem la client doar
    // pentru logarea experimentului. Daca lipsesc, trimitem null.
    const usage = json.usageMetadata || {};
    return {
      text: answer,
      places,
      promptTokens:
        typeof usage.promptTokenCount === "number" ?
          usage.promptTokenCount :
          null,
      responseTokens:
        typeof usage.candidatesTokenCount === "number" ?
          usage.candidatesTokenCount :
          null,
      geminiLatencyMs,
      model: MODEL,
    };
  },
);
