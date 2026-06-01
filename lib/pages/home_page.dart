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

import 'ai_assistant_page.dart';
import 'favorite_places_page.dart';
import 'offline_tours_page.dart';
import 'profile_page.dart';
import '../widgets/app_bottom_nav.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.showTour = false});
  final bool showTour;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  GoogleMapController? _mapController;
  bool _hasLocationPermission = false;
  // Centrăm pe locația utilizatorului o singură dată la deschidere, indiferent
  // dacă permisiunea sau harta se inițializează prima.
  bool _didInitialLocate = false;
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
  bool _showTourMarkers = false;
  Set<Polyline> _tourPolylines = {};
  String? _activeCategory;
  Set<Marker> _categoryMarkers = {};
  Set<Marker> _aiMarkers = {};

  static const CameraPosition _initialCameraPosition = CameraPosition(
    target: LatLng(45.7489, 21.2087), // Timisoara
    zoom: 13,
  );
  static const String _offlineTimisoaraTourKey = 'offline_tour_timisoara_v2';
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

  @override
  void initState() {
    super.initState();
    _ensureLocationPermission();
    _startCompass();
    _loadDirectionsApiKey();
    _loadPlacesApiKey();
    _seedTopPlacesIfEmpty();
    _loadOfflineTour();
    aiMapPlacesRequest.addListener(_handleAiPlacesRequest);
  }

  @override
  void dispose() {
    aiMapPlacesRequest.removeListener(_handleAiPlacesRequest);
    _positionSub?.cancel();
    _compassSub?.cancel();
    _mapController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                if (_showTourMarkers) ..._tourMarkers,
                ..._searchMarkers,
                ..._categoryMarkers,
                ..._aiMarkers,
              };
              return GoogleMap(
                onMapCreated: (controller) {
                  _mapController = controller;
                  _centerOnUserInitial();
                },
                initialCameraPosition: _initialCameraPosition,
                markers: combinedMarkers,
                polylines: {..._polylines, ..._tourPolylines},
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
          if (_navSteps.isEmpty)
            Positioned(
              top: 70,
              left: 0,
              right: 0,
              child: SafeArea(child: _buildFilterRow()),
            ),
          if (_showTourMarkers)
            Positioned(
              top: 80,
              left: 16,
              right: 16,
              child: SafeArea(
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(12),
                  color: const Color(0xFF1565C0),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.route, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Timișoara City Tour',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _exitTour,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                          ),
                          child: const Text(
                            'Exit',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
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
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: -1,
        onProfile: () => _openPage(const ProfilePage()),
        onOffline: () => _openPage(const OfflineToursPage()),
        onCamera: _openCamera,
        onFavorites: () => _openPage(const FavoritePlacesPage()),
        onAiAssistant: () => _openPage(const AiAssistantPage()),
      ),
    );
  }

  void _openPage(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  void _handleAiPlacesRequest() {
    final places = aiMapPlacesRequest.value;
    if (places.isEmpty || !mounted) return;
    aiMapPlacesRequest.value = const [];
    _showAiPlacesOnMap(places);
  }

  void _showAiPlacesOnMap(List<AiMapPlace> places) {
    final markers = <Marker>{};
    for (var i = 0; i < places.length; i++) {
      final p = places[i];
      final id = p.placeId.isNotEmpty ? p.placeId : 'ai-$i';
      markers.add(
        Marker(
          markerId: MarkerId('ai-$id'),
          position: LatLng(p.lat, p.lng),
          infoWindow: InfoWindow(title: p.name),
          onTap: () => _showPlaceDetails(
            placeId: id,
            name: p.name,
            subtitle: p.area,
            description: p.address.isEmpty ? p.area : p.address,
            imageUrl: p.photoUrl,
            lat: p.lat,
            lng: p.lng,
          ),
        ),
      );
    }
    setState(() => _aiMarkers = markers);
    if (places.length == 1) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(places.first.lat, places.first.lng),
          14,
        ),
      );
    } else {
      _animateToBounds(
        places.map((p) => LatLng(p.lat, p.lng)).toList(growable: false),
      );
    }
    _showSnack('Locurile recomandate de asistent sunt acum pe hartă.');
  }

  void _onSearch() {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _showSnack('Enter a place to search.');
      return;
    }

    _showSnack('No matching place found.');
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
      final subtitle = data['subtitle']?.toString() ?? '';
      final description = data['description']?.toString() ?? subtitle;
      final imageUrl = _placePhotoUrls[doc.id] ??
          data['imageUrl']?.toString() ?? '';
      _ensurePlacePhoto(doc.id, name, lat, lng);
      markers.add(
        Marker(
          markerId: MarkerId(doc.id),
          position: LatLng(lat, lng),
          infoWindow: InfoWindow(title: name),
          onTap: () => _showPlaceDetails(
            placeId: doc.id,
            name: name,
            subtitle: subtitle,
            description: description,
            imageUrl: imageUrl,
            lat: lat,
            lng: lng,
          ),
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
      final imageUrl = _placePhotoUrls[place.id] ?? place.imageUrl;
      _ensurePlacePhoto(place.id, place.name, place.lat, place.lng);
      markers.add(
        Marker(
          markerId: MarkerId(place.id),
          position: LatLng(place.lat!, place.lng!),
          infoWindow: InfoWindow(title: place.name),
          onTap: () => _showPlaceDetails(
            placeId: place.id,
            name: place.name,
            subtitle: place.subtitle,
            description: place.description.isEmpty
                ? place.subtitle
                : place.description,
            imageUrl: imageUrl,
            lat: place.lat,
            lng: place.lng,
          ),
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
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked == null) return; // user canceled
      final saved = await _persistPickedPhoto(
        picked: picked,
        filenamePrefix: 'capture',
      );
      setState(() {
        _lastCapturedPhoto = XFile(saved.path);
      });
      _showSnack(
        'Photo saved: ${saved.path.split(Platform.pathSeparator).last}',
      );
    } catch (_) {
      _showSnack('Could not open camera.');
    }
  }

  Future<void> _ensureLocationPermission() async {
    final granted = await _requestLocationPermission();
    if (!mounted) return;
    setState(() => _hasLocationPermission = granted);
    if (granted) {
      await _centerOnUserInitial();
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

  // Centrare automată pe utilizator la prima deschidere. E apelată atât din
  // onMapCreated cât și după ce se acordă permisiunea — oricare se termină ultima
  // declanșează efectiv mutarea, o singură dată (gardată de _didInitialLocate).
  Future<void> _centerOnUserInitial() async {
    if (_didInitialLocate) return;
    if (_mapController == null || !_hasLocationPermission) return;

    // Sărim instant pe ultima poziție cunoscută (din cache, fără așteptare GPS),
    // ca să nu se mai vadă Timișoara la deschidere.
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (!mounted || _mapController == null) return;
      if (last != null) {
        _didInitialLocate = true;
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(last.latitude, last.longitude), 15),
        );
      }
    } catch (_) {
      // Fără ultima poziție; rafinăm direct cu poziția curentă mai jos.
    }

    // Rafinăm cu poziția reală curentă.
    final ok = await _goToCurrentLocation();
    if (ok) _didInitialLocate = true;
  }

  Future<bool> _goToCurrentLocation() async {
    if (_mapController == null) return false;
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
      return true;
    } catch (_) {
      _showSnack('Could not fetch current location.');
      return false;
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
      final saved = await _persistPickedPhoto(
        picked: picked,
        filenamePrefix: 'memory_$placeId',
      );
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

  Future<File> _persistPickedPhoto({
    required XFile picked,
    required String filenamePrefix,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final target = File(
      '${dir.path}/${filenamePrefix}_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    return File(picked.path).copy(target.path);
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

  Widget _buildFilterRow() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: _categoryFilters.map((filter) {
          final isActive = _activeCategory == filter.type;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              avatar: Icon(
                filter.icon,
                size: 16,
                color: isActive ? Colors.white : filter.color,
              ),
              label: Text(
                filter.label,
                style: TextStyle(
                  color: isActive ? Colors.white : null,
                  fontWeight: isActive ? FontWeight.w600 : null,
                ),
              ),
              selected: isActive,
              selectedColor: filter.color,
              backgroundColor: isDark ? Colors.grey.shade800 : Colors.white,
              elevation: 3,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _activeCategory = filter.type;
                    _categoryMarkers = {};
                  });
                  _fetchCategoryPlaces(filter.type);
                } else {
                  setState(() {
                    _activeCategory = null;
                    _categoryMarkers = {};
                  });
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  static const _categoryExcludedTypes = <String, Set<String>>{
    'restaurant': {'gas_station', 'fuel', 'lodging', 'convenience_store'},
    'museum': {'restaurant', 'lodging', 'gas_station'},
    'park': {'restaurant', 'lodging', 'gas_station'},
    'lodging': {'gas_station', 'fuel', 'restaurant'},
  };

  Future<void> _fetchCategoryPlaces(String type) async {
    if (_placesApiKey.isEmpty) return;
    if (!mounted) return;
    double lat = 45.7489, lng = 21.2087;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {}

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
        '?location=$lat,$lng'
        '&radius=5000'
        '&type=$type'
        '&rankby=prominence'
        '&key=$_placesApiKey',
      );
      final response = await http.get(url);
      if (response.statusCode != 200 || !mounted) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>? ?? [];
      final excluded = _categoryExcludedTypes[type] ?? const {};
      final markers = <Marker>{};

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

        // Skip places whose types overlap with the exclusion list for this category.
        final placeTypes =
            (place['types'] as List<dynamic>?)?.cast<String>().toSet() ??
            const <String>{};
        if (placeTypes.intersection(excluded).isNotEmpty) continue;

        markers.add(
          Marker(
            markerId: MarkerId('cat_$placeId'),
            position: LatLng(pLat.toDouble(), pLng.toDouble()),
            infoWindow: InfoWindow(title: name),
            icon: BitmapDescriptor.defaultMarkerWithHue(_categoryHue(type)),
            onTap: () => _showNearbyPlaceDetails(
              _NearbyPlace(
                id: placeId,
                name: name,
                position: LatLng(pLat.toDouble(), pLng.toDouble()),
              ),
            ),
          ),
        );
      }

      if (!mounted) return;
      setState(() => _categoryMarkers = markers);
      if (markers.isNotEmpty) {
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(lat, lng), 14),
        );
      } else {
        _showSnack('No ${type}s found nearby.');
      }
    } catch (_) {
      if (mounted) _showSnack('Could not load places.');
    }
  }

  double _categoryHue(String type) {
    switch (type) {
      case 'restaurant':
        return BitmapDescriptor.hueOrange;
      case 'museum':
        return BitmapDescriptor.hueViolet;
      case 'park':
        return BitmapDescriptor.hueGreen;
      case 'lodging':
        return BitmapDescriptor.hueAzure;
      default:
        return BitmapDescriptor.hueRed;
    }
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
      if (widget.showTour) _activateTour();
    } catch (_) {
      // Ignore invalid offline data.
    }
  }

  void _activateTour() {
    if (_offlinePlaces.isEmpty) return;
    final sorted = [..._offlinePlaces]
      ..sort((a, b) => a.order.compareTo(b.order));
    final points = sorted
        .where((p) => p.lat != null && p.lng != null)
        .map((p) => LatLng(p.lat!, p.lng!))
        .toList();
    if (points.isEmpty) return;

    final tourMarkers = _buildTourMarkersFromOffline(sorted);
    final polyline = Polyline(
      polylineId: const PolylineId('tour_route'),
      points: points,
      color: const Color(0xFF1565C0),
      width: 4,
      patterns: [PatternItem.dash(20), PatternItem.gap(10)],
    );

    setState(() {
      _showTourMarkers = true;
      _tourMarkers = tourMarkers;
      _tourPolylines = {polyline};
    });

    if (points.length > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _mapController == null) return;
        _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(_latLngBounds(points), 60),
        );
      });
    }
  }

  void _exitTour() {
    setState(() {
      _showTourMarkers = false;
      _tourPolylines = {};
    });
  }

  LatLngBounds _latLngBounds(List<LatLng> points) {
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  Set<Marker> _buildTourMarkersFromOffline(List<_OfflinePlace> sorted) {
    final valid = sorted.where((p) => p.lat != null && p.lng != null).toList();
    return valid.asMap().entries.map((e) {
      final p = e.value;
      final displayOrder = p.order > 0 ? p.order : e.key + 1;
      return Marker(
        markerId: MarkerId('tour_${p.id}'),
        position: LatLng(p.lat!, p.lng!),
        infoWindow: InfoWindow(
          title: '$displayOrder. ${p.name}',
          snippet: p.subtitle,
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        onTap: () => _showTourStopDetail(p),
      );
    }).toSet();
  }

  void _showTourStopDetail(_OfflinePlace place) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.of(ctx).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stop ${place.order}: ${place.name}',
              style: Theme.of(
                ctx,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (place.subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(place.subtitle, style: const TextStyle(color: Colors.grey)),
            ],
            if (place.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(place.description),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.navigation),
                label: const Text('Navigate here'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _startNavigation(LatLng(place.lat!, place.lng!));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryFilter {
  const _CategoryFilter({
    required this.label,
    required this.type,
    required this.icon,
    required this.color,
  });

  final String label;
  final String type;
  final IconData icon;
  final Color color;
}

const _categoryFilters = [
  _CategoryFilter(
    label: 'Restaurant',
    type: 'restaurant',
    icon: Icons.restaurant,
    color: Colors.orange,
  ),
  _CategoryFilter(
    label: 'Muzeu',
    type: 'museum',
    icon: Icons.museum_outlined,
    color: Colors.purple,
  ),
  _CategoryFilter(
    label: 'Parc',
    type: 'park',
    icon: Icons.park_outlined,
    color: Colors.green,
  ),
  _CategoryFilter(
    label: 'Hotel',
    type: 'lodging',
    icon: Icons.hotel_outlined,
    color: Colors.blue,
  ),
];

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
