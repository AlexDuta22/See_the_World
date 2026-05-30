import 'package:flutter/material.dart';

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onProfile,
    required this.onOffline,
    required this.onCamera,
    required this.onFavorites,
    required this.onAiAssistant,
  });

  final int currentIndex;
  final VoidCallback onProfile;
  final VoidCallback onOffline;
  final VoidCallback onCamera;
  final VoidCallback onFavorites;
  final VoidCallback onAiAssistant;

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    if (isKeyboardOpen) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? Colors.black : Colors.grey.shade100;
    final baseColor =
        isDark ? Colors.grey.shade200 : Colors.blueGrey.shade800;
    final selectedColor =
        isDark ? Colors.white : Colors.blueGrey.shade900;

    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        color: background,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: _NavButton(
                icon: Icons.person_outline,
                label: 'Profile',
                isSelected: currentIndex == 0,
                baseColor: baseColor,
                selectedColor: selectedColor,
                onTap: onProfile,
              ),
            ),
            Expanded(
              child: _NavButton(
                icon: Icons.offline_pin_outlined,
                label: 'Offline Tours',
                isSelected: currentIndex == 1,
                baseColor: baseColor,
                selectedColor: selectedColor,
                onTap: onOffline,
              ),
            ),
            Expanded(
              child: _NavButton(
                icon: Icons.camera_alt_outlined,
                label: 'Camera',
                isSelected: currentIndex == 2,
                baseColor: baseColor,
                selectedColor: selectedColor,
                onTap: onCamera,
              ),
            ),
            Expanded(
              child: _NavButton(
                icon: Icons.favorite_border,
                label: 'Favorites',
                isSelected: currentIndex == 3,
                baseColor: baseColor,
                selectedColor: selectedColor,
                onTap: onFavorites,
              ),
            ),
            Expanded(
              child: _NavButton(
                icon: Icons.smart_toy_outlined,
                label: 'AI',
                isSelected: currentIndex == 4,
                baseColor: baseColor,
                selectedColor: selectedColor,
                onTap: onAiAssistant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isSelected,
    required this.baseColor,
    required this.selectedColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isSelected;
  final Color baseColor;
  final Color selectedColor;

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? selectedColor : baseColor;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: color),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
