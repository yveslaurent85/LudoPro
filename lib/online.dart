import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import 'accounts.dart';
import 'lang.dart';
import 'main.dart';

// ----------------------------------------------------------------------
// Parties en ligne (Firestore, collection « games »)
// ----------------------------------------------------------------------

const BoxDecoration _bg = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1F5BFF), Color(0xFF0B2FA6), Color(0xFF061A66)],
  ),
);

const List<Color> _seatPalette = [
  Color(0xFFE5262B), // Rouge
  Color(0xFF22B14C), // Vert
  Color(0xFF1E6BFF), // Bleu
  Color(0xFFFFC21A), // Jaune
];
const List<String> _seatNames = ['Rouge', 'Vert', 'Bleu', 'Jaune'];

/// Couleurs utilisées selon le nombre de joueurs (comme dans le jeu).
List<int> _colorsFor(int maxPlayers) => maxPlayers == 2
    ? [0, 2]
    : (maxPlayers == 3 ? [0, 1, 2] : [0, 1, 2, 3]);

/// Pions au départ : à la base (-1), ou déjà dehors sur les positions 43 et 44
/// de leur chemin (près du centre) quand l'option « pions dehors au
/// départ » est activée.
List<int> _startPawns(int count, bool startOut) =>
    List<int>.generate(count, (i) => startOut ? 43 + (i % 2) : -1);

/// Infos passées au plateau de jeu quand la partie est en ligne.
class OnlineSession {
  const OnlineSession({
    required this.gameId,
    required this.uid,
    required this.mySeat,
    required this.names,
    this.uids = const [],
    this.spectator = false,
  });

  /// uid des joueurs, dans l'ordre des places (détection des déconnexions).
  final List<String> uids;

  /// Vrai si on regarde la partie sans y jouer.
  final bool spectator;

  final String gameId;
  final String uid;
  final int mySeat; // place dans la partie (0 = créateur)
  final List<String> names; // pseudos, dans l'ordre des places
}

CollectionReference<Map<String, dynamic>> get _games =>
    FirebaseFirestore.instance.collection('games');

String _stakeText(Map<String, dynamic> d) {
  final s = (d['stake'] as num?)?.toInt();
  if (s == null) return '';
  return s > 0
      ? tr(' • mise $s', ' • stake $s')
      : tr(' • gratuite', ' • free');
}

/// Date et heure de création d'une partie : « • 24/10/2026 19:55 ».
String _createdText(dynamic t) {
  if (t is! Timestamp) return '';
  final d = t.toDate();
  String two(int n) => n < 10 ? '0$n' : '$n';
  return ' • ${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

String _displayName(User u) {
  final n = u.displayName;
  if (n != null && n.isNotEmpty) return n;
  return u.email ?? 'Joueur';
}

/// Code de salle à 6 caractères (sans 0/O/1/I pour éviter les confusions).
String _newCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = Random.secure();
  return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
}

