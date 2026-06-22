// ARHIVĂ — dovadă a modului experimental (studiile de caz). NU face parte din
// aplicație și NU se compilează (folderul docs/ e exclus din analyzer). Locația
// originală: test/experiment_personalization_test.dart. Vezi README.md.
//
// Testul valida invariantul personalizării pe hartă: din ACELAȘI pool, brațul
// „Personalizat" (full) reordonează după profilul de gust și scoate categoriile
// nepotrivite, iar pe un pool mic ambele brațe dau aceleași locuri (doar ordinea
// diferă) — exact ce vedea utilizatorul.

import 'package:flutter_test/flutter_test.dart';
import 'package:see_the_world/experiment/profile_scoring.dart';
import 'package:see_the_world/services/discover_service.dart';
import 'package:see_the_world/services/discover_themes.dart';

// Timișoara, Piața Victoriei.
const originLat = 45.7537;
const originLng = 21.2257;

// 1 km ≈ 0.0129° longitudine la latitudinea Timișoarei.
DiscoverCandidate place(String name, List<String> types, double dxKm) {
  return DiscoverCandidate(
    placeId: name,
    name: name,
    lat: originLat,
    lng: originLng + dxKm * 0.0129,
    theme: themeForTypes(types) ?? DiscoverTheme.hiddenGems,
    types: types,
    rating: 4.5,
    userRatingsTotal: 500,
  );
}

bool isFood(DiscoverCandidate c) =>
    c.types.toSet().intersection(kFoodTypes).isNotEmpty;

void main() {
  // Profilul REAL al utilizatorului din favorite: 4 lăcașuri (Arhitectură) +
  // 2 muzee (Istorie). Niciun restaurant.
  final profile = normalizedThemeProfile(const {
    DiscoverTheme.architecture: 4,
    DiscoverTheme.history: 2,
  });

  // Pool variat: restaurante/cafenele + parcuri aproape de centru, muzee și
  // biserici răspândite pe 10 km.
  final pool = <DiscoverCandidate>[
    place('Restaurant Lloyd', ['restaurant'], 0.2),
    place('Cafenea Scârț', ['cafe'], 0.3),
    place('Berăria 700', ['restaurant'], 0.5),
    place('Bistro Central', ['restaurant'], 0.6),
    place('Cafenea Boemă', ['cafe'], 0.8),
    place('Food Court', ['restaurant'], 1.0),
    place('Parcul Central', ['park'], 0.7),
    place('Parcul Rozelor', ['park'], 1.2),
    place('Muzeul de Artă', ['museum'], 0.5),
    place('Domul Romano-Catolic', ['church'], 0.6),
    place('Sinagoga din Cetate', ['synagogue'], 0.7),
    place('Catedrala Mitropolitană', ['church'], 0.9),
    place('Biserica Sârbească', ['church'], 1.1),
    place('Memorialul Revoluției', ['museum'], 1.4),
    place('Biserica Millennium', ['church'], 2.2),
    place('Sinagoga din Fabric', ['synagogue'], 2.4),
    place('Muzeul Banatului', ['museum'], 2.8),
    place('Biserica din Iosefin', ['church'], 3.2),
    place('Muzeul Satului', ['museum'], 4.5),
    place('Biserica din Mehala', ['church'], 5.0),
    place('Muzeul Transportului', ['museum'], 6.0),
    place('Biserica din Freidorf', ['church'], 7.5),
    place('Mănăstirea Timișeni', ['church'], 9.0),
    place('Sinagoga Iosefin', ['synagogue'], 9.5),
  ];

  List<String> names(List<ScoredCandidate> s) =>
      s.map((e) => e.candidate.name).toList();

  test(
    'pool mare: brațul Personalizat scoate restaurantele și aduce cultura',
    () {
      final generic = selectArm(
        mode: ContextMode.none,
        pool: pool,
        profileThemes: profile,
        originLat: originLat,
        originLng: originLng,
        n: 15,
      );
      final personal = selectArm(
        mode: ContextMode.full,
        pool: pool,
        profileThemes: profile,
        originLat: originLat,
        originLng: originLng,
        n: 15,
      );

      final genericFood = generic.where((s) => isFood(s.candidate)).length;
      final personalFood = personal.where((s) => isFood(s.candidate)).length;

      // ignore: avoid_print
      print('GENERIC      : ${names(generic)}');
      // ignore: avoid_print
      print('PERSONALIZAT : ${names(personal)}');
      // ignore: avoid_print
      print('restaurante  -> generic=$genericFood, personalizat=$personalFood');

      // Cele două brațe NU mai dau aceleași locuri.
      expect(names(generic).toSet(), isNot(equals(names(personal).toSet())));
      // Generic (după distanță) prinde restaurantele din centru.
      expect(genericFood, greaterThan(0));
      // Personalizat (după profil istorie/arhitectură) nu mai are restaurante.
      expect(personalFood, equals(0));
      // Primul loc personalizat e din categoriile preferate.
      final topTheme = themeForTypes(personal.first.candidate.types);
      expect(
        topTheme == DiscoverTheme.architecture ||
            topTheme == DiscoverTheme.history,
        isTrue,
      );
    },
  );

  test(
    'pool ≈ N: ambele brațe dau ACELEAȘI locuri (cauza din build-ul vechi)',
    () {
      final small = pool.take(12).toList(); // pool mic, sub N=15
      final generic = selectArm(
        mode: ContextMode.none,
        pool: small,
        profileThemes: profile,
        originLat: originLat,
        originLng: originLng,
        n: 15,
      );
      final personal = selectArm(
        mode: ContextMode.full,
        pool: small,
        profileThemes: profile,
        originLat: originLat,
        originLng: originLng,
        n: 15,
      );
      // Același set de locuri (doar ordinea diferă) — exact ce vedea utilizatorul.
      expect(names(generic).toSet(), equals(names(personal).toSet()));
    },
  );
}
