import 'package:flutter_test/flutter_test.dart';
import 'package:see_the_world/services/discover_service.dart';
import 'package:see_the_world/services/discover_themes.dart';
import 'package:see_the_world/services/taste_profile.dart';

// Timișoara, Piața Victoriei.
const originLat = 45.7537;
const originLng = 21.2257;

// 1 km ≈ 0.0129° longitudine la latitudinea Timișoarei.
DiscoverCandidate place(
  String name,
  List<String> types,
  double dxKm, {
  required double rating,
  required int reviews,
}) {
  return DiscoverCandidate(
    placeId: name,
    name: name,
    lat: originLat,
    lng: originLng + dxKm * 0.0129,
    theme: themeForTypes(types) ?? DiscoverTheme.hiddenGems,
    types: types,
    rating: rating,
    userRatingsTotal: reviews,
  );
}

void main() {
  group('profileMatchScore', () {
    test('întoarce ponderea temei dominante a locului', () {
      const weights = {DiscoverTheme.history: 0.8, DiscoverTheme.food: 0.2};
      expect(profileMatchScore(['museum'], weights), 0.8);
      expect(profileMatchScore(['restaurant'], weights), 0.2);
      // tip necunoscut profilului -> 0
      expect(profileMatchScore(['lodging'], weights), 0);
    });

    test('profil gol -> 0', () {
      expect(profileMatchScore(['museum'], const {}), 0);
    });
  });

  group('TasteProfile.normalizedWeights', () {
    test('normalizează numărătoarea la ponderi 0..1', () {
      const profile = TasteProfile(
        counts: {DiscoverTheme.history: 3, DiscoverTheme.food: 1},
        rankedThemes: [DiscoverTheme.history, DiscoverTheme.food],
        classifiedPlaces: 4,
      );
      final w = profile.normalizedWeights;
      expect(w[DiscoverTheme.history], closeTo(0.75, 1e-9));
      expect(w[DiscoverTheme.food], closeTo(0.25, 1e-9));
    });

    test('profil gol -> hartă goală', () {
      expect(TasteProfile.empty.normalizedWeights, isEmpty);
    });
  });

  group('rank cu profil de gust', () {
    final service = DiscoverService(placesApiKey: '');
    // Un muzeu (istorie) decent, ceva mai departe, și un restaurant (food) cu
    // notă/recenzii mai mari, foarte aproape.
    List<DiscoverCandidate> pool() => [
      place('Muzeu', ['museum'], 2.0, rating: 4.2, reviews: 200),
      place('Restaurant', ['restaurant'], 0.2, rating: 4.9, reviews: 3000),
    ];

    test('fără profil: câștigă calitatea + apropierea (restaurantul)', () {
      final list = pool();
      service.rank(list, lat: originLat, lng: originLng, radius: 10000);
      expect(list.first.name, 'Restaurant');
    });

    test('cu profil înclinat spre istorie: muzeul urcă primul', () {
      final list = pool();
      service.rank(
        list,
        lat: originLat,
        lng: originLng,
        radius: 10000,
        profileThemes: const {
          DiscoverTheme.history: 0.8,
          DiscoverTheme.food: 0.2,
        },
      );
      expect(list.first.name, 'Muzeu');
    });
  });
}
