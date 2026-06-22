import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/tile_cache.dart';
import '../widgets/app_bottom_nav.dart';
import 'ai_assistant_page.dart';
import 'favorite_places_page.dart';
import 'home_page.dart';
import 'offline_tour_map_page.dart';
import 'profile_page.dart';

class OfflineToursPage extends StatefulWidget {
  const OfflineToursPage({super.key});

  @override
  State<OfflineToursPage> createState() => _OfflineToursPageState();
}

class _OfflineToursPageState extends State<OfflineToursPage> {
  static const String _timisoaraTourKey = 'offline_tour_timisoara_v2';
  bool _isDownloading = false;
  bool _isDownloaded = false;
  double _downloadProgress = 0;

  @override
  void initState() {
    super.initState();
    _loadDownloadStatus();
  }

  Future<void> _loadDownloadStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_timisoaraTourKey);
    if (!mounted) return;
    setState(() {
      _isDownloaded = stored != null && stored.isNotEmpty;
    });
  }

  Future<void> _downloadTimisoaraTour() async {
    if (_isDownloading) return;
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });
    try {
      final places = <Map<String, dynamic>>[
        {
          'id': 'tour_1',
          'order': 1,
          'name': 'Castelul Huniade',
          'subtitle': 'Historic castle and museum',
          'description':
              'The Huniade Castle is Timisoara\u2019s oldest surviving building and a key historical landmark. It houses collections focused on regional history and culture.',
          'imageUrl': '',
          'lat': 45.75316676189038,
          'lng': 21.22720473898475,
        },
        {
          'id': 'tour_2',
          'order': 2,
          'name': 'Placheta J\u00e1nos Bolyai',
          'subtitle': 'Mathematical heritage marker',
          'description':
              'A small memorial plaque honoring J\u00e1nos Bolyai, linked to the city\u2019s scientific and cultural heritage.',
          'imageUrl': '',
          'lat': 45.7544632964315,
          'lng': 21.228836998275344,
        },
        {
          'id': 'tour_3',
          'order': 3,
          'name': 'P-\u0163a Libert\u0103\u0163ii',
          'subtitle': 'Historic central square',
          'description':
              'Liberty Square is a historic plaza surrounded by military and civic architecture, reflecting Timisoara\u2019s Habsburg-era urban layout.',
          'imageUrl': '',
          'lat': 45.755545082901975,
          'lng': 21.227339797589877,
        },
        {
          'id': 'tour_4',
          'order': 4,
          'name': 'P-\u0163a Unirii',
          'subtitle': 'Baroque square and terraces',
          'description':
              'Union Square is Timisoara\u2019s baroque centerpiece, known for pastel facades, the cathedral, and lively cafes.',
          'imageUrl': '',
          'lat': 45.7580752638924,
          'lng': 21.22893310678457,
        },
        {
          'id': 'tour_5',
          'order': 5,
          'name': 'Pomul Breslelor',
          'subtitle': 'Symbol of historic guilds',
          'description':
              'The Guilds Tree is a decorative landmark celebrating the city\u2019s traditional crafts and artisan history.',
          'imageUrl': '',
          'lat': 45.756109884355304,
          'lng': 21.230756525491252,
        },
        {
          'id': 'tour_6',
          'order': 6,
          'name': 'P-\u0163a Sf. Gheorghe',
          'subtitle': 'Square with layered history',
          'description':
              'Saint George Square sits near archaeological layers of the old fortress and highlights Timisoara\u2019s historical continuity.',
          'imageUrl': '',
          'lat': 45.75574049954334,
          'lng': 21.228803538984867,
        },
        {
          'id': 'tour_7',
          'order': 7,
          'name': 'P-\u0163a Operei',
          'subtitle': 'Cultural and civic hub',
          'description':
              'Opera Square is a key public space framed by the Opera House and Orthodox Cathedral, known for its civic gatherings.',
          'imageUrl': '',
          'lat': 45.75382149049453,
          'lng': 21.225737254326503,
        },
        {
          'id': 'tour_8',
          'order': 8,
          'name': 'Catedrala Mitropolitan\u0103',
          'subtitle': 'Romanian Orthodox cathedral',
          'description':
              'The Metropolitan Cathedral is one of Timisoara\u2019s most recognizable landmarks, featuring tall spires and rich interior decoration.',
          'imageUrl': '',
          'lat': 45.75101731165475,
          'lng': 21.22430179665542,
        },
      ];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_timisoaraTourKey, jsonEncode(places));

      // Pre-descarcam dalele de hart\u0103 ale centrului Timi\u0219oarei, ca turul s\u0103
      // mearg\u0103 f\u0103r\u0103 internet. Pe web open() \u00eentoarce null \u0219i s\u0103rim peste.
      final cache = await TileCache.open();
      if (cache != null) {
        await cache.downloadRegion(
          minLat: 45.745,
          minLng: 21.215,
          maxLat: 45.765,
          maxLng: 21.240,
          minZoom: 13,
          maxZoom: 17,
          onProgress: (done, total) {
            if (mounted) {
              setState(
                () => _downloadProgress = total == 0 ? 0 : done / total,
              );
            }
          },
        );
      }

      if (!mounted) return;
      setState(() => _isDownloaded = true);
      _showSnack('Timi\u015foara City Tour downloaded.');
    } catch (_) {
      _showSnack('Download failed. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Tours'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Material(
            elevation: 2,
            borderRadius: BorderRadius.circular(12),
            child: ListTile(
              leading: const Icon(Icons.route, color: Color(0xFF1565C0)),
              title: const Text('Timi\u015foara City Tour'),
              subtitle: Text(
                _isDownloading
                    ? 'Downloading map tiles\u2026 '
                          '${(_downloadProgress * 100).round()}%'
                    : _isDownloaded
                    ? 'Tap to explore on map \u00b7 8 stops \u00b7 offline'
                    : 'Download 8 stops + map for offline access.',
              ),
              onTap: _isDownloaded
                  ? () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => const OfflineTourMapPage(),
                      ),
                    )
                  : null,
              trailing: _isDownloading
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: _downloadProgress > 0 && _downloadProgress < 1
                            ? _downloadProgress
                            : null,
                      ),
                    )
                  : IconButton(
                      icon: Icon(
                        _isDownloaded ? Icons.map_outlined : Icons.download,
                      ),
                      tooltip: _isDownloaded ? 'Open tour' : 'Download',
                      onPressed: _isDownloaded
                          ? () => Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => const OfflineTourMapPage(),
                              ),
                            )
                          : _downloadTimisoaraTour,
                    ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 1,
        onProfile: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const ProfilePage()),
          );
        },
        onOffline: () {},
        onCamera: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomePage()),
          );
        },
        onFavorites: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const FavoritePlacesPage()),
          );
        },
        onAiAssistant: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const AiAssistantPage()),
          );
        },
      ),
    );
  }
}
