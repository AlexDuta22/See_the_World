import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'discover_themes.dart';

// un loc candidat din Google Places (coordonatele vin direct din rezultat)
class DiscoverCandidate {
  DiscoverCandidate({
    required this.placeId,
    required this.name,
    required this.lat,
    required this.lng,
    required this.theme,
    required this.types,
    this.rating,
    this.userRatingsTotal,
  });

  final String placeId;
  final String name;
  final double lat;
  final double lng;
  final DiscoverTheme theme;
  final List<String> types;
  final double? rating;
  final int? userRatingsTotal;
}

// candidati din Google Places Nearby Search, filtrati pe tema
class DiscoverService {
  DiscoverService({required this.placesApiKey});

  final String placesApiKey;

  // candidati pentru o tema: interogam tipurile, unim, scoatem vizitatele, ordonam
  Future<List<DiscoverCandidate>> fetchForTheme({
    required DiscoverTheme theme,
    required double lat,
    required double lng,
    required double radius,
    required Set<String> excludeIds,
    int limit = 20,
  }) async {
    final merged = <String, DiscoverCandidate>{};
    for (final type in themeInfo(theme).nearbyTypes) {
      final found = await _nearby(
        type: type,
        lat: lat,
        lng: lng,
        radius: radius,
        filterTheme: theme,
        assign: (_) => theme,
      );
      for (final c in found) {
        if (excludeIds.contains(c.placeId)) continue;
        merged.putIfAbsent(c.placeId, () => c);
      }
    }
    final list = merged.values.toList();
    rank(list, theme: theme, lat: lat, lng: lng, radius: radius);
    return list.take(limit).toList();
  }

  // „Popular near you”: atractiile din jur, fiecare cu tema derivata din tipuri
  Future<List<DiscoverCandidate>> fetchPopular({
    required double lat,
    required double lng,
    required double radius,
    required Set<String> excludeIds,
    int limit = 20,
  }) async {
    final found = await _nearby(
      type: 'tourist_attraction',
      lat: lat,
      lng: lng,
      radius: radius,
      filterTheme: DiscoverTheme.hiddenGems,
      assign: (types) => themeForTypes(types) ?? DiscoverTheme.hiddenGems,
    );
    final list = found.where((c) => !excludeIds.contains(c.placeId)).toList();
    rank(list, theme: null, lat: lat, lng: lng, radius: radius);
    return list.take(limit).toList();
  }

  Future<List<DiscoverCandidate>> _nearby({
    required String type,
    required double lat,
    required double lng,
    required double radius,
    required DiscoverTheme filterTheme,
    required DiscoverTheme Function(List<String> types) assign,
  }) async {
    if (placesApiKey.isEmpty) return const [];
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
      '?location=$lat,$lng&radius=${radius.round()}&type=$type'
      '&key=$placesApiKey',
    );
    try {
      final response = await http.get(url);
      if (response.statusCode != 200) return const [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>? ?? [];
      final out = <DiscoverCandidate>[];
      for (final item in results) {
        final place = item as Map<String, dynamic>;
        final placeId = place['place_id']?.toString();
        final name = place['name']?.toString();
        final location =
            (place['geometry'] as Map<String, dynamic>?)?['location']
                as Map<String, dynamic>?;
        final pLat = location?['lat'] as num?;
        final pLng = location?['lng'] as num?;
        if (placeId == null || name == null || pLat == null || pLng == null) {
          continue;
        }
        final types =
            (place['types'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[];
        if (!isAllowedForTheme(types.toSet(), filterTheme)) continue;
        out.add(
          DiscoverCandidate(
            placeId: placeId,
            name: name,
            lat: pLat.toDouble(),
            lng: pLng.toDouble(),
            theme: assign(types),
            types: types,
            rating: (place['rating'] as num?)?.toDouble(),
            userRatingsTotal: (place['user_ratings_total'] as num?)?.toInt(),
          ),
        );
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  // scor rating + apropiere; la hidden gems premiem nota mare cu putine recenzii
  void rank(
    List<DiscoverCandidate> list, {
    required DiscoverTheme? theme,
    required double lat,
    required double lng,
    required double radius,
  }) {
    double score(DiscoverCandidate c) {
      final distance = Geolocator.distanceBetween(lat, lng, c.lat, c.lng);
      final proximity = 1 - (distance / radius).clamp(0.0, 1.0);
      final ratingScore = (c.rating ?? 0) / 5;
      if (theme == DiscoverTheme.hiddenGems) {
        final crowd = ((c.userRatingsTotal ?? 0) / 2000).clamp(0.0, 1.0);
        return 0.5 * ratingScore + 0.3 * proximity + 0.2 * (1 - crowd);
      }
      return 0.6 * ratingScore + 0.4 * proximity;
    }

    list.sort((a, b) => score(b).compareTo(score(a)));
  }

  Future<Set<String>> visitedPlaceIds(String uid) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('visited')
          .get();
      return snapshot.docs.map((d) => d.id).toSet();
    } catch (_) {
      return <String>{};
    }
  }
}
