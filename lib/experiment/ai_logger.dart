import 'package:cloud_firestore/cloud_firestore.dart';

// Logger uniform al experimentului. Fiecare rulare (un brat, o suprafata) scrie
// un document in colectia top-level `ai_logs`. Schema e aceeasi pentru Home si
// Assistant, ca sa pot face comparatie pereche dupa pairId. Best-effort: inghite
// erorile ca o logare ratata sa nu strice fluxul / demo-ul.
//
// Necesita regula Firestore pentru /ai_logs (vezi firestore.rules) deployata,
// altfel scrierea e respinsa silentios.
Future<void> logRun({
  required String arm, // 'none' (A) sau 'full' (B)
  required String surface, // 'home' sau 'assistant'
  required String uid,
  required String query, // interogarea (Home) sau promptul (Assistant)
  required List<Map<String, dynamic>> items, // {id, name, score}
  required String pairId, // acelasi pentru A si B la aceeasi interogare+persoana
  required int latencyMs,
}) async {
  try {
    await FirebaseFirestore.instance.collection('ai_logs').add({
      'arm': arm,
      'surface': surface,
      'uid': uid,
      'query': query,
      'items': items,
      'itemCount': items.length,
      'pairId': pairId,
      'latencyMs': latencyMs,
      'timestamp': FieldValue.serverTimestamp(),
    });
  } catch (_) {
    // logare best-effort
  }
}

// Id stabil (FNV-1a) dintr-un seed, ca aceeasi interogare+persoana sa produca
// acelasi pairId pentru ambele brate. String.hashCode nu e garantat stabil.
String experimentPairId(String seed) {
  final normalized = seed.trim().toLowerCase();
  var hash = 0x811c9dc5;
  for (final unit in normalized.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
