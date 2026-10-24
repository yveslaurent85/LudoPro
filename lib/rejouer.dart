import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;

import 'accounts.dart';
import 'lang.dart';

// ----------------------------------------------------------------------
// Rejouer : chaque joueur accepte ou refuse. L'hôte relance avec ceux qui
// ont accepté ; si l'hôte ne rejoue pas, le premier joueur qui a accepté
// relance à sa place. Chacun repaie sa mise dans la nouvelle partie.
// ----------------------------------------------------------------------

/// Erreur lisible (message déjà prêt à afficher).
class RematchException implements Exception {
  RematchException(this.message);
  final String message;
  @override
  String toString() => message;
}

String _newCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = Random.secure();
  return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
}

String _userName(User u) {
  final n = u.displayName;
  if (n != null && n.isNotEmpty) return n;
  return u.email ?? 'Joueur';
}

List<int> _startPawns(int count, bool startOut) =>
    List<int>.generate(count, (i) => startOut ? 43 + (i % 2) : -1);

Future<void> _checkBalance(String uid, int stake) async {
  if (stake <= 0) return;
  final s = await FirebaseFirestore.instance.collection('users').doc(uid).get();
  final b = s.data()?['balance'];
  if ((b is num ? b.toInt() : 0) < stake) {
    throw RematchException(tr(
      'Solde insuffisant : il te faut au moins ${Wallet.format(stake)}.',
      'Insufficient balance: you need at least ${Wallet.format(stake)}.',
    ));
  }
}

/// Paie la mise de la nouvelle salle ; en cas d'échec, on la quitte.
Future<void> _payOrRollback(String id) async {
  try {
    await Wallet.payStake(id);
  } catch (e) {
    try {
      await Wallet.leaveGame(id);
    } catch (_) {}
    throw RematchException(Wallet.errorText(e));
  }
}

/// Crée la salle de revanche du Ludo (mêmes réglages que la partie finie).
/// La salle est privée : seuls ceux qui ont accepté la rejoignent.
Future<String> createLudoRematchRoom(Map<String, dynamic> old, int count) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw RematchException('Connexion requise.');
  final stake = (old['stake'] as num?)?.toInt() ?? 0;
  await _checkBalance(user.uid, stake);

  final pawns = (old['pawnCount'] as num?)?.toInt() ?? 4;
  final startOut = old['startOut'] == true;
  final team = old['teamMode'] == true && count == 4;
  final ref = FirebaseFirestore.instance.collection('games').doc();
  try {
    await ref.set({
      'hostUid': user.uid,
      'hostName': _userName(user),
      'maxPlayers': count,
      'pawnCount': pawns,
      'doorSafe': old['doorSafe'] != false,
      'starSafe': old['starSafe'] != false,
      'startOut': startOut,
      'private': true,
      'teamMode': team,
      'stake': stake,
      'paid': <String>[],
      'pot': 0,
      'partners': [-1, -1, -1, -1],
      'invites': <Map<String, int>>[],
      'code': _newCode(),
      'status': 'waiting',
      'players': [
        {'uid': user.uid, 'name': _userName(user)},
      ],
      'uids': [user.uid],
      'createdAt': FieldValue.serverTimestamp(),
      'p0': _startPawns(pawns, startOut),
      'p1': _startPawns(pawns, startOut),
      'p2': _startPawns(pawns, startOut),
      'p3': _startPawns(pawns, startOut),
      'cur': 0,
      'hasRolled': false,
      'dice': 1,
      'lastRoll': [1, 1, 1, 1],
      'msg': 'Touche ton dé ou glisse-le pour le lancer !',
      'over': false,
      'writer': '',
      'rev': 0,
    });
  } catch (_) {
    throw RematchException('Impossible de créer la nouvelle partie.');
  }
  await _payOrRollback(ref.id);
  return ref.id;
}

