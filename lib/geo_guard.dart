import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'lang.dart';

/// Erreur de localisation (message lisible pour le joueur).
class GeoException implements Exception {
  GeoException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Position du joueur, exigée par les jeux anti-triche (Fap-Fap).
/// Fonctionne sur le web (le navigateur demande l'autorisation) et sur Android.
class GeoGuard {
  /// Renvoie { lat, lng, acc } ou lève une [GeoException] si la localisation
  /// est désactivée, refusée, simulée ou introuvable.
  static Future<Map<String, dynamic>> position() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw GeoException(tr(
            'Active la localisation (GPS) de ton téléphone pour jouer au Fap-Fap.',
            'Turn on your phone location (GPS) to play Fap-Fap.'));
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw GeoException(tr(
            'La géolocalisation est obligatoire au Fap-Fap. Autorise la localisation pour Katika dans les réglages du navigateur ou du téléphone, puis réessaie.',
            'Location is required for Fap-Fap. Allow location for Katika in your browser or phone settings, then try again.'));
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (p.isMocked) {
        throw GeoException(tr(
            'Position simulée détectée : désactive l\'appli de fausse position pour jouer.',
            'Fake location detected: turn off the mock-location app to play.'));
      }
      return <String, dynamic>{'lat': p.latitude, 'lng': p.longitude, 'acc': p.accuracy};
    } on GeoException {
      rethrow;
    } on TimeoutException {
      throw GeoException(tr(
          'Position introuvable. Active le GPS (localisation précise), sors si tu es dans un bâtiment et réessaie.',
          'Position not found. Turn on precise GPS, go outside if you are in a building and try again.'));
    } catch (_) {
      throw GeoException(tr(
          'Impossible de lire ta position. Vérifie que la localisation est activée et autorisée.',
          'Could not read your position. Check that location is on and allowed.'));
    }
  }
}
