import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart' hide Text;

import 'accounts.dart';
import 'lang.dart';
import 'push_setup.dart';

/// Permet d'afficher un message depuis n'importe quel écran (mis sur le MaterialApp).
final GlobalKey<ScaffoldMessengerState> kMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Avis globaux :
///  • gains / pertes des paris (CHAT, Duel, Défi 7…) : « +950 FCFA » ou « −1000 FCFA » + nouveau solde ;
///  • notifications reçues pendant que l'appli est ouverte (le navigateur ne les affiche pas seul) ;
///  • renouvellement du jeton de notification à chaque ouverture (sinon les alertes finissent par ne plus arriver).
class AppNotices {
  static bool _started = false;
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  static String? _seen;
  static bool _first = true;

  static void start() {
    if (_started) return;
    _started = true;
    try {
      FirebaseAuth.instance.authStateChanges().listen(_onUser, onError: (Object _) {});
    } catch (_) {}
    try {
      FirebaseMessaging.onMessage.listen(_onPush, onError: (Object _) {});
      FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
        if (await pushIsOn()) {
          try {
            await Wallet.setPush(t, true);
          } catch (_) {}
        }
      }, onError: (Object _) {});
    } catch (_) {}
  }

  static Future<void> _onUser(User? u) async {
    await _userSub?.cancel();
    _userSub = null;
    _first = true;
    _seen = null;
    if (u == null) return;
    _userSub = FirebaseFirestore.instance.collection('users').doc(u.uid).snapshots().listen(_onDoc, onError: (Object _) {});
    try {
      if (await pushIsOn()) {
        final t = await FirebaseMessaging.instance.getToken(vapidKey: kWebPushKey);
        if (t != null && t.isNotEmpty) await Wallet.setPush(t, true);
      }
    } catch (_) {}
  }

  static void _onDoc(DocumentSnapshot<Map<String, dynamic>> s) {
    final data = s.data();
    final n = data?['betNotice'];
    if (n is! Map) {
      _first = false;
      return;
    }
    final id = '${n['id']}';
    if (_first) {
      _first = false;
      _seen = id; // avis déjà là à l'ouverture : on ne le remontre pas
      return;
    }
    if (id == _seen) return;
    _seen = id;
    final delta = (n['delta'] as num?)?.toInt() ?? 0;
    if (delta == 0) return;
    final bal = (data?['balance'] as num?)?.toInt();
    final win = delta > 0;
    final label = '${n['label'] ?? ''}';
    final detail = '${n['detail'] ?? ''}';
    final m = kMessengerKey.currentState;
    if (m == null) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      behavior: SnackBarBehavior.floating,
      backgroundColor: win ? const Color(0xFF1B8A3A) : const Color(0xFFB3261E),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${win ? '+' : '−'}${Wallet.format(delta.abs())}${label.isEmpty ? '' : '  ($label)'}',
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
          ),
          Text(
            '${win ? tr('Bravo, pari gagné ! ', 'Well done, bet won! ') : tr('Pari perdu. ', 'Bet lost. ')}'
            '${detail.isEmpty ? '' : '$detail · '}'
            '${bal == null ? '' : '${tr('Nouveau solde', 'New balance')} : ${Wallet.format(bal)}'}',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    ));
  }

  static void _onPush(RemoteMessage msg) {
    final n = msg.notification;
    if (n == null) return;
    final m = kMessengerKey.currentState;
    if (m == null) return;
    m.showSnackBar(SnackBar(
      duration: const Duration(seconds: 7),
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF1E6BFF),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(n.title ?? 'Katika', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
          if ((n.body ?? '').isNotEmpty) Text(n.body!, style: const TextStyle(color: Colors.white, fontSize: 13)),
        ],
      ),
    ));
  }
}
