import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;

import 'accounts.dart';
import 'damier.dart';
import 'lang.dart';

/// Damier « DEUX BUTS SORT » : salle ouverte à tous avec file d'attente.
class DeuxButsScreen extends StatefulWidget {
  const DeuxButsScreen({super.key});

  @override
  State<DeuxButsScreen> createState() => _DeuxButsScreenState();
}

class _DeuxButsScreenState extends State<DeuxButsScreen> {
  static const Color _gold = Color(0xFFFFC21A);

  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _rooms = [];
  String? _rid; // salle ouverte (null = liste des salles)
  Timer? _timer;
  final Set<String> _opened = {};
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && !_busy) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final r = await Wallet.dbList(_rid);
      final l = (r['rooms'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _rooms = l;
        _error = null;
        _loading = false;
      });
      _autoOpen();
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _error = Wallet.errorText(e);
          _loading = false;
        });
      }
    }
  }

  Map<String, dynamic>? get _room {
    for (final r in _rooms) {
      if (r['id'] == _rid) return r;
    }
    return null;
  }

  /// Quand c'est à moi de jouer, la partie s'ouvre toute seule (une seule fois par match).
  void _autoOpen() {
    final r = _room;
    if (r == null) return;
    final me = r['me'] as Map?;
    final gid = (r['gameId'] as String?) ?? '';
    if (me == null || me['state'] != 'playing' || gid.isEmpty) return;
    if (_opened.contains(gid)) return;
    _opened.add(gid);
    _openGame(gid, false);
  }

  void _openGame(String gid, bool spectate) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
          builder: (_) => DamierRoomPage(roomId: gid, spectate: spectate),
        ))
        .then((_) {
      if (mounted) _load(silent: true);
    });
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _run(Future<void> Function() job, [String? ok]) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
      if (ok != null) _snack(ok);
    } catch (e) {
      _snack(Wallet.errorText(e));
    }
    if (mounted) setState(() => _busy = false);
    await _load(silent: true);
  }

  Future<void> _create() async {
    final stakeCtrl = TextEditingController(text: '500');
    int minutes = 10;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(tr('Nouvelle salle', 'New room')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: stakeCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: tr('Mise par match (FCFA)', 'Stake per match (FCFA)'),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButton<int>(
                value: minutes,
                isExpanded: true,
                items: [
                  for (final m in [3, 5, 10, 15, 20, 30])
                    DropdownMenuItem(value: m, child: Text('$m min ${tr('par joueur', 'per player')}')),
                ],
                onChanged: (v) => set(() => minutes = v ?? minutes),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Annuler', 'Cancel'))),
            TextButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Créer', 'Create'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final stake = int.tryParse(stakeCtrl.text.trim()) ?? 0;
    await _run(() async {
      final r = await Wallet.dbCreate(stake: stake, timeMin: minutes);
      _rid = r['id'] as String?;
      await Wallet.dbJoin(_rid!);
    }, tr('Salle créée, tu es dans la file.', 'Room created, you are in the queue.'));
  }

  void _rules() {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('DEUX BUTS SORT'),
        content: SingleChildScrollView(
          child: Text(tr(
            '• Tout le monde peut rejoindre la salle. Les joueurs entrent à la table par ordre d\'arrivée.\n'
            '• Chaque match est misé : le gagnant reçoit 2 mises moins 5 %, un match nul rend les mises.\n'
            '• Tu sors si tu perds 2 matchs, ou si tu perds 1 match et fais 1 nul.\n'
            '• Deux joueurs rejouent ensemble (couleurs inversées) tant qu\'aucun ne sort.\n'
            '• Si après 2 matchs aucun ne sort (1 victoire chacun…) : match de BARRAGE. Le perdant sort ; en cas de nul, les deux sortent et les deux suivants entrent.\n'
            '• Le gagnant reste à la table et affronte le suivant de la file.\n'
            '• Tu peux revenir dans la file après être sorti, avec zéro faute.',
            '• Anyone can join the room. Players take the table in order of arrival.\n'
            '• Every match is staked: the winner gets 2 stakes minus 5 %, a draw refunds the stakes.\n'
            '• You are out if you lose 2 matches, or lose 1 match and draw 1.\n'
            '• Two players keep playing each other (colours swapped) while neither is out.\n'
            '• If after 2 matches nobody is out (1 win each…): TIE-BREAK match. The loser is out; on a draw both are out and the next two come in.\n'
            '• The winner stays at the table and faces the next in the queue.\n'
            '• You can rejoin the queue after being out, with a clean slate.',
          )),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Fermer', 'Close')))],
      ),
    );
  }

  Widget _faults(Map<String, dynamic> p) {
    final l = (p['losses'] as num?)?.toInt() ?? 0;
    final d = (p['draws'] as num?)?.toInt() ?? 0;
    return Text('${tr('Défaites', 'Losses')} $l • ${tr('Nuls', 'Draws')} $d');
  }

  Widget _roomCard(Map<String, dynamic> r) {
    final n = (r['players'] as List).length;
    return Card(
      color: Colors.white.withOpacity(0.96),
      child: ListTile(
        title: Text('♟ ${r['title']}', style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('${Wallet.format((r['stake'] as num).toInt())} / match • ${r['timeMin']} min • $n ${tr('joueur(s)', 'player(s)')}\n${tr('Créée par', 'Created by')} ${r['hostName']}'),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          setState(() => _rid = r['id'] as String);
          _load();
        },
      ),
    );
  }

  Widget _roomView(Map<String, dynamic> r) {
    final players = (r['players'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final pair = (r['pair'] as List).cast<String>();
    final me = r['me'] == null ? null : Map<String, dynamic>.from(r['me'] as Map);
    final inRoom = me != null && (me['state'] == 'waiting' || me['state'] == 'table' || me['state'] == 'playing');
    final gid = (r['gameId'] as String?) ?? '';
    final matchNo = (r['matchNo'] as num?)?.toInt() ?? 0;
    final tablePl = [for (final u in pair) players.firstWhere((p) => p['uid'] == u, orElse: () => <String, dynamic>{})]
        .where((p) => p.isNotEmpty)
        .toList();
    final queue = players.where((p) => p['state'] == 'waiting').toList();
    final isHost = r['hostUid'] == _uid;

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Card(
          color: Colors.white.withOpacity(0.96),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('♟ ${r['title']}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                Text('${Wallet.format((r['stake'] as num).toInt())} / match • ${r['timeMin']} min ${tr('par joueur', 'per player')}'),
                const Divider(),
                Text(tr('🎯 À la table', '🎯 At the table'), style: const TextStyle(fontWeight: FontWeight.w800)),
                if (tablePl.isEmpty) Text(tr('Table vide — en attente de joueurs.', 'Table empty — waiting for players.')),
                for (final p in tablePl)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(children: [
                      Expanded(child: Text('${p['name']}${p['uid'] == _uid ? tr(' (toi)', ' (you)') : ''}', style: const TextStyle(fontWeight: FontWeight.w700))),
                      _faults(p),
                    ]),
                  ),
                if (tablePl.length == 1) Text(tr('⏳ En attente d\'un adversaire…', '⏳ Waiting for an opponent…')),
                if (gid.isNotEmpty)
                  Text(matchNo >= 3
                      ? tr('⚔️ MATCH DE BARRAGE', '⚔️ TIE-BREAK MATCH')
                      : tr('Match $matchNo de la série', 'Match $matchNo of the series')),
                if (gid.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  if (me != null && me['state'] == 'playing')
                    FilledButton.icon(
                      onPressed: () => _openGame(gid, false),
                      icon: const Icon(Icons.play_arrow),
                      label: Text(tr('Jouer mon match', 'Play my match')),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () => _openGame(gid, true),
                      icon: const Icon(Icons.visibility),
                      label: Text(tr('Regarder le match', 'Watch the match')),
                    ),
                ],
              ],
            ),
          ),
        ),
        Card(
          color: Colors.white.withOpacity(0.96),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${tr('⏳ File d\'attente', '⏳ Queue')} (${queue.length})', style: const TextStyle(fontWeight: FontWeight.w800)),
                if (queue.isEmpty) Text(tr('Personne en attente.', 'Nobody waiting.')),
                for (var i = 0; i < queue.length; i++)
                  Text('${i + 1}. ${queue[i]['name']}${queue[i]['uid'] == _uid ? tr(' (toi)', ' (you)') : ''}'),
              ],
            ),
          ),
        ),
        if (me != null && me['state'] == 'out')
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              (me['note'] == 'solde')
                  ? tr('Solde insuffisant : recharge puis reviens dans la file.', 'Not enough balance: top up, then rejoin the queue.')
                  : tr('Tu es sorti. Tu peux revenir dans la file.', 'You are out. You can rejoin the queue.'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 4, children: [
          if (!inRoom && r['status'] == 'open')
            FilledButton(
              onPressed: _busy ? null : () => _run(() async {
                    await Wallet.dbJoin(r['id'] as String);
                  }, tr('Tu es dans la file.', 'You are in the queue.')),
              child: Text(tr('Rejoindre la salle', 'Join the room')),
            ),
          if (inRoom && me != null && me['state'] != 'playing')
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
              onPressed: _busy ? null : () => _run(() async {
                    await Wallet.dbLeave(r['id'] as String);
                  }, tr('Tu as quitté la salle.', 'You left the room.')),
              child: Text(tr('Quitter la salle', 'Leave the room')),
            ),
          if (isHost && r['status'] == 'open')
            TextButton(
              onPressed: _busy ? null : () => _run(() async {
                    await Wallet.dbClose(r['id'] as String);
                    _rid = null;
                  }, tr('Salle fermée.', 'Room closed.')),
              child: Text(tr('Fermer la salle', 'Close the room'), style: const TextStyle(color: _gold)),
            ),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = _rid == null ? null : _room;
    return Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1F5BFF), Color(0xFF0B2FA6), Color(0xFF061A66)],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          if (_rid != null) {
                            setState(() => _rid = null);
                          } else {
                            Navigator.of(context).maybePop();
                          }
                        },
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      const Expanded(
                        child: Text('♟ DEUX BUTS SORT', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900)),
                      ),
                      IconButton(onPressed: _rules, icon: const Icon(Icons.info_outline, color: _gold)),
                      if (_rid == null)
                        IconButton(onPressed: _busy ? null : _create, icon: const Icon(Icons.add_circle, color: _gold)),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator(color: _gold))
                      : _error != null
                          ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!, style: const TextStyle(color: Colors.white))))
                          : room != null
                              ? _roomView(room)
                              : _rooms.isEmpty
                                  ? Center(child: Text(tr('Aucune salle ouverte. Crée la première avec le bouton +.', 'No open room. Create the first one with +.'), style: const TextStyle(color: Colors.white), textAlign: TextAlign.center))
                                  : ListView(
                                      padding: const EdgeInsets.all(14),
                                      children: [for (final r in _rooms) _roomCard(r)],
                                    ),
                ),
              ],
            ),
          ),
        ),
    );
  }
}
