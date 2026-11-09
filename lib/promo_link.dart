import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

/// Lien promo personnel : https://katikagames.com/jouer/?ref=CODE
/// Quand quelqu'un ouvre le site ou la PWA avec ce lien, le code est gardé en mémoire
/// et rempli tout seul à la création de son compte : il devient directement son filleul.
class PromoLink {
  static const String _key = 'katika_ref';
  static const String _site = 'https://katikagames.com';

  static String? _cached;

  /// À appeler une fois au démarrage : lit « ?ref=... » dans l'adresse et le garde.
  static Future<void> capture() async {
    try {
      if (kIsWeb) {
        final q = Uri.base.queryParameters;
        final raw = (q['ref'] ?? q['promo'] ?? '').trim();
        final code = _clean(raw);
        if (code.isNotEmpty) {
          _cached = code;
          final p = await SharedPreferences.getInstance();
          await p.setString(_key, code);
          return;
        }
      }
      final p = await SharedPreferences.getInstance();
      _cached = p.getString(_key);
    } catch (_) {}
  }

  /// Code du parrain venu par un lien ('' si aucun).
  static Future<String> pending() async {
    if (_cached != null && _cached!.isNotEmpty) return _cached!;
    try {
      final p = await SharedPreferences.getInstance();
      _cached = p.getString(_key) ?? '';
    } catch (_) {}
    return _cached ?? '';
  }

  /// Une fois le code appliqué (ou refusé), on l'oublie.
  static Future<void> clear() async {
    _cached = '';
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_key);
    } catch (_) {}
  }

  static String _clean(String s) {
    final t = s.replaceAll(RegExp(r'[^\p{L}\p{N}_ .-]', unicode: true), '').trim();
    return t.length > 40 ? t.substring(0, 40) : t;
  }

  /// Lien à partager pour ce code.
  static String linkFor(String code) {
    var base = '$_site/jouer/';
    if (kIsWeb) {
      final o = Uri.base.origin;
      if (o.startsWith('http')) base = '$o/jouer/';
    }
    return '$base?ref=${Uri.encodeQueryComponent(code)}';
  }
}