List<Map<String, dynamic>> _playersOf(Map<String, dynamic> d) {
  return ((d['players'] as List?) ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
}

// --- Mode équipe (2 contre 2) -----------------------------------------
// Avec 4 joueurs, la place (seat) est égale à la couleur : 0 Rouge,
// 1 Vert, 2 Bleu, 3 Jaune. « partners » donne le binôme de chaque place
// (-1 = pas encore de binôme). « invites » = invitations en attente.

List<int> _partnersOf(Map<String, dynamic> d) {
  final l = d['partners'];
  if (l is List && l.length == 4) {
    return l.map((e) => (e as num).toInt()).toList();
  }
  return [-1, -1, -1, -1];
}

List<Map<String, int>> _invitesOf(Map<String, dynamic> d) {
  return ((d['invites'] as List?) ?? const []).map((e) {
    final m = e as Map;
    return <String, int>{
      'from': (m['from'] as num).toInt(),
      'to': (m['to'] as num).toInt(),
    };
  }).toList();
}

/// Modifie les binômes / invitations dans une transaction (salle d'attente).
/// Quand les 4 joueurs sont là et que tous ont un binôme, la partie démarre.
Future<void> _teamTx(
  String gameId,
  String uid,
  void Function(
    int seat,
    List<int> partners,
    List<Map<String, int>> invites,
  ) change,
) async {
  final ref = _games.doc(gameId);
  await FirebaseFirestore.instance.runTransaction<void>((tx) async {
    final snap = await tx.get(ref);
    final d = snap.data();
    if (d == null || d['status'] != 'waiting' || d['teamMode'] != true) {
      return;
    }
    final players = _playersOf(d);
    final seat = players.indexWhere((p) => p['uid'] == uid);
    if (seat < 0) return;

    final partners = _partnersOf(d);
    final invites = _invitesOf(d);
    change(seat, partners, invites);

    final max = (d['maxPlayers'] as num).toInt();
    final paidCount = ((d['paid'] as List?) ?? const []).length;
    final ready = players.length >= max &&
        paidCount >= max &&
        partners.every((p) => p != -1);
    tx.update(ref, {
      'partners': partners,
      'invites': invites,
      if (ready) 'status': 'playing',
    });
  });
}

/// Rangée de choix (2/3/4, 1/2/3/4...). Si [enabled] est faux, la rangée
/// est grisée et on ne peut plus changer la valeur.
Widget _pickerRow(
  String title,
  List<int> values,
  int current,
  void Function(int) onPick, {
  bool enabled = true,
}) {
  return Opacity(
    opacity: enabled ? 1.0 : 0.45,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final v in values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: enabled ? () => onPick(v) : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: v == current
                            ? const Color(0xFFFFC21A)
                            : Colors.white.withOpacity(0.12),
                      ),
                      child: Text(
                        '$v',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: v == current
                              ? const Color(0xFF1A1F3A)
                              : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

Widget _sectionTitle(String text) {
  return Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 17,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

Widget _switchRow(
  String title,
  String subtitle,
  bool value,
  void Function(bool) onChanged,
) {
  return SwitchListTile(
    contentPadding: EdgeInsets.zero,
    activeColor: const Color(0xFFFFC21A),
    title: Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w800,
      ),
    ),
    subtitle: Text(
      subtitle,
      style: const TextStyle(color: Colors.white70, fontSize: 12),
    ),
    value: value,
    onChanged: onChanged,
  );
}

Widget _hint(String text) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white70, fontSize: 13),
    ),
  );
}

Widget _tile(
  String title,
  String subtitle,
  String buttonLabel,
  VoidCallback? onTap,
) {
  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      color: Colors.white.withOpacity(0.12),
      border: Border.all(color: Colors.white24),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF22B14C),
            foregroundColor: Colors.white,
          ),
          onPressed: onTap,
          child: Text(buttonLabel),
        ),
      ],
    ),
  );
}

// ----------------------------------------------------------------------
// Salon : créer une partie, rejoindre une partie ouverte ou avec un code
// ----------------------------------------------------------------------

class OnlineLobbyScreen extends StatefulWidget {
  const OnlineLobbyScreen({super.key});

  @override
  State<OnlineLobbyScreen> createState() => _OnlineLobbyScreenState();
}

class _OnlineLobbyScreenState extends State<OnlineLobbyScreen> {
  int numPlayers = 2;
  int stake = Wallet.minStake;
  int pawnCount = 4;
  bool doorSafe = true;
  bool starSafe = true;
  bool startOut = false; // pions déjà dehors au départ (pas besoin de 6)
  bool privateRoom = false;
  bool teamMode = false; // 2 contre 2 (4 joueurs seulement)
  bool busy = false;
  String? error;

  final TextEditingController codeCtrl = TextEditingController();

  late final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  late final Stream<QuerySnapshot<Map<String, dynamic>>> openStream =
      _games.where('status', isEqualTo: 'waiting').limit(30).snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> liveStream =
      _games.where('status', isEqualTo: 'playing').limit(30).snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> mineStream =
      _games.where('uids', arrayContains: uid).snapshots();

