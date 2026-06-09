import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// Temele Discover. Restul (culori, tipuri Places) se derivă din enum mai jos.
enum DiscoverTheme { history, nature, food, architecture, hotels, hiddenGems }

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
    nearbyTypes: ['museum', 'tourist_attraction'],
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
    nearbyTypes: ['restaurant', 'cafe'],
  ),
  DiscoverTheme.architecture: DiscoverThemeInfo(
    label: 'Architecture',
    icon: Icons.apartment_outlined,
    color: Color(0xFF6A1B9A),
    markerHue: BitmapDescriptor.hueViolet,
    nearbyTypes: ['church', 'tourist_attraction'],
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
  // History
  'museum': DiscoverTheme.history,
  'art_gallery': DiscoverTheme.history,
  'library': DiscoverTheme.history,
  'cemetery': DiscoverTheme.history,
  'city_hall': DiscoverTheme.history,
  'courthouse': DiscoverTheme.history,
  'local_government_office': DiscoverTheme.history,
  // Architecture (bisericile etc. intra aici)
  'church': DiscoverTheme.architecture,
  'place_of_worship': DiscoverTheme.architecture,
  'hindu_temple': DiscoverTheme.architecture,
  'mosque': DiscoverTheme.architecture,
  'synagogue': DiscoverTheme.architecture,
  // Nature
  'park': DiscoverTheme.nature,
  'natural_feature': DiscoverTheme.nature,
  'campground': DiscoverTheme.nature,
  'rv_park': DiscoverTheme.nature,
  // Food
  'restaurant': DiscoverTheme.food,
  'cafe': DiscoverTheme.food,
  'bakery': DiscoverTheme.food,
  'bar': DiscoverTheme.food,
  'meal_takeaway': DiscoverTheme.food,
  'meal_delivery': DiscoverTheme.food,
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

// chestii pe care nu le vrem ca destinatie (lodging lipseste: e tinta Hotels)
const Set<String> kJunkTypes = {
  'gas_station',
  'fuel',
  'car_rental',
  'car_repair',
  'car_dealer',
  'atm',
  'bank',
  'pharmacy',
  'convenience_store',
  'supermarket',
  'parking',
};

// comercial/nightlife: le scoatem din toate temele in afara de Food
const Set<String> kNonTouristTypes = {
  'casino',
  'night_club',
  'bar',
  'liquor_store',
  'shopping_mall',
  'store',
};

bool isAllowedForTheme(Set<String> placeTypes, DiscoverTheme theme) {
  if (placeTypes.intersection(kJunkTypes).isNotEmpty) return false;
  if (theme == DiscoverTheme.hotels) return true; // lodging e tinta
  if (placeTypes.contains('lodging')) return false;
  if (theme != DiscoverTheme.food &&
      placeTypes.intersection(kNonTouristTypes).isNotEmpty) {
    return false;
  }
  return true;
}

DiscoverTheme? themeFromName(String name) {
  for (final theme in DiscoverTheme.values) {
    if (theme.name == name) return theme;
  }
  return null;
}
