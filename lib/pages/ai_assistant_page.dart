import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../services/discover_themes.dart';

final ValueNotifier<List<AiMapPlace>> aiMapPlacesRequest =
    ValueNotifier<List<AiMapPlace>>(const []);

class AiAssistantPage extends StatefulWidget {
  const AiAssistantPage({super.key});

  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

class _AiAssistantPageState extends State<AiAssistantPage> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _speech = SpeechToText();
  final _tts = FlutterTts();

  final List<_ChatMessage> _messages = [];
  bool _isListening = false;
  bool _isLoading = false;
  bool _speechAvailable = false;
  bool _ttsEnabled = false;
  bool _english = false;
  String _partialText = '';

  // Comutatorul de context. ON (implicit): asistentul foloseste contextul personal
  // (locatie + profil de gusturi + locuri salvate/vizitate recent) ca sa
  // personalizeze recomandarile. OFF: ignora tot acest context si raspunde generic.
  bool _contextEnabled = true;

  // Locația curentă (reverse-geocodată) injectată în contextul AI, ca Gemini să
  // prioritizeze locuri apropiate. O luăm o singură dată per sesiune ca să nu
  // adăugăm latență/cereri la fiecare mesaj.
  String _locationArea = '';
  String _locationCoords = '';
  bool _locationTried = false;

  // Cheia Gemini NU mai există în client. Stă exclusiv pe server, ca secret
  // Firebase, iar apelul trece printr-o Cloud Function autentificată
  // (askGemini). Astfel cheia nu poate fi extrasă din APK sau din trafic.
  static const String _functionsRegion = 'europe-west1';

  // Câte mesaje din istoric trimitem la Gemini per apel. Plafonarea ține
  // costul și latența constante: fără ea, fiecare tură ar retrimite toată
  // conversația, care crește nelimitat. ~12 mesaje = ~6 schimburi, suficient
  // pentru continuitate fără să cărăm tot firul.
  static const int _maxHistoryMessages = 12;

  // Tipuri Google Places prea generice ca să spună ceva despre gust — apar la
  // aproape orice loc, așa că le excludem din profilul de gusturi ca top-ul să
  // reflecte categoriile care chiar diferențiază (muzeu, parc, biserică...).
  static const Set<String> _genericTypes = {
    'point_of_interest',
    'establishment',
    'premise',
    'geocode',
    'political',
    'tourist_attraction',
  };