/// Crée la salle de revanche de Deux dés.
Future<String> createDeuxDesRematchRoom(
  Map<String, dynamic> old,
  int count,
) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw RematchException('Connexion requise.');
  final stake = (old['stake'] as num?)?.toInt() ?? 0;
  await _checkBalance(user.uid, stake);

  final ref = FirebaseFirestore.instance.collection('deuxdes').doc();
  try {
    await ref.set({
      'hostUid': user.uid,
      'hostName': _userName(user),
      'maxPlayers': count,
      'private': true,
      'stake': stake,
      'paid': <String>[],
      'pot': 0,
      'code': _newCode(),
      'status': 'waiting',
      'players': [
        {'uid': user.uid, 'name': _userName(user)},
      ],
      'uids': [user.uid],
      'scores': List<int>.filled(count, 0),
      'cur': 0,
      'rolled': false,
      'over': false,
      'winners': <int>[],
      'd1': 1,
      'd2': 1,
      'spin1': [2, 3, 1],
      'spin2': [3, 2, 2],
      'rollN': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
  } catch (_) {
    throw RematchException('Impossible de créer la nouvelle partie.');
  }
  await _payOrRollback(ref.id);
  return ref.id;
}

/// Rejoint la salle de revanche (ajout dans la salle + paiement de la mise).
/// Renvoie un message d'erreur, ou null si tout s'est bien passé.
Future<String?> joinRoom(String collection, String id) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return 'Connexion requise.';
  final ref = FirebaseFirestore.instance.collection(collection).doc(id);
  try {
    final pre = await ref.get();
    final pd = pre.data();
    final isMember = ((pd?['uids'] as List?) ?? const []).contains(user.uid);
    if (!isMember) {
      await _checkBalance(user.uid, (pd?['stake'] as num?)?.toInt() ?? 0);
    }

    final result =
        await FirebaseFirestore.instance.runTransaction<String?>((tx) async {
      final snap = await tx.get(ref);
      final d = snap.data();
      if (d == null) return "Cette partie n'existe plus.";
      final players = ((d['players'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (players.any((p) => p['uid'] == user.uid)) return null;
      final max = (d['maxPlayers'] as num).toInt();
      if (d['status'] != 'waiting' || players.length >= max) {
        return 'La nouvelle partie est déjà complète.';
      }
      players.add({'uid': user.uid, 'name': _userName(user)});
      tx.update(ref, {
        'players': players,
        'uids': FieldValue.arrayUnion([user.uid]),
      });
      return null;
    });
    if (result != null) return result;

    try {
      await Wallet.payStake(id);
    } catch (e) {
      try {
        await Wallet.leaveGame(id);
      } catch (_) {}
      return Wallet.errorText(e);
    }
    return null;
  } on RematchException catch (e) {
    return e.message;
  } catch (_) {
    return 'Impossible de rejoindre la nouvelle partie.';
  }
}

Widget _box(List<Widget> children) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      color: Colors.white.withOpacity(0.1),
      border: Border.all(color: Colors.white24),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

const TextStyle _title = TextStyle(
  color: Colors.white,
  fontSize: 15,
  fontWeight: FontWeight.w900,
);
const TextStyle _small = TextStyle(color: Colors.white70, fontSize: 12);

// ----------------------------------------------------------------------
// En ligne : vote de chaque joueur dans le document de la partie finie
//   rematch.<uid> = true / false   et   nextGame = id de la nouvelle salle
// ----------------------------------------------------------------------

class RematchPanel extends StatefulWidget {
  const RematchPanel({
    super.key,
    required this.collection,
    required this.gameId,
    required this.data,
    required this.createRoom,
    required this.openRoom,
  });

  /// « games » (Ludo) ou « deuxdes ».
  final String collection;
  final String gameId;

  /// Dernier état connu de la partie terminée.
  final Map<String, dynamic> data;

  /// Crée la nouvelle salle (le créateur y a déjà payé sa mise).
  final Future<String> Function(Map<String, dynamic> old, int count) createRoom;

  /// Ouvre la nouvelle salle (remplace l'écran actuel).
  final void Function(String roomId) openRoom;

  @override
  State<RematchPanel> createState() => _RematchPanelState();
}

class _RematchPanelState extends State<RematchPanel> {
  final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  bool _busy = false;
  bool _joinStarted = false;
  String? _error;

  DocumentReference<Map<String, dynamic>> get _ref => FirebaseFirestore.instance
      .collection(widget.collection)
      .doc(widget.gameId);

  List<Map<String, dynamic>> get _players =>
      ((widget.data['players'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  Map<String, dynamic> get _votes {
    final r = widget.data['rematch'];
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  String? get _next {
    final n = widget.data['nextGame'];
    return n is String && n.isNotEmpty ? n : null;
  }

  List<Map<String, dynamic>> get _accepted =>
      _players.where((p) => _votes[p['uid']] == true).toList();

  /// Qui relance : l'hôte s'il rejoue, sinon le premier joueur qui a accepté.
  String? get _launcherUid {
    final host = widget.data['hostUid'];
    if (host is String && _votes[host] == true) return host;
    final a = _accepted;
    return a.isEmpty ? null : '${a.first['uid']}';
  }

  Future<void> _vote(bool yes) async {
    setState(() => _error = null);
    try {
      await _ref.update({'rematch.$uid': yes});
    } catch (_) {
      if (mounted) setState(() => _error = 'Action impossible. Réessaie.');
    }
  }

  Future<void> _launch() async {
    final count = _accepted.length;
    if (_busy || count < 2) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await widget.createRoom(widget.data, count);
      _joinStarted = true; // le créateur ouvre sa salle lui-même
      await _ref.update({'nextGame': id});
      if (!mounted) return;
      widget.openRoom(id);
    } on RematchException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Impossible de relancer la partie.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Un autre joueur a relancé : ceux qui ont accepté rejoignent la salle.
  void _maybeJoin() {
    final next = _next;
    if (next == null || _joinStarted || _votes[uid] != true) return;
    _joinStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      setState(() => _busy = true);
      final err = await joinRoom(widget.collection, next);
      if (!mounted) return;
      if (err != null) {
        setState(() {
          _busy = false;
          _error = err;
        });
      } else {
        widget.openRoom(next);
      }
    });
  }

  String _nameOf(String? u) {
    for (final p in _players) {
      if (p['uid'] == u) return '${p['name']}';
    }
    return '?';
  }

  @override
  Widget build(BuildContext context) {
    final players = _players;
    if (!players.any((p) => p['uid'] == uid)) return const SizedBox.shrink();

    _maybeJoin();

    final votes = _votes;
    final me = votes[uid];
    final launcher = _launcherUid;
    final iAmLauncher = launcher == uid;
    final accepted = _accepted.length;
    final stake = (widget.data['stake'] as num?)?.toInt() ?? 0;
    final next = _next;

    Widget action;
    if (me == null) {
      action = Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
              ),
              onPressed: () => _vote(false),
              child: const Text('Non merci'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22B14C),
                foregroundColor: Colors.white,
              ),
              onPressed: () => _vote(true),
              child: const Text('Rejouer'),
            ),
          ),
        ],
      );
    } else if (me == false) {
      action = Row(
        children: [
          Expanded(child: Text(tr('Tu ne rejoues pas.', "You're not playing again."), style: _small)),
          if (next == null)
            TextButton(
              onPressed: () => _vote(true),
              child: const Text('Changer d\'avis'),
            ),
        ],
      );
    } else if (next != null) {
      action = Text(
        tr('Nouvelle partie : on te place dans la salle...',
            'New game: moving you to the room...'),
        style: _small,
      );
    } else if (iAmLauncher) {
      action = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22B14C),
                foregroundColor: Colors.white,
              ),
              onPressed: (!_busy && accepted >= 2) ? _launch : null,
              child: Text(_busy
                  ? 'Patiente...'
                  : tr('Relancer avec $accepted joueurs',
                      'Restart with $accepted players')),
            ),
          ),
          if (accepted < 2)
            Text(
              tr("Il faut au moins 2 joueurs : attends que d'autres acceptent.",
                  'At least 2 players are needed: wait for others to accept.'),
              style: _small,
            ),
        ],
      );
    } else {
      action = Row(
        children: [
          Expanded(
            child: Text(
              tr('En attente de ${_nameOf(launcher)} pour relancer...',
                  'Waiting for ${_nameOf(launcher)} to restart...'),
              style: _small,
            ),
          ),
          TextButton(
            onPressed: () => _vote(false),
            child: const Text('Finalement non'),
          ),
        ],
      );
    }

    return _box([
      Text(tr('🔁 Rejouer ?', '🔁 Play again?'), style: _title),
      if (stake > 0)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            tr('Chaque joueur repaie sa mise (${Wallet.format(stake)}).',
                'Each player pays the stake again (${Wallet.format(stake)}).'),
            style: _small,
          ),
        ),
      const SizedBox(height: 8),
      for (final p in players)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${p['name']}${p['uid'] == widget.data['hostUid'] ? ' (hôte)' : ''}',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              Text(
                votes[p['uid']] == true
                    ? '✅'
                    : (votes[p['uid']] == false ? '❌' : '⏳'),
              ),
            ],
          ),
        ),
      const SizedBox(height: 8),
      action,
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            _error!,
            style: const TextStyle(
              color: Color(0xFFFF8A80),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
    ]);
  }
}

