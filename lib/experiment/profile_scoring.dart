import 'package:geolocator/geolocator.dart';

import '../services/discover_service.dart';
import '../services/discover_themes.dart';

// Cele doua brate ale experimentului. none = brat A (fara preferinte personale),
// full = brat B (cu profil de gusturi). Ambele au mereu acces la locatie; difera
// DOAR ce preferinte se folosesc, niciodata cati itemi se intorc.
enum ContextMode { none, full }

extension ContextModeArm on ContextMode {
  // eticheta scrisa in ai_logs: A -> 'none', B -> 'full'
  String get arm => this == ContextMode.full ? 'full' : 'none';

  String get uiLabel => this == ContextMode.full ? 'Personalizat' : 'Generic';
}

// Refolosesc taxonomia existenta (DiscoverTheme + themeForTypes din
// discover_themes.dart). Aici doar normalizez numaratoarea profilului in ponderi
// 0..1 ca scorul de potrivire sa fie comparabil intre utilizatori.
Map<DiscoverTheme, double> normalizedThemeProfile(
  Map<DiscoverTheme, int> counts,
) {
  final total = counts.values.fold<int>(0, (sum, c) => sum + c);
  if (total == 0) return const {};
  return {
    for (final entry in counts.entries) entry.key: entry.value / total,
  };
}

// Scor 0..1 intre tipurile unui loc si profilul de gusturi. Mapez fiecare tip la
// tema lui (acelasi themeForTypes folosit peste tot) si iau ponderea cea mai mare
// din profil — locul "se potriveste" cat de mult conteaza pentru user tema lui.
double profileMatchScore(
  List<String> placeTypes,
  Map<DiscoverTheme, double> profileThemes,
) {
  if (profileThemes.isEmpty || placeTypes.isEmpty) return 0;
  var best = 0.0;
  for (final type in placeTypes) {
    final theme = themeForTypes([type]);
    if (theme == null) continue;
    final weight = profileThemes[theme] ?? 0;
    if (weight > best) best = weight;
  }
  return best.clamp(0.0, 1.0);
}

// Un candidat cu scorul lui de profil, pastrand legatura cu locul original.
class ScoredCandidate {
  const ScoredCandidate({required this.candidate, required this.score});
  final DiscoverCandidate candidate;
  final double score;
}

// Inima experimentului: din ACELASI pool, alege ce N itemi apar pentru bratul dat.
// none (A): cele mai apropiate N (fara sa se uite la preferinte).
// full (B): cele mai potrivite N dupa profil, departajate dupa distanta.
// Ambele brate fac take(n) din acelasi pool -> acelasi numar de itemi mereu.
List<ScoredCandidate> selectArm({
  required ContextMode mode,
  required List<DiscoverCandidate> pool,
  required Map<DiscoverTheme, double> profileThemes,
  required double originLat,
  required double originLng,
  required int n,
}) {
  double distanceOf(DiscoverCandidate c) =>
      Geolocator.distanceBetween(originLat, originLng, c.lat, c.lng);

  final scored = [
    for (final c in pool)
      ScoredCandidate(
        candidate: c,
        score: profileMatchScore(c.types, profileThemes),
      ),
  ];

  if (mode == ContextMode.none) {
    scored.sort(
      (a, b) => distanceOf(a.candidate).compareTo(distanceOf(b.candidate)),
    );
  } else {
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return distanceOf(a.candidate).compareTo(distanceOf(b.candidate));
    });
  }

  return scored.take(n).toList();
}
