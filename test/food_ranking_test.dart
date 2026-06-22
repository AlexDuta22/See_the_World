import 'package:flutter_test/flutter_test.dart';
import 'package:see_the_world/services/discover_service.dart';
import 'package:see_the_world/services/discover_themes.dart';

// Timișoara, Piața Victoriei.
const originLat = 45.7537;
const originLng = 21.2257;

// 1 km ≈ 0.0129° longitudine la latitudinea Timișoarei.
DiscoverCandidate foodPlace(
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
    theme: themeForTypes(types) ?? DiscoverTheme.food,
    types: types,
    rating: rating,
    userRatingsTotal: reviews,
  );
}

void main() {
  final service = DiscoverService(placesApiKey: '');

  // Cazul real: multe cafenele cu nota/recenzii mari + restaurante ceva mai jos.
  // Inainte de fix, scorul calitate+apropiere ridica cafenelele in top.
  List<DiscoverCandidate> mixedPool() => <DiscoverCandidate>[
    for (var i = 0; i < 12; i++)
      foodPlace('Cafenea $i', ['cafe'], 0.2 + i * 0.04, rating: 4.8, reviews: 1500),
    for (var i = 0; i < 10; i++)
      foodPlace(
        'Restaurant $i',
        ['restaurant'],
        0.3 + i * 0.04,
        rating: 4.3,
        reviews: 600,
      ),
    foodPlace('Pizza Roma', ['pizza_restaurant', 'restaurant'], 0.4,
        rating: 4.1, reviews: 900),
    foodPlace('Burger Spot', ['meal_takeaway', 'restaurant'], 0.6,
        rating: 3.9, reviews: 1200),
  ];

  bool isCafe(DiscoverCandidate c) => isCafeLike(c.types);

  test('rankFood: restaurantele domina, cafenelele sunt plafonate la ~20%', () {
    final ranked = service.rankFood(
      mixedPool(),
      lat: originLat,
      lng: originLng,
      radius: 10000,
      limit: 15,
    );
    final cafeCount = ranked.where(isCafe).length;
    final restCount = ranked.length - cafeCount;

    // ignore: avoid_print
    print('FOOD ranking -> restaurante=$restCount, cafenele=$cafeCount');
    // ignore: avoid_print
    print('primele 5: ${ranked.take(5).map((c) => c.name).toList()}');

    expect(ranked.length, 15);
    // Vrem 10-15 restaurante si 2-3 cafenele, nu invers.
    expect(restCount, greaterThanOrEqualTo(12));
    expect(cafeCount, lessThanOrEqualTo(3));
    // Restaurantele apar primele.
    expect(isCafe(ranked.first), isFalse);
    expect(ranked.take(restCount).every((c) => !isCafe(c)), isTrue);
  });

  test('rankFood: fara restaurante, cafenelele umplu (fallback)', () {
    final onlyCafes = <DiscoverCandidate>[
      for (var i = 0; i < 8; i++)
        foodPlace('Cafenea $i', ['cafe'], 0.2 + i * 0.05, rating: 4.7, reviews: 800),
    ];
    final ranked = service.rankFood(
      onlyCafes,
      lat: originLat,
      lng: originLng,
      radius: 10000,
      limit: 15,
    );
    // Nu blocam harta goala: daca nu exista restaurante, aratam cafenelele.
    expect(ranked.length, 8);
    expect(ranked.every(isCafe), isTrue);
  });
}
