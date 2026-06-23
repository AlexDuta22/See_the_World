import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// Temele Discover. Restul (culori, tipuri Places) se derivă din enum mai jos.
enum DiscoverTheme { history, nature, food, entertainment, hotels, hiddenGems }

class DiscoverThemeInfo {
  const DiscoverThemeInfo({
    required this.label,
    required this.icon,
    required this.color,
    required this.markerHue,
    required this.nearbyTypes,
  });

  final String label;
  final IconData icon;
  final Color color;

  // nuanta pinului pe harta
  final double markerHue;

  // tipurile cerute la Nearby Search pentru tema asta
  final List<String> nearbyTypes;
}

const Map<DiscoverTheme, DiscoverThemeInfo> kThemeInfo = {
  DiscoverTheme.history: DiscoverThemeInfo(
    label: 'History',
    icon: Icons.account_balance_outlined,
    color: Color(0xFF1565C0),
    markerHue: BitmapDescriptor.hueAzure,
    // Bisericile/catedralele/sinagogile au trecut aici (patrimoniu cultural),
    // asa ca le cerem si pe ele, nu doar muzeele.
    nearbyTypes: ['museum', 'church', 'tourist_attraction'],
  ),
  DiscoverTheme.nature: DiscoverThemeInfo(
    label: 'Nature',
    icon: Icons.park_outlined,
    color: Color(0xFF2E7D32),
    markerHue: BitmapDescriptor.hueGreen,
    nearbyTypes: ['park'],
  ),
  DiscoverTheme.food: DiscoverThemeInfo(
    label: 'Food',
    icon: Icons.restaurant,
    color: Color(0xFFEF6C00),
    markerHue: BitmapDescriptor.hueOrange,
    // Cerem si meal_takeaway (fast-food/la pachet), nu doar restaurant+cafe, ca
    // sa intre in pool si localurile populare de mancare rapida. Cafe ramane, dar
    // e tinut in frau de prioritatea sub-categoriei la ranking (vezi foodPriority).
    nearbyTypes: ['restaurant', 'meal_takeaway', 'cafe'],
  ),
  DiscoverTheme.entertainment: DiscoverThemeInfo(
    label: 'Entertainment',
    icon: Icons.local_activity_outlined,
    color: Color(0xFF6A1B9A),
    markerHue: BitmapDescriptor.hueViolet,
    // Distractie: cinema, parc de distractii, bowling. Strandurile, locurile de
    // joaca si teatrul (live) nu exista ca tip in API-ul legacy, deci le aducem
    // din Text Search (vezi _themeTextQuery).
    nearbyTypes: ['movie_theater', 'amusement_park', 'bowling_alley'],
  ),
  DiscoverTheme.hotels: DiscoverThemeInfo(
    label: 'Hotels',
    icon: Icons.hotel_outlined,
    color: Color(0xFFAD1457),
    markerHue: BitmapDescriptor.hueRose,
    nearbyTypes: ['lodging'],
  ),
  DiscoverTheme.hiddenGems: DiscoverThemeInfo(
    label: 'Hidden gems',
    icon: Icons.auto_awesome_outlined,
    color: Color(0xFF00838F),
    markerHue: BitmapDescriptor.hueCyan,
    nearbyTypes: ['tourist_attraction'],
  ),
};

DiscoverThemeInfo themeInfo(DiscoverTheme theme) => kThemeInfo[theme]!;

// tip Places -> tema, pentru numaratul din profilul de gust
const Map<String, DiscoverTheme> _typeToTheme = {
  // History (lacasurile de cult au trecut aici, ca patrimoniu cultural)
  'museum': DiscoverTheme.history,
  'art_gallery': DiscoverTheme.history,
  'library': DiscoverTheme.history,
  'cemetery': DiscoverTheme.history,
  'city_hall': DiscoverTheme.history,
  'courthouse': DiscoverTheme.history,
  'local_government_office': DiscoverTheme.history,
  'church': DiscoverTheme.history,
  'place_of_worship': DiscoverTheme.history,
  'hindu_temple': DiscoverTheme.history,
  'mosque': DiscoverTheme.history,
  'synagogue': DiscoverTheme.history,
  // Entertainment (divertisment)
  'movie_theater': DiscoverTheme.entertainment,
  'amusement_park': DiscoverTheme.entertainment,
  'water_park': DiscoverTheme.entertainment,
  'bowling_alley': DiscoverTheme.entertainment,
  'playground': DiscoverTheme.entertainment,
  'performing_arts_theater': DiscoverTheme.entertainment,
  // Nature
  'park': DiscoverTheme.nature,
  'natural_feature': DiscoverTheme.nature,
  'campground': DiscoverTheme.nature,
  'rv_park': DiscoverTheme.nature,
  // Food
  'restaurant': DiscoverTheme.food,
  'cafe': DiscoverTheme.food,
  'coffee_shop': DiscoverTheme.food,
  'bakery': DiscoverTheme.food,
  'bar': DiscoverTheme.food,
  'meal_takeaway': DiscoverTheme.food,
  'meal_delivery': DiscoverTheme.food,
  'fast_food': DiscoverTheme.food,
  'food_court': DiscoverTheme.food,
  // Hotels
  'lodging': DiscoverTheme.hotels,
};

