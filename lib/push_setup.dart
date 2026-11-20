import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:shared_preferences/shared_preferences.dart';
import 'accounts.dart';
import 'lang.dart';

/// Clé « Web Push » du projet Firebase (publique, faite pour être dans l'appli).
const String kWebPushKey =
    'BHLBQxfH_s9yJtL2SVytqhgVq_iXU18irWpX0d_hXyMrn30zHLaAQbPF1YdtoKWrCOSTelKTXBy2HqG9C18pyYc';

const String _kPushPref = 'push_on';

Future<bool> pushIsOn() async {
  try {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kPushPref) ?? false;
  } catch (_) {
    return false;
  }
}

/// Demande l'autorisation, récupère l'appareil et l'enregistre sur le serveur.
/// Renvoie un message à montrer au joueur.
Future<String> enablePush() async {
  try {
    final m = FirebaseMessaging.instance;
    final s = await m.requestPermission(alert: true, badge: true, sound: true);
    if (s.authorizationStatus != AuthorizationStatus.authorized &&
        s.authorizationStatus != AuthorizationStatus.provisional) {
      return tr(
          'Notifications refusées. Autorise-les dans les réglages du navigateur (cadenas à côté de l\'adresse) puis réessaie.',
          'Notifications blocked. Allow them in your browser settings (padlock next to the address) then try again.');
    }
    final token = await m.getToken(vapidKey: kWebPushKey);
    if (token == null || token.isEmpty) {
      return tr('Impossible d\'activer les notifications sur cet appareil.',
          'Could not enable notifications on this device.');
    }
    await Wallet.setPush(token, true);
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kPushPref, true);
    return tr('🔔 Notifications activées : tu seras prévenu des nouvelles parties.',
        '🔔 Notifications on: you will be told about new games.');
  } catch (e) {
    return tr('Notifications indisponibles sur cet appareil (${Wallet.errorText(e)}).',
        'Notifications unavailable on this device (${Wallet.errorText(e)}).');
  }
}

Future<String> disablePush() async {
  try {
    final token = await FirebaseMessaging.instance.getToken(vapidKey: kWebPushKey);
    if (token != null && token.isNotEmpty) await Wallet.setPush(token, false);
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kPushPref, false);
    return tr('🔕 Notifications coupées.', '🔕 Notifications off.');
  } catch (e) {
    return Wallet.errorText(e);
  }
}

/// Action du bouton du menu : active ou coupe les notifications, puis informe le joueur.
Future<void> pushMenuAction(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final on = await pushIsOn();
  final msg = on ? await disablePush() : await enablePush();
  messenger.showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 5)));
}