// ----------------------------------------------------------------------
// Présentiel : un seul téléphone, chaque joueur touche ✅ ou ❌
// ----------------------------------------------------------------------

class LocalRematchPanel extends StatefulWidget {
  const LocalRematchPanel({
    super.key,
    required this.names,
    required this.ids,
    required this.onRelaunch,
    this.stake = 0,
  });

  /// Nom de chaque joueur de la partie finie.
  final List<String> names;

  /// Identifiant de chaque joueur (couleur ou place), dans le même ordre.
  final List<int> ids;
  final int stake;

  /// Appelé avec les identifiants de ceux qui ont accepté.
  final void Function(List<int> accepted) onRelaunch;

  @override
  State<LocalRematchPanel> createState() => _LocalRematchPanelState();
}

class _LocalRematchPanelState extends State<LocalRematchPanel> {
  final Map<int, bool> _choice = {};

  List<int> get _accepted => [
        for (final id in widget.ids)
          if (_choice[id] == true) id,
      ];

  Widget _pick(int id, bool yes) {
    final selected = _choice[id] == yes;
    return GestureDetector(
      onTap: () => setState(() => _choice[id] = yes),
      child: Container(
        width: 38,
        height: 32,
        margin: const EdgeInsets.only(left: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: selected
              ? (yes ? const Color(0xFF22B14C) : const Color(0xFFE5262B))
              : Colors.white.withOpacity(0.12),
        ),
        child: Text(yes ? '✅' : '❌'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accepted = _accepted;
    final n = accepted.length;
    return _box([
      Text(tr('🔁 Rejouer ?', '🔁 Play again?'), style: _title),
      Text(
        widget.stake > 0
            ? tr('Chaque joueur qui rejoue repaie sa mise (${Wallet.format(widget.stake)}).',
                'Each player who plays again pays the stake (${Wallet.format(widget.stake)}).')
            : tr('Chaque joueur choisit : ✅ rejouer ou ❌ arrêter.',
                'Each player picks: ✅ play again or ❌ stop.'),
        style: _small,
      ),
      const SizedBox(height: 8),
      for (int i = 0; i < widget.ids.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.names[i],
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              _pick(widget.ids[i], true),
              _pick(widget.ids[i], false),
            ],
          ),
        ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF22B14C),
            foregroundColor: Colors.white,
          ),
          onPressed: n >= 2 ? () => widget.onRelaunch(accepted) : null,
          child: Text(n >= 2
              ? tr('Relancer avec $n joueurs', 'Restart with $n players')
              : tr('Il faut au moins 2 joueurs', 'At least 2 players needed')),
        ),
      ),
    ]);
  }
}