// prima tema care se potriveste cu tipurile locului
DiscoverTheme? themeForTypes(Iterable<String> types) {
  for (final t in types) {
    final theme = _typeToTheme[t];
    if (theme != null) return theme;
  }
  return null;
}

// Cat de bine se potriveste un loc cu profilul de gust (0..1). Mapam fiecare tip
// al locului pe tema lui si luam ponderea cea mai mare din profil: locul „se
// potriveste" cat de mult conteaza pentru user tema lui preponderenta. Profilul e
// gol pana cand userul are istoric, caz in care intoarcem 0 (nicio preferinta).
double profileMatchScore(
  Iterable<String> placeTypes,
  Map<DiscoverTheme, double> profileWeights,
) {
  if (profileWeights.isEmpty) return 0;
  var best = 0.0;
  for (final type in placeTypes) {
    final theme = themeForTypes([type]);
    if (theme == null) continue;
    final weight = profileWeights[theme] ?? 0;
    if (weight > best) best = weight;
  }
  return best.clamp(0.0, 1.0);
}

// utilitati/comert/industrie pe care nu le vrem niciodata ca destinatie
// (lodging lipseste intentionat: e tinta temei Hotels)
const Set<String> kJunkTypes = {
  'gas_station',
  'fuel',
  'car_rental',
  'car_repair',
  'car_dealer',
  'car_wash',
  'atm',
  'bank',
  'pharmacy',
  'convenience_store',
  'supermarket',
  'parking',
  'storage',
  'moving_company',
  'general_contractor',
  'hardware_store',
  'home_goods_store',
  'electrician',
  'plumber',
  'casino',
  'night_club',
  'liquor_store',
  'shopping_mall',
};

// Tipuri Google Places care chiar inseamna obiectiv turistic. Sunt baza listei
// ALBE de mai jos.
const Set<String> kTourismTypes = {
  'tourist_attraction',
  'museum',
  'art_gallery',
  'church',
  'place_of_worship',
  'hindu_temple',
  'mosque',
  'synagogue',
  'park',
  'national_park',
  'natural_feature',
  'zoo',
  'aquarium',
  'amusement_park',
  'city_hall',
  'courthouse',
  'library',
  'stadium',
};

// Sub-categoriile temei Food, dupa intentie. Cand cineva alege „Food" / intreaba
// unde sa manance, vrea in primul rand o masa (restaurant), nu o cafea. Pastram 3
// niveluri de prioritate. Tipurile granulare (pizza_restaurant, steak_house...)
// apar in `types` pe rezultate chiar daca Nearby legacy nu le accepta ca parametru
// de cautare, deci le folosim la clasificare/ranking.

// Prioritate MARE: locuri unde mananci o masa propriu-zisa.
const Set<String> kRestaurantTypes = {
  'restaurant',
  'meal_takeaway',
  'meal_delivery',
  'fast_food',
  'fast_food_restaurant',
  'pizza_restaurant',
  'hamburger_restaurant',
  'burger_restaurant',
  'steak_house',
  'seafood_restaurant',
  'barbecue_restaurant',
  'grill_restaurant',
  'sandwich_shop',
};

// Prioritate MEDIE: tot pentru masa, dar mai informal.
const Set<String> kMidFoodTypes = {
  'food_court',
  'diner',
  'bistro',
};

// Prioritate MICA: bauturi/desert, nu o masa.
const Set<String> kCafeTypes = {
  'cafe',
  'coffee_shop',
  'cafeteria',
  'bakery',
  'bar',
  'ice_cream_shop',
  'tea_house',
};

// Tipuri valide pentru tema Food (restaurante & co.) = reuniunea celor 3 niveluri.
const Set<String> kFoodTypes = {
  ...kRestaurantTypes,
  ...kMidFoodTypes,
  ...kCafeTypes,
};

// Prioritate 0..1 a unui loc in tema Food, dupa cat de mult e „o masa".
// restaurant/fast-food = 1.0 > food court/diner = 0.6 > cafenea = 0.25. Asa
// restaurantele trec inaintea cafenelelor cand userul cauta unde sa manance.
double foodPriority(Iterable<String> types) {
  final set = types.toSet();
  if (set.intersection(kRestaurantTypes).isNotEmpty) return 1.0;
  if (set.intersection(kMidFoodTypes).isNotEmpty) return 0.6;
  if (set.intersection(kCafeTypes).isNotEmpty) return 0.25;
  return 0.5; // tip food fara sub-categorie clara: la mijloc
}

// Cafenea „pura": are tip de cafenea/bar/cofetarie si NU are si tip de restaurant.
// Folosit ca sa plafonam cafenelele in rezultatul Food.
bool isCafeLike(Iterable<String> types) {
  final set = types.toSet();
  return set.intersection(kCafeTypes).isNotEmpty &&
      set.intersection(kRestaurantTypes).isEmpty;
}

