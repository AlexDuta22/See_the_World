import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import 'package:google_places_flutter/model/prediction.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'favorite_places_page.dart';
import 'offline_tours_page.dart';
import 'profile_page.dart';
import '../widgets/app_bottom_nav.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  GoogleMapController? _mapController;
  bool _hasLocationPermission = false;
  bool _isRouting = false;
  bool _isNavigating = false;
  Set<Polyline> _polylines = {};
  Set<Marker> _searchMarkers = {};
  final Map<String, String> _placePhotoUrls = {};
  final Set<String> _photoLoading = {};
  final Set<String> _photoMissing = {};
  final Map<String, String> _memoryPhotoCache = {};
  bool _proximityActive = false;
  final Map<String, _NearbyPlace> _nearbyPlaces = {};
  Set<Marker> _nearbyMarkers = {};
  StreamSubscription<CompassEvent>? _compassSub;
  double? _headingDegrees;
  Position? _lastPosition;
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _searchController = TextEditingController();
  XFile? _lastCapturedPhoto;
  StreamSubscription<Position>? _positionSub;
  List<_NavStep> _navSteps = [];
  List<_OfflinePlace> _offlinePlaces = [];
  Set<Marker> _tourMarkers = {};

  static const CameraPosition _initialCameraPosition = CameraPosition(
    target: LatLng(45.7489, 21.2087), // Timisoara
    zoom: 13,
  );
  static const String _offlineTimisoaraTourKey = 'offline_tour_timisoara';
  static const double _nearbyRadiusMeters = 5000;
  static const double _fieldOfViewDegrees = 45;

  static const String _googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );
  static const String _googleDirectionsApiKey = String.fromEnvironment(
    'GOOGLE_DIRECTIONS_API_KEY',
    defaultValue: '',
  );
  static const String _googlePlacesApiKey = String.fromEnvironment(
    'GOOGLE_PLACES_API_KEY',
    defaultValue: '',
  );
  static const MethodChannel _platformKeys = MethodChannel(
    'com.example.see_the_world/keys',
  );
  String _directionsApiKey = _googleDirectionsApiKey.isNotEmpty
      ? _googleDirectionsApiKey
      : _googleMapsApiKey;
  String _placesApiKey = _googlePlacesApiKey.isNotEmpty
      ? _googlePlacesApiKey
      : _googleMapsApiKey;

  static final List<Marker> _sampleMarkers = [
    const Marker(
      markerId: MarkerId('biserica-centrala'),
      position: LatLng(45.7561, 21.2286),
      infoWindow: InfoWindow(title: 'Biserica Centrala'),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _ensureLocationPermission();
    _startCompass();
    _loadDirectionsApiKey();
    _loadPlacesApiKey();
    _seedTopPlacesIfEmpty();
    _loadOfflineTour();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _compassSub?.cancel();
    _mapController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetColor = isDark ? Colors.black : Colors.white;
    final titleColor = isDark ? Colors.white : Colors.black;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            onPressed: _onLocateMe,
            icon: const Icon(Icons.my_location_outlined),
            tooltip: 'Locate me',
          ),
          IconButton(
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: Stack(
        children: [
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('top_places')
                .orderBy('name')
                .snapshots(),
            builder: (context, snapshot) {
              final places = snapshot.data?.docs ?? [];
              final useOffline =
                  snapshot.data == null && _offlinePlaces.isNotEmpty;
              final baseMarkers = useOffline
                  ? _markersFromOffline(_offlinePlaces)
                  : _markersFromPlaces(places);
              final markers = _proximityActive ? _nearbyMarkers : baseMarkers;
              final combinedMarkers = <Marker>{
                ...markers,
                ..._tourMarkers,
                ..._searchMarkers,
              };
              return GoogleMap(
                onMapCreated: (controller) {
                  _mapController = controller;
                  if (_hasLocationPermission) _goToCurrentLocation();
                },
                initialCameraPosition: _initialCameraPosition,
                markers: combinedMarkers.isEmpty
                    ? _markersWithNavigationTap()
                    : combinedMarkers,
                polylines: _polylines,
                myLocationEnabled: _hasLocationPermission,
                myLocationButtonEnabled: _hasLocationPermission,
                compassEnabled: true,
              );
            },
          ),
          if (_lastCapturedPhoto != null)
            Positioned(
              bottom: 96,
              right: 16,
              child: SafeArea(
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      SizedBox(
                        width: 120,
                        height: 160,
                        child: Image.file(
                          File(_lastCapturedPhoto!.path),
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            iconSize: 18,
                            color: Colors.white,
                            icon: const Icon(Icons.close),
                            tooltip: 'Remove photo preview',
                            onPressed: () => setState(() {
                              _lastCapturedPhoto = null;
                            }),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: SafeArea(
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                color: isDark ? Colors.black : Colors.white,
                child: _placesApiKey.isEmpty
                    ? _buildLocalSearchField()
                    : _buildPlacesSearchField(),
              ),
            ),
          ),
          if (_navSteps.isNotEmpty)
            Positioned(
              top: 68,
              left: 16,
              right: 16,
              child: SafeArea(
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    color: isDark ? Colors.black : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Directions',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                              TextButton(
                                onPressed: () =>
                                    _stopNavigation(freeRoute: true),
                                child: Text(
                                  'Stop',
                                  style: TextStyle(
                                    color: isDark ? Colors.white : Colors.blue,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        SizedBox(
                          height: 140,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: _navSteps.length,
                            // ignore: unnecessary_underscores
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final step = _navSteps[index];
                              final subtitle =
                                  (step.distance.isEmpty &&
                                      step.duration.isEmpty)
                                  ? null
                                  : '${step.distance} - ${step.duration}'
                                        .trim();
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  Icons.directions,
                                  size: 20,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                                title: Text(
                                  step.instruction,
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                                subtitle: subtitle == null
                                    ? null
                                    : Text(
                                        subtitle,
                                        style: TextStyle(
                                          color: isDark
                                              ? Colors.grey.shade400
                                              : Colors.grey.shade600,
                                        ),
                                      ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_isRouting)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 4),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.2,
              minChildSize: 0.1,
              maxChildSize: 0.5,
              builder: (context, scrollController) {
                return Material(
                  elevation: 10,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    color: sheetColor,
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.grey.shade700
                                : Colors.grey.shade400,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Top places',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: titleColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: FirebaseFirestore.instance
                                .collection('top_places')
                                .orderBy('name')
                                .snapshots(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                if (_offlinePlaces.isEmpty) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }
                              }
                              final docs = snapshot.data?.docs ?? [];
                              final isDark =
                                  Theme.of(context).brightness ==
                                  Brightness.dark;
                              final itemTitleColor = isDark
                                  ? Colors.white
                                  : Colors.black87;
                              final itemSubtitleColor = isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600;
                              final items = <Widget>[];
                              if (docs.isEmpty && _offlinePlaces.isEmpty) {
                                items.add(
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    child: Center(
                                      child: Text('No places yet.'),
                                    ),
                                  ),
                                );
                              } else if (docs.isNotEmpty) {
                                for (final doc in docs) {
                                  final data = doc.data();
                                  final name = data['name']?.toString() ?? '';
                                  final subtitle =
                                      data['subtitle']?.toString() ?? '';
                                  final description =
                                      data['description']?.toString() ??
                                      subtitle;
                                  final lat = data['lat'] is num
                                      ? (data['lat'] as num).toDouble()
                                      : null;
                                  final lng = data['lng'] is num
                                      ? (data['lng'] as num).toDouble()
                                      : null;
                                  final imageUrl =
                                      data['imageUrl']?.toString() ?? '';
                                  final cachedUrl =
                                      _placePhotoUrls[doc.id] ?? '';
                                  final resolvedImageUrl = cachedUrl.isNotEmpty
                                      ? cachedUrl
                                      : imageUrl;
                                  _ensurePlacePhoto(doc.id, name, lat, lng);
                                  items.add(
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              onTap: () => _showPlaceDetails(
                                                placeId: doc.id,
                                                name: name,
                                                subtitle: subtitle,
                                                description: description,
                                                imageUrl: resolvedImageUrl,
                                                lat: lat,
                                                lng: lng,
                                              ),
                                              child: Row(
                                                children: [
                                                  _buildThumbnail(
                                                    resolvedImageUrl,
                                                    name,
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          name.isEmpty
                                                              ? 'Unknown place'
                                                              : name,
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color:
                                                                itemTitleColor,
                                                          ),
                                                        ),
                                                        if (subtitle.isNotEmpty)
                                                          Text(
                                                            subtitle,
                                                            style: TextStyle(
                                                              color:
                                                                  itemSubtitleColor,
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.navigation),
                                            color: itemTitleColor,
                                            tooltip: 'Navigate',
                                            onPressed: () {
                                              if (lat == null || lng == null) {
                                                _showSnack(
                                                  'Missing location for $name.',
                                                );
                                                return;
                                              }
                                              _startNavigation(
                                                LatLng(lat, lng),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }
                              } else {
                                for (final place in _offlinePlaces) {
                                  final name = place.name;
                                  final subtitle = place.subtitle;
                                  final description = place.description.isEmpty
                                      ? subtitle
                                      : place.description;
                                  final resolvedImageUrl =
                                      _placePhotoUrls[place.id] ??
                                      place.imageUrl;
                                  _ensurePlacePhoto(
                                    place.id,
                                    name,
                                    place.lat,
                                    place.lng,
                                  );
                                  items.add(
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              onTap: () => _showPlaceDetails(
                                                placeId: place.id,
                                                name: name,
                                                subtitle: subtitle,
                                                description: description,
                                                imageUrl: resolvedImageUrl,
                                                lat: place.lat,
                                                lng: place.lng,
                                              ),
                                              child: Row(
                                                children: [
                                                  _buildThumbnail(
                                                    resolvedImageUrl,
                                                    name,
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          name.isEmpty
                                                              ? 'Unknown place'
                                                              : name,
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color:
                                                                itemTitleColor,
                                                          ),
                                                        ),
                                                        if (subtitle.isNotEmpty)
                                                          Text(
                                                            subtitle,
                                                            style: TextStyle(
                                                              color:
                                                                  itemSubtitleColor,
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.navigation),
                                            color: itemTitleColor,
                                            tooltip: 'Navigate',
                                            onPressed: () {
                                              if (place.lat == null ||
                                                  place.lng == null) {
                                                _showSnack(
                                                  'Missing location for $name.',
                                                );
                                                return;
                                              }
                                              _startNavigation(
                                                LatLng(place.lat!, place.lng!),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }
                              }
                              return ListView.builder(
                                controller: scrollController,
                                itemCount: items.length,
                                itemBuilder: (context, index) {
                                  return items[index];
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: -1,
        onProfile: () => _openPage(const ProfilePage()),
        onOffline: () => _openPage(const OfflineToursPage()),
        onCamera: _openCamera,
        onFavorites: () => _openPage(const FavoritePlacesPage()),
      ),
    );
  }

  void _openPage(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  void _onSearch() {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _showSnack('Enter a place to search.');
      return;
    }

    final normalized = query.toLowerCase();
    Marker? match;
    for (final marker in _sampleMarkers) {
      final title = marker.infoWindow.title?.toLowerCase() ?? '';
      if (title.contains(normalized)) {
        match = marker;
        break;
      }
    }

    if (match == null) {
      _showSnack('No matching place found.');
      return;
    }

    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(match.position, 15),
    );
    _showSnack('Moved to ${match.infoWindow.title}.');
  }

  Set<Marker> _markersWithNavigationTap() {
    return _sampleMarkers
        .map((m) => m.copyWith(onTapParam: () => _startNavigation(m.position)))
        .toSet();
  }

  Set<Marker> _markersFromPlaces(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final markers = <Marker>{};
    for (final doc in docs) {
      final data = doc.data();
      final name = data['name']?.toString();
      final lat = data['lat'] is num ? (data['lat'] as num).toDouble() : null;
      final lng = data['lng'] is num ? (data['lng'] as num).toDouble() : null;
      if (name == null || name.isEmpty || lat == null || lng == null) {
        continue;
      }
      markers.add(
        Marker(
          markerId: MarkerId(doc.id),
          position: LatLng(lat, lng),
          infoWindow: InfoWindow(title: name),
          onTap: () => _startNavigation(LatLng(lat, lng)),
        ),
      );
    }
    return markers;
  }

  Set<Marker> _markersFromOffline(List<_OfflinePlace> places) {
    final markers = <Marker>{};
    for (final place in places) {
      if (place.name.isEmpty || place.lat == null || place.lng == null) {
        continue;
      }
      markers.add(
        Marker(
          markerId: MarkerId(place.id),
          position: LatLng(place.lat!, place.lng!),
          infoWindow: InfoWindow(title: place.name),
          onTap: () => _startNavigation(LatLng(place.lat!, place.lng!)),
        ),
      );
    }
    return markers;
  }

  void _startCompass() {
    _compassSub = FlutterCompass.events?.listen((event) {
      final heading = event.heading;
      if (heading == null) return;
      final normalized = (heading + 360) % 360;
      if (!mounted) return;
      if (_headingDegrees != null &&
          (normalized - _headingDegrees!).abs() < 1) {
        return;
      }
      _headingDegrees = normalized;
      _applyDirectionalFilter();
    });
  }

  void _applyDirectionalFilter() {
    if (!_proximityActive) return;
    final position = _lastPosition;
    if (position == null || _nearbyPlaces.isEmpty) {
      if (!mounted) return;
      setState(() {
        _nearbyMarkers = {};
      });
      return;
    }

    if (_headingDegrees == null) {
      if (!mounted) return;
      setState(() {
        _nearbyMarkers = _buildNearbyMarkers(_nearbyPlaces.values);
      });
      return;
    }

    final heading = _headingDegrees!;
    final suggested = <_NearbyPlace>[];
    for (final place in _nearbyPlaces.values) {
      final bearing = Geolocator.bearingBetween(
        position.latitude,
        position.longitude,
        place.position.latitude,
        place.position.longitude,
      );
      final normalizedBearing = (bearing + 360) % 360;
      final delta = _angularDifference(normalizedBearing, heading);
      if (delta <= _fieldOfViewDegrees) {
        suggested.add(place);
      }
    }
    if (!mounted) return;
    setState(() {
      _nearbyMarkers = _buildNearbyMarkers(suggested);
    });
  }

  double _angularDifference(double a, double b) {
    final diff = (a - b + 540) % 360 - 180;
    return diff.abs();
  }

  Set<Marker> _buildNearbyMarkers(Iterable<_NearbyPlace> places) {
    return places
        .map(
          (place) => Marker(
            markerId: MarkerId(place.id),
            position: place.position,
            infoWindow: InfoWindow(title: place.name),
            onTap: () => _showNearbyPlaceDetails(place),
          ),
        )
        .toSet();
  }

  Future<Map<String, dynamic>?> _fetchNearbyPlaceDetails(
    _NearbyPlace place,
  ) async {
    if (_placesApiKey.isEmpty) return null;
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/details/json'
      '?place_id=${place.id}'
      '&fields=name,formatted_address,rating,user_ratings_total,'
      'international_phone_number,website,opening_hours,photos'
      '&key=$_placesApiKey',
    );
    final response = await http.get(url);
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final result = data['result'] as Map<String, dynamic>?;
    return result;
  }

  String? _placePhotoUrl(Map<String, dynamic>? details) {
    final photos = details?['photos'] as List<dynamic>?;
    if (photos == null || photos.isEmpty) return null;
    final photo = photos.first as Map<String, dynamic>?;
    final reference = photo?['photo_reference']?.toString();
    if (reference == null || reference.isEmpty) return null;
    return 'https://maps.googleapis.com/maps/api/place/photo'
        '?maxwidth=800&photoreference=$reference&key=$_placesApiKey';
  }

  void _showNearbyPlaceDetails(_NearbyPlace place) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return FutureBuilder<Map<String, dynamic>?>(
          future: _fetchNearbyPlaceDetails(place),
          builder: (context, snapshot) {
            final isLoading =
                snapshot.connectionState == ConnectionState.waiting;
            final details = snapshot.data;
            final name = details?['name']?.toString() ?? place.name;
            final address = details?['formatted_address']?.toString() ?? '';
            final rating = details?['rating'];
            final ratingsTotal = details?['user_ratings_total'];
            final phone =
                details?['international_phone_number']?.toString() ?? '';
            final website = details?['website']?.toString() ?? '';
            final openNow =
                (details?['opening_hours']
                    as Map<String, dynamic>?)?['open_now'];
            final photoUrl = _placePhotoUrl(details);
            final isFavorite = _favoriteCache[place.id] ?? false;
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (photoUrl != null)
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      child: Image.network(
                        photoUrl,
                        height: 200,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 200,
                          color: Colors.grey.shade200,
                          child: const Center(
                            child: Icon(Icons.photo, color: Colors.black45),
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (address.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(address),
                          ),
                        if (rating != null || ratingsTotal != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Rating: ${rating ?? '-'}'
                              '${ratingsTotal != null ? ' ($ratingsTotal)' : ''}',
                            ),
                          ),
                        if (openNow != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(openNow ? 'Open now' : 'Closed now'),
                          ),
                        if (phone.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('Phone: $phone'),
                          ),
                        if (website.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('Website: $website'),
                          ),
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                                _startNavigation(place.position);
                              },
                              icon: const Icon(Icons.directions),
                              label: const Text('Directions'),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Add memory photo',
                              icon: const Icon(Icons.camera_alt_outlined),
                              onPressed: () async {
                                final path = await _captureMemoryPhoto(
                                  place.id,
                                );
                                if (!mounted) return;
                                if (path == null || path.isEmpty) return;
                                setState(() {
                                  _memoryPhotoCache[place.id] = path;
                                });
                              },
                            ),
                            TextButton.icon(
                              onPressed: () async {
                                final user = FirebaseAuth.instance.currentUser;
                                if (user == null) {
                                  _showSnack('Sign in to save favorites.');
                                  return;
                                }
                                final next = !isFavorite;
                                setState(() {
                                  _favoriteCache[place.id] = next;
                                });
                                await _setFavorite(
                                  placeId: place.id,
                                  isFavorite: next,
                                  name: place.name,
                                  subtitle: '',
                                  description: address,
                                  imageUrl: photoUrl ?? '',
                                  lat: place.position.latitude,
                                  lng: place.position.longitude,
                                );
                              },
                              icon: Icon(
                                isFavorite
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: isFavorite ? Colors.red : null,
                              ),
                              label: Text(
                                isFavorite ? 'Favorited' : 'Add to favorites',
                              ),
                            ),
                          ],
                        ),
                        if (isLoading)
                          const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Close'),
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
      },
    );
  }

  final Map<String, bool> _favoriteCache = {};

  Future<bool> _loadFavoriteStatus(String placeId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('favorites')
        .doc(placeId)
        .get();
    return doc.exists;
  }

  Future<void> _setFavorite({
    required String placeId,
    required bool isFavorite,
    required String name,
    required String subtitle,
    required String description,
    required String imageUrl,
    required double? lat,
    required double? lng,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('favorites')
        .doc(placeId);
    if (!isFavorite) {
      await docRef.delete();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final memoryPath = prefs.getString('memory_photo_$placeId') ?? '';
    final memoryUrl = prefs.getString('memory_photo_url_$placeId') ?? '';
    await docRef.set({
      'name': name,
      'subtitle': subtitle,
      'description': description,
      'imageUrl': imageUrl,
      'memoryPhotoPath': memoryPath,
      'memoryPhotoUrl': memoryUrl,
      'lat': lat,
      'lng': lng,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Widget _circleIconButton({
    required IconData icon,
    required VoidCallback? onPressed,
    Color? color,
  }) {
    return Material(
      // ignore: deprecated_member_use
      color: Colors.white.withOpacity(0.9),
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon, color: color ?? Colors.black87),
        onPressed: onPressed,
      ),
    );
  }

  Future<void> _startNavigation(LatLng destination) async {
    if (_isRouting) return;
    setState(() {
      _isRouting = true;
    });

    final hasPermission = await _requestLocationPermission();
    if (!mounted || !hasPermission) {
      setState(() => _isRouting = false);
      return;
    }

    try {
      if (_directionsApiKey.isEmpty) {
        await _loadDirectionsApiKey();
      }
      await _stopNavigation(freeRoute: false);
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final origin = LatLng(position.latitude, position.longitude);
      final route = await _fetchRoute(origin, destination);
      if (!mounted) return;
      if (route == null || route.points.isEmpty) {
        _showSnack('Could not fetch a route.');
        return;
      }

      final polyline = Polyline(
        polylineId: const PolylineId('route'),
        color: Colors.blue,
        width: 6,
        points: route.points,
      );

      setState(() {
        _polylines = {polyline};
        _navSteps = route.steps;
        _isNavigating = true;
      });
      await _animateToBounds(route.points);
      _startFollowingUser();
    } catch (_) {
      _showSnack('Navigation failed. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isRouting = false);
      }
    }
  }

  Future<_RouteData?> _fetchRoute(LatLng origin, LatLng destination) async {
    if (_directionsApiKey.isEmpty) {
      _showSnack('Set the directions API key to enable navigation.');
      return null;
    }

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=${origin.latitude},${origin.longitude}'
      '&destination=${destination.latitude},${destination.longitude}'
      '&mode=walking&key=$_directionsApiKey',
    );

    final response = await http.get(url);
    if (response.statusCode != 200) {
      _showSnack('Directions request failed (${response.statusCode}).');
      return null;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['status'] != 'OK') {
      final errorMessage = data['error_message']?.toString();
      final status = data['status']?.toString() ?? 'UNKNOWN';
      _showSnack(
        errorMessage == null || errorMessage.isEmpty
            ? 'Directions unavailable: $status'
            : 'Directions unavailable: $status. $errorMessage',
      );
      return null;
    }

    final routes = data['routes'] as List<dynamic>;
    if (routes.isEmpty) {
      _showSnack('No routes returned for this destination.');
      return null;
    }
    final route = routes.first as Map<String, dynamic>;
    final overview = route['overview_polyline'] as Map<String, dynamic>;
    final points = overview['points'] as String;

    final decoded = PolylinePoints.decodePolyline(points);
    final steps = _parseSteps(route);
    final decodedPoints = decoded
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList(growable: false);
    return _RouteData(points: decodedPoints, steps: steps);
  }

  Future<void> _animateToBounds(List<LatLng> points) async {
    if (_mapController == null || points.isEmpty) return;
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final p in points.skip(1)) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    await _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 64),
    );
  }

  Future<void> _openCamera() async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.camera);
      if (picked == null) return; // user canceled
      setState(() {
        _lastCapturedPhoto = picked;
      });
      _showSnack('Photo captured: ${picked.name}');
    } catch (_) {
      _showSnack('Could not open camera.');
    }
  }

  Future<void> _ensureLocationPermission() async {
    final granted = await _requestLocationPermission();
    if (!mounted) return;
    setState(() => _hasLocationPermission = granted);
    if (granted) {
      await _goToCurrentLocation();
    }
  }

  Future<bool> _requestLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnack('Please enable location services.');
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      _showSnack('Location permission denied.');
      return false;
    }

    if (permission == LocationPermission.deniedForever) {
      _showSnack(
        'Location permission permanently denied. Enable it in Settings.',
      );
      return false;
    }

    return true;
  }

  Future<void> _onLocateMe() async {
    final granted = await _requestLocationPermission();
    if (!mounted) return;
    setState(() => _hasLocationPermission = granted);
    if (granted) {
      await _goToCurrentLocation();
    }
  }

  Future<void> _goToCurrentLocation() async {
    if (_mapController == null) return;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _lastPosition = position;
      final target = LatLng(position.latitude, position.longitude);
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(target, 15),
      );
      await _refreshNearbySuggestions();
    } catch (_) {
      _showSnack('Could not fetch current location.');
    }
  }

  void _startFollowingUser() {
    _positionSub?.cancel();
    _positionSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen((position) {
          if (!_isNavigating || _mapController == null) return;
          final target = LatLng(position.latitude, position.longitude);
          _mapController!.animateCamera(CameraUpdate.newLatLngZoom(target, 16));
        });
  }

  Future<void> _refreshNearbySuggestions() async {
    if (!_hasLocationPermission) return;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _lastPosition = position;
      if (_placesApiKey.isEmpty) return;
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
        '?location=${position.latitude},${position.longitude}'
        '&radius=$_nearbyRadiusMeters'
        '&type=tourist_attraction'
        '&key=$_placesApiKey',
      );
      final response = await http.get(url);
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>? ?? [];
      final nearbyPlaces = <String, _NearbyPlace>{};
      for (final item in results) {
        final place = item as Map<String, dynamic>;
        final placeId = place['place_id']?.toString();
        final name = place['name']?.toString();
        final location =
            (place['geometry'] as Map<String, dynamic>?)?['location']
                as Map<String, dynamic>?;
        final lat = location?['lat'] as num?;
        final lng = location?['lng'] as num?;
        if (placeId == null || name == null || lat == null || lng == null) {
          continue;
        }
        nearbyPlaces[placeId] = _NearbyPlace(
          id: placeId,
          name: name,
          position: LatLng(lat.toDouble(), lng.toDouble()),
        );
      }
      if (!mounted) return;
      setState(() {
        _nearbyPlaces
          ..clear()
          ..addAll(nearbyPlaces);
        _proximityActive = true;
      });
      _applyDirectionalFilter();
    } catch (_) {}
  }

  Future<void> _stopNavigation({required bool freeRoute}) async {
    await _positionSub?.cancel();
    _positionSub = null;
    if (!mounted) return;
    setState(() {
      _isNavigating = false;
      _navSteps = [];
      if (freeRoute) _polylines = {};
    });
  }

  List<_NavStep> _parseSteps(Map<String, dynamic> route) {
    final legs = route['legs'] as List<dynamic>? ?? [];
    if (legs.isEmpty) return [];
    final steps = legs.first['steps'] as List<dynamic>? ?? [];
    return steps
        .map((step) {
          final data = step as Map<String, dynamic>;
          final instructionRaw = data['html_instructions']?.toString() ?? '';
          final distance =
              (data['distance'] as Map<String, dynamic>?)?['text']
                  ?.toString() ??
              '';
          final duration =
              (data['duration'] as Map<String, dynamic>?)?['text']
                  ?.toString() ??
              '';
          return _NavStep(
            instruction: _stripHtml(instructionRaw),
            distance: distance,
            duration: duration,
          );
        })
        .toList(growable: false);
  }

  String _stripHtml(String value) {
    final stripped = value.replaceAll(RegExp('<[^>]*>'), '');
    return stripped
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&#39;', '\'');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadDirectionsApiKey() async {
    if (_directionsApiKey.isNotEmpty) return;
    try {
      final key = await _platformKeys.invokeMethod<String>(
        'getDirectionsApiKey',
      );
      if (key != null && key.isNotEmpty) {
        _directionsApiKey = key;
      }
    } catch (_) {}
  }

  Future<void> _loadPlacesApiKey() async {
    if (_placesApiKey.isNotEmpty) return;
    try {
      final key = await _platformKeys.invokeMethod<String>('getPlacesApiKey');
      if (key != null && key.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _placesApiKey = key;
        });
      }
    } catch (_) {}
  }

  Future<String?> _captureMemoryPhoto(String placeId) async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 75,
        maxWidth: 1280,
        maxHeight: 1280,
      );
      if (picked == null) return null;
      final dir = await getApplicationDocumentsDirectory();
      final target = File(
        '${dir.path}/memory_${placeId}_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      final saved = await File(picked.path).copy(target.path);
      try {} catch (_) {
        // Ignore gallery save errors; local save still succeeds.
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('memory_photo_$placeId', saved.path);
      await _incrementVisitedCount();
      _showSnack('Memory photo saved.');
      return saved.path;
    } catch (_) {
      _showSnack('Could not save memory photo.');
      return null;
    }
  }

  Future<void> _incrementVisitedCount() async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'visited_places_count';
    final current = prefs.getInt(key) ?? 0;
    await prefs.setInt(key, current + 1);
  }

  Widget _buildLocalSearchField() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hintColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final iconColor = isDark ? Colors.grey.shade300 : Colors.grey.shade700;
    return TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _onSearch(),
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        hintText: 'Search places',
        hintStyle: TextStyle(color: hintColor),
        prefixIcon: Icon(Icons.search, color: iconColor),
        suffixIcon: IconButton(
          icon: Icon(Icons.clear, color: iconColor),
          onPressed: () => _searchController.clear(),
        ),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 12,
          horizontal: 12,
        ),
      ),
    );
  }

  Widget _buildPlacesSearchField() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hintColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final iconColor = isDark ? Colors.grey.shade300 : Colors.grey.shade700;
    return GooglePlaceAutoCompleteTextField(
      textEditingController: _searchController,
      googleAPIKey: _placesApiKey,
      debounceTime: 600,
      countries: const ['ro'],
      isLatLngRequired: true,
      textStyle: TextStyle(color: isDark ? Colors.white : Colors.black87),
      inputDecoration: InputDecoration(
        hintText: 'Search places',
        hintStyle: TextStyle(color: hintColor),
        prefixIcon: Icon(Icons.search, color: iconColor),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 12,
          horizontal: 12,
        ),
      ),
      isCrossBtnShown: true,
      boxDecoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      itemBuilder: (context, index, Prediction prediction) {
        final description = prediction.description ?? '';
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.location_on, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
      seperatedBuilder: const Divider(height: 1),
      itemClick: (Prediction prediction) {
        final description = prediction.description ?? '';
        _searchController.text = description;
        _searchController.selection = TextSelection.fromPosition(
          TextPosition(offset: description.length),
        );
      },
      getPlaceDetailWithLatLng: (Prediction prediction) {
        _onPlaceSelected(prediction);
      },
    );
  }

  void _onPlaceSelected(Prediction prediction) {
    final lat = _parseLatLng(prediction.lat);
    final lng = _parseLatLng(prediction.lng);
    if (lat == null || lng == null) {
      _showSnack('Selected place has no location.');
      return;
    }
    final name = prediction.description ?? 'Selected place';
    final position = LatLng(lat, lng);
    setState(() {
      _searchMarkers = {
        Marker(
          markerId: const MarkerId('search-result'),
          position: position,
          infoWindow: InfoWindow(title: name),
          onTap: () => _startNavigation(position),
        ),
      };
    });
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(position, 15));
    _showSnack('Moved to $name. Tap marker to start navigation.');
  }

  double? _parseLatLng(Object? value) {
    if (value == null) return null;
    return double.tryParse(value.toString());
  }

  Future<void> _ensurePlacePhoto(
    String docId,
    String name,
    double? lat,
    double? lng,
  ) async {
    if (_placesApiKey.isEmpty || name.trim().isEmpty) return;
    if (_photoLoading.contains(docId) ||
        _placePhotoUrls.containsKey(docId) ||
        _photoMissing.contains(docId)) {
      return;
    }
    _photoLoading.add(docId);
    try {
      final url = await _fetchPlacePhotoUrl(name, lat, lng);
      if (!mounted) return;
      setState(() {
        if (url == null || url.isEmpty) {
          _photoMissing.add(docId);
        } else {
          _placePhotoUrls[docId] = url;
        }
      });
    } finally {
      _photoLoading.remove(docId);
    }
  }

  Future<String?> _fetchPlacePhotoUrl(
    String name,
    double? lat,
    double? lng,
  ) async {
    if (_placesApiKey.isEmpty) return null;
    String? reference;
    if (lat != null && lng != null) {
      final nearbyUrl = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
        '?location=$lat,$lng&radius=1500'
        '&type=tourist_attraction'
        '&keyword=${Uri.encodeComponent(name)}'
        '&key=$_placesApiKey',
      );
      final nearbyResponse = await http.get(nearbyUrl);
      if (nearbyResponse.statusCode == 200) {
        final data = jsonDecode(nearbyResponse.body) as Map<String, dynamic>;
        final results = data['results'] as List<dynamic>? ?? [];
        final photos = results.isNotEmpty
            ? (results.first as Map<String, dynamic>)['photos']
                  as List<dynamic>?
            : null;
        reference = photos != null && photos.isNotEmpty
            ? (photos.first as Map<String, dynamic>)['photo_reference']
                  ?.toString()
            : null;
      }
    }
    if (reference == null || reference.isEmpty) {
      final query = Uri.encodeComponent('$name Timisoara');
      final findUrl = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/findplacefromtext/json'
        '?input=$query&inputtype=textquery&fields=photos'
        '&key=$_placesApiKey',
      );
      final findResponse = await http.get(findUrl);
      if (findResponse.statusCode == 200) {
        final data = jsonDecode(findResponse.body) as Map<String, dynamic>;
        final candidates = data['candidates'] as List<dynamic>? ?? [];
        final photos = candidates.isNotEmpty
            ? (candidates.first as Map<String, dynamic>)['photos']
                  as List<dynamic>?
            : null;
        reference = photos != null && photos.isNotEmpty
            ? (photos.first as Map<String, dynamic>)['photo_reference']
                  ?.toString()
            : null;
      }
    }
    if (reference == null || reference.isEmpty) return null;
    return 'https://maps.googleapis.com/maps/api/place/photo'
        '?maxwidth=400&photoreference=$reference&key=$_placesApiKey';
  }

  Widget _buildThumbnail(
    String imageUrl,
    String name, {
    String localPath = '',
  }) {
    final placeholder = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.photo, color: Colors.black45),
    );
    if (localPath.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          File(localPath),
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          // ignore: unnecessary_underscores
          errorBuilder: (_, __, ___) => placeholder,
        ),
      );
    }
    if (imageUrl.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        imageUrl,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        // ignore: unnecessary_underscores
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }

  void _showPlaceDetails({
    required String placeId,
    required String name,
    required String subtitle,
    required String description,
    required String imageUrl,
    required double? lat,
    required double? lng,
  }) {
    showDialog<void>(
      context: context,
      builder: (context) {
        final resolvedName = name.isEmpty ? 'Unknown place' : name;
        final resolvedDescription = description.isEmpty
            ? 'No description available.'
            : description;
        return StatefulBuilder(
          builder: (context, setState) {
            var isFavorite = _favoriteCache[placeId] ?? false;
            if (!_favoriteCache.containsKey(placeId)) {
              _loadFavoriteStatus(placeId).then((value) {
                if (!mounted) return;
                setState(() {
                  _favoriteCache[placeId] = value;
                });
              });
            }
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                        child: imageUrl.isEmpty
                            ? Container(
                                height: 220,
                                color: Colors.grey.shade200,
                                child: const Center(
                                  child: Icon(
                                    Icons.photo,
                                    color: Colors.black45,
                                  ),
                                ),
                              )
                            : Image.network(
                                imageUrl,
                                height: 220,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                // ignore: unnecessary_underscores
                                errorBuilder: (_, __, ___) => Container(
                                  height: 220,
                                  color: Colors.grey.shade200,
                                  child: const Center(
                                    child: Icon(
                                      Icons.photo,
                                      color: Colors.black45,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        child: _circleIconButton(
                          icon: Icons.arrow_back,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Row(
                          children: [
                            _circleIconButton(
                              icon: Icons.map_outlined,
                              onPressed: (lat == null || lng == null)
                                  ? null
                                  : () {
                                      Navigator.of(context).pop();
                                      _startNavigation(LatLng(lat, lng));
                                    },
                            ),
                            const SizedBox(width: 8),
                            _circleIconButton(
                              icon: Icons.camera_alt_outlined,
                              onPressed: () async {
                                final path = await _captureMemoryPhoto(placeId);
                                if (!mounted) return;
                                if (path == null || path.isEmpty) return;
                                setState(() {
                                  _memoryPhotoCache[placeId] = path;
                                });
                              },
                            ),
                            const SizedBox(width: 8),
                            _circleIconButton(
                              icon: Icons.favorite,
                              color: isFavorite ? Colors.red : Colors.white,
                              onPressed: () async {
                                final user = FirebaseAuth.instance.currentUser;
                                if (user == null) {
                                  _showSnack('Sign in to save favorites.');
                                  return;
                                }
                                final next = !isFavorite;
                                setState(() {
                                  _favoriteCache[placeId] = next;
                                });
                                await _setFavorite(
                                  placeId: placeId,
                                  isFavorite: next,
                                  name: resolvedName,
                                  subtitle: subtitle,
                                  description: resolvedDescription,
                                  imageUrl: imageUrl,
                                  lat: lat,
                                  lng: lng,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          resolvedName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (subtitle.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              subtitle,
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Text(resolvedDescription),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _seedTopPlacesIfEmpty() async {
    try {
      final collection = FirebaseFirestore.instance.collection('top_places');
      final snapshot = await collection.get();
      final existingDocs =
          <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final doc in snapshot.docs) {
        final name = doc.data()['name']?.toString().toLowerCase().trim() ?? '';
        if (name.isEmpty || existingDocs.containsKey(name)) continue;
        existingDocs[name] = doc;
      }
      final bastionDoc = existingDocs['bastionul maria theresia'];
      if (bastionDoc != null) {
        await collection.doc(bastionDoc.id).delete();
        existingDocs.remove('bastionul maria theresia');
      }
      final cathedralDoc = existingDocs['catedrala mitropolitana'];
      if (cathedralDoc != null) {
        await collection.doc(cathedralDoc.id).update({
          'lat': 45.75100975109226,
          'lng': 21.22429104948917,
        });
      }
      final seeds = <Map<String, dynamic>>[
        {
          'name': 'Piata Victoriei',
          'subtitle': 'Timisoara city center',
          'description':
              'Piata Victoriei is Timisoara’s central square, lined with historic facades and opening to the Metropolitan Cathedral. It is a lively pedestrian area with cafes, events, and a strong architectural mix of Secession and Neoclassical styles.',
          'imageUrl':
              'https://lh3.googleusercontent.com/gps-cs-s/AG0ilSx-yWta5LSlmBlZcx4OyK0V_jIB-p3Sg5igodUekbVSZ21BLX4Ls4ci_pQZQIrjnow_UvOsLtSPGwbFYUCid2cysDYBJNn8k3k-L48uimJNIMkUUQ7cnHtWD9zchDZkIQI9uG8=w270-h312-n-k-no',
          'lat': 45.7537,
          'lng': 21.2257,
        },
        {
          'name': 'Piata Unirii',
          'subtitle': 'Historic square with baroque buildings',
          'description':
              'Piata Unirii is the baroque heart of Timisoara, known for its pastel buildings, cathedral, and elegant squareside terraces. The open plaza highlights the city’s Habsburg-era heritage and remains a popular gathering spot.',
          'imageUrl':
              'https://upload.wikimedia.org/wikipedia/commons/thumb/e/ef/Pia%C8%9Ba_Victoriei_Timi%C8%99oara.jpg/1200px-Pia%C8%9Ba_Victoriei_Timi%C8%99oara.jpg',
          'lat': 45.7576,
          'lng': 21.2296,
        },
        {
          'name': 'Catedrala Mitropolitana',
          'subtitle': 'Romanian Orthodox cathedral',
          'description':
              'The Metropolitan Cathedral is one of Timisoara’s most recognizable landmarks, featuring tall spires, richly decorated interiors, and a prominent position near the city center. It reflects Romanian Orthodox architecture and history.',
          'imageUrl':
              'https://dynamic-media-cdn.tripadvisor.com/media/photo-o/0e/09/40/bf/impresionante-architektur.jpg?w=1200&h=-1&s=1',
          'lat': 45.75100975109226,
          'lng': 21.22429104948917,
        },
        {
          'name': 'Muzeul Satului Banatean',
          'subtitle': 'Open-air museum of Banat village life',
          'description':
              'The Banat Village Museum is an open-air collection of traditional houses, workshops, and churches that recreate rural life in the Banat region. It offers a walk-through of local crafts, architecture, and everyday history.',
          'imageUrl':
              'https://upload.wikimedia.org/wikipedia/commons/a/a8/2023_-_Muzeul_Satului_B%C4%83n%C4%83%C8%9Bean_-_biserica_de_lemn_din_Topla%2C_Timi%C8%99_-_img_0.jpg',
          'lat': 45.7794001339114,
          'lng': 21.266045925406583,
        },
      ];
      for (final place in seeds) {
        final name = place['name']?.toString().toLowerCase().trim() ?? '';
        if (name.isEmpty) continue;
        final existingDoc = existingDocs[name];
        if (existingDoc != null) {
          final data = existingDoc.data();
          final updates = <String, dynamic>{};
          final subtitle = data['subtitle']?.toString().trim() ?? '';
          final imageUrl = data['imageUrl']?.toString().trim() ?? '';
          if (subtitle.isEmpty && place['subtitle'] != null) {
            updates['subtitle'] = place['subtitle'];
          }
          if (place['description'] != null) {
            updates['description'] = place['description'];
          }
          if (imageUrl.isEmpty && place['imageUrl'] != null) {
            updates['imageUrl'] = place['imageUrl'];
          }
          if (updates.isNotEmpty) {
            await collection.doc(existingDoc.id).update(updates);
          }
          continue;
        }
        await collection.add(place);
      }
    } catch (_) {
      // Ignore seeding errors.
    }
  }

  Future<void> _loadOfflineTour() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_offlineTimisoaraTourKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final data = jsonDecode(raw) as List<dynamic>;
      final places = data
          .map((item) => _OfflinePlace.fromJson(item))
          .whereType<_OfflinePlace>()
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _offlinePlaces = places;
        _tourMarkers = _markersFromOffline(places);
      });
    } catch (_) {
      // Ignore invalid offline data.
    }
  }
}

class _NearbyPlace {
  const _NearbyPlace({
    required this.id,
    required this.name,
    required this.position,
  });

  final String id;
  final String name;
  final LatLng position;
}

class _RouteData {
  const _RouteData({required this.points, required this.steps});

  final List<LatLng> points;
  final List<_NavStep> steps;
}

class _NavStep {
  const _NavStep({
    required this.instruction,
    required this.distance,
    required this.duration,
  });

  final String instruction;
  final String distance;
  final String duration;
}

class _OfflinePlace {
  const _OfflinePlace({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.description,
    required this.imageUrl,
    required this.lat,
    required this.lng,
    required this.order,
  });

  final String id;
  final String name;
  final String subtitle;
  final String description;
  final String imageUrl;
  final double? lat;
  final double? lng;
  final int order;

  static _OfflinePlace? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString() ?? '';
    final name = raw['name']?.toString() ?? '';
    final subtitle = raw['subtitle']?.toString() ?? '';
    final description = raw['description']?.toString() ?? '';
    final imageUrl = raw['imageUrl']?.toString() ?? '';
    final lat = raw['lat'] is num ? (raw['lat'] as num).toDouble() : null;
    final lng = raw['lng'] is num ? (raw['lng'] as num).toDouble() : null;
    final order = raw['order'] is num ? (raw['order'] as num).toInt() : 0;
    if (id.isEmpty || name.isEmpty) return null;
    return _OfflinePlace(
      id: id,
      name: name,
      subtitle: subtitle,
      description: description,
      imageUrl: imageUrl,
      lat: lat,
      lng: lng,
      order: order,
    );
  }
}
