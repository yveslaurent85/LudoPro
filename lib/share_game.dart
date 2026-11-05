import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'accounts.dart';
import 'damier.dart';
import 'deux_des.dart';
import 'lang.dart';
import 'online.dart';
import 'songo.dart';

/// Adresse du site (utilisée pour les liens partagés depuis l'appli Android).
/// Sur le site web, c'est l'adresse réelle du site qui est utilisée.
const String kSiteUrl = 'https://katikagames.com';

String _gameName(String col) {
  switch (col) {
    case 'deuxdes':
      return tr('Deux dés', 'Two dice');
    case 'songo':
      return 'Songô';
    case 'damier':
      return tr('Damier', 'Draughts');
    default:
      return 'Ludo';
  }
}

String _siteBase() {
  if (kIsWeb) {
    final o = Uri.base.origin;
    if (o.startsWith('http')) return '$o/jouer/';
  }
  return '$kSiteUrl/jouer/';
}

String _link(String col, String id, String mode) =>
    '${_siteBase()}?g=$col.$id&m=$mode';

String _date(dynamic t) {
  if (t is! Timestamp) return '';
  final d = t.toDate();
  String two(int n) => n < 10 ? '0$n' : '$n';
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

/// Le message à partager : informations de la partie + liens pour
/// rejoindre ou regarder.
String buildShareMessage(String col, String id, Map<String, dynamic> d) {
  final players = ((d['players'] as List?) ?? const []).length;
  final max = (d['maxPlayers'] as num?)?.toInt() ?? (players > 0 ? players : 2);
  final stake = (d['stake'] as num?)?.toInt() ?? 0;
  final team = d['teamMode'] == true;
  final host = '${d['hostName'] ?? ''}';
  final lines = <String>[
    tr('🎲 Rejoins ma partie de ${_gameName(col)} sur Katika !',
        '🎲 Join my ${_gameName(col)} game on Katika!'),
    '',
    if (team)
      tr('🤝 Partie en ÉQUIPE 2 vs 2 — gain partagé entre les 2 vainqueurs',
          '🤝 TEAM game 2 vs 2 — prize shared between the 2 winners'),
    if (host.isNotEmpty) tr('👤 Créateur : $host', '👤 Host: $host'),
    tr('👥 Joueurs : $max', '👥 Players: $max'),
    if (col == 'games')
      tr('🎯 Pions/joueur : ${(d['pawnCount'] as num?)?.toInt() ?? 4}',
          '🎯 Pawns/player: ${(d['pawnCount'] as num?)?.toInt() ?? 4}'),
    if (col == 'games')
      tr('⏱️ Timer : ${(d['autoSecs'] as num?)?.toInt() ?? 10}s/tour',
          '⏱️ Timer: ${(d['autoSecs'] as num?)?.toInt() ?? 10}s/turn'),
    if (stake > 0)
      tr('💰 Mise/joueur : ${Wallet.format(stake)}',
          '💰 Stake/player: ${Wallet.format(stake)}')
    else
      tr('💰 Partie gratuite', '💰 Free game'),
    if (stake > 0)
      tr('🏆 Gain total espéré : ${Wallet.format(stake)} × $max = ${Wallet.format(stake * max)}',
          '🏆 Expected total prize: ${Wallet.format(stake)} × $max = ${Wallet.format(stake * max)}'),
    if (_date(d['createdAt']).isNotEmpty)
      tr('📅 Créée le : ${_date(d['createdAt'])}',
          '📅 Created on: ${_date(d['createdAt'])}'),
    '',
    tr('🔗 Rejoindre le challenge : ${_link(col, id, 'join')}',
        '🔗 Join the challenge: ${_link(col, id, 'join')}'),
    tr('📺 Voir le match en direct : ${_link(col, id, 'live')}',
        '📺 Watch the match live: ${_link(col, id, 'live')}'),
  ];
  return lines.join('\n');
}

/// Fenêtre de partage d'une partie (WhatsApp ou copie du message).
Future<void> showShareSheet(
  BuildContext context, {
  required String collection,
  required String gameId,
}) async {
  Map<String, dynamic>? d;
  try {
    final s = await FirebaseFirestore.instance
        .collection(collection)
        .doc(gameId)
        .get();
    d = s.data();
  } catch (_) {}
  if (!context.mounted) return;
  if (d == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr('Partie introuvable.', 'Game not found.'))),
    );
    return;
  }
  final text = buildShareMessage(collection, gameId, d);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('📤 Partager la partie', '📤 Share the game')),
      content: SingleChildScrollView(
        child: SelectableText(text, style: const TextStyle(fontSize: 13)),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text(tr('Message copié', 'Message copied'))),
              );
            }
          },
          child: Text(tr('Copier', 'Copy')),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF25D366),
            foregroundColor: Colors.white,
          ),
          onPressed: () async {
            final uri =
                Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
            final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
            if (!ok) await Clipboard.setData(ClipboardData(text: text));
          },
          child: const Text('WhatsApp'),
        ),
      ],
    ),
  );
}

// ----------------------------------------------------------------------
// Ouverture d'un lien partagé : ?g=<jeu>.<id>&m=join|live
// ----------------------------------------------------------------------

const List<String> _cols = ['games', 'deuxdes', 'songo', 'damier'];

