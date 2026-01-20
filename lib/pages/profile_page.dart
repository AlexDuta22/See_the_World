import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/app_bottom_nav.dart';
import 'favorite_places_page.dart';
import 'home_page.dart';
import 'offline_tours_page.dart';
import '../services/app_theme.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  static const String _visitedCountKey = 'visited_places_count';
  static const String _toursCompletedKey = 'tours_completed_count';
  static const String _userNameKey = 'USERNAMEKEY';

  int _visitedCount = 0;
  int _toursCompleted = 0;
  bool _isUploadingPhoto = false;
  final ImagePicker _picker = ImagePicker();
  String _cachedDisplayName = '';

  @override
  void initState() {
    super.initState();
    _loadCounters();
    _loadCachedProfile();
  }

  Future<void> _loadCounters() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _visitedCount = prefs.getInt(_visitedCountKey) ?? 0;
      _toursCompleted = prefs.getInt(_toursCompletedKey) ?? 0;
    });
  }

  Future<void> _loadCachedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _cachedDisplayName = prefs.getString(_userNameKey) ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          TextButton(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (!mounted) return;
              _showSnack('Signed out.');
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text(
              'Sign out',
              style: TextStyle(decoration: TextDecoration.underline),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _profileHeader(user),
          const SizedBox(height: 16),
          const Divider(height: 24),
          _settingsSection(),
          _sectionTile(
            icon: Icons.offline_pin_outlined,
            title: 'Offline guides',
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const OfflineToursPage()),
              );
            },
          ),
          _sectionTile(
            icon: Icons.star_border,
            title: 'Rate the app',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showSnack('Thanks for your feedback!'),
          ),
          _sectionTile(
            icon: Icons.feedback_outlined,
            title: 'Share feedback',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showSnack('Feedback form coming soon.'),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 0,
        onProfile: () {},
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
        onFavorites: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const FavoritePlacesPage()),
          );
        },
      ),
    );
  }

  Widget _favoritesStatRow(User? user) {
    if (user == null) {
      return _statRow(
        icon: Icons.favorite,
        color: Colors.red,
        label: 'Favorite places',
        value: 0,
      );
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('favorites')
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        return _statRow(
          icon: Icons.favorite,
          color: Colors.red,
          label: 'Favorite places',
          value: count,
        );
      },
    );
  }

  Widget _profileHeader(User? user) {
    if (user == null) {
      return _profileRow(name: 'Guest', photoUrl: '', canEdit: false);
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final firestoreName = data?['name']?.toString().trim();
        final firestorePhoto = data?['photoUrl']?.toString().trim();
        final authName = user.displayName?.trim();
        final authEmail = user.email?.trim();
        final name = (firestoreName != null && firestoreName.isNotEmpty)
            ? firestoreName
            : (authName != null && authName.isNotEmpty)
            ? authName
            : (_cachedDisplayName.isNotEmpty)
            ? _cachedDisplayName
            : (authEmail != null && authEmail.isNotEmpty)
            ? authEmail
            : 'Guest';
        final photoUrl = (firestorePhoto != null && firestorePhoto.isNotEmpty)
            ? firestorePhoto
            : (user.photoURL ?? '');
        return _profileRow(name: name, photoUrl: photoUrl, canEdit: true);
      },
    );
  }

  Widget _profileRow({
    required String name,
    required String photoUrl,
    required bool canEdit,
  }) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'G';
    return Row(
      children: [
        GestureDetector(
          onTap: canEdit ? _pickProfilePhoto : null,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.brown.shade700,
                backgroundImage: (photoUrl.isNotEmpty)
                    ? NetworkImage(photoUrl)
                    : null,
                child: (photoUrl.isEmpty)
                    ? Text(
                        initial,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              ),
              if (_isUploadingPhoto)
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              _statRow(
                icon: Icons.check_circle,
                color: Colors.green,
                label: 'Places visited',
                value: _visitedCount,
              ),
              const SizedBox(height: 6),
              _favoritesStatRow(FirebaseAuth.instance.currentUser),
              const SizedBox(height: 6),
              _statRow(
                icon: Icons.route,
                color: Colors.blue,
                label: 'Tours completed',
                value: _toursCompleted,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statRow({
    required IconData icon,
    required Color color,
    required String label,
    required int value,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(
          '$label: $value',
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _sectionTile({
    required IconData icon,
    required String title,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: trailing,
      onTap: onTap,
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickProfilePhoto() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      setState(() => _isUploadingPhoto = true);
      final ref = FirebaseStorage.instance
          .ref()
          .child('users')
          .child(user.uid)
          .child('profile.jpg');
      await ref.putFile(File(picked.path));
      final url = await ref.getDownloadURL();
      await user.updatePhotoURL(url);
      await user.reload();
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'photoUrl': url,
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() {});
      _showSnack('Profile photo updated.');
    } on FirebaseException catch (e) {
      _showSnack(e.message ?? 'Could not update profile photo.');
    } catch (_) {
      _showSnack('Could not update profile photo.');
    } finally {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
      }
    }
  }

  Widget _settingsSection() {
    final mode = AppTheme.notifier.value;
    return ExpansionTile(
      leading: const Icon(Icons.settings),
      title: const Text(
        'Settings',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      children: [
        ListTile(
          title: const Text('App theme'),
          trailing: DropdownButton<ThemeMode>(
            value: mode,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
              DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
            ],
            onChanged: (next) {
              if (next == null) return;
              AppTheme.setTheme(next);
              setState(() {});
            },
          ),
        ),
        ListTile(
          title: Text('Clear visited history ($_visitedCount)'),
          trailing: const Icon(Icons.delete_outline),
          onTap: _confirmClearVisitedHistory,
        ),
      ],
    );
  }

  Future<void> _confirmClearVisitedHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Clear visited history?'),
          content: const Text('This will reset your visited places counter.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Clear'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_visitedCountKey, 0);
    if (!mounted) return;
    setState(() => _visitedCount = 0);
    _showSnack('Visited history cleared.');
  }
}
