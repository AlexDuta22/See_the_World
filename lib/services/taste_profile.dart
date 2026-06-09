import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import 'discover_themes.dart';

// Profilul de gust: numaram temele din locurile salvate si vizitate.
class TasteProfile {
  const TasteProfile({
    required this.counts,
    required this.rankedThemes,
    required this.classifiedPlaces,
  });

  // cate locuri pe fiecare tema
  final Map<DiscoverTheme, int> counts;

  // temele ordonate dupa numar
  final List<DiscoverTheme> rankedThemes;

  // cate locuri am reusit sa clasificam
  final int classifiedPlaces;

  bool get hasHistory => classifiedPlaces >= 3;

  List<DiscoverTheme> get topThemes => rankedThemes.take(3).toList();

  static const empty = TasteProfile(
    counts: {},
    rankedThemes: [],
    classifiedPlaces: 0,
  );
}

class TasteProfileService {
  TasteProfileService({required this.placesApiKey});

  final String placesApiKey;

  // limitam cererile Place Details ca sa nu ardem quota
  static const int _maxDetailLookups = 25;

  final Map<String, List<String>> _typeCache = {};
  int _detailCalls = 0;

  Future<TasteProfile> build(String uid) async {
    final favorites = await _readDocs(uid, 'favorites');
    final visited = await _readDocs(uid, 'visited');

    final counts = <DiscoverTheme, int>{};
    var classified = 0;

    for (final doc in [...favorites, ...visited]) {
      final types = await _typesForDoc(doc);
      if (types.isEmpty) continue;
      final theme = themeForTypes(types);
      if (theme == null) continue;
      counts[theme] = (counts[theme] ?? 0) + 1;
      classified++;
    }

    final ranked = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));

    return TasteProfile(
      counts: counts,
      rankedThemes: ranked,
      classifiedPlaces: classified,
    );
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _readDocs(
    String uid,
    String collection,
  ) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection(collection)
          .limit(50)
          .get();
      return snapshot.docs;
    } catch (_) {
      return const [];
    }
  }

  // tipurile locului: din campul `types` daca exista, altfel din Place Details
  // dupa place_id (documentele vechi nu au `types`)
  Future<List<String>> _typesForDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final stored = doc.data()['types'];
    if (stored is List && stored.isNotEmpty) {
      return stored.map((e) => e.toString()).toList();
    }
    return _fetchTypesByPlaceId(doc.id);
  }

  Future<List<String>> _fetchTypesByPlaceId(String id) async {
    if (_typeCache.containsKey(id)) return _typeCache[id]!;
    if (placesApiKey.isEmpty || !_looksLikePlaceId(id)) return const [];
    if (_detailCalls >= _maxDetailLookups) return const [];
    _detailCalls++;

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=$id&fields=types&key=$placesApiKey',
      );
      final response = await http.get(url);
      if (response.statusCode != 200) return const [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final result = data['result'] as Map<String, dynamic>?;
      final types =
          (result?['types'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          const <String>[];
      _typeCache[id] = types;
      return types;
    } catch (_) {
      return const [];
    }
  }

  // markerele AI au id-uri „ai-...”; le sarim. restul le incercam ca place_id
  bool _looksLikePlaceId(String id) {
    if (id.startsWith('ai-')) return false;
    return id.length >= 20;
  }
}