  @override
  void dispose() {
    codeCtrl.dispose();
    super.dispose();
  }

  void _openRoom(String id) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => OnlineGameRoom(gameId: id),
      ),
    );
  }

  /// Ouvre une partie en cours en tant que spectateur.
  void _watchRoom(String id) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => OnlineGameRoom(gameId: id, spectate: true),
      ),
    );
  }

  Future<int> _myBalance() async {
    final s =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final b = s.data()?['balance'];
    return b is num ? b.toInt() : 0;
  }

  Future<void> _create() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (await _myBalance() < stake) {
        if (mounted) {
          setState(() => error =
              tr('Solde insuffisant : il te faut au moins ${Wallet.format(stake)}.',
                  'Insufficient balance: you need at least ${Wallet.format(stake)}.'));
        }
        return;
      }
      final team = teamMode && numPlayers == 4;
      // Position 54 : toujours 2 pions chacun.
      final pawns = startOut ? 2 : pawnCount;
      final ref = _games.doc();
      await ref.set({
        'hostUid': user.uid,
        'hostName': _displayName(user),
        'maxPlayers': numPlayers,
        'pawnCount': pawns,
        'doorSafe': doorSafe,
        'starSafe': starSafe,
        'startOut': startOut,
        'private': privateRoom,
        'teamMode': team,
        'stake': stake,
        'paid': <String>[],
        'pot': 0,
        'partners': [-1, -1, -1, -1],
        'invites': <Map<String, int>>[],
        'code': _newCode(),
        'status': 'waiting',
        'players': [
          {'uid': user.uid, 'name': _displayName(user)},
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
      try {
        await Wallet.payStake(ref.id);
      } catch (e) {
        try {
          await Wallet.leaveGame(ref.id);
        } catch (_) {}
        if (mounted) setState(() => error = Wallet.errorText(e));
        return;
      }
      if (!mounted) return;
      _openRoom(ref.id);
    } catch (_) {
      if (mounted) {
        setState(() {
          error = "Impossible de créer la partie. Vérifie que Firestore est "
              "activé et que les règles autorisent les joueurs connectés.";
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _join(String id) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final ref = _games.doc(id);
      final pre = await ref.get();
      final need = (pre.data()?['stake'] as num?)?.toInt() ?? 0;
      if (pre.exists && need > 0 && await _myBalance() < need) {
        if (mounted) {
          setState(() => error =
              tr('Solde insuffisant : mise de ${Wallet.format(need)}.',
                  'Insufficient balance: stake of ${Wallet.format(need)}.'));
        }
        return;
      }
      final result =
          await FirebaseFirestore.instance.runTransaction<String?>((tx) async {
        final snap = await tx.get(ref);
        final d = snap.data();
        if (d == null) return "Cette partie n'existe plus.";
        final players = _playersOf(d);
        if (players.any((p) => p['uid'] == user.uid)) return null;
        final max = (d['maxPlayers'] as num).toInt();
        if (d['status'] != 'waiting' || players.length >= max) {
          return 'Cette partie est déjà complète.';
        }
        players.add({'uid': user.uid, 'name': _displayName(user)});
        // La partie démarre quand tout le monde a payé sa mise (voir le
        // serveur) et, en équipe, quand les binômes sont formés.
        tx.update(ref, {
          'players': players,
          'uids': FieldValue.arrayUnion([user.uid]),
        });
        return null;
      });
      if (!mounted) return;
      if (result != null) {
        setState(() => error = result);
      } else {
        try {
          await Wallet.payStake(id);
          if (mounted) _openRoom(id);
        } catch (e) {
          try {
            await Wallet.leaveGame(id);
          } catch (_) {}
          if (mounted) setState(() => error = Wallet.errorText(e));
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Impossible de rejoindre la partie.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Rejoindre une salle (privée ou non) grâce à son code.
  Future<void> _joinByCode() async {
    final code = codeCtrl.text.trim().toUpperCase();
    if (busy) return;
    if (code.length != 6) {
      setState(() => error = 'Entre le code à 6 caractères.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    String? id;
    try {
      final q = await _games.where('code', isEqualTo: code).limit(1).get();
      if (q.docs.isEmpty) {
        error = 'Aucune partie avec ce code.';
      } else {
        id = q.docs.first.id;
      }
    } catch (_) {
      error = 'Impossible de chercher la partie.';
    }
    if (mounted) setState(() => busy = false);
    if (id != null && mounted) await _join(id);
  }

  int _createdMs(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final t = doc.data()['createdAt'];
    return t is Timestamp ? t.millisecondsSinceEpoch : 0;
  }

  Widget _mineSection() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: mineStream,
      builder: (context, snap) {
        final docs = (snap.data?.docs ?? [])
            .where((d) => d.data()['status'] != 'finished')
            .toList()
          ..sort((a, b) => _createdMs(b).compareTo(_createdMs(a)));
        if (docs.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Mes parties'),
            for (final doc in docs)
              Builder(
                builder: (context) {
                  final d = doc.data();
                  final n = _playersOf(d).length;
                  final max = (d['maxPlayers'] as num).toInt();
                  final waiting = d['status'] == 'waiting';
                  final priv = d['private'] == true ? ' 🔒' : '';
                  final team = d['teamMode'] == true ? ' • 2v2' : '';
                  final when = _createdText(d['createdAt']);
                  return _tile(
                    tr("Partie de ${d['hostName']}$priv",
                        "${d['hostName']}'s game$priv"),
                    waiting
                        ? tr(
                            'En attente ($n/$max joueurs)$team${_stakeText(d)}$when',
                            'Waiting ($n/$max players)$team${_stakeText(d)}$when',
                          )
                        : tr(
                            'En cours$team${_stakeText(d)}$when',
                            'In progress$team${_stakeText(d)}$when',
                          ),
                    waiting ? 'Ouvrir' : 'Reprendre',
                    busy ? null : () => _openRoom(doc.id),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  Widget _openSection() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: openStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return _hint(
            'Impossible de charger les parties. Vérifie les règles Firestore.',
          );
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final docs = snap.data!.docs
            .where((d) => !((d.data()['uids'] as List?) ?? []).contains(uid))
            .where((d) => d.data()['private'] != true)
            .toList()
          ..sort((a, b) => _createdMs(b).compareTo(_createdMs(a)));
        if (docs.isEmpty) {
          return _hint('Aucune partie ouverte pour le moment. Crée la tienne !');
        }
        return Column(
          children: [
            for (final doc in docs)
              Builder(
                builder: (context) {
                  final d = doc.data();
                  final n = _playersOf(d).length;
                  final max = (d['maxPlayers'] as num).toInt();
                  final pawns = (d['pawnCount'] as num).toInt();
                  final team = d['teamMode'] == true ? ' • 2v2' : '';
                  final when = _createdText(d['createdAt']);
                  return _tile(
                    tr("Partie de ${d['hostName']}",
                        "${d['hostName']}'s game"),
                    tr(
                      '$n/$max joueurs • $pawns pion${pawns > 1 ? 's' : ''}$team${_stakeText(d)}$when',
                      '$n/$max players • $pawns pawn${pawns > 1 ? 's' : ''}$team${_stakeText(d)}$when',
                    ),
                    'Rejoindre',
                    busy ? null : () => _join(doc.id),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  /// Parties publiques en cours : on peut les regarder.
  Widget _liveSection() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: liveStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return _hint('Impossible de charger les parties en cours.');
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final docs = snap.data!.docs
            .where((d) => !((d.data()['uids'] as List?) ?? []).contains(uid))
            .where((d) => d.data()['private'] != true)
            .where((d) => d.data()['over'] != true)
            .toList()
          ..sort((a, b) => _createdMs(b).compareTo(_createdMs(a)));
        if (docs.isEmpty) {
          return _hint('Aucune partie en cours à regarder pour le moment.');
        }
        return Column(
          children: [
            for (final doc in docs)
              Builder(
                builder: (context) {
                  final d = doc.data();
                  final names = _playersOf(d).map((p) => '${p['name']}');
                  final team = d['teamMode'] == true ? ' • 2v2' : '';
                  final when = _createdText(d['createdAt']);
                  return _tile(
                    names.join(' vs '),
                    tr(
                      '${(d['maxPlayers'] as num).toInt()} joueurs$team${_stakeText(d)}$when',
                      '${(d['maxPlayers'] as num).toInt()} players$team${_stakeText(d)}$when',
                    ),
                    'Regarder',
                    () => _watchRoom(doc.id),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  Widget _stakeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        StreamBuilder<int>(
          stream: Wallet.watch(uid),
          builder: (context, s) => Text(
            tr(
              'Mise de chaque joueur · ton solde : ${Wallet.format(s.data ?? 0)}',
              "Each player's stake · your balance: ${Wallet.format(s.data ?? 0)}",
            ),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final v in Wallet.stakes)
              ChoiceChip(
                label: Text(Wallet.stakeLabel(v)),
                selected: stake == v,
                onSelected: (_) => setState(() => stake = v),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          stake == 0
              ? 'Partie gratuite : aucun jeton en jeu, pas de jackpot.'
              : tr(
                  'Gain du gagnant : ${Wallet.format(Wallet.prize(stake * numPlayers))} '
                  '(cagnotte ${stake * numPlayers}, commission ${Wallet.commissionPercent} %)',
                  'Winner gets: ${Wallet.format(Wallet.prize(stake * numPlayers))} '
                  '(pot ${stake * numPlayers}, commission ${Wallet.commissionPercent} %)',
                ),
          style: const TextStyle(color: Color(0xFFFFE082), fontSize: 13),
        ),
      ],
    );
  }

  Widget _codeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Rejoindre avec un code'),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: codeCtrl,
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  letterSpacing: 4,
                ),
                cursorColor: const Color(0xFFFFC21A),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'CODE',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Colors.white30),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        const BorderSide(color: Color(0xFFFFC21A), width: 2),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22B14C),
                  foregroundColor: Colors.white,
                ),
                onPressed: busy ? null : _joinByCode,
                child: const Text('Rejoindre'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: _bg,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const Text(
                    'Parties en ligne',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const JackpotBanner(),
              _sectionTitle('Créer une partie'),
              _pickerRow(
                'Nombre de joueurs',
                const [2, 3, 4],
                numPlayers,
                (v) => setState(() {
                  numPlayers = v;
                  if (v != 4) teamMode = false;
                }),
              ),
              const SizedBox(height: 14),
              _pickerRow(
                'Nombre de pions par joueur',
                const [1, 2, 3, 4],
                pawnCount,
                (v) => setState(() => pawnCount = v),
                enabled: !startOut,
              ),
              if (startOut)
                _hint('Position 54 : la partie se joue avec 2 pions chacun.'),
              _stakeSection(),
              const SizedBox(height: 6),
              if (numPlayers == 4)
                _switchRow(
                  'Jouer en équipe (2 contre 2)',
                  'Les binômes se choisissent par invitation et ne se '
                      'capturent pas',
                  teamMode,
                  (v) => setState(() => teamMode = v),
                ),
              _switchRow(
                'Protection des portes',
                'Un pion sur une case de départ ne peut pas être capturé',
                doorSafe,
                (v) => setState(() => doorSafe = v),
              ),
              _switchRow(
                'Protection des étoiles',
                'Un pion sur une étoile ne peut pas être capturé',
                starSafe,
                (v) => setState(() => starSafe = v),
              ),
              _switchRow(
                'Position 54',
                'Les pions démarrent déjà sur le plateau, près du centre : '
                    "pas besoin de 6 au début. Un pion capturé a besoin d'un "
                    '6 pour ressortir. Se joue avec 2 pions chacun.',
                startOut,
                (v) => setState(() {
                  startOut = v;
                  if (v) pawnCount = 2;
                }),
              ),
              _switchRow(
                'Partie privée',
                'Invisible dans la liste : on la rejoint avec un code',
                privateRoom,
                (v) => setState(() => privateRoom = v),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22B14C),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: busy ? null : _create,
                  child: Text(
                    busy ? 'Patiente...' : 'Créer la partie',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: const TextStyle(
                      color: Color(0xFFFF8A80),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              _codeSection(),
              _mineSection(),
              _sectionTitle('Parties ouvertes'),
              _openSection(),
              _sectionTitle('Parties en cours'),
              _liveSection(),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Salle d'une partie : attente des joueurs, puis plateau de jeu
// ----------------------------------------------------------------------

class OnlineGameRoom extends StatelessWidget {
  const OnlineGameRoom({
    super.key,
    required this.gameId,
    this.spectate = false,
  });

  final String gameId;

  /// Vrai : on regarde la partie sans y participer.
  final bool spectate;

  Widget _info(BuildContext context, String text, {bool loading = false}) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: _bg,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading) const CircularProgressIndicator(),
                if (text.isNotEmpty)
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Retour'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _leave(
    BuildContext context,
    Map<String, dynamic> d,
    String uid,
  ) async {
    Navigator.of(context).pop();
    try {
      await Wallet.leaveGame(gameId); // la mise est remboursée
    } catch (_) {}
  }

  Widget _codeCard(BuildContext context, Map<String, dynamic> d) {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.black26,
        border: Border.all(color: const Color(0xFFFFC21A), width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d['private'] == true
                      ? 'Code de la salle privée'
                      : 'Code de la salle',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  '${d['code']}',
                  style: const TextStyle(
                    color: Color(0xFFFFC21A),
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.white),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: '${d['code']}'));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Code copié')),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Section « Binômes » de la salle d'attente (mode 2 contre 2).
  /// Chaque joueur peut inviter un autre joueur libre ; l'invité
  /// accepte ou refuse depuis son propre téléphone.
  Widget _teamSection(
    BuildContext context,
    Map<String, dynamic> d,
    List<Map<String, dynamic>> players,
    String uid,
  ) {
    final me = players.indexWhere((p) => p['uid'] == uid);
    if (me < 0) return const SizedBox.shrink();

    final partners = _partnersOf(d);
    final invites = _invitesOf(d);
    String nameOfSeat(int s) =>
        s >= 0 && s < players.length ? '${players[s]['name']}' : '?';

    TextStyle white([double size = 14, FontWeight w = FontWeight.w700]) =>
        TextStyle(color: Colors.white, fontSize: size, fontWeight: w);

    Widget card(List<Widget> children) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white.withOpacity(0.12),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(children: children),
        );

    void run(
      void Function(
        int seat,
        List<int> partners,
        List<Map<String, int>> invites,
      ) change,
    ) {
      _teamTx(gameId, uid, change).catchError((_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Action impossible. Réessaie.')),
          );
        }
      });
    }

    final widgets = <Widget>[
      const SizedBox(height: 6),
      const Text(
        'Binômes (2 contre 2)',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 8),
    ];

    if (partners[me] != -1) {
      // J'ai déjà un binôme.
      widgets.add(
        card([
          Expanded(
            child: Text(
              tr('🤝 Ton binôme : ${nameOfSeat(partners[me])}',
                  '🤝 Your partner: ${nameOfSeat(partners[me])}'),
              style: white(),
            ),
          ),
          TextButton(
            onPressed: () => run((seat, p, inv) {
              final m = p[seat];
              p[seat] = -1;
              if (m != -1) p[m] = -1;
            }),
            child: const Text('Annuler'),
          ),
        ]),
      );
    } else {
      // Invitations reçues : accepter ou refuser.
      for (final inv in invites.where((i) => i['to'] == me)) {
        final from = inv['from']!;
        if (partners[from] != -1) continue;
        widgets.add(
          card([
            Expanded(
              child: Text(
                tr("${nameOfSeat(from)} t'invite comme binôme",
                    '${nameOfSeat(from)} invites you as a partner'),
                style: white(),
              ),
            ),
            TextButton(
              onPressed: () => run((seat, p, i) {
                i.removeWhere(
                  (x) => x['from'] == from && x['to'] == seat,
                );
              }),
              child: const Text(
                'Refuser',
                style: TextStyle(color: Color(0xFFFF8A80)),
              ),
            ),
            TextButton(
              onPressed: () => run((seat, p, i) {
                final valid = p[seat] == -1 &&
                    p[from] == -1 &&
                    i.any((x) => x['from'] == from && x['to'] == seat);
                if (!valid) return;
                p[seat] = from;
                p[from] = seat;
                i.removeWhere(
                  (x) =>
                      x['from'] == seat ||
                      x['to'] == seat ||
                      x['from'] == from ||
                      x['to'] == from,
                );
              }),
              child: const Text('Accepter'),
            ),
          ]),
        );
      }

      // Inviter les autres joueurs encore libres.
      for (int s = 0; s < players.length; s++) {
        if (s == me || partners[s] != -1) continue;
        final sent = invites.any((i) => i['from'] == me && i['to'] == s);
        widgets.add(
          card([
            CircleAvatar(radius: 8, backgroundColor: _seatPalette[s]),
            const SizedBox(width: 10),
            Expanded(child: Text(nameOfSeat(s), style: white())),
            sent
                ? TextButton(
                    onPressed: () => run((seat, p, i) {
                      i.removeWhere(
                        (x) => x['from'] == seat && x['to'] == s,
                      );
                    }),
                    child: const Text('Invitation envoyée · Annuler'),
                  )
                : TextButton(
                    onPressed: () => run((seat, p, i) {
                      if (p[seat] != -1 || p[s] != -1) return;
                      // Une seule invitation envoyée à la fois.
                      i.removeWhere((x) => x['from'] == seat);
                      i.add({'from': seat, 'to': s});
                    }),
                    child: const Text('Inviter'),
                  ),
          ]),
        );
      }

      if (players.length < 2) {
        widgets.add(
          const Text(
            "Attends que d'autres joueurs rejoignent pour inviter un binôme.",
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _waiting(
    BuildContext context,
    Map<String, dynamic> d,
    List<Map<String, dynamic>> players,
    String uid,
  ) {
    final max = (d['maxPlayers'] as num).toInt();
    final pawns = (d['pawnCount'] as num).toInt();
    final colors = _colorsFor(max);
    final teamOn = d['teamMode'] == true;
    final partners = _partnersOf(d);
    final stake = (d['stake'] as num?)?.toInt() ?? 0;
    final pot = (d['pot'] as num?)?.toInt() ?? 0;
    final paid = ((d['paid'] as List?) ?? const []).map((e) => '$e').toList();
    final createdLabel =
        _createdText(d['createdAt']).replaceFirst(' • ', '');

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: _bg,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Salle d'attente",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  tr(
                    '${players.length}/$max joueurs • $pawns pion${pawns > 1 ? 's' : ''} chacun'
                    '${teamOn ? ' • 2 contre 2' : ''}'
                    '${d['startOut'] == true ? ' • position 54' : ''}',
                    '${players.length}/$max players • $pawns pawn${pawns > 1 ? 's' : ''} each'
                    '${teamOn ? ' • 2 vs 2' : ''}'
                    '${d['startOut'] == true ? ' • position 54' : ''}',
                  ),
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                if (createdLabel.isNotEmpty)
                  Text(
                    tr('Créée le $createdLabel', 'Created on $createdLabel'),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                const SizedBox(height: 4),
                Text(
                  teamOn
                      ? 'La partie démarre quand les 4 joueurs sont là et que '
                          'les binômes sont formés.'
                      : 'La partie démarre dès que tout le monde est là.',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                if (d['stake'] != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    stake > 0
                        ? tr(
                            'Mise : ${Wallet.format(stake)} • '
                            'Cagnotte : ${Wallet.format(pot)} '
                            '(gain ${Wallet.format(Wallet.prize(pot))})',
                            'Stake: ${Wallet.format(stake)} • '
                            'Pot: ${Wallet.format(pot)} '
                            '(prize ${Wallet.format(Wallet.prize(pot))})',
                          )
                        : 'Partie gratuite',
                    style: const TextStyle(
                      color: Color(0xFFFFE082),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (!paid.contains(uid))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF22B14C),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () async {
                          try {
                            await Wallet.payStake(gameId);
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(Wallet.errorText(e))),
                              );
                            }
                          }
                        },
                        child: Text(
                          stake > 0
                              ? tr('Payer ma mise (${Wallet.format(stake)})',
                                  'Pay my stake (${Wallet.format(stake)})')
                              : 'Valider ma participation',
                        ),
                      ),
                    ),
                ],
                if (d['code'] != null) _codeCard(context, d),
                const SizedBox(height: 20),
                for (int i = 0; i < max; i++)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.white.withOpacity(0.12),
                      border: Border.all(
                        color: _seatPalette[colors[i]].withOpacity(0.9),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: _seatPalette[colors[i]],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            i < players.length
                                ? '${players[i]['name']}'
                                    '${paid.contains(players[i]['uid']) ? ' ✅' : ''}'
                                    '${teamOn && partners[i] != -1 && partners[i] < players.length ? '  🤝 ${players[partners[i]]['name']}' : ''}'
                                : "En attente d'un joueur...",
                            style: TextStyle(
                              color: i < players.length
                                  ? Colors.white
                                  : Colors.white54,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          _seatNames[colors[i]],
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (teamOn) _teamSection(context, d, players, uid),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                    onPressed: () => _leave(context, d, uid),
                    child: Text(
                      d['hostUid'] == uid
                          ? 'Annuler la partie'
                          : 'Quitter la partie',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return _info(context, 'Tu dois être connecté.');

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _games.doc(gameId).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _info(context, 'Erreur de connexion à la partie.');
        }
        if (!snap.hasData) return _info(context, '', loading: true);

        final d = snap.data!.data();
        if (d == null) return _info(context, "Cette partie n'existe plus.");

        final players = _playersOf(d);
        final seat = players.indexWhere((p) => p['uid'] == user.uid);

        if (spectate && seat < 0) {
          if (d['status'] != 'playing') {
            return _info(context, "Cette partie n'est pas (ou plus) en cours.");
          }
          return LudoGame(
            key: ValueKey('watch_$gameId'),
            numPlayers: (d['maxPlayers'] as num).toInt(),
            pawnCount: (d['pawnCount'] as num).toInt(),
            doorSafe: d['doorSafe'] != false,
            starSafe: d['starSafe'] != false,
            startOut: d['startOut'] == true,
            stake: (d['stake'] as num?)?.toInt() ?? 0,
            partners: d['teamMode'] == true ? _partnersOf(d) : null,
            online: OnlineSession(
              gameId: gameId,
              uid: user.uid,
              mySeat: -1,
              spectator: true,
              names: [for (final p in players) '${p['name']}'],
              uids: [for (final p in players) '${p['uid']}'],
            ),
          );
        }

        if (seat < 0) {
          return _info(context, 'Tu ne fais pas partie de cette partie.');
        }

        if (d['status'] == 'waiting') {
          return _waiting(context, d, players, user.uid);
        }

        return LudoGame(
          key: ValueKey('game_$gameId'),
          numPlayers: (d['maxPlayers'] as num).toInt(),
          pawnCount: (d['pawnCount'] as num).toInt(),
          doorSafe: d['doorSafe'] != false,
          starSafe: d['starSafe'] != false,
          startOut: d['startOut'] == true,
          stake: (d['stake'] as num?)?.toInt() ?? 0,
          partners: d['teamMode'] == true ? _partnersOf(d) : null,
          online: OnlineSession(
            gameId: gameId,
            uid: user.uid,
            mySeat: seat,
            names: [for (final p in players) '${p['name']}'],
            uids: [for (final p in players) '${p['uid']}'],
          ),
        );
      },
    );
  }
}
