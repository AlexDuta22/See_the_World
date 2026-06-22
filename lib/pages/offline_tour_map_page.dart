import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/tile_cache.dart';

// Harta turului pe flutter_map + OSM. Dalele vin din cache-ul local (offline) cu
// fallback la rețea; opririle și traseul se desenează din datele salvate.
class OfflineTourMapPage extends StatefulWidget {
  const OfflineTourMapPage({super.key});

  @override
  State<OfflineTourMapPage> createState() => _OfflineTourMapPageState();
}

class _OfflineTourMapPageState extends State<OfflineTourMapPage> {
  static const String _tourKey = 'offline_tour_timisoara_v2';

  TileProvider? _tileProvider;
  List<_Stop> _stops = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cache = await TileCache.open();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_tourKey);
    final stops = <_Stop>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        for (final item in jsonDecode(raw) as List) {
          final m = item as Map<String, dynamic>;
          final lat = (m['lat'] as num?)?.toDouble();
          final lng = (m['lng'] as num?)?.toDouble();
          if (lat == null || lng == null) continue;
          stops.add(
            _Stop(
              order: (m['order'] as num?)?.toInt() ?? 0,
              name: m['name']?.toString() ?? '',
              subtitle: m['subtitle']?.toString() ?? '',
              description: m['description']?.toString() ?? '',
              point: LatLng(lat, lng),
            ),
          );
        }
      } catch (_) {
        // date offline invalide -> lista goala
      }
    }
    stops.sort((a, b) => a.order.compareTo(b.order));
    if (!mounted) return;
    setState(() {
      _tileProvider = cache?.tileProvider() ?? NetworkTileProvider();
      _stops = stops;
      _loading = false;
    });
  }

  void _showStop(_Stop s) {
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
              'Stop ${s.order}: ${s.name}',
              style: Theme.of(
                ctx,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (s.subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(s.subtitle, style: const TextStyle(color: Colors.grey)),
            ],
            if (s.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(s.description),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final points = _stops.map((s) => s.point).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Timișoara City Tour')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _stops.isEmpty
          ? const Center(child: Text('Descarcă turul mai întâi.'))
          : FlutterMap(
              options: MapOptions(
                initialCenter: points.first,
                initialZoom: 15,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  tileProvider: _tileProvider,
                  userAgentPackageName: 'com.example.see_the_world',
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: points,
                      strokeWidth: 4,
                      color: const Color(0xFF1565C0),
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    for (final s in _stops)
                      Marker(
                        point: s.point,
                        width: 40,
                        height: 40,
                        child: GestureDetector(
                          onTap: () => _showStop(s),
                          child: const Icon(
                            Icons.location_on,
                            color: Color(0xFF1565C0),
                            size: 40,
                          ),
                        ),
                      ),
                  ],
                ),
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
    );
  }
}

class _Stop {
  const _Stop({
    required this.order,
    required this.name,
    required this.subtitle,
    required this.description,
    required this.point,
  });

  final int order;
  final String name;
  final String subtitle;
  final String description;
  final LatLng point;
}