  static const String _googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );
  static const String _googlePlacesApiKey = String.fromEnvironment(
    'GOOGLE_PLACES_API_KEY',
    defaultValue: '',
  );
  static const MethodChannel _platformKeys = MethodChannel(
    'com.example.see_the_world/keys',
  );
  String _placesApiKey = _googlePlacesApiKey.isNotEmpty
      ? _googlePlacesApiKey
      : _googleMapsApiKey;

  // Recuperăm tipurile lipsă din Place Details (cache pe sesiune + plafon de
  // apeluri), ca un favorit salvat fără `types` să conteze totuși în profil.
  final Map<String, List<String>> _typeCache = {};
  int _typeLookupCalls = 0;
  static const int _maxTypeLookups = 25;

  static const String _systemPromptRo =
      'Ești un asistent de călătorie care poate oferi recomandări pentru orice oraș sau țară din lume. '
      'Dacă îți este indicată locația curentă a utilizatorului, ține cont de ea și prioritizează recomandări relevante pentru zona respectivă, fără a te limita la o singură țară. '
      'Când utilizatorul îți descrie timpul disponibil, preferințele și interesele, '
      'oferi recomandări personalizate de destinații, locuri de vizitat, '
      'activități, rute și sfaturi practice. '
      'Răspunde întotdeauna în română. '
      'Fii concis dar informativ — oferă 3-5 recomandări specifice cu descrieri scurte. '
      'Dacă utilizatorul menționează tipul de vacanță (munte, mare, oraș, natură) și durata, '
      'adaptează recomandările exact la aceste criterii. '
      'Când recomanzi locuri, include și ce activități se pot face acolo.';

  static const String _systemPromptEn =
      'You are a travel assistant that can recommend places in any city or country in the world. '
      "If the user's current location is provided, take it into account and prioritize recommendations relevant to that area, without limiting yourself to a single country. "
      'When the user describes their available time, preferences and interests, '
      'you give personalized recommendations of destinations, places to visit, '
      'activities, routes and practical tips. '
      'Always reply in English. '
      'Be concise but informative — give 3-5 specific recommendations with short descriptions. '
      'If the user mentions the type of trip (mountains, seaside, city, nature) and the duration, '
      'adapt the recommendations exactly to these criteria. '
      'When recommending places, include what activities can be done there.';

  String get _systemPrompt => _english ? _systemPromptEn : _systemPromptRo;

  // Directiva culinara: cand userul cere unde sa manance, vrea restaurante (locale,
  // fast-food populare, pizza, gratar), nu cafenele. Fara ea, modelul tinde sa
  // amestece multe cafenele/coffee shop-uri.
  static const String _foodFocusRo =
      ' Când utilizatorul întreabă unde să mănânce sau cere recomandări culinare, '
      'prioritizează restaurante — inclusiv localuri tradiționale/locale, fast-food '
      'populare, pizzerii, grătare și restaurante apreciate —, NU cafenele sau '
      'coffee shop-uri. Poți menționa cel mult o cafenea, și doar dacă se potrivește '
      'cu ce a cerut utilizatorul.';
  static const String _foodFocusEn =
      ' When the user asks where to eat or for culinary recommendations, prioritize '
      'restaurants — including local/traditional spots, popular fast-food, pizza, '
      'grill and well-rated restaurants —, NOT cafes or coffee shops. Mention at '
      'most one cafe, and only if it fits what the user asked for.';
  String get _foodFocus => _english ? _foodFocusEn : _foodFocusRo;

  // Cerem un numar fix de recomandari, ca raspunsul sa fie mereu compact si
  // consistent (5 locuri).
  static const String _exactCountInstructionRo =
      ' Oferă exact 5 recomandări de locuri, nici mai multe, nici mai puține.';
  static const String _exactCountInstructionEn =
      ' Provide exactly 5 place recommendations, no more and no fewer.';
  String get _exactCountInstruction =>
      _english ? _exactCountInstructionEn : _exactCountInstructionRo;

  // Pusă ULTIMA în instrucțiune (recența contează): forțează limba chiar dacă
  // istoricul conversației e în cealaltă limbă, după ce utilizatorul comută.
  String get _languageDirective => _english
      ? ' Reply only in English, regardless of the language of previous messages.'
      : ' Răspunde doar în română, indiferent de limba mesajelor anterioare.';

  static const String _welcomeRo =
      'Salut! Sunt asistentul tău de călătorie AI. 🗺️\n\n'
      'Spune-mi câte zile ai libere, ce tip de destinație preferi '
      '(munte, mare, oraș, natură) și orice alte preferințe, '
      'iar eu îți voi oferi recomandări personalizate.\n\n'
      'Poți vorbi prin microfon sau scrie direct.';

  static const String _welcomeEn =
      "Hi! I'm your AI travel assistant. 🗺️\n\n"
      'Tell me how many days you have free, what type of destination you prefer '
      '(mountains, seaside, city, nature) and any other preferences, '
      'and I will give you personalized recommendations.\n\n'
      'You can speak through the microphone or type directly.';

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _initTts();
    _messages.add(
      const _ChatMessage(text: _welcomeRo, isUser: false, isWelcome: true),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _speech.stop();
    _tts.stop();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onError: (_) {
        if (mounted) setState(() => _isListening = false);
      },
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
    );
    if (mounted) setState(() => _speechAvailable = available);
  }

  Future<void> _initTts() async {
    await _tts.setLanguage(_english ? 'en-US' : 'ro-RO');
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  void _toggleLanguage() {
    setState(() {
      _english = !_english;
      // Dacă nu s-a început încă o conversație, actualizează mesajul de bun venit.
      if (_messages.length == 1 && _messages.first.isWelcome) {
        _messages[0] = _ChatMessage(
          text: _english ? _welcomeEn : _welcomeRo,
          isUser: false,
          isWelcome: true,
        );
      }
    });
    _tts.stop();
    _tts.setLanguage(_english ? 'en-US' : 'ro-RO');
  }

  void _toggleContext() {
    setState(() => _contextEnabled = !_contextEnabled);
    final String message;
    if (_contextEnabled) {
      message = _english
          ? 'Context on — recommendations are personalized to you.'
          : 'Context pornit — recomandările sunt personalizate pentru tine.';
    } else {
      message = _english
          ? 'Context off — the assistant replies generically.'
          : 'Context oprit — asistentul răspunde generic.';
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      if (_partialText.trim().isNotEmpty) {
        final text = _partialText.trim();
        _partialText = '';
        await _sendMessage(text);
      }
      return;
    }
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Recunoașterea vocală nu este disponibilă pe acest dispozitiv.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _isListening = true;
      _partialText = '';
    });
    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        setState(() => _partialText = result.recognizedWords);
        if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
          final text = result.recognizedWords.trim();
          _partialText = '';
          _isListening = false;
          _sendMessage(text);
        }
      },
      listenOptions: SpeechListenOptions(
        localeId: _english ? 'en_US' : 'ro_RO',
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (FirebaseAuth.instance.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _english
                ? 'Sign in to use the assistant.'
                : 'Autentifică-te ca să folosești asistentul.',
          ),
        ),
      );
      return;
    }

    _textController.clear();
    setState(() {
      _messages.add(_ChatMessage(text: trimmed, isUser: true));
      _isLoading = true;
    });
    _scrollToBottom();

    final result = await _callGemini();
    if (!mounted) return;
    if (result.text != null) {
      final aiMessage = _ChatMessage(text: result.text!, isUser: false);
      setState(() {
        _isLoading = false;
        _messages.add(aiMessage);
      });
      if (_ttsEnabled) _tts.speak(result.text!);
      _scrollToBottom();
      if (result.places.isNotEmpty) _resolvePlaces(aiMessage, result.places);
    } else {
      setState(() {
        _isLoading = false;
        _messages.add(
          _ChatMessage(
            text:
                result.error ??
                'Nu am putut obține un răspuns. Verifică conexiunea la internet.',
            isUser: false,
          ),
        );
      });
      _scrollToBottom();
    }
  }

  Future<void> _resolvePlaces(
    _ChatMessage message,
    List<({String name, String area})> raw,
  ) async {
    await _ensurePlacesApiKey();
    if (_placesApiKey.isEmpty) return;
    final resolved = <AiMapPlace>[];
    for (final p in raw) {
      final place = await _geocodePlace(p.name, p.area);
      if (place != null) resolved.add(place);
    }
    if (!mounted || resolved.isEmpty) return;
    final index = _messages.indexOf(message);
    if (index == -1) return;
    setState(() {
      _messages[index] = message.copyWith(places: resolved);
    });
    _scrollToBottom();
  }

  Future<void> _ensurePlacesApiKey() async {
    if (_placesApiKey.isNotEmpty) return;
    try {
      final key = await _platformKeys.invokeMethod<String>('getPlacesApiKey');
      if (key != null && key.isNotEmpty) _placesApiKey = key;
    } catch (_) {}
  }

  Future<AiMapPlace?> _geocodePlace(String name, String area) async {
    final input = Uri.encodeComponent(area.isEmpty ? name : '$name, $area');
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/findplacefromtext/json'
      '?input=$input&inputtype=textquery'
      '&fields=geometry,name,formatted_address,photos,place_id'
      '&key=$_placesApiKey',
    );
    try {
      final response = await http.get(url);
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List<dynamic>? ?? [];
      if (candidates.isEmpty) return null;
      final c = candidates.first as Map<String, dynamic>;
      final location =
          (c['geometry'] as Map<String, dynamic>?)?['location']
              as Map<String, dynamic>?;
      final lat = (location?['lat'] as num?)?.toDouble();
      final lng = (location?['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      final resolvedName = (c['name']?.toString().trim().isNotEmpty ?? false)
          ? c['name'].toString()
          : name;
      final address = c['formatted_address']?.toString() ?? '';
      final placeId = c['place_id']?.toString() ?? '';
      var photoUrl = '';
      final photos = c['photos'] as List<dynamic>?;
      if (photos != null && photos.isNotEmpty) {
        final ref = (photos.first as Map<String, dynamic>)['photo_reference']
            ?.toString();
        if (ref != null && ref.isNotEmpty) {
          photoUrl =
              'https://maps.googleapis.com/maps/api/place/photo'
              '?maxwidth=400&photoreference=$ref&key=$_placesApiKey';
        }
      }
      return AiMapPlace(
        name: resolvedName,
        area: area,
        address: address,
        lat: lat,
        lng: lng,
        placeId: placeId,
        photoUrl: photoUrl,
      );
    } catch (_) {
      return null;
    }
  }

  // Colectează semnalele utilizatorului (locație + profil de gusturi + nume
  // recente) cu care personalizăm recomandările asistentului.
  Future<_UserSignals> _collectSignals() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return _UserSignals.empty;

    final location = await _fetchLocationContext();
    final favorites = await _readPlaceEntries(user.uid, 'favorites');
    final visited = await _readPlaceEntries(user.uid, 'visited');

    // Profil de gusturi: numărăm tipurile Google Places din favorite + vizitate
    // (recuperate din Place Details când documentul n-are `types`) și păstrăm
    // primele 5 categorii după frecvență, ignorând tipurile generice.
    final categoryCounts = <String, int>{};
    for (final entry in [...favorites, ...visited]) {
      for (final type in await _usableTypes(entry.id, entry.types)) {
        categoryCounts[type] = (categoryCounts[type] ?? 0) + 1;
      }
    }
    final ranked = categoryCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topCategories = ranked
        .take(5)
        .map((e) => (type: e.key, count: e.value))
        .toList();

    // Până la 8 nume salvate recent (favorite întâi, apoi vizitate), fără dubluri.
    final recentNames = <String>[];
    for (final entry in [...favorites, ...visited]) {
      if (entry.name.isEmpty || recentNames.contains(entry.name)) continue;
      recentNames.add(entry.name);
      if (recentNames.length >= 8) break;
    }

    return _UserSignals(
      location: location,
      topCategories: topCategories,
      recentNames: recentNames,
    );
  }

  // Etichete lizibile ale celor 6 teme, ca profilul injectat să fie clar pentru
  // model — nu tipuri brute Google („church", „cafe"), ci categorii pe înțeles.
  static const Map<DiscoverTheme, String> _themeLabelRo = {
    DiscoverTheme.history: 'istorie și cultură (muzee, biserici, monumente)',
    DiscoverTheme.nature: 'natură (parcuri, grădini, peisaje)',
    DiscoverTheme.food: 'gastronomie (restaurante, localuri)',
    DiscoverTheme.entertainment: 'divertisment (cinema, teatru, distracție)',
    DiscoverTheme.hotels: 'cazare',
    DiscoverTheme.hiddenGems: 'atracții turistice',
  };
  static const Map<DiscoverTheme, String> _themeLabelEn = {
    DiscoverTheme.history: 'history & culture (museums, churches, monuments)',
    DiscoverTheme.nature: 'nature (parks, gardens, scenery)',
    DiscoverTheme.food: 'food (restaurants, eateries)',
    DiscoverTheme.entertainment: 'entertainment (cinema, theater, fun)',
    DiscoverTheme.hotels: 'lodging',
    DiscoverTheme.hiddenGems: 'tourist attractions',
  };

  // Agregă tipurile brute din profil pe cele 6 teme Discover și le întoarce
  // ordonate descrescător, cu ponderea 0..1 a fiecăreia. E semnalul „tare" din
  // prompt: teme clare, nu tipuri răzlețe care se pierd lângă locație + întrebare.
  List<MapEntry<DiscoverTheme, double>> _profileThemes(_UserSignals s) {
    final counts = <DiscoverTheme, int>{};
    var total = 0;
    for (final c in s.topCategories) {
      final theme = themeForTypes([c.type]);
      if (theme == null) continue;
      counts[theme] = (counts[theme] ?? 0) + c.count;
      total += c.count;
    }
    if (total == 0) return const [];
    final ranked = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in ranked) MapEntry(e.key, e.value / total)];
  }

  // Contextul de personalizare injectat în prompt: locație + profil de gusturi +
  // locuri recente. Se construiește doar cât timp comutatorul de context e ON
  // (vezi _contextEnabled / _callGemini); pe OFF asistentul răspunde generic.
  String _contextText(_UserSignals s) {
    final themes = _profileThemes(s);
    final hasTaste = themes.isNotEmpty;
    final hasRecent = s.recentNames.isNotEmpty;
    if (s.location.isEmpty && !hasTaste && !hasRecent) return '';

    final buffer = StringBuffer();
    if (_english) {
      buffer.write(
        '\n\nUser personalization context — use it to silently tailor every '
        'recommendation. Do NOT mention these preferences explicitly to the user.',
      );
      if (s.location.isNotEmpty) {
        buffer.write(
          '\n- The user is currently ${s.location}. Prioritize places near this '
          'location and reachable within the time the user says they have '
          'available; estimate realistic travel time and do not suggest '
          'destinations too far for their time budget.',
        );
      }
      if (hasTaste) {
        final formatted = themes
            .map((e) => '${_themeLabelEn[e.key]} ${(e.value * 100).round()}%')
            .join(', ');
        final topLabels =
            themes.take(2).map((e) => _themeLabelEn[e.key]).join(' and ');
        final firstLabel = _themeLabelEn[themes.first.key];
        final rawTypes =
            s.topCategories.map((e) => '${e.type} (${e.count})').join(', ');
        buffer.write(
          '\n- Taste profile, inferred from the places the user saves and visits, '
          'ranked by weight: $formatted. This is the MOST important signal — it '
          'outweighs generic popularity. At least 3 of your 5 recommendations MUST '
          'belong to the dominant categories ($topLabels), and the FIRST one must '
          'be $firstLabel. Only the remaining recommendations may fall outside '
          'these. (Underlying place types: $rawTypes.)',
        );
      }
      if (hasRecent) {
        buffer.write(
          '\n- Places the user recently saved or visited: ${s.recentNames.join(", ")}. '
          'Do NOT recommend these same places again; suggest fresh ones instead.',
        );
      }
    } else {
      buffer.write(
        '\n\nContext de personalizare despre utilizator — folosește-l ca să '
        'adaptezi discret fiecare recomandare. NU menționa explicit aceste '
        'preferințe utilizatorului.',
      );
      if (s.location.isNotEmpty) {
        buffer.write(
          '\n- Utilizatorul se află acum ${s.location}. Prioritizează locuri '
          'apropiate de această poziție și care pot fi atinse în timpul pe care '
          'spune că îl are la dispoziție; estimează realist timpul de deplasare '
          'și nu sugera destinații prea îndepărtate pentru timpul lui.',
        );
      }
      if (hasTaste) {
        final formatted = themes
            .map((e) => '${_themeLabelRo[e.key]} ${(e.value * 100).round()}%')
            .join(', ');
        final topLabels =
            themes.take(2).map((e) => _themeLabelRo[e.key]).join(' și ');
        final firstLabel = _themeLabelRo[themes.first.key];
        final rawTypes =
            s.topCategories.map((e) => '${e.type} (${e.count})').join(', ');
        buffer.write(
          '\n- Profil de gust, dedus din locurile pe care utilizatorul le salvează '
          'și vizitează, ordonat după pondere: $formatted. Acesta e cel MAI '
          'important semnal — contează mai mult decât popularitatea generică. Cel '
          'puțin 3 din cele 5 recomandări TREBUIE să fie din categoriile dominante '
          '($topLabels), iar PRIMA să fie din $firstLabel. Doar restul pot ieși din '
          'aceste categorii. (Tipuri de loc în detaliu: $rawTypes.)',
        );
      }
      if (hasRecent) {
        buffer.write(
          '\n- Locuri salvate sau vizitate recent: ${s.recentNames.join(", ")}. '
          'NU recomanda din nou aceleași locuri; sugerează altele noi.',
        );
      }
    }
    return buffer.toString();
  }

  // Citim fără orderBy: dacă un document n-are câmpul de timp, orderBy l-ar fi
  // scos tăcut și profilul ar ieși gol. Întoarcem și id-ul (place_id) ca să
  // putem recupera tipurile lipsă din Place Details.
  Future<List<({String id, String name, List<String> types})>> _readPlaceEntries(
    String uid,
    String collection,
  ) async {
    final entries = <({String id, String name, List<String> types})>[];
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection(collection)
          .limit(50)
          .get();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final name = data['name']?.toString().trim() ?? '';
        final rawTypes = data['types'];
        final types = rawTypes is List
            ? rawTypes.map((e) => e.toString()).toList()
            : <String>[];
        entries.add((id: doc.id, name: name, types: types));
      }
    } catch (_) {}
    return entries;
  }

  // Tipurile relevante ale unui loc: din `types` stocat dacă mai rămâne ceva
  // după scoaterea celor generice; altfel le cerem din Place Details după id.
  Future<List<String>> _usableTypes(String id, List<String> stored) async {
    final fromStored = stored.where((t) => !_genericTypes.contains(t)).toList();
    if (fromStored.isNotEmpty) return fromStored;
    final fetched = await _fetchTypesByPlaceId(id);
    return fetched.where((t) => !_genericTypes.contains(t)).toList();
  }

  // Tipurile unui place_id din Place Details. Sărim id-urile AI (nu sunt
  // place_id reale) și plafonăm apelurile ca să nu ardem quota.
  Future<List<String>> _fetchTypesByPlaceId(String id) async {
    if (_typeCache.containsKey(id)) return _typeCache[id]!;
    if (id.startsWith('ai-') || id.length < 20) return const [];
    await _ensurePlacesApiKey();
    if (_placesApiKey.isEmpty || _typeLookupCalls >= _maxTypeLookups) {
      return const [];
    }
    _typeLookupCalls++;
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=$id&fields=types&key=$_placesApiKey',
      );
      final response = await http.get(url);
      if (response.statusCode != 200) return const [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final result = data['result'] as Map<String, dynamic>?;
      final types =
          (result?['types'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[];
      _typeCache[id] = types;
      return types;
    } catch (_) {
      return const [];
    }
  }

  // Locația curentă pentru contextul AI. Returnează o expresie gata de inserat
  // (ex. „în zona Timișoara, Timiș, România (lat, lng)") sau '' dacă nu avem
  // permisiune/poziție. O luăm o singură dată per sesiune; dacă utilizatorul
  // refuză permisiunea, nu mai insistăm.
  Future<String> _fetchLocationContext() async {
    if (!_locationTried) {
      _locationTried = true;
      try {
        if (await _ensureLocationPermissionSilent()) {
          Position? pos = await Geolocator.getLastKnownPosition();
          pos ??= await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 8),
            ),
          );
          _locationCoords =
              'lat ${pos.latitude.toStringAsFixed(4)}, '
              'lng ${pos.longitude.toStringAsFixed(4)}';
          _locationArea = await _reverseGeocode(pos.latitude, pos.longitude);
        }
      } catch (_) {
        // Context de locație opțional: dacă pică (timeout, GPS oprit), mergem fără el.
      }
    }
    if (_locationCoords.isEmpty) return '';
    final coords = '($_locationCoords)';
    if (_locationArea.isEmpty) {
      return _english ? 'at coordinates $coords' : 'la coordonatele $coords';
    }
    return _english
        ? 'near $_locationArea $coords'
        : 'în zona $_locationArea $coords';
  }

  Future<bool> _ensureLocationPermissionSilent() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission != LocationPermission.denied &&
        permission != LocationPermission.deniedForever;
  }

  // Transformă coordonatele într-o zonă lizibilă (oraș, județ, țară) prin
  // Geocoding API, cu aceeași cheie Places. Returnează '' la orice eroare.
  Future<String> _reverseGeocode(double lat, double lng) async {
    await _ensurePlacesApiKey();
    if (_placesApiKey.isEmpty) return '';
    final lang = _english ? 'en' : 'ro';
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/geocode/json'
      '?latlng=$lat,$lng&language=$lang&key=$_placesApiKey',
    );
    try {
      final response = await http.get(url);
      if (response.statusCode != 200) return '';
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>? ?? [];
      if (results.isEmpty) return '';
      final components =
          (results.first as Map<String, dynamic>)['address_components']
              as List<dynamic>? ??
          [];
      String pick(String type) {
        for (final c in components) {
          final types = (c as Map<String, dynamic>)['types'] as List<dynamic>?;
          if (types != null && types.contains(type)) {
            return c['long_name']?.toString() ?? '';
          }
        }
        return '';
      }

      final city = [
        pick('locality'),
        pick('postal_town'),
        pick('administrative_area_level_2'),
      ].firstWhere((s) => s.isNotEmpty, orElse: () => '');
      final county = pick('administrative_area_level_1');
      final country = pick('country');
      final parts = [city, county, country].where((p) => p.isNotEmpty).toList();
      return parts.join(', ');
    } catch (_) {
      return '';
    }
  }

  Future<_GeminiResult> _callGemini() async {
    // Cu contextul oprit nici nu mai colectam semnalele (locatie/profil): trimitem
    // doar promptul + conversatia, ca raspunsul sa fie complet generic.
    final contextUsed = _contextEnabled
        ? _contextText(await _collectSignals())
        : '';
    try {
      // _messages conține deja întreaga conversație, inclusiv mesajul tocmai
      // trimis de utilizator (adăugat în _sendMessage), așa că NU îl mai adăugăm
      // încă o dată — altfel ultima tură 'user' ajungea dublată în request.
      final allContents = <Map<String, dynamic>>[];
      for (final m in _messages) {
        if (m.isWelcome) continue;
        allContents.add({
          'role': m.isUser ? 'user' : 'model',
          'parts': [
            {'text': m.text},
          ],
        });
      }

      // Trimitem doar ultimele _maxHistoryMessages mesaje (mesajul curent e
      // ultimul, deci mereu inclus). Gemini cere ca primul element să aibă
      // rolul 'user', așa că după tăiere eliminăm un eventual 'model' rămas
      // în frunte.
      final start = allContents.length > _maxHistoryMessages
          ? allContents.length - _maxHistoryMessages
          : 0;
      final contents = allContents.sublist(start);
      while (contents.isNotEmpty && contents.first['role'] == 'model') {
        contents.removeAt(0);
      }

      final systemInstruction =
          _systemPrompt + _foodFocus + contextUsed + _exactCountInstruction + _languageDirective;

      // Apelul nu mai conține cheia API. Cloud Function-ul autentificat
      // (askGemini) o ține pe server și vorbește el cu Gemini.
      final callable = FirebaseFunctions.instanceFor(region: _functionsRegion)
          .httpsCallable(
            'askGemini',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
          );
      final response = await callable.call<Map<String, dynamic>>({
        'systemInstruction': systemInstruction,
        'contents': contents,
      });

      final text = response.data['text']?.toString();
      if (text == null || text.isEmpty) {
        return const _GeminiResult(
          text: null,
          places: [],
          error: 'Răspuns gol de la asistent.',
        );
      }
      final rawPlaces = response.data['places'];
      final places = <({String name, String area})>[];
      if (rawPlaces is List) {
        for (final item in rawPlaces) {
          if (item is Map) {
            final name = item['name']?.toString().trim() ?? '';
            if (name.isEmpty) continue;
            final area = item['area']?.toString().trim() ?? '';
            places.add((name: name, area: area));
          }
        }
      }
      return _GeminiResult(text: text, places: places, error: null);
    } on FirebaseFunctionsException catch (e) {
      // Includem și codul (not-found, unauthenticated, unavailable...) ca să fie
      // ușor de diagnosticat. 'not-found' = funcția nu e deployată / regiune greșită.
      final detail = e.message ?? 'fără detalii';
      return _GeminiResult(
        text: null,
        places: const [],
        error: 'Eroare asistent [${e.code}]: $detail',
      );
    } catch (e) {
      return _GeminiResult(text: null, places: const [], error: 'Excepție: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildPlacesCard(_ChatMessage message, bool isDark) {
    final places = message.places;
    return Container(
      margin: const EdgeInsets.only(right: 48, top: 2, bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 180,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: LatLng(places.first.lat, places.first.lng),
                zoom: 11,
              ),
              markers: _markersForPlaces(places),
              onMapCreated: (controller) => _fitToPlaces(controller, places),
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              scrollGesturesEnabled: false,
              zoomGesturesEnabled: false,
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
              liteModeEnabled: false,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 2,
              children: [
                for (final place in places)
                  ActionChip(
                    avatar: const Icon(Icons.place, size: 16),
                    label: Text(place.name),
                    onPressed: () => _showAiPlaceDetails(place),
                  ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                aiMapPlacesRequest.value = places;
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              icon: const Icon(Icons.map_outlined, size: 18),
              label: Text(
                _english ? 'See on the big map' : 'Vezi pe harta mare',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Set<Marker> _markersForPlaces(List<AiMapPlace> places) {
    final markers = <Marker>{};
    for (var i = 0; i < places.length; i++) {
      final place = places[i];
      final id = place.placeId.isNotEmpty ? place.placeId : 'ai-$i';
      markers.add(
        Marker(
          markerId: MarkerId(id),
          position: LatLng(place.lat, place.lng),
          infoWindow: InfoWindow(title: place.name),
          onTap: () => _showAiPlaceDetails(place),
        ),
      );
    }
    return markers;
  }

  Future<void> _fitToPlaces(
    GoogleMapController controller,
    List<AiMapPlace> places,
  ) async {
    if (places.length == 1) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(places.first.lat, places.first.lng),
          12,
        ),
      );
      return;
    }
    var minLat = places.first.lat;
    var maxLat = places.first.lat;
    var minLng = places.first.lng;
    var maxLng = places.first.lng;
    for (final p in places.skip(1)) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lng < minLng) minLng = p.lng;
      if (p.lng > maxLng) maxLng = p.lng;
    }
    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    try {
      await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 48));
    } catch (_) {}
  }

  void _showAiPlaceDetails(AiMapPlace place) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (place.photoUrl.isNotEmpty)
                Image.network(
                  place.photoUrl,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  // ignore: unnecessary_underscores
                  errorBuilder: (_, __, ___) => Container(
                    height: 180,
                    color: Colors.grey.shade300,
                    child: const Center(
                      child: Icon(Icons.photo, color: Colors.black45),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (place.address.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.place_outlined, size: 16),
                          const SizedBox(width: 4),
                          Expanded(child: Text(place.address)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(_english ? 'Close' : 'Închide'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy_outlined, size: 22),
            SizedBox(width: 8),
            Flexible(
              child: Text('AI Assistant', overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _toggleLanguage,
            style: TextButton.styleFrom(
              minimumSize: const Size(40, 40),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(
              _english ? 'EN' : 'RO',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          // Comutator ON/OFF pentru contextul personal al asistentului.
          IconButton(
            icon: Icon(
              _contextEnabled
                  ? Icons.person_pin_circle
                  : Icons.person_off_outlined,
            ),
            tooltip: _contextEnabled
                ? (_english ? 'Context: ON' : 'Context: PORNIT')
                : (_english ? 'Context: OFF' : 'Context: OPRIT'),
            onPressed: _toggleContext,
          ),
          IconButton(
            icon: Icon(_ttsEnabled ? Icons.volume_up : Icons.volume_off),
            tooltip: _ttsEnabled ? 'Dezactivează vocea' : 'Activează vocea',
            onPressed: () {
              setState(() => _ttsEnabled = !_ttsEnabled);
              if (!_ttsEnabled) _tts.stop();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return const _TypingIndicator();
                }
                final message = _messages[index];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _MessageBubble(message: message, isDark: isDark),
                    if (!message.isUser && message.places.isNotEmpty)
                      _buildPlacesCard(message, isDark),
                  ],
                );
              },
            ),
          ),
          if (_isListening && _partialText.isNotEmpty)
            Container(
              width: double.infinity,
              color: isDark ? Colors.blue.shade900 : Colors.blue.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.mic,
                    size: 16,
                    color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _partialText,
                      style: TextStyle(
                        color: isDark
                            ? Colors.blue.shade300
                            : Colors.blue.shade700,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          _buildInputBar(isDark),
        ],
      ),
    );
  }

  Widget _buildInputBar(bool isDark) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey.shade900 : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: _sendMessage,
                decoration: InputDecoration(
                  hintText: _english
                      ? 'E.g. I have 2 days and want mountains...'
                      : 'Ex: Am 2 zile și vreau la munte...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: isDark
                      ? Colors.grey.shade800
                      : Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _MicButton(isListening: _isListening, onTap: _toggleListening),
            const SizedBox(width: 4),
            IconButton(
              style: IconButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
              ),
              icon: const Icon(Icons.send, size: 20),
              onPressed: _isLoading
                  ? null
                  : () => _sendMessage(_textController.text),
            ),
          ],
        ),
      ),
    );
  }
}

