// ----------------------------------------------------------------------
// Paris entre joueurs pour « Deux dés » en ligne (parties avec mise).
//
//  • Duel    : un joueur défie un adversaire (ou tous) avec une nouvelle
//              mise. Le plus haut score gagne, égalité = remboursés.
//  • Défi 7  : un joueur annonce « je fais plus de 7 » (ou moins de 7).
//              Un autre relève le pari. 7 pile = remboursés.
//
// Règle commune : on ne peut proposer / relever un pari que tant qu'on n'a
// pas encore lancé ses dés. Tout l'argent bouge côté serveur
// (functions/sidebets.js), jamais depuis l'appli.
// ----------------------------------------------------------------------

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:http/http.dart' as http;

import 'accounts.dart';
import 'lang.dart';

const Color _navy = Color(0xFF0A1B66);
const Color _gold = Color(0xFFFFC21A);
const Color _goldSoft = Color(0xFFFFE082);
const Color _green = Color(0xFF22B14C);

DocumentReference<Map<String, dynamic>> _roomRef(String roomId) =>
    FirebaseFirestore.instance.collection('deuxdes').doc(roomId);

CollectionReference<Map<String, dynamic>> _betsOf(String roomId) =>
    _roomRef(roomId).collection('bets');

// ----------------------------------------------------------------------
// Appels serveur (même Worker que Wallet)
// ----------------------------------------------------------------------

class SideBets {
  static Future<void> _post(String name, Map<String, dynamic> body) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw WalletException('Connexion requise.');
    final token = await u.getIdToken();
    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('$kWorkerUrl/$name'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw WalletException('Pas de connexion. Réessaie.');
    }
    if (res.statusCode != 200) {
      Map<String, dynamic> j = {};
      try {
        j = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
      } catch (_) {}
      throw WalletException(
        (j['error'] as String?) ??
            tr('Erreur du serveur (${res.statusCode}).',
                'Server error (${res.statusCode}).'),
      );
    }
  }

  /// [type] = 'duel' ou 'seven'. [targetUid] null = tous (duel seulement).
  /// [over7] : pour « seven », true = « je fais plus de 7 ».
  static Future<void> propose(
    String roomId, {
    required String type,
    required int amount,
    String? targetUid,
    bool over7 = true,
  }) =>
      _post('sideBetPropose', {
        'roomId': roomId,
        'type': type,
        'amount': amount,
        'targetUid': targetUid,
        'side': over7 ? 'over' : 'under',
      });

  static Future<void> accept(String roomId, String betId) =>
      _post('sideBetAccept', {'roomId': roomId, 'betId': betId});

  /// Le parieur annule, ou l'adversaire visé refuse (mise remboursée).
  static Future<void> cancel(String roomId, String betId) =>
      _post('sideBetCancel', {'roomId': roomId, 'betId': betId});

  /// Règle les paris prêts (gains / remboursements). Idempotent.
  static Future<void> sync(String roomId) =>
      _post('sideBetSync', {'roomId': roomId});
}

// ----------------------------------------------------------------------
// Modèles
// ----------------------------------------------------------------------

class SideBet {
  SideBet(this.id, this.d);

  final String id;
  final Map<String, dynamic> d;

  bool get isSeven => d['type'] == 'seven';
  String get status => '${d['status']}';
  bool get isOpen => status == 'open';
  bool get isAccepted => status == 'accepted';
  bool get isSettled => status == 'settled';
  bool get isClosed =>
      status == 'cancelled' || status == 'declined' || status == 'expired';
  String get proposerUid => '${d['proposerUid']}';
  String get proposerName => '${d['proposerName']}';
  String? get targetUid => d['targetUid'] as String?;
  String? get targetName => d['targetName'] as String?;
  String? get opponentUid => d['opponentUid'] as String?;
  String? get opponentName => d['opponentName'] as String?;
  String? get winnerUid => d['winnerUid'] as String?;
  bool get refunded => d['result'] == 'refund';
  bool get over7 => d['side'] != 'under';
  int get amount => (d['amount'] as num?)?.toInt() ?? 0;
  int get prize => (d['prize'] as num?)?.toInt() ?? 0;
  int get createdMs {
    final t = d['createdAt'];
    return t is Timestamp ? t.millisecondsSinceEpoch : 0;
  }
}

