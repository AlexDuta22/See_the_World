import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'discover_themes.dart';

// Intrare de cache pentru un raspuns Places brut (lista de candidati + momentul
// cererii). Tinem raspunsul deja parsat, ca reluarea sa nu implice iar JSON.
class _PlacesCacheEntry {
  _PlacesCacheEntry(this.candidates) : fetchedAt = DateTime.now();
  final List<DiscoverCandidate> candidates;
  final DateTime fetchedAt;

  bool get isExpired =>
      DateTime.now().difference(fetchedAt) > const Duration(minutes: 15);
}

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

  // Cache in memorie, comun tuturor instantelor DiscoverService din sesiune
  // (fiecare tap pe un chip de tema creeaza o instanta noua). Evita sa
  // refacem acelasi Nearby/Text Search cand userul comuta rapid intre teme
  // sau cand ecranul se re-initializeaza pe aceeasi zona. Coordonatele sunt
  // rotunjite la ~110m (4 zecimale) — suficient de fin cat sa nu amestece
  // zone diferite, suficient de larg cat sa prinda re-cererile reale.
  static final Map<String, _PlacesCacheEntry> _cache = {};

  String _roundCoord(double v) => v.toStringAsFixed(4);

  Future<List<DiscoverCandidate>> _cached(
    String key,
    Future<List<DiscoverCandidate>> Function() fetch,
  ) async {
    final hit = _cache[key];
    if (hit != null && !hit.isExpired) return hit.candidates;
    final result = await fetch();
    _cache[key] = _PlacesCacheEntry(result);
    return result;
  }

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
    // Completam cu Text Search ca sa prindem obiectivele pe care cautarea pe
    // tipuri le rateaza (teatre, cetati, palate marcate doar point_of_interest).
    final textQuery = textQueryForTheme(theme);
    if (textQuery != null) {
      final found = await _textSearch(
        query: textQuery,
        lat: lat,
        lng: lng,
        radius: radius,
        assignDefault: theme,
      );
      for (final c in found) {
        if (excludeIds.contains(c.placeId)) continue;
        merged.putIfAbsent(c.placeId, () => c);
      }
    }
    final list = _filterByQuality(merged.values.toList());
    // Tema Food are nevoie de ordonare pe sub-categorii: altfel cafenelele (cu
    // nota/recenzii mai mari) domina, desi userul cauta unde sa manance. Pentru
    // restul temelor ordonarea pe calitate+apropiere e suficienta.
    if (theme == DiscoverTheme.food) {
      return rankFood(list, lat: lat, lng: lng, radius: radius, limit: limit);
    }
    rank(list, lat: lat, lng: lng, radius: radius);
    return list.take(limit).toList();
  }

  // „Popular near you”: atractiile din jur, fiecare cu tema derivata din tipuri.
  // Interogam mai multe tipuri turistice (nu doar tourist_attraction) ca sa prinda
  // si muzeele/galeriile care altfel lipseau (ex. Complexul Muzeal), apoi filtram
  // pe calitate si ordonam dupa nota+popularitate.
  Future<List<DiscoverCandidate>> fetchPopular({
    required double lat,
    required double lng,
    required double radius,
    required Set<String> excludeIds,
    int limit = 20,
    Map<DiscoverTheme, double> profileThemes = const {},
  }) async {
    const popularTypes = ['tourist_attraction', 'museum'];
    final merged = <String, DiscoverCandidate>{};
    for (final type in popularTypes) {
      final found = await _nearby(
        type: type,
        lat: lat,
        lng: lng,
        radius: radius,
        // lista alba = toate tipurile turistice, nu doar tema unui singur tip
        filterTheme: DiscoverTheme.hiddenGems,
        assign: (types) => themeForTypes(types) ?? DiscoverTheme.hiddenGems,
      );
      for (final c in found) {
        if (excludeIds.contains(c.placeId)) continue;
        merged.putIfAbsent(c.placeId, () => c);
      }
    }
    // Text Search pentru atractiile cunoscute care nu vin pe tipuri.
    final textFound = await _textSearch(
      query: kPopularTextQuery,
      lat: lat,
      lng: lng,
      radius: radius,
      assignDefault: DiscoverTheme.hiddenGems,
    );
    for (final c in textFound) {
      if (excludeIds.contains(c.placeId)) continue;
      merged.putIfAbsent(c.placeId, () => c);
    }
    final list = _filterByQuality(merged.values.toList());
    rank(list, lat: lat, lng: lng, radius: radius, profileThemes: profileThemes);
    return list.take(limit).toList();
  }

  // Text Search: gaseste obiective dupa o interogare ("muzee teatre"), nu dupa un
  // tip. Asa prindem teatrele/cetatile pe care Nearby pe tipuri le rateaza. Aici
  // relevanta o da interogarea, deci filtram doar gunoiul/entitatile geografice
  // (isTouristyTextResult), nu lista alba de tipuri. Pastram doar ce e in raza.
  Future<List<DiscoverCandidate>> _textSearch({
    required String query,
    required double lat,
    required double lng,
    required double radius,
    required DiscoverTheme assignDefault,
  }) async {
    if (placesApiKey.isEmpty) return const [];
    final key =
        'text|$query|${_roundCoord(lat)}|${_roundCoord(lng)}|${radius.round()}';
    return _cached(key, () async {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/textsearch/json'
        '?query=${Uri.encodeComponent(query)}'
        '&location=$lat,$lng&radius=${radius.round()}'
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
          // Text Search e doar polarizat pe locatie, nu limitat — taiem ce e in
          // afara razei ca eticheta „within X km" sa ramana corecta.
          final distance = Geolocator.distanceBetween(
            lat,
            lng,
            pLat.toDouble(),
            pLng.toDouble(),
          );
          if (distance > radius) continue;
          final types =
              (place['types'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const <String>[];
          if (!isTouristyTextResult(types.toSet())) continue;
          out.add(
            DiscoverCandidate(
              placeId: placeId,
              name: name,
              lat: pLat.toDouble(),
              lng: pLng.toDouble(),
              theme: themeForTypes(types) ?? assignDefault,
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
    });
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
    final key =
        'nearby|$type|${_roundCoord(lat)}|${_roundCoord(lng)}|${radius.round()}';
    return _cached(key, () async {
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
    });
  }

  // Filtru de calitate cu relaxare progresiva: pastram intai doar locurile bine
  // notate si cu destule recenzii; daca zona are prea putine, coboram pragul ca
  // harta sa nu ramana goala — dar niciodata locuri fara nicio recenzie.
  List<DiscoverCandidate> _filterByQuality(List<DiscoverCandidate> list) {
    bool isFood(DiscoverCandidate c) =>
        c.types.toSet().intersection(kFoodTypes).isNotEmpty;
    bool isRestaurant(DiscoverCandidate c) =>
        c.types.toSet().intersection(kRestaurantTypes).isNotEmpty;
    bool strictOk(DiscoverCandidate c) {
      final rating = c.rating ?? 0;
      final reviews = c.userRatingsTotal ?? 0;
      // Restaurantele/fast-food au adesea nota putin mai mica decat cafenelele de
      // specialitate; le cerem un prag mai bland ca sa nu pierdem toata categoria.
      if (isRestaurant(c)) return rating >= 3.8 && reviews >= 40;
      if (isFood(c)) return rating >= 4.0 && reviews >= 80;
      return rating >= 4.0 && reviews >= 30;
    }

    final strict = list.where(strictOk).toList();
    if (strict.length >= 5) return strict;
    final relaxed = list
        .where((c) => (c.rating ?? 0) >= 3.8 && (c.userRatingsTotal ?? 0) >= 10)
        .toList();
    if (relaxed.length >= 3) return relaxed;
    return list; // ultim resort: a trecut deja de lista alba de tipuri
  }

  // Calitate 0..1: nota ponderata bayesian cu numarul de recenzii + un bonus de
  // popularitate (log). Asa un 4.8 cu 2000 recenzii bate un 4.9 cu 3 recenzii.
  double _qualityScore(DiscoverCandidate c) {
    final rating = c.rating ?? 0;
    final reviews = (c.userRatingsTotal ?? 0).toDouble();
    const prior = 3.7; // nota „neutra" spre care tragem locurile cu putine voturi
    const confidence = 50; // cate recenzii pana avem incredere in nota
    final weighted =
        (reviews * rating + confidence * prior) / (reviews + confidence);
    final popularity = reviews <= 0
        ? 0.0
        : (log(reviews) / log(5000)).clamp(0.0, 1.0);
    return (0.7 * (weighted / 5) + 0.3 * popularity).clamp(0.0, 1.0);
  }

  // Scor final fara profil: 75% calitate (nota+popularitate), 25% apropiere.
  // Prominenta unui obiectiv cunoscut conteaza mai mult decat cativa metri in plus.
  //
  // Cand primim un profil de gust (`profileThemes` ne-gol), inclinam puternic
  // recomandarile spre categoriile preponderente: 50% potrivire cu profilul, 40%
  // calitate, 10% apropiere. Asa un loc din tema preferata urca peste unul mai
  // bine notat dar dintr-o categorie care nu il intereseaza pe user.
  void rank(
    List<DiscoverCandidate> list, {
    required double lat,
    required double lng,
    required double radius,
    Map<DiscoverTheme, double> profileThemes = const {},
  }) {
    double score(DiscoverCandidate c) {
      final distance = Geolocator.distanceBetween(lat, lng, c.lat, c.lng);
      final proximity = 1 - (distance / radius).clamp(0.0, 1.0);
      if (profileThemes.isEmpty) {
        return 0.75 * _qualityScore(c) + 0.25 * proximity;
      }
      final match = profileMatchScore(c.types, profileThemes);
      return 0.5 * match + 0.4 * _qualityScore(c) + 0.1 * proximity;
    }

    list.sort((a, b) => score(b).compareTo(score(a)));
  }

  // Ranking dedicat temei Food: restaurantele primeaza, cafenelele raman doar
  // umplutura plafonata. Ordonam intai dupa prioritatea sub-categoriei
  // (restaurant > food court/diner > cafenea), apoi dupa scorul calitate+apropiere
  // — asa un restaurant bun bate o cafenea cu nota mare. La final plafonam
  // cafenelele la ~20% din N cat timp avem destule restaurante.
  List<DiscoverCandidate> rankFood(
    List<DiscoverCandidate> list, {
    required double lat,
    required double lng,
    required double radius,
    required int limit,
  }) {
    double base(DiscoverCandidate c) {
      final distance = Geolocator.distanceBetween(lat, lng, c.lat, c.lng);
      final proximity = 1 - (distance / radius).clamp(0.0, 1.0);
      return 0.75 * _qualityScore(c) + 0.25 * proximity;
    }

    int byPriorityThenScore(DiscoverCandidate a, DiscoverCandidate b) {
      final pa = foodPriority(a.types);
      final pb = foodPriority(b.types);
      if (pa != pb) return pb.compareTo(pa);
      return base(b).compareTo(base(a));
    }

    final restaurants = <DiscoverCandidate>[];
    final cafes = <DiscoverCandidate>[];
    for (final c in list) {
      (isCafeLike(c.types) ? cafes : restaurants).add(c);
    }
    restaurants.sort(byPriorityThenScore);
    cafes.sort(byPriorityThenScore);

    // Rezervam cateva locuri pentru cafenele (2-3 la N=15), restul merg la
    // restaurante. Daca lipsesc dintr-o parte, cealalta umple golul — asa
    // cafenelele apar doar cat e nevoie, niciodata in fata restaurantelor.
    final cafeQuota = (limit * 0.2).round().clamp(2, limit);
    final cafeCount = min(cafes.length, cafeQuota);
    final restCount = min(restaurants.length, limit - cafeCount);
    final out = <DiscoverCandidate>[
      ...restaurants.take(restCount),
      ...cafes.take(cafeCount),
    ];
    if (out.length < limit) {
      out.addAll(restaurants.skip(restCount).take(limit - out.length));
    }
    if (out.length < limit) {
      out.addAll(cafes.skip(cafeCount).take(limit - out.length));
    }
    return out;
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

  // Locurile salvate de user (favorite + vizitate), unite pe place_id (un loc
  // poate fi si favorit, si vizitat). Le folosim ca strat prioritar pe harta si
  // ca lista de excludere din Discover, ca acelasi loc sa nu apara de doua ori.
  Future<List<SavedPlace>> savedPlaces(String uid) async {
    final byId = <String, SavedPlace>{};
    Future<void> read(String collection, {required bool favorite}) async {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection(collection)
            .get();
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final lat = (data['lat'] as num?)?.toDouble();
          final lng = (data['lng'] as num?)?.toDouble();
          final types =
              (data['types'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const <String>[];
          final existing = byId[doc.id];
          // Pentru un loc favorit+vizitat pastram datele bogate citite intai (din
          // favorite); completam doar campurile pe care prima colectie nu le avea.
          String keep(String? prev, String? incoming) {
            if (prev != null && prev.isNotEmpty) return prev;
            return incoming?.toString() ?? '';
          }

          byId[doc.id] = SavedPlace(
            id: doc.id,
            name: keep(existing?.name, data['name']?.toString()),
            subtitle: keep(existing?.subtitle, data['subtitle']?.toString()),
            description: keep(
              existing?.description,
              data['description']?.toString(),
            ),
            imageUrl: keep(existing?.imageUrl, data['imageUrl']?.toString()),
            lat: existing?.lat ?? lat,
            lng: existing?.lng ?? lng,
            types: (existing?.types.isNotEmpty ?? false)
                ? existing!.types
                : types,
            isFavorite: favorite || (existing?.isFavorite ?? false),
            isVisited: !favorite || (existing?.isVisited ?? false),
          );
        }
      } catch (_) {
        // best-effort: daca o colectie pica, aratam ce am apucat sa citim
      }
    }

    // favorite intai, ca un loc favorit+vizitat sa pastreze numele/poza salvate
    await read('favorites', favorite: true);
    await read('visited', favorite: false);
    return byId.values.toList();
  }
}

// Un loc din listele personale ale userului (favorite/vizitate). Tine si tipurile
// Places, ca sa-l putem clasifica pe tema, si flagurile pentru pinul de pe harta.
class SavedPlace {
  const SavedPlace({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.description,
    required this.imageUrl,
    required this.lat,
    required this.lng,
    required this.types,
    required this.isFavorite,
    required this.isVisited,
  });

  final String id;
  final String name;
  final String subtitle;
  final String description;
  final String imageUrl;
  final double? lat;
  final double? lng;
  final List<String> types;
  final bool isFavorite;
  final bool isVisited;

  bool get hasLocation => lat != null && lng != null;
}