// Semnalele utilizatorului folosite ca să personalizăm recomandările: locație +
// profil de gusturi + nume recente.
class _UserSignals {
  const _UserSignals({
    required this.location,
    required this.topCategories,
    required this.recentNames,
  });

  final String location;
  // top-5 categorii (tip Google Places + nr. apariții) din favorite + vizitate
  final List<({String type, int count})> topCategories;
  final List<String> recentNames;

  static const empty = _UserSignals(
    location: '',
    topCategories: [],
    recentNames: [],
  );
}

class _GeminiResult {
  const _GeminiResult({
    required this.text,
    required this.places,
    required this.error,
  });
  final String? text;
  final List<({String name, String area})> places;
  final String? error;
}

class _ChatMessage {
  const _ChatMessage({
    required this.text,
    required this.isUser,
    this.isWelcome = false,
    this.places = const [],
  });
  final String text;
  final bool isUser;
  final bool isWelcome;
  final List<AiMapPlace> places;

  _ChatMessage copyWith({List<AiMapPlace>? places}) {
    return _ChatMessage(
      text: text,
      isUser: isUser,
      isWelcome: isWelcome,
      places: places ?? this.places,
    );
  }
}

class AiMapPlace {
  const AiMapPlace({
    required this.name,
    required this.area,
    required this.address,
    required this.lat,
    required this.lng,
    required this.placeId,
    required this.photoUrl,
  });
  final String name;
  final String area;
  final String address;
  final double lat;
  final double lng;
  final String placeId;
  final String photoUrl;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isDark});
  final _ChatMessage message;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 4,
          bottom: 4,
          left: isUser ? 48 : 0,
          right: isUser ? 0 : 48,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser
              ? Colors.blue
              : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: isUser
                ? Colors.white
                : (isDark ? Colors.white : Colors.black87),
            fontSize: 15,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
          ),
        ),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final delay = i / 3;
              final opacity = ((_ctrl.value - delay).abs() < 0.4)
                  ? 0.3 + 0.7 * _ctrl.value
                  : 0.3;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white54 : Colors.grey.shade500)
                      .withValues(alpha: opacity.clamp(0.3, 1.0)),
                  shape: BoxShape.circle,
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({required this.isListening, required this.onTap});
  final bool isListening;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isListening ? Colors.red : Colors.blue.shade700,
          boxShadow: isListening
              ? [
                  BoxShadow(
                    color: Colors.red.withValues(alpha: 0.45),
                    blurRadius: 14,
                    spreadRadius: 3,
                  ),
                ]
              : [],
        ),
        child: Icon(
          isListening ? Icons.stop : Icons.mic,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }
}