/// Lecture de l'état de la salle (miroir des règles du serveur, pour l'affichage).
class _Room {
  _Room(this.d, this.uid);

  final Map<String, dynamic> d;
  final String uid;

  List<Map<String, dynamic>> get players =>
      ((d['players'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  int get cur => (d['cur'] as num?)?.toInt() ?? 0;
  int get rollN => (d['rollN'] as num?)?.toInt() ?? 0;
  int get stake => (d['stake'] as num?)?.toInt() ?? 0;
  bool get over => d['over'] == true;
  bool get rolled => d['rolled'] == true;
  bool get started => d['status'] != 'waiting';
  int seatOf(String u) => players.indexWhere((p) => p['uid'] == u);
  int get mySeat => seatOf(uid);

  /// Ce joueur a déjà lancé ses dés (ou la partie est finie).
  bool hasRolled(int seat) =>
      seat < 0 || over || cur > seat || (cur == seat && rolled);

  bool get canUse => stake > 0 && started;
  bool get canPropose => canUse && !over && !hasRolled(mySeat);

  bool canAccept(SideBet b) {
    if (!canUse || over || !b.isOpen || b.proposerUid == uid) return false;
    final t = b.targetUid;
    if (t != null && t != uid) return false;
    if (hasRolled(mySeat)) return false;
    if (hasRolled(seatOf(b.proposerUid))) return false;
    return true;
  }
}

// ----------------------------------------------------------------------
// Barre « Défis » (à placer au-dessus de la table de jeu)
// ----------------------------------------------------------------------

class SideBetsBar extends StatefulWidget {
  const SideBetsBar({
    super.key,
    required this.roomId,
    required this.uid,
    required this.room,
  });

  final String roomId;
  final String uid;

  /// Document Firestore de la salle (déjà écouté par l'écran de jeu).
  final Map<String, dynamic> room;

  @override
  State<SideBetsBar> createState() => _SideBetsBarState();
}

class _SideBetsBarState extends State<SideBetsBar> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream =
      _betsOf(widget.roomId).snapshots();

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant SideBetsBar old) {
    super.didUpdateWidget(old);
    final a = _Room(old.room, old.uid);
    final b = _Room(widget.room, widget.uid);
    // Un lancer ou la fin de partie : on règle les paris prêts.
    if (a.rollN != b.rollN || a.over != b.over) _sync();
  }

  void _sync() {
    SideBets.sync(widget.roomId).catchError((_) {});
  }

  void _open() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _navy,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _SideBetSheet(roomId: widget.roomId, uid: widget.uid),
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = _Room(widget.room, widget.uid);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        final pending = [
          for (final doc in snap.data?.docs ??
              const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            SideBet(doc.id, doc.data()),
        ].where(room.canAccept).length;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: SizedBox(
            width: double.infinity,
            height: 40,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(
                  color: pending > 0 ? _gold : Colors.white54,
                  width: pending > 0 ? 2 : 1,
                ),
              ),
              onPressed: _open,
              icon: const Icon(Icons.local_fire_department, size: 18),
              label: Text(
                pending > 0
                    ? tr('⚔️ Défis et paris ($pending à relever)',
                        '⚔️ Challenges & bets ($pending to accept)')
                    : tr('⚔️ Défis et paris', '⚔️ Challenges & bets'),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ----------------------------------------------------------------------
// Feuille de paris : proposer + liste
// ----------------------------------------------------------------------

class _SideBetSheet extends StatefulWidget {
  const _SideBetSheet({required this.roomId, required this.uid});

  final String roomId;
  final String uid;

  @override
  State<_SideBetSheet> createState() => _SideBetSheetState();
}

class _SideBetSheetState extends State<_SideBetSheet> {
  String type = 'duel';
  String? target; // null = tous
  bool over7 = true;
  int amount = 0;
  bool busy = false;
  String? error;
  int balance = 0;
  StreamSubscription<int>? _sub;

  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _roomStream =
      _roomRef(widget.roomId).snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _betsStream =
      _betsOf(widget.roomId).snapshots();

  List<int> get _amounts {
    final l = [
      for (final v in Wallet.stakes)
        if (v > 0) v,
    ];
    return l.isEmpty ? [Wallet.minStake] : l;
  }

  @override
  void initState() {
    super.initState();
    amount = _amounts.first;
    _sub = Wallet.watch(widget.uid).listen(
      (b) {
        if (mounted) setState(() => balance = b);
      },
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() job) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await job();
    } catch (e) {
      if (mounted) setState(() => error = Wallet.errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  bool _involved(SideBet b) =>
      b.proposerUid == widget.uid ||
      b.opponentUid == widget.uid ||
      b.targetUid == widget.uid;

  Widget _title(String s) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Text(
          s,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      );

  Widget _note(String s) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          s,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      );

  Widget _chip(String label, bool selected, VoidCallback? onTap) => ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: onTap == null ? null : (_) => onTap(),
      );

  // --- Formulaire -------------------------------------------------------

  Widget _form(_Room room) {
    if (!room.canUse) {
      return _note(tr(
          'Les paris sont disponibles dans les parties avec mise, une fois la partie lancée.',
          'Bets are available in stake games, once the game has started.'));
    }
    if (room.over) {
      return _note(tr('Partie terminée.', 'Game over.'));
    }
    if (!room.canPropose) {
      return _note(tr(
          'Tu as déjà lancé tes dés : tu ne peux plus proposer de pari.',
          'You already rolled: you can no longer propose a bet.'));
    }

    final opponents = [
      for (final p in room.players)
        if (p['uid'] != widget.uid &&
            !room.hasRolled(room.seatOf('${p['uid']}')))
          p,
    ];
    final t = opponents.any((p) => p['uid'] == target) ? target : null;
    final noOne = type == 'duel' && opponents.isEmpty;
    final tooPoor = amount > balance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            _chip('⚔️ Duel', type == 'duel', () => setState(() => type = 'duel')),
            _chip(tr('🎲 Défi 7', '🎲 Challenge 7'), type == 'seven',
                () => setState(() => type = 'seven')),
          ],
        ),
        const SizedBox(height: 8),
        if (type == 'duel') ...[
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _chip(tr('Tous', 'Everyone'), t == null,
                  () => setState(() => target = null)),
              for (final p in opponents)
                _chip('${p['name']}', t == p['uid'],
                    () => setState(() => target = '${p['uid']}')),
            ],
          ),
          _note(noOne
              ? tr('Plus personne à défier : tous les autres ont déjà lancé.',
                  'Nobody left to challenge: everyone else already rolled.')
              : tr('Le plus haut score gagne. Égalité : mises remboursées.',
                  'Highest score wins. Tie: stakes refunded.')),
        ] else ...[
          Wrap(
            spacing: 8,
            children: [
              _chip(tr('Je fais plus de 7', 'I roll more than 7'), over7,
                  () => setState(() => over7 = true)),
              _chip(tr('Je fais moins de 7', 'I roll less than 7'), !over7,
                  () => setState(() => over7 = false)),
            ],
          ),
          _note(tr(
              'Un autre joueur parie le contraire. 7 pile : mises remboursées.',
              'Another player bets the opposite. Exactly 7: stakes refunded.')),
        ],
        Text(
          tr('Mise de chacun · ton solde : ${Wallet.format(balance)}',
              "Each player's stake · your balance: ${Wallet.format(balance)}"),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final v in _amounts)
              _chip(Wallet.format(v), amount == v,
                  () => setState(() => amount = v)),
          ],
        ),
        const SizedBox(height: 8),
        if (tooPoor)
          _note(tr('Solde insuffisant pour cette mise.',
              'Insufficient balance for this stake.')),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
            ),
            onPressed: (busy || noOne || tooPoor)
                ? null
                : () => _run(() => SideBets.propose(
                      widget.roomId,
                      type: type,
                      amount: amount,
                      targetUid: type == 'duel' ? t : null,
                      over7: over7,
                    )),
            child: Text(busy
                ? tr('Patiente...', 'Please wait...')
                : tr('Proposer le pari', 'Propose the bet')),
          ),
        ),
      ],
    );
  }

  // --- Liste ------------------------------------------------------------

  String _what(SideBet b) {
    final mine = b.proposerUid == widget.uid;
    final name = b.proposerName;
    if (b.isSeven) {
      final side = b.over7
          ? tr('plus de 7', 'more than 7')
          : tr('moins de 7', 'less than 7');
      return mine
          ? tr('🎲 Tu défies 7 : tu fais $side',
              '🎲 You challenge 7: you roll $side')
          : tr('🎲 $name défie 7 : il annonce $side',
              '🎲 $name challenges 7: calls $side');
    }
    final who = b.targetName ?? tr('tous les joueurs', 'everyone');
    if (mine) {
      return tr('⚔️ Tu défies $who', '⚔️ You challenge $who');
    }
    if (b.targetUid == widget.uid) {
      return tr('⚔️ $name te défie', '⚔️ $name challenges you');
    }
    return tr('⚔️ $name défie $who', '⚔️ $name challenges $who');
  }

  String _status(SideBet b) {
    final me = widget.uid;
    switch (b.status) {
      case 'open':
        return b.proposerUid == me
            ? tr("En attente d'un adversaire…", 'Waiting for an opponent…')
            : '';
      case 'accepted':
        final o = b.opponentName ?? '?';
        return tr('Relevé par $o · en cours', 'Accepted by $o · in progress');
      case 'settled':
        if (b.refunded) {
          return tr('🤝 Égalité : mises remboursées',
              '🤝 Tie: stakes refunded');
        }
        final w = b.winnerUid;
        if (w == me) {
          return tr('🏆 Tu as gagné ${Wallet.format(b.prize)}',
              '🏆 You won ${Wallet.format(b.prize)}');
        }
        final wn = w == b.proposerUid ? b.proposerName : (b.opponentName ?? '?');
        return tr('$wn a gagné ${Wallet.format(b.prize)}',
            '$wn won ${Wallet.format(b.prize)}');
      default:
        return tr('Annulé · mise remboursée', 'Cancelled · stake refunded');
    }
  }

  Widget _card(SideBet b, _Room room) {
    final me = widget.uid;
    final acceptable = room.canAccept(b);
    final canClose = b.isOpen && (b.proposerUid == me || b.targetUid == me);
    final status = _status(b);
    final opposite = b.over7
        ? tr('moins de 7', 'less than 7')
        : tr('plus de 7', 'more than 7');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withOpacity(0.12),
        border: Border.all(
          color: acceptable ? _gold : Colors.white24,
          width: acceptable ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _what(b),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            tr('Mise ${Wallet.format(b.amount)} chacun · gain ${Wallet.format(b.prize)}',
                'Stake ${Wallet.format(b.amount)} each · prize ${Wallet.format(b.prize)}'),
            style: const TextStyle(color: _goldSoft, fontSize: 12),
          ),
          Text(
            b.isSeven
                ? tr('7 pile : mises remboursées', 'Exactly 7: stakes refunded')
                : tr('Égalité : mises remboursées', 'Tie: stakes refunded'),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (acceptable && b.isSeven)
            Text(
              tr('En relevant, tu paries $opposite.',
                  'By accepting, you bet $opposite.'),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          if (status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                status,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (acceptable || canClose)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  if (acceptable)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: busy
                          ? null
                          : () => _run(
                              () => SideBets.accept(widget.roomId, b.id)),
                      child: Text(tr('Relever', 'Accept')),
                    ),
                  if (acceptable && canClose) const SizedBox(width: 8),
                  if (canClose)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                      ),
                      onPressed: busy
                          ? null
                          : () => _run(
                              () => SideBets.cancel(widget.roomId, b.id)),
                      child: Text(b.proposerUid == me
                          ? tr('Annuler', 'Cancel')
                          : tr('Refuser', 'Decline')),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _roomStream,
        builder: (context, rs) {
          final data = rs.data?.data();
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final room = _Room(data, widget.uid);
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _betsStream,
            builder: (context, bs) {
              final bets = <SideBet>[
                for (final doc in bs.data?.docs ??
                    const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                  SideBet(doc.id, doc.data()),
              ]..removeWhere((b) => b.isClosed && !_involved(b));
              bets.sort((a, b) {
                final ka = room.canAccept(a) ? 0 : 1;
                final kb = room.canAccept(b) ? 0 : 1;
                if (ka != kb) return ka - kb;
                return b.createdMs.compareTo(a.createdMs);
              });
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  Text(
                    tr('⚔️ Défis et paris', '⚔️ Challenges & bets'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  _title(tr('Proposer un pari', 'Propose a bet')),
                  _form(room),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        error!,
                        style: const TextStyle(
                          color: Color(0xFFFF8A80),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  _title(tr('Paris de la partie', 'Bets in this game')),
                  if (bets.isEmpty)
                    _note(tr('Aucun pari pour le moment.', 'No bets yet.')),
                  for (final b in bets.take(20)) _card(b, room),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
