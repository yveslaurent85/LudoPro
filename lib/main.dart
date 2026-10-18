import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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

/// Infos passées au plateau de jeu quand la partie est en ligne.
class OnlineSession {
  const OnlineSession({
    required this.gameId,
    required this.uid,
    required this.mySeat,
    required this.names,
  });

  final String gameId;
  final String uid;
  final int mySeat; // place dans la partie (0 = créateur)
  final List<String> names; // pseudos, dans l'ordre des places
}

CollectionReference<Map<String, dynamic>> get _games =>
    FirebaseFirestore.instance.collection('games');

String _displayName(User u) {
  final n = u.displayName;
  if (n != null && n.isNotEmpty) return n;
  return u.email ?? 'Joueur';
}

List<Map<String, dynamic>> _playersOf(Map<String, dynamic> d) {
  return ((d['players'] as List?) ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
}

Widget _pickerRow(
  String title,
  List<int> values,
  int current,
  void Function(int) onPick,
) {
  return Column(
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
                  onTap: () => onPick(v),
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
// Salon : créer une partie, rejoindre une partie ouverte
// ----------------------------------------------------------------------

class OnlineLobbyScreen extends StatefulWidget {
  const OnlineLobbyScreen({super.key});

  @override
  State<OnlineLobbyScreen> createState() => _OnlineLobbyScreenState();
}

class _OnlineLobbyScreenState extends State<OnlineLobbyScreen> {
  int numPlayers = 2;
  int pawnCount = 4;
  bool busy = false;
  String? error;

  late final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  late final Stream<QuerySnapshot<Map<String, dynamic>>> openStream =
      _games.where('status', isEqualTo: 'waiting').limit(30).snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> mineStream =
      _games.where('uids', arrayContains: uid).snapshots();

  void _openRoom(String id) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => OnlineGameRoom(gameId: id),
      ),
    );
  }

  Future<void> _create() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final ref = _games.doc();
      await ref.set({
        'hostUid': user.uid,
        'hostName': _displayName(user),
        'maxPlayers': numPlayers,
        'pawnCount': pawnCount,
        'status': 'waiting',
        'players': [
          {'uid': user.uid, 'name': _displayName(user)},
        ],
        'uids': [user.uid],
        'createdAt': FieldValue.serverTimestamp(),
        'p0': List<int>.filled(pawnCount, -1),
        'p1': List<int>.filled(pawnCount, -1),
        'p2': List<int>.filled(pawnCount, -1),
        'p3': List<int>.filled(pawnCount, -1),
        'cur': 0,
        'hasRolled': false,
        'dice': 1,
        'lastRoll': [1, 1, 1, 1],
        'msg': 'Touche ton dé ou glisse-le pour le lancer !',
        'over': false,
        'writer': '',
        'rev': 0,
      });
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
        tx.update(ref, {
          'players': players,
          'uids': FieldValue.arrayUnion([user.uid]),
          if (players.length >= max) 'status': 'playing',
        });
        return null;
      });
      if (!mounted) return;
      if (result != null) {
        setState(() => error = result);
      } else {
        _openRoom(id);
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Impossible de rejoindre la partie.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
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
                  return _tile(
                    'Partie de ${d['hostName']}',
                    waiting ? 'En attente ($n/$max joueurs)' : 'En cours',
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
                  return _tile(
                    'Partie de ${d['hostName']}',
                    '$n/$max joueurs • $pawns pion${pawns > 1 ? 's' : ''}',
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
              _sectionTitle('Créer une partie'),
              _pickerRow(
                'Nombre de joueurs',
                const [2, 3, 4],
                numPlayers,
                (v) => setState(() => numPlayers = v),
              ),
              const SizedBox(height: 14),
              _pickerRow(
                'Nombre de pions par joueur',
                const [1, 2, 3, 4],
                pawnCount,
                (v) => setState(() => pawnCount = v),
              ),
              const SizedBox(height: 14),
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
              _mineSection(),
              _sectionTitle('Parties ouvertes'),
              _openSection(),
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
  const OnlineGameRoom({super.key, required this.gameId});

  final String gameId;

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
    final ref = _games.doc(gameId);
    try {
      if (d['hostUid'] == uid) {
        await ref.delete();
      } else {
        await FirebaseFirestore.instance.runTransaction<void>((tx) async {
          final snap = await tx.get(ref);
          final data = snap.data();
          if (data == null) return;
          final players = _playersOf(data)
            ..removeWhere((p) => p['uid'] == uid);
          tx.update(ref, {
            'players': players,
            'uids': FieldValue.arrayRemove([uid]),
          });
        });
      }
    } catch (_) {}
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

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: _bg,
        child: SafeArea(
          child: Padding(
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
                  '${players.length}/$max joueurs • $pawns pion${pawns > 1 ? 's' : ''} chacun',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 4),
                const Text(
                  'La partie démarre dès que tout le monde est là.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
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
                const Spacer(),
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
          online: OnlineSession(
            gameId: gameId,
            uid: user.uid,
            mySeat: seat,
            names: [for (final p in players) '${p['name']}'],
          ),
        );
      },
    );
  }
}
