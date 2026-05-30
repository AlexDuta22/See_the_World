import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/app_bottom_nav.dart';
import 'ai_assistant_page.dart';
import 'home_page.dart';
import 'offline_tours_page.dart';
import 'profile_page.dart';

class FavoritePlacesPage extends StatefulWidget {
  const FavoritePlacesPage({super.key});

  @override
  State<FavoritePlacesPage> createState() => _FavoritePlacesPageState();
}

class _FavoritePlacesPageState extends State<FavoritePlacesPage> {
  static const MethodChannel _platformKeys = MethodChannel(
    'com.example.see_the_world/keys',
  );

  String _placesApiKey = '';
  final Map<String, String> _freshPhotoUrls = {};
  final Set<String> _refreshing = {};

  @override
  void initState() {
    super.initState();
    _loadPlacesApiKey();
  }

  Future<void> _loadPlacesApiKey() async {
    try {
      final key = await _platformKeys.invokeMethod<String>('getPlacesApiKey');
      if (key != null && key.isNotEmpty && mounted) {
        setState(() => _placesApiKey = key);
      }
    } catch (_) {}
  }

  // Only URLs with photo_reference can expire; static Wikipedia/storage URLs don't.
  bool _needsRefresh(String imageUrl) =>
      imageUrl.contains('photo_reference') &&
      imageUrl.contains('maps.googleapis.com');

  Future<void> _refreshPhotoUrl(String placeId, String currentUrl) async {
    if (_placesApiKey.isEmpty) return;
    if (_freshPhotoUrls.containsKey(placeId)) return;
    if (_refreshing.contains(placeId)) return;
    _refreshing.add(placeId);

    try {
      final detailsUrl = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=$placeId'
        '&fields=photos'
        '&key=$_placesApiKey',
      );
      final response = await http.get(detailsUrl);
      if (response.statusCode != 200) return;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['status'] != 'OK') return;

      final photos =
          (body['result'] as Map<String, dynamic>?)?['photos'] as List?;
      if (photos == null || photos.isEmpty) return;

      final ref =
          (photos.first as Map<String, dynamic>)['photo_reference']
              ?.toString();
      if (ref == null || ref.isEmpty) return;

      final freshUrl =
          'https://maps.googleapis.com/maps/api/place/photo'
          '?maxwidth=800&photoreference=$ref&key=$_placesApiKey';

      if (!mounted) return;
      setState(() => _freshPhotoUrls[placeId] = freshUrl);

      // Persist fresh URL in Firestore so the next app launch uses it directly.
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('favorites')
            .doc(placeId)
            .update({'imageUrl': freshUrl});
      }
    } catch (_) {
      // Ignore errors; placeholder is shown until the next successful refresh.
    } finally {
      _refreshing.remove(placeId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Favorite Places')),
      body: user == null
          ? const Center(child: Text('Sign in to see your favorites.'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('favorites')
                  .orderBy('updatedAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text('No favorites yet.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  // ignore: unnecessary_underscores
                  separatorBuilder: (_, __) => const Divider(height: 16),
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final name =
                        data['name']?.toString() ?? 'Unknown place';
                    final subtitle = data['subtitle']?.toString() ?? '';
                    final storedUrl = data['imageUrl']?.toString() ?? '';
                    final docId = docs[index].id;
                    final memoryPhotoUrl =
                        data['memoryPhotoUrl']?.toString() ?? '';

                    // Prefer freshly fetched URL; fall back to stored URL.
                    final imageUrl = _freshPhotoUrls[docId] ?? storedUrl;

                    // Trigger a background refresh for expired photo_reference URLs.
                    if (_needsRefresh(storedUrl) &&
                        !_freshPhotoUrls.containsKey(docId)) {
                      _refreshPhotoUrl(docId, storedUrl);
                    }

                    return InkWell(
                      onTap: () => _showFavoriteDetails(
                        context: context,
                        placeId: docId,
                        name: name,
                        subtitle: subtitle,
                        description: data['description']?.toString() ?? '',
                        imageUrl: imageUrl,
                        memoryPhotoPath:
                            data['memoryPhotoPath']?.toString() ?? '',
                        memoryPhotoUrl: memoryPhotoUrl,
                      ),
                      child: Row(
                        children: [
                          _buildThumbnail(imageUrl: imageUrl),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (subtitle.isNotEmpty)
                                  Text(
                                    subtitle,
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Remove from favorites',
                            onPressed: () async {
                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(user.uid)
                                  .collection('favorites')
                                  .doc(docId)
                                  .delete();
                            },
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 3,
        onProfile: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const ProfilePage()),
          );
        },
        onOffline: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const OfflineToursPage()),
          );
        },
        onCamera: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomePage()),
          );
        },
        onFavorites: () {},
        onAiAssistant: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const AiAssistantPage()),
          );
        },
      ),
    );
  }
}

Widget _buildThumbnail({required String imageUrl, String localPath = ''}) {
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

Future<String?> _loadMemoryPhotoPath(String placeId) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('memory_photo_$placeId');
}

Future<void> _removeMemoryPhoto(String placeId, String path) async {
  try {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {
    // Ignore file deletion errors.
  }
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('memory_photo_$placeId');
  await prefs.remove('memory_photo_url_$placeId');
}

void _showFavoriteDetails({
  required BuildContext context,
  required String placeId,
  required String name,
  required String subtitle,
  required String description,
  required String imageUrl,
  required String memoryPhotoPath,
  required String memoryPhotoUrl,
}) {
  showDialog<void>(
    context: context,
    builder: (context) {
      final resolvedDescription = description.isEmpty
          ? 'No description available.'
          : description;
      return StatefulBuilder(
        builder: (context, setState) {
          var localPath = memoryPhotoPath;
          if (localPath.isEmpty) {
            _loadMemoryPhotoPath(placeId).then((path) {
              if (path == null || path.isEmpty) return;
              setState(() => localPath = path);
            });
          }
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
              children: [
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      child: imageUrl.isEmpty
                          ? Container(
                              height: 300,
                              color: Colors.grey.shade200,
                              child: const Center(
                                child: Icon(Icons.photo, color: Colors.black45),
                              ),
                            )
                          : Image.network(
                              imageUrl,
                              height: 300,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              // ignore: unnecessary_underscores
                              errorBuilder: (_, __, ___) => Container(
                                height: 300,
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
                      top: 8,
                      right: 8,
                      child: Row(
                        children: [
                          Material(
                            // ignore: deprecated_member_use
                            color: Colors.white.withOpacity(0.9),
                            shape: const CircleBorder(),
                            child: IconButton(
                              icon: const Icon(Icons.photo_library_outlined),
                              tooltip: 'View memory photo',
                              onPressed: () {
                                if (localPath.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'No memory photo saved yet.',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                _showFullImage(context, localPath, '');
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (localPath.isNotEmpty)
                            Material(
                              // ignore: deprecated_member_use
                              color: Colors.white.withOpacity(0.9),
                              shape: const CircleBorder(),
                              child: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Remove memory photo',
                                onPressed: () async {
                                  await _removeMemoryPhoto(placeId, localPath);
                                  setState(() {
                                    localPath = '';
                                  });
                                },
                              ),
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
                        name,
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

void _showFullImage(BuildContext context, String memoryPath, String imageUrl) {
  if (memoryPath.isEmpty && imageUrl.isEmpty) return;
  showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (context) {
      final image = memoryPath.isNotEmpty
          ? Image.file(File(memoryPath), fit: BoxFit.contain)
          : Image.network(imageUrl, fit: BoxFit.contain);
      return Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: image,
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
