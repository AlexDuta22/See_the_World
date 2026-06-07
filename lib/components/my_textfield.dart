import 'package:flutter/material.dart';

class MyTextField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final bool obscureText;

  const MyTextField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.obscureText,
  });

  @override
  State<MyTextField> createState() => _MyTextFieldState();
}

class _MyTextFieldState extends State<MyTextField> {
  // Pornește ascuns dacă e câmp de parolă; butonul „ochi" comută starea asta.
  late bool _obscured = widget.obscureText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25.0),
      child: TextField(
        controller: widget.controller,
        obscureText: _obscured,
        decoration: InputDecoration(
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          fillColor: Colors.grey.shade200,
          filled: true,
          hintText: widget.hintText,
          hintStyle: TextStyle(color: Colors.grey[500]),
          // Butonul în formă de ochi apare doar la câmpurile de parolă și comută
          // între afișarea și ascunderea textului introdus. Iconița face o
          // tranziție lină (fade + scale) la apăsare, ca în aplicațiile uzuale.
          suffixIcon: widget.obscureText
              ? IconButton(
                  tooltip: _obscured ? 'Arată parola' : 'Ascunde parola',
                  onPressed: () => setState(() => _obscured = !_obscured),
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) => ScaleTransition(
                      scale: animation,
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: Icon(
                      _obscured ? Icons.visibility_off : Icons.visibility,
                      key: ValueKey<bool>(_obscured),
                      color: Colors.grey[600],
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
