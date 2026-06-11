import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../widgets/app_bottom_nav.dart';
import 'ai_assistant_page.dart';
import 'favorite_places_page.dart';
import 'home_page.dart';
import 'offline_tours_page.dart';
import '../services/app_theme.dart';
import '../services/shared_pref.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // Configurare EmailJS (gratis, fără server). Completează cu valorile din
  // contul tău de pe emailjs.com — nu sunt secrete, pot sta în client:
  //   Service ID  → Email Services
  //   Template ID → Email Templates
  //   Public Key  → Account → General → Public Key
  static const String _emailjsServiceId = 'service_o6yfvqi';
  static const String _emailjsTemplateId = 'template_gn1xa5f';
  static const String _emailjsPublicKey = 'PtrjFCqBBeKC63h8s';

  // „Tours completed" nu e încă implementat (nu se scrie nicăieri), deci rămâne 0.
  final int _toursCompleted = 0;
  bool _isUploadingPhoto = false;
  final ImagePicker _picker = ImagePicker();
  String _cachedDisplayName = '';

  @override
  void initState() {
    super.initState();
    _loadCachedProfile();
  }

  Future<void> _loadCachedProfile() async {
    final name = await SharedpreferenceHelper().getUserDisplayName();
    if (!mounted) return;
    setState(() {
      _cachedDisplayName = name ?? '';
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
              if (!context.mounted) return;
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
            icon: Icons.rate_review_outlined,
            title: 'Rate & feedback',
            trailing: const Icon(Icons.chevron_right),
            onTap: _onSendFeedback,
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
        onAiAssistant: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const AiAssistantPage()),
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

  Widget _visitedStatRow(User? user) {
    if (user == null) {
      return _statRow(
        icon: Icons.check_circle,
        color: Colors.green,
        label: 'Places visited',
        value: 0,
      );
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('visited')
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        return _statRow(
          icon: Icons.check_circle,
          color: Colors.green,
          label: 'Places visited',
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
                    color: Colors.black.withValues(alpha: 0.4),
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
              _visitedStatRow(FirebaseAuth.instance.currentUser),
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

  Future<void> _onSendFeedback() async {
    // Un singur dialog adună și nota (stele), și mesajul; ambele pleacă
    // împreună, deci primești un singur email.
    final result = await showDialog<({int rating, String message})>(
      context: context,
      builder: (_) => const _FeedbackDialog(),
    );
    if (result == null) return;
    final message = result.message.trim();
    await _submitFeedback(
      rating: result.rating > 0 ? result.rating : null,
      message: message.isNotEmpty ? message : null,
    );
  }

  // Trimite rating-ul și/sau mesajul pe email prin EmailJS (gratis, fără server).
  // Cererea pleacă direct din aplicație; cheile EmailJS sunt publice prin design.
  Future<void> _submitFeedback({int? rating, String? message}) async {
    final email = FirebaseAuth.instance.currentUser?.email ?? 'necunoscut';
    final stars = rating != null ? '★' * rating + '☆' * (5 - rating) : '—';
    try {
      final response = await http.post(
        Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'service_id': _emailjsServiceId,
          'template_id': _emailjsTemplateId,
          'user_id': _emailjsPublicKey,
          'template_params': {
            'rating': rating?.toString() ?? '—',
            'stars': stars,
            'message': message ?? '(fără mesaj)',
            'from_email': email,
          },
        }),
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        _showSnack(
          rating != null
              ? 'Mulțumim pentru aprecierea ta de $rating ${rating == 1 ? 'stea' : 'stele'}!'
              : 'Mulțumim! Feedback-ul tău a fost trimis.',
        );
      } else {
        final reason = response.body.trim();
        _showSnack(
          'Nu am putut trimite (${response.statusCode})'
          '${reason.isEmpty ? '' : ': $reason'}',
        );
      }
    } catch (_) {
      if (mounted) {
        _showSnack('Nu am putut trimite feedback-ul. Încearcă din nou.');
      }
    }
  }

  Future<void> _pickProfilePhoto() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      if (!mounted) return;
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
      if (mounted) {
        _showSnack(e.message ?? 'Could not update profile photo.');
      }
    } catch (_) {
      if (mounted) {
        _showSnack('Could not update profile photo.');
      }
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
          title: const Text('Clear visited history'),
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
          content: const Text('This will delete all your visited places.'),
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
    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (confirmed != true || user == null) return;
    try {
      final visited = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('visited');
      final snapshot = await visited.get();
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      // StreamBuilder-ul din profil reflectă singur noul total (0).
      if (mounted) _showSnack('Visited history cleared.');
    } on FirebaseException catch (e) {
      if (mounted) _showSnack(e.message ?? 'Could not clear visited history.');
    } catch (_) {
      if (mounted) _showSnack('Could not clear visited history.');
    }
  }
}

/// Dialog estetic unic pentru „Rate & feedback": adună nota (stele animate) și
/// un mesaj opțional, întoarse împreună ca (rating, message) — sau null la
/// renunțare. Cu ambele într-un singur dialog rezultă un singur email.
class _FeedbackDialog extends StatefulWidget {
  const _FeedbackDialog();

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  final TextEditingController _controller = TextEditingController();
  int _rating = 0;

  static const List<String> _labels = [
    'Atinge o stea',
    'Slab',
    'Acceptabil',
    'Bun',
    'Foarte bun',
    'Extraordinar!',
  ];

  // Permitem trimiterea cu o notă SAU un mesaj (nu obligăm ambele).
  bool get _canSend => _rating > 0 || _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2A) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header cu gradient.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 26),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.emoji_emotions_outlined,
                      color: Colors.white,
                      size: 46,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Îți place See the World?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Acordă-ne o notă atingând stelele',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              const SizedBox(height: 14),
              // Stele animate.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final index = i + 1;
                  final selected = index <= _rating;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _rating = index),
                    child: AnimatedScale(
                      scale: selected ? 1.18 : 1.0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutBack,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          selected
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 44,
                          color: selected
                              ? const Color(0xFFFFC107)
                              : (isDark ? Colors.white30 : Colors.black26),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 10),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: Text(
                  _labels[_rating],
                  key: ValueKey<int>(_rating),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _rating == 0
                        ? (isDark ? Colors.white38 : Colors.black38)
                        : const Color(0xFFFFA000),
                  ),
                ),
              ),
              // Mesaj opțional, în cuvinte.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: TextField(
                  controller: _controller,
                  maxLines: 4,
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Spune-ne și în cuvinte (opțional)...',
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : const Color(0xFFF7F8FB),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              // Butoane.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Mai târziu'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _canSend
                            ? () => Navigator.of(context).pop(
                                (rating: _rating, message: _controller.text),
                              )
                            : null,
                        child: const Text('Trimite'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