// Lista ALBA per tema: un loc trece doar daca are CEL PUTIN un tip de aici.
// Inainte filtrul era o lista neagra (respingea cateva tipuri si accepta restul),
// asa ca locurile cu tipuri generice goale — doar „establishment"/
// „point_of_interest" (centre de fier vechi, firme, hale industriale) — treceau.
// Acum cerem explicit un tip cu valoare turistica.
const Map<DiscoverTheme, Set<String>> _allowedTypesByTheme = {
  DiscoverTheme.history: {
    'museum',
    'art_gallery',
    'library',
    'city_hall',
    'courthouse',
    'tourist_attraction',
    // lacasurile de cult au trecut la History
    'church',
    'place_of_worship',
    'mosque',
    'synagogue',
    'hindu_temple',
  },
  DiscoverTheme.nature: {
    'park',
    'national_park',
    'natural_feature',
    'zoo',
    'aquarium',
    'amusement_park',
    'campground',
    'tourist_attraction',
  },
  DiscoverTheme.food: kFoodTypes,
  DiscoverTheme.entertainment: {
    'movie_theater',
    'amusement_park',
    'water_park',
    'bowling_alley',
    'playground',
    'performing_arts_theater',
    'tourist_attraction',
  },
  DiscoverTheme.hotels: {'lodging'},
  DiscoverTheme.hiddenGems: kTourismTypes,
};

// Entitati geografice/administrative: orase, sate, cartiere, zone, strazi.
// NU sunt destinatii punctuale, chiar daca Google le mai taggeaza si cu
// „tourist_attraction" (asa aparea Sânleani — un sat — la History).
const Set<String> kGeoTypes = {
  'locality',
  'sublocality',
  'sublocality_level_1',
  'sublocality_level_2',
  'neighborhood',
  'political',
  'administrative_area_level_1',
  'administrative_area_level_2',
  'administrative_area_level_3',
  'postal_code',
  'route',
  'street_address',
  'colloquial_area',
  'country',
  'continent',
  'intersection',
  'plus_code',
};

bool isAllowedForTheme(Set<String> placeTypes, DiscoverTheme theme) {
  // Lista neagra dura: niciodata utilitati/comert/industrie, indiferent de tema.
  if (placeTypes.intersection(kJunkTypes).isNotEmpty) return false;
  // Niciodata orase/sate/zone (entitati geografice).
  if (placeTypes.intersection(kGeoTypes).isNotEmpty) return false;
  final allowed = _allowedTypesByTheme[theme] ?? kTourismTypes;
  // Lista alba: pastram doar daca are macar un tip relevant pentru tema.
  return placeTypes.intersection(allowed).isNotEmpty;
}

// Pentru rezultatele Text Search relevanta vine din interogarea in sine
// (ex. „muzee teatre"), deci NU mai cerem lista alba de tipuri — altfel am
// pierde teatrele/cetatile pe care Google le marcheaza doar „point_of_interest".
// Respingem totusi gunoiul evident si entitatile geografice.
bool isTouristyTextResult(Set<String> placeTypes) {
  if (placeTypes.intersection(kJunkTypes).isNotEmpty) return false;
  if (placeTypes.intersection(kGeoTypes).isNotEmpty) return false;
  // hotelurile au tema lor (Hotels); nu le vrem la „obiective turistice".
  if (placeTypes.contains('lodging')) return false;
  return true;
}

// Interogarea Text Search per tema, pentru a prinde obiectivele pe care
// cautarea pe tipuri nu le returneaza (teatre, cetati, palate, monumente).
// null = tema se acopera bine doar din tipuri (nu mai facem un apel in plus).
const Map<DiscoverTheme, String> _themeTextQuery = {
  // Teatrul (live) a trecut la Entertainment; aici raman muzeele, lacasurile si
  // cetatile (patrimoniu).
  DiscoverTheme.history: 'muzee biserici catedrale cetati obiective istorice',
  // Food: tinteste mancarea propriu-zisa (restaurante, fast-food, pizza, gratar),
  // ca pool-ul sa nu fie dominat de cafenelele care vin pe type=cafe.
  DiscoverTheme.food: 'restaurante fast-food pizza burger gratar local traditional',
  // Entertainment: aduce strandurile, locurile de joaca si teatrele pe care
  // Nearby legacy nu le da ca tip.
  DiscoverTheme.entertainment:
      'strand teatru cinema parc de distractii loc de joaca bowling',
  DiscoverTheme.hiddenGems: 'obiective turistice',
};

String? textQueryForTheme(DiscoverTheme theme) => _themeTextQuery[theme];

// Interogarea generica pentru „Popular near you" si pool-ul experimentului.
const String kPopularTextQuery = 'obiective turistice';

DiscoverTheme? themeFromName(String name) {
  for (final theme in DiscoverTheme.values) {
    if (theme.name == name) return theme;
  }
  return null;
}
