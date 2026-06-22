// ARHIVĂ — dovadă a modului experimental pe HARTĂ (studiile de caz). NU face
// parte din aplicație și NU se compilează (docs/ e exclus din analyzer). Codul
// trăia inline în lib/pages/home_page.dart și a fost scos la revenirea la
// varianta de lansare. Snippet de referință (folosește starea privată din
// _HomePageState: _placesApiKey, _tasteProfile, _nearbyPlaces, _showSnack etc.).
// Vezi README.md și commit-ul a27e974 pentru implementarea completă în context.

// ---- Câmpurile experimentului (în _HomePageState) -------------------------

// Experiment 2 brate pe harta. Acelasi pool de candidati pentru ambele brate;
// bratul decide DOAR ordinea, niciodata cati itemi apar. N e fix.
static const int _experimentN = 15;
// Experimentul caută mereu pe 10 km: pool-ul iese destul de mare și variat
// încât bratul Personalizat să poată reordona vizibil față de Generic. La raze
// mici pool-ul ajungea aproape egal cu N, deci ambele brațe ieșeau identice.
static const double _experimentRadius = 10000;
ContextMode _experimentArm = ContextMode.none;
bool _experimentActive = false;
bool _experimentBusy = false;

// În _applyDirectionalFilter, înaintea filtrului pe busolă:
//   // In modul experiment aratam fix cele N markere ale bratului, nedependent de
//   // directia busolei — altfel N-ul nu ar mai fi garantat.
//   if (_experimentActive) return;
//
// În _refreshDiscover, la intrarea pe fluxul normal Discover:
//   // iesim din modul experiment: revine filtrul pe directie + temele
//   _experimentActive = false;
//
// În build(), bara experimentului (jos pe hartă):
//   if (_navSteps.isEmpty && !_showTourMarkers)
//     Positioned(
//       left: 12, right: 12, bottom: 16,
//       child: SafeArea(child: _buildExperimentBar(isDark)),
//     ),

// ---- Pool partajat + selecția brațului ------------------------------------

// Pool partajat: aceleasi locuri din jur pentru ambele brate. Returneaza
// (pozitie, pool, vizitate) sau null. Vizitatele NU se scot din pool: excluderea
// lor e tot context personal, deci se aplica DOAR la bratul Personalizat (in
// selectArm). Altfel si Generic ar primi context si locul vizitat ar disparea.
Future<(Position, List<DiscoverCandidate>, Set<String>)?>
_fetchExperimentPool() async {
  if (!_hasLocationPermission || _placesApiKey.isEmpty) {
    _showSnack('Activează locația pentru experiment.');
    return null;
  }
  final position = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
  );
  _lastPosition = position;
  await _ensureTasteProfile(force: true);

  final service = DiscoverService(placesApiKey: _placesApiKey);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  final visited =
      uid == null ? <String>{} : await service.visitedPlaceIds(uid);

  // Un singur apel pe 10 km, cu pool mare (nu ne oprim la primul N): vrem cât
  // mai mulți candidați variați, ca cele două brațe să poată diferi. Pool-ul
  // include și locurile vizitate — Generic le păstrează, Personalizat le scoate.
  final pool = await service.fetchMixedPool(
    lat: position.latitude,
    lng: position.longitude,
    radius: _experimentRadius,
    excludeIds: const <String>{},
    limit: 40,
  );
  return (position, pool, visited);
}

// Afiseaza pe harta cele N locuri ale unui brat (fix N, fara filtru busola).
void _showExperimentArm({
  required ContextMode arm,
  required List<ScoredCandidate> selected,
}) {
  final places = <String, _NearbyPlace>{
    for (final s in selected)
      s.candidate.placeId: _NearbyPlace(
        id: s.candidate.placeId,
        name: s.candidate.name,
        position: LatLng(s.candidate.lat, s.candidate.lng),
        types: s.candidate.types,
        theme: s.candidate.theme,
        rating: s.candidate.rating,
      ),
  };
  setState(() {
    _experimentActive = true;
    _proximityActive = true;
    _experimentArm = arm;
    _nearbyPlaces
      ..clear()
      ..addAll(places);
    _nearbyMarkers = _buildNearbyMarkers(places.values);
    _discoverLabel = 'Experiment: ${arm.uiLabel} · N=${selected.length} · '
        '${(_experimentRadius / 1000).toStringAsFixed(0)} km';
  });
}

List<Map<String, dynamic>> _experimentLogItems(
  List<ScoredCandidate> selected,
) => [
  for (final s in selected)
    {
      'id': s.candidate.placeId,
      'name': s.candidate.name,
      'score': double.parse(s.score.toStringAsFixed(4)),
    },
];