class SharedLink {
  static String? _col;
  static String? _id;
  static bool _watch = false;
  static bool _parsed = false;

  static void _parse() {
    if (_parsed) return;
    _parsed = true;
    if (!kIsWeb) return;
    try {
      final q = Uri.base.queryParameters;
      final g = q['g'] ?? '';
      final i = g.indexOf('.');
      if (i <= 0) return;
      final col = g.substring(0, i);
      final id = g.substring(i + 1);
      if (!_cols.contains(col) || !RegExp(r'^[A-Za-z0-9_-]{6,40}$').hasMatch(id)) {
        return;
      }
      _col = col;
      _id = id;
      _watch = q['m'] == 'live';
    } catch (_) {}
  }

  static bool get pending {
    _parse();
    return _id != null;
  }

  static Future<void> handle(BuildContext context) async {
    _parse();
    final col = _col, id = _id;
    if (col == null || id == null) return;
    _col = null;
    _id = null;

    var user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      try {
        user = await FirebaseAuth.instance
            .authStateChanges()
            .firstWhere((u) => u != null)
            .timeout(const Duration(minutes: 10));
      } catch (_) {
        return;
      }
    }
    if (user == null || !context.mounted) return;
    final me = user;

    void toast(String m) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
      }
    }

    final ref = FirebaseFirestore.instance.collection(col).doc(id);
    Map<String, dynamic>? d0;
    try {
      d0 = (await ref.get()).data();
    } catch (_) {}
    if (d0 == null) {
      toast(tr('Cette partie n\'existe plus.', 'This game no longer exists.'));
      return;
    }
    if (!context.mounted) return;
    final d = d0;

    final players = ((d['players'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final mine = players.any((p) => p['uid'] == me.uid);
    final max = (d['maxPlayers'] as num?)?.toInt() ?? 2;
    final waiting = d['status'] == 'waiting';

    if (mine) {
      _push(context, _room(col, id, spectate: false));
      return;
    }
    if (_watch || !waiting || players.length >= max) {
      if (!_watch) {
        toast(tr('Cette partie est complète ou déjà commencée : tu la regardes.',
            'This game is full or already started: you are watching it.'));
      }
      _push(context, _room(col, id, spectate: true));
      return;
    }

    final stake = (d['stake'] as num?)?.toInt() ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Rejoindre la partie ?', 'Join the game?')),
        content: Text(tr(
            '${_gameName(col)} · créée par ${d['hostName'] ?? ''}\n'
                '${stake > 0 ? 'Mise : ${Wallet.format(stake)}' : 'Partie gratuite'}',
            '${_gameName(col)} · hosted by ${d['hostName'] ?? ''}\n'
                '${stake > 0 ? 'Stake: ${Wallet.format(stake)}' : 'Free game'}')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('Regarder seulement', 'Just watch')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr('Rejoindre', 'Join')),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (ok != true) {
      _push(context, _room(col, id, spectate: true));
      return;
    }

    final name = (me.displayName != null && me.displayName!.isNotEmpty)
        ? me.displayName!
        : (me.email ?? 'Joueur');
    try {
      final err = await FirebaseFirestore.instance.runTransaction<String?>((tx) async {
        final snap = await tx.get(ref);
        final x = snap.data();
        if (x == null) return tr('Cette partie n\'existe plus.', 'This game no longer exists.');
        final list = ((x['players'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        if (list.any((p) => p['uid'] == me.uid)) return null;
        final mx = (x['maxPlayers'] as num?)?.toInt() ?? 2;
        if (x['status'] != 'waiting' || list.length >= mx) {
          return tr('Cette partie est déjà complète.', 'This game is already full.');
        }
        list.add({'uid': me.uid, 'name': name});
        tx.update(ref, {
          'players': list,
          'uids': FieldValue.arrayUnion([me.uid]),
        });
        return null;
      });
      if (err != null) {
        toast(err);
        return;
      }
      try {
        await Wallet.payStake(id);
      } catch (e) {
        try {
          await Wallet.leaveGame(id);
        } catch (_) {}
        toast(Wallet.errorText(e));
        return;
      }
      if (context.mounted) _push(context, _room(col, id, spectate: false));
    } catch (_) {
      toast(tr('Impossible de rejoindre la partie.', 'Could not join the game.'));
    }
  }

  static void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  static Widget _room(String col, String id, {required bool spectate}) {
    switch (col) {
      case 'deuxdes':
        return spectate ? DeuxDesSpectator(roomId: id) : deuxDesRoomPage(id);
      case 'songo':
        return spectate ? SongoSpectator(roomId: id) : songoRoomPage(id);
      case 'damier':
        return spectate ? DamierSpectator(roomId: id) : damierRoomPage(id);
      default:
        return OnlineGameRoom(gameId: id, spectate: spectate);
    }
  }
}

/// Enveloppe l'écran d'accueil : ouvre le lien partagé (s'il y en a un)
/// dès que l'appli est prête.
class SharedLinkGate extends StatefulWidget {
  const SharedLinkGate({super.key, required this.child});

  final Widget child;

  @override
  State<SharedLinkGate> createState() => _SharedLinkGateState();
}

class _SharedLinkGateState extends State<SharedLinkGate> {
  @override
  void initState() {
    super.initState();
    if (SharedLink.pending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) SharedLink.handle(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
