import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/app_bottom_nav.dart';
import 'home_page.dart';
import 'offline_tours_page.dart';
import 'profile_page.dart';

class FavoritePlacesPage extends StatelessWidget {
  const FavoritePlacesPage({super.key});

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
                    final name = data['name']?.toString() ?? 'Unknown place';
                    final subtitle = data['subtitle']?.toString() ?? '';
                    final imageUrl = data['imageUrl']?.toString() ?? '';
                    final docId = docs[index].id;
                    final memoryPhotoUrl =
                        data['memoryPhotoUrl']?.toString() ?? '';
                    final content = InkWell(
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
                    return content;
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
    builder: (context) {
      final image = memoryPath.isNotEmpty
          ? Image.file(File(memoryPath), fit: BoxFit.contain)
          : Image.network(imageUrl, fit: BoxFit.contain);
      return Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: AspectRatio(aspectRatio: 1, child: Center(child: image)),
        ),
      );
    },
  );
}
