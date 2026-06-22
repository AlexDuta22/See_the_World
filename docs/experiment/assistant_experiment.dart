// ARHIVĂ — dovadă a modului experimental pentru ASISTENTUL AI (studiile de caz).
// NU face parte din aplicație și NU se compilează (docs/ e exclus din analyzer).
// Codul trăia inline în lib/pages/ai_assistant_page.dart. Snippet de referință
// (folosește starea privată din _AiAssistantPageState). Vezi README.md și
// commit-ul a27e974 pentru implementarea completă în context.

// Cele 2 brațe ale experimentului. Butonul comută între ele. Ambele au locația;
// none = fără context personal, full = cu profil de gusturi + locuri recente.
enum _ContextMode { none, full }

// Brațul curent (în _AiAssistantPageState): _ContextMode _contextMode = _ContextMode.full;
// Modelul logat (sincron cu functions/index.js): const _geminiModel = 'gemini-2.5-flash';

// ---- Construirea contextului în funcție de braț -----------------------------
// (varianta cu braț: none → doar locația, full → locație + gusturi + recente)

String _contextText(_UserSignals s, _ContextMode arm) {
  final full = arm == _ContextMode.full;
  final themes = full
      ? _profileThemes(s)
      : const <MapEntry<DiscoverTheme, double>>[];
  final hasTaste = themes.isNotEmpty;
  final hasRecent = full && s.recentNames.isNotEmpty;
  // ... construiește buffer-ul: locație (ambele brațe) + profil de gust + locuri
  //     recente (doar full). Identic ca text de bază pe ambele brațe; diferă DOAR
  //     ce semnale se injectează.
  return /* buffer.toString() */ '';
}

// ---- Apelul Gemini cu măsurători (latență + tokeni) -------------------------

Future<_GeminiResult> _callGemini(_ContextMode arm) async {
  // Construim contextul ÎNAINTE de cronometru: vrem ca latencyMs să măsoare
  // doar apelul către funcție/Gemini, nu și citirile din Firestore/locație.
  // Semnalele se colectează mereu (pentru logare); doar injectarea ține de braț.
  final signals = await _collectSignals();
  final contextUsed = _contextText(signals, arm);
  final stopwatch = Stopwatch();
  // ... construiește systemInstruction + contents, apoi:
  stopwatch.start();
  // final response = await callable.call(...);
  stopwatch.stop();
  // final promptTokens = _asInt(response.data['promptTokens']);
  // final responseTokens = _asInt(response.data['responseTokens']);
  // final geminiLatencyMs = _asInt(response.data['geminiLatencyMs']);
  // întoarce _GeminiResult cu contextUsed, signals, latencyMs, tokeni,
  // recommendedCategories, recommendedPlaces (pentru aliniere).
  throw UnimplementedError('vezi commit a27e974');
}

// ---- Logare bogată per apel: users/{uid}/ai_logs ----------------------------

