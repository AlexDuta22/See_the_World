# Modul experimental — dovadă pentru studiile de caz

Acest folder păstrează, ca **dovadă pentru lucrare**, codul modului experimental
A/B folosit la studiile de caz. Codul **nu mai face parte din aplicația de
lansare**: a fost scos din `lib/` la 2026-06-23 pentru a livra o variantă curată
(Home fără butoanele Generic/Personalizat, asistent AI mereu personalizat).

Folderul `docs/` este **exclus din analyzer** (`analysis_options.yaml`) și nu se
află sub `lib/` sau `test/`, deci **nu se compilează și nu influențează aplicația**.
Fișierele `.dart` de aici sunt arhivă/referință, nu cod buildabil.

> Implementarea completă, în context, există în istoricul Git la commit-ul
> **`a27e974` — "Add a two-arm context experiment for AI recommendations"**.
> O poți vedea integral cu: `git show a27e974`.

## Designul experimentului

Comparație **împerecheată (A/B), within-subject**, pe două suprafețe:

| Braț | Etichetă UI | Ce primește |
|------|-------------|-------------|
| A | **Generic** (`none`) | doar baseline-ul comun (locația) |
| B | **Personalizat** (`full`) | locație **+ profil de gust + locuri recente** |

Invariant cheie: ambele brațe pornesc din **același pool** și întorc **același
număr** de itemi (N pe hartă, 5 recomandări la asistent). Diferă **DOAR care**
locuri apar și **în ce ordine** — niciodată **câte**. Astfel efectul măsurat e
strict al personalizării, nu al cantității.

Profilul de gust = numărarea tipurilor Google Places din locurile salvate
(favorite) și vizitate, agregate pe cele 6 teme `DiscoverTheme`
(`history / nature / food / architecture / hotels / hiddenGems`) și normalizate.

### Suprafața 1 — Harta (Discover)
- `_fetchExperimentPool` aduce un pool divers pe 10 km (`fetchMixedPool`).
- `selectArm` alege N itemi: A după distanță, B după potrivirea cu profilul
  (`profileMatchScore`), departajat pe distanță; B scoate și locurile vizitate.
- Bara cu segmented `Generic`/`Personalizat`, chip `N=15` și butonul „rulează
  ambele brațe" (pereche A/B cu același `pairId`).

### Suprafața 2 — Asistentul AI
- Același prompt e trimis prin ambele brațe (`_runBothArms`), cu același istoric,
  ca singura diferență să fie contextul injectat (`_contextText(arm)`).
- Se măsoară latența totală, latența Gemini (server), tokenii prompt/răspuns și
  alinierea recomandărilor la profil.

## Fișiere din arhivă

| Fișier | Locația originală | Conținut |
|--------|-------------------|----------|
| `profile_scoring.dart` | `lib/experiment/profile_scoring.dart` | `ContextMode`, `normalizedThemeProfile`, `profileMatchScore`, `selectArm`, `ScoredCandidate` — inima personalizării |
| `ai_logger.dart` | `lib/experiment/ai_logger.dart` | `logRun` (schema uniformă) + `experimentPairId` (hash FNV-1a stabil) |
| `experiment_personalization_test.dart` | `test/experiment_personalization_test.dart` | testul invariantului de selecție pe hartă |
| `home_experiment.dart` | inline în `lib/pages/home_page.dart` | metodele experimentului pe hartă |
| `assistant_experiment.dart` | inline în `lib/pages/ai_assistant_page.dart` | brațele + logarea din asistent |

## Schema datelor logate

**`ai_logs`** (top-level, uniform pentru ambele suprafețe) — scris de `logRun`:
`arm` (`none`/`full`), `surface` (`home`/`assistant`), `uid`, `query`, `items`
(`{id, name, score}`), `itemCount`, `pairId`, `latencyMs`, `promptTokens`,
`responseTokens`, `timestamp`.

**`users/{uid}/ai_logs`** (log bogat, doar asistent) — scris de `_logInteraction`:
în plus `conditionLabel`, `prompt`, `response`, `contextUsed`, `profileCategories`,
`profileThemes`, `signalsCount`, `hasLocation`, `geminiLatencyMs`,
`recommendedCategories`, `recommendedPlaces` (cu tema derivată), `model`.

`pairId` leagă rularea brațului A de B pentru aceeași întrebare+persoană
(comparație împerecheată).

## Pipeline-ul de analiză

Scripturile de export/analiză a log-urilor sunt în **`analysis/`** (rămas în
repo): `analysis/export_ai_logs.py` + `analysis/requirements.txt`. Acolo se
agregă pe braț alinierea, noutatea, latența și costul (tokeni).

## Cum se reactivează (dacă e nevoie)

1. `git checkout a27e974 -- lib/experiment lib/pages/home_page.dart lib/pages/ai_assistant_page.dart`
   (sau cherry-pick selectiv din acest folder).
2. Reactivează regula Firestore pentru `/ai_logs`.
3. Rulează `flutter run` și folosește butoanele Generic/Personalizat și „rulează
   ambele brațe".