// O singura rulare a bratului selectat (toggle). pairId stabil din persoana +
// locatie, ca acelasi loc + acelasi user sa imperecheze A cu B.
Future<void> _runExperimentArm(ContextMode arm) async {
  if (_experimentBusy) return;
  setState(() => _experimentBusy = true);
  final stopwatch = Stopwatch()..start();
  try {
    final fetched = await _fetchExperimentPool();
    if (fetched == null || !mounted) return;
    final (position, pool, visited) = fetched;
    final profile = normalizedThemeProfile(_tasteProfile.counts);
    final selected = selectArm(
      mode: arm,
      pool: pool,
      profileThemes: profile,
      originLat: position.latitude,
      originLng: position.longitude,
      n: _experimentN,
      excludeVisited: visited,
    );
    stopwatch.stop();
    _showExperimentArm(arm: arm, selected: selected);

    // DIAGNOSTIC: ne arată de ce ies (ne)identice brațele.
    final profileStr = profile.isEmpty
        ? 'GOL'
        : (profile.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .map((e) => '${e.key.name}=${e.value.toStringAsFixed(2)}')
              .join(' ');
    final foodInResult = selected
        .where((s) => s.candidate.types.toSet().intersection(kFoodTypes).isNotEmpty)
        .length;
    _showSnack(
      '${arm.uiLabel}: pool=${pool.length} · food=$foodInResult · profil: $profileStr',
    );

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final coords =
        '${position.latitude.toStringAsFixed(4)},'
        '${position.longitude.toStringAsFixed(4)}';
    await logRun(
      arm: arm.arm,
      surface: 'home',
      uid: uid,
      query: 'nearby@$coords',
      items: _experimentLogItems(selected),
      pairId: experimentPairId(
        '$uid|${position.latitude.toStringAsFixed(3)},'
        '${position.longitude.toStringAsFixed(3)}',
      ),
      latencyMs: stopwatch.elapsedMilliseconds,
    );
  } catch (_) {
    _showSnack('Experimentul a eșuat. Încearcă din nou.');
  } finally {
    if (mounted) setState(() => _experimentBusy = false);
  }
}

// Debug: ruleaza A si B pe ACELASI pool, cu acelasi pairId -> perechea
// before/after pentru lucrare. Afiseaza pe harta bratul curent selectat.
Future<void> _runBothArms() async {
  if (_experimentBusy) return;
  setState(() => _experimentBusy = true);
  try {
    final fetched = await _fetchExperimentPool();
    if (fetched == null || !mounted) return;
    final (position, pool, visited) = fetched;
    final profile = normalizedThemeProfile(_tasteProfile.counts);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final coords =
        '${position.latitude.toStringAsFixed(4)},'
        '${position.longitude.toStringAsFixed(4)}';
    // Acelasi pairId pentru ambele brate la aceasta rulare pereche.
    final pairId = experimentPairId(
      '$uid|${position.latitude.toStringAsFixed(3)},'
      '${position.longitude.toStringAsFixed(3)}|'
      '${DateTime.now().millisecondsSinceEpoch}',
    );

    final selections = <ContextMode, List<ScoredCandidate>>{};
    for (final arm in ContextMode.values) {
      final stopwatch = Stopwatch()..start();
      final selected = selectArm(
        mode: arm,
        pool: pool,
        profileThemes: profile,
        originLat: position.latitude,
        originLng: position.longitude,
        n: _experimentN,
        excludeVisited: visited,
      );
      stopwatch.stop();
      selections[arm] = selected;
      await logRun(
        arm: arm.arm,
        surface: 'home',
        uid: uid,
        query: 'nearby@$coords',
        items: _experimentLogItems(selected),
        pairId: pairId,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    }
    if (!mounted) return;
    _showExperimentArm(
      arm: _experimentArm,
      selected: selections[_experimentArm]!,
    );
    _showSnack(
      'Logged A=${selections[ContextMode.none]!.length}, '
      'B=${selections[ContextMode.full]!.length} · pairId=$pairId',
    );
  } catch (_) {
    _showSnack('Experimentul a eșuat. Încearcă din nou.');
  } finally {
    if (mounted) setState(() => _experimentBusy = false);
  }
}

// Bara experimentului: toggle braț (Generic = A / Personalizat = B), N-ul
// afisat ca dovada ca ambele brate intorc acelasi numar, si butonul de debug
// care ruleaza ambele brate pe acelasi pool.
Widget _buildExperimentBar(bool isDark) {
  return Material(
    elevation: 4,
    borderRadius: BorderRadius.circular(12),
    color: isDark ? Colors.black : Colors.white,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<ContextMode>(
              segments: const [
                ButtonSegment(
                  value: ContextMode.none,
                  label: Text('Generic'),
                  icon: Icon(Icons.public, size: 16),
                ),
                ButtonSegment(
                  value: ContextMode.full,
                  label: Text('Personalizat'),
                  icon: Icon(Icons.person_pin_circle, size: 16),
                ),
              ],
              selected: {_experimentArm},
              showSelectedIcon: false,
              onSelectionChanged: _experimentBusy
                  ? null
                  : (selection) => _runExperimentArm(selection.first),
            ),
          ),
          const SizedBox(width: 8),
          Chip(
            visualDensity: VisualDensity.compact,
            label: Text('N=$_experimentN'),
          ),
          IconButton(
            tooltip: 'Rulează ambele brațe',
            onPressed: _experimentBusy ? null : _runBothArms,
            icon: _experimentBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.compare_arrows),
          ),
        ],
      ),
    ),
  );
}