Future<void> _logInteraction({
  required String prompt,
  required _GeminiResult result,
  required _ContextMode arm,
  required String pairId,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  try {
    // Profil agregat pe cele 6 teme Discover (aceeași taxonomie cu care mapăm
    // recomandările), ca alinierea să se calculeze pe aceeași riglă pe ambele brațe.
    final profileThemeCounts = <String, int>{};
    for (final c in result.signals.topCategories) {
      final theme = themeForTypes([c.type])?.name;
      if (theme == null) continue;
      profileThemeCounts[theme] = (profileThemeCounts[theme] ?? 0) + c.count;
    }
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('ai_logs')
        .add({
          'timestamp': FieldValue.serverTimestamp(),
          // brațul. 'condition' bool (true doar la full) pentru compatibilitate;
          // 'conditionLabel' dă brațul exact.
          'condition': arm == _ContextMode.full,
          'conditionLabel': arm.name,
          'pairId': pairId, // leagă același prompt între brațe (comparație pereche)
          'prompt': prompt,
          'response': result.text ?? result.error ?? '',
          'contextUsed': result.contextUsed,
          'profileCategories': result.signals.topCategories
              .map((c) => {'type': c.type, 'count': c.count})
              .toList(),
          'profileThemes': profileThemeCounts.entries
              .map((e) => {'theme': e.key, 'count': e.value})
              .toList(),
          'signalsCount': result.signals.signalsCount,
          'hasLocation': result.signals.location.isNotEmpty,
          'latencyMs': result.latencyMs,
          'geminiLatencyMs': result.geminiLatencyMs,
          'promptTokens': result.promptTokens,
          'responseTokens': result.responseTokens,
          'recommendedCategories': result.recommendedCategories,
          'recommendedPlaces': result.recommendedPlaces
              .map((p) => {
                    'name': p.name,
                    'area': p.area,
                    'category': p.category,
                    'theme': themeForTypes([p.category])?.name,
                  })
              .toList(),
          'model': _geminiModel,
        });
  } catch (_) {
    // best-effort
  }
}

// ---- Log uniform al experimentului: colecția top-level ai_logs ---------------

Future<void> _logExperimentRun({
  required String prompt,
  required _GeminiResult result,
  required _ContextMode arm,
  required String pairId,
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final publicArm = arm == _ContextMode.full
      ? ContextMode.full
      : ContextMode.none;

  final counts = <DiscoverTheme, int>{};
  for (final c in result.signals.topCategories) {
    final theme = themeForTypes([c.type]);
    if (theme == null) continue;
    counts[theme] = (counts[theme] ?? 0) + c.count;
  }
  final profile = normalizedThemeProfile(counts);

  final items = [
    for (final p in result.recommendedPlaces)
      {
        'id': '',
        'name': p.name,
        'area': p.area,
        'score': double.parse(
          profileMatchScore([p.category], profile).toStringAsFixed(4),
        ),
      },
  ];

  await logRun(
    arm: publicArm.arm,
    surface: 'assistant',
    uid: uid,
    query: prompt,
    items: items,
    pairId: pairId,
    latencyMs: result.latencyMs,
    promptTokens: result.promptTokens,
    responseTokens: result.responseTokens,
  );
}

// ---- Debug: rulează AMBELE brațe pe același prompt (pereche A/B) -------------

Future<void> _runBothArms() async {
  final trimmed = _textController.text.trim();
  if (trimmed.isEmpty || _isLoading) return;
  // ... validări + adăugare mesaj user.
  // pairId unic per apăsare (uid + prompt + timestamp).
  final pairId = experimentPairId(
    '${FirebaseAuth.instance.currentUser!.uid}|$trimmed|'
    '${DateTime.now().millisecondsSinceEpoch}',
  );
  // Rulăm A apoi B pe ACELAȘI istoric (răspunsurile intră în _messages abia după
  // ce ambele apeluri s-au terminat), ca singura diferență să fie contextul.
  final resultA = await _callGemini(_ContextMode.none);
  final resultB = await _callGemini(_ContextMode.full);
  // logăm A și B (ambele loggere) cu același pairId, apoi afișăm răspunsurile
  // etichetate „A · fără context" / „B · cu context" (câmpul _ChatMessage.armLabel).
}

// ---- Structura rezultatului (cu câmpurile de măsurare pentru analiză) --------

class _GeminiResult {
  const _GeminiResult({
    required this.text,
    required this.places,
    required this.error,
    required this.contextUsed,
    required this.signals,
    required this.latencyMs,
    required this.geminiLatencyMs,
    required this.promptTokens,
    required this.responseTokens,
    required this.recommendedCategories,
    required this.recommendedPlaces,
  });
  final String? text;
  final List<({String name, String area})> places;
  final String? error;
  final String contextUsed; // textul injectat (logat ca dovadă a brațului)
  final _UserSignals signals; // profilul din clipa apelului
  final int latencyMs;
  final int? geminiLatencyMs;
  final int? promptTokens;
  final int? responseTokens;
  final List<String>? recommendedCategories;
  final List<({String name, String area, String category})> recommendedPlaces;
}
