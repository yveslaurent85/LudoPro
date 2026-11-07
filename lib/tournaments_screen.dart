import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import 'accounts.dart';
import 'lang.dart';
import 'online.dart';

const List<String> _moisFr = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
];
const List<String> _moisEn = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _two(int n) => n < 10 ? '0$n' : '$n';

String _fmtDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final m = appLang.value == 'en' ? _moisEn[d.month - 1] : _moisFr[d.month - 1];
  return '${d.day} $m ${d.year} • ${_two(d.hour)}h${_two(d.minute)}';
}

String _fcfa(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return '${b.toString()} FCFA';
}

/// Tournois Katika : liste, inscription payée sur le solde, équipes (duos).
class TournamentsScreen extends StatefulWidget {
  const TournamentsScreen({super.key});

  @override
  State<TournamentsScreen> createState() => _TournamentsScreenState();
}

class _TournamentsScreenState extends State<TournamentsScreen> {
  static const Color _gold = Color(0xFFFFC21A);

  bool _loading = true;
  bool _busy = false;
  bool _admin = false;
  String? _error;
  List<Map<String, dynamic>> _list = [];
  final Map<String, Map<String, dynamic>?> _mine = {};
  List<Map<String, dynamic>> _matches = [];
  bool _test = false;

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && !_busy) _silentLoad();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _silentLoad() async {
    try {
      final r = await Wallet.tournamentList();
      if (!mounted) return;
      setState(() {
        _list = (r['tournaments'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _matches = (r['matches'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Wallet.tournamentList();
      final l = (r['tournaments'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final mine = <String, Map<String, dynamic>?>{};
      for (final m in (r['mine'] as List? ?? const [])) {
        final mm = Map<String, dynamic>.from(m as Map);
        mine[mm['tid'] as String] =
            mm['team'] == null ? <String, dynamic>{} : Map<String, dynamic>.from(mm['team'] as Map);
      }
      final ms = (r['matches'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _matches = ms;
        _list = l;
        _mine
          ..clear()
          ..addAll(mine);
        _admin = r['admin'] == true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = Wallet.errorText(e);
        _loading = false;
      });
    }
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _run(Future<void> Function() job, String ok) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
      _snack(ok);
    } catch (e) {
      _snack(Wallet.errorText(e));
    }
    if (mounted) setState(() => _busy = false);
    await _load();
  }

  Future<bool> _confirm(String title, String body) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Annuler', 'Cancel'))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Confirmer', 'Confirm'))),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _register(Map<String, dynamic> t) async {
    final fee = t['fee'] as int;
    if (!await _confirm(
      tr('S\'inscrire', 'Register'),
      tr('${_fcfa(fee)} seront débités de ton solde. Remboursement intégral si tu te désinscris avant la clôture ou si le tournoi est annulé.',
          '${_fcfa(fee)} will be taken from your balance. Full refund if you leave before the deadline or if the tournament is cancelled.'),
    )) return;
    await _run(() async {
      await Wallet.tournamentRegister(t['id'] as String);
    }, tr('Inscription confirmée ✅', 'Registered ✅'));
  }

  Future<void> _createTeam(Map<String, dynamic> t) async {
    final ctrl = TextEditingController();
    final fee = t['fee'] as int;
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Créer mon équipe', 'Create my team')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              maxLength: 30,
              decoration: InputDecoration(labelText: tr('Nom de l\'équipe (facultatif)', 'Team name (optional)')),
            ),
            Text(tr('${_fcfa(fee)} seront débités. Tu recevras un code à donner à ton partenaire, qui paiera sa part.',
                '${_fcfa(fee)} will be taken. You will get a code to give your partner, who pays their share.')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Annuler', 'Cancel'))),
          TextButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: Text(tr('Payer et créer', 'Pay and create'))),
        ],
      ),
    );
    if (name == null) return;
    await _run(() async {
      await Wallet.tournamentTeamCreate(t['id'] as String, name);
    }, tr('Équipe créée : donne le code à ton partenaire.', 'Team created: give the code to your partner.'));
  }

  Future<void> _joinTeam() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Rejoindre une équipe', 'Join a team')),
        content: TextField(
          controller: ctrl,
          textCapitalization: TextCapitalization.characters,
          maxLength: 12,
          decoration: InputDecoration(labelText: tr('Code reçu de ton partenaire', 'Code from your partner')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Annuler', 'Cancel'))),
          TextButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: Text(tr('Payer et rejoindre', 'Pay and join'))),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;
    await _run(() async {
      await Wallet.tournamentTeamJoin(code);
    }, tr('Tu as rejoint l\'équipe ✅', 'You joined the team ✅'));
  }

  Future<void> _leave(Map<String, dynamic> t) async {
    if (!await _confirm(
      tr('Se désinscrire', 'Leave'),
      tr('Tu seras remboursé. Si tu es chef d\'une équipe complète, ton partenaire est aussi remboursé et l\'équipe est dissoute.',
          'You will be refunded. If you lead a complete team, your partner is refunded too and the team is dissolved.'),
    )) return;
    await _run(() async {
      await Wallet.tournamentLeave(t['id'] as String);
    }, tr('Remboursé ✅', 'Refunded ✅'));
  }

  Future<void> _adminCancel(Map<String, dynamic> t) async {
    if (!await _confirm(
      tr('Annuler le tournoi', 'Cancel tournament'),
      tr('Tous les inscrits seront remboursés.', 'All players will be refunded.'),
    )) return;
    await _run(() async {
      await Wallet.adminTournamentCancel(t['id'] as String);
    }, tr('Tournoi annulé, inscrits remboursés.', 'Tournament cancelled, players refunded.'));
  }

  Future<void> _adminCreate() async {
    String type = 'katika';
    bool test = false;
    DateTime? start;
    DateTime? limit;
    Future<DateTime?> pick(BuildContext c, DateTime? init) async {
      final now = DateTime.now();
      final d = await showDatePicker(
        context: c,
        initialDate: init ?? now.add(const Duration(days: 7)),
        firstDate: now,
        lastDate: now.add(const Duration(days: 365)),
      );
      if (d == null || !c.mounted) return null;
      final tm = await showTimePicker(context: c, initialTime: const TimeOfDay(hour: 18, minute: 0));
      if (tm == null) return null;
      return DateTime(d.year, d.month, d.day, tm.hour, tm.minute);
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(tr('Nouveau tournoi', 'New tournament')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<String>(
                value: type,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'katika', child: Text('Katika Tournament (duos, 2 500)')),
                  DropdownMenuItem(value: 'mondly', child: Text('Katika Mondly (solo, 2 000)')),
                ],
                onChanged: (v) => set(() => type = v ?? type),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: test,
                onChanged: (v) => set(() => test = v == true),
                title: Text(tr('Tournoi d\'essai (4 joueurs, 100 FCFA)', 'Test tournament (4 players, 100 FCFA)')),
              ),
              TextButton(
                onPressed: () async {
                  final d = await pick(c, start);
                  if (d != null) set(() => start = d);
                },
                child: Text(start == null
                    ? tr('Choisir la date de début', 'Pick start date')
                    : '${tr('Début', 'Start')} : ${_fmtDate(start!.millisecondsSinceEpoch)}'),
              ),
              TextButton(
                onPressed: () async {
                  final d = await pick(c, limit);
                  if (d != null) set(() => limit = d);
                },
                child: Text(limit == null
                    ? tr('Choisir la clôture des inscriptions', 'Pick registration deadline')
                    : '${tr('Clôture', 'Deadline')} : ${_fmtDate(limit!.millisecondsSinceEpoch)}'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Annuler', 'Cancel'))),
            TextButton(
              onPressed: start != null && limit != null ? () => Navigator.pop(c, true) : null,
              child: Text(tr('Créer', 'Create')),
            ),
          ],
        ),
      ),
    );
    if (ok != true || start == null || limit == null) return;
    await _run(() async {
      await Wallet.adminTournamentCreate(
        type: type,
        startAt: start!.millisecondsSinceEpoch,
        regDeadline: limit!.millisecondsSinceEpoch,
        test: test,
      );
    }, tr('Tournoi créé ✅', 'Tournament created ✅'));
  }

  void _rules() {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Règlement', 'Rules')),
        content: SingleChildScrollView(
          child: Text(tr(
            '• Inscription payée depuis ton solde Katika.\n'
            '• Katika Tournament : 64 joueurs en duos (32 équipes), 2 500 FCFA par joueur. Un chef d\'équipe crée le duo et paie, puis son partenaire rejoint avec le code et paie sa part.\n'
            '• Katika Mondly : 32 joueurs en solo, 2 000 FCFA.\n'
            '• Tournoi incomplet à la clôture des inscriptions : annulation automatique et remboursement intégral.\n'
            '• Désinscription possible avant la clôture, avec remboursement.\n'
            '• Sois connecté 10 minutes avant ton match ; après 5 minutes d\'absence, tu perds par forfait.\n'
            '• Les gains des équipes sont partagés à parts égales entre les deux partenaires.',
            '• Registration is paid from your Katika balance.\n'
            '• Katika Tournament: 64 players in pairs (32 teams), 2,500 FCFA each. A team leader creates the pair and pays, then the partner joins with the code and pays their share.\n'
            '• Katika Mondly: 32 solo players, 2,000 FCFA.\n'
            '• Tournament not full at the registration deadline: automatic cancellation and full refund.\n'
            '• You can leave before the deadline and get a refund.\n'
            '• Be online 10 minutes before your match; after 5 minutes absent you forfeit.\n'
            '• Team prizes are split equally between both partners.',
          )),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Fermer', 'Close')))],
      ),
    );
  }

  String _roundName(Map<String, dynamic> t, Map<String, dynamic> m) {
    final rounds = (t['rounds'] as num?)?.toInt() ?? 0;
    final r = (m['round'] as num).toInt();
    if (m['kind'] == 'third') return tr('Petite finale', 'Third-place match');
    if (rounds > 0 && r == rounds) return tr('Finale', 'Final');
    if (rounds > 1 && r == rounds - 1 && t['type'] == 'katika') return tr('Demi-finale', 'Semi-final');
    return tr('Tour $r', 'Round $r');
  }

  List<Widget> _matchInfo(Map<String, dynamic> t) {
    final id = t['id'] as String;
    final status = t['status'] as String;
    final mine = _matches.where((m) => m['tid'] == id).toList();
    final out = <Widget>[];
    if (status == 'running' || status == 'finished') {
      out.add(const Divider());
      if (mine.isEmpty && _mine.containsKey(id)) {
        out.add(Text(tr('Bracket en préparation…', 'Bracket being prepared…')));
      }
      if (mine.isNotEmpty) {
        final last = mine.first; // la plus récente
        if (last['status'] == 'playing') {
          out.add(Text('⚔️ ${_roundName(t, last)} — ${tr('ta partie est prête !', 'your game is ready!')}',
              style: const TextStyle(fontWeight: FontWeight.w800)));
          out.add(const SizedBox(height: 6));
          out.add(FilledButton.icon(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(
                  builder: (_) => OnlineGameRoom(gameId: last['gameId'] as String),
                ))
                .then((_) => _load()),
            icon: const Icon(Icons.play_arrow),
            label: Text(tr('Jouer ma partie', 'Play my game')),
          ));
        } else if (last['advanced'] == true && status == 'running') {
          out.add(Text('✅ ${tr('Qualifié pour le tour suivant. Reste connecté !', 'Qualified for the next round. Stay online!')}',
              style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF22B14C))));
        } else if (last['advanced'] != true && status == 'running') {
          out.add(Text('❌ ${tr('Éliminé. Merci d\'avoir participé !', 'Eliminated. Thanks for playing!')}'));
        }
      }
      final pl = (t['placings'] as List? ?? const []);
      if (pl.isNotEmpty) {
        out.add(const SizedBox(height: 6));
        out.add(Text(tr('Classement final :', 'Final ranking:'), style: const TextStyle(fontWeight: FontWeight.w800)));
        for (final p in pl) {
          final m = Map<String, dynamic>.from(p as Map);
          out.add(Text('${m['place']}. ${m['label']}'));
        }
      }
    }
    return out;
  }

  Widget _card(Map<String, dynamic> t) {
    final id = t['id'] as String;
    final type = t['type'] as String;
    final status = t['status'] as String;
    final fee = t['fee'] as int;
    final cap = t['capacity'] as int;
    final taken = t['taken'] as int;
    final paid = t['paid'] as int;
    final prizes = (t['prizes'] as List).map((e) => (e as num).toInt()).toList();
    final team = _mine[id];
    final registered = _mine.containsKey(id);
    final isTeam = type == 'katika';
    final open = status == 'open';
    final labels = [
      tr('🥇 1er', '🥇 1st'),
      tr('🥈 2e', '🥈 2nd'),
      tr('🥉 3e', '🥉 3rd'),
      tr('4e', '4th'),
    ];
    final statusTxt = {
      'open': tr('Inscriptions ouvertes', 'Registration open'),
      'ready': tr('Complet — départ prévu', 'Full — starting soon'),
      'running': tr('En cours', 'In progress'),
      'finished': tr('Terminé', 'Finished'),
      'cancelled': tr('Annulé (remboursé)', 'Cancelled (refunded)'),
    }[status] ?? status;

    final buttons = <Widget>[];
    if (open && !registered) {
      if (isTeam) {
        buttons.add(FilledButton(onPressed: _busy ? null : () => _createTeam(t), child: Text(tr('Créer mon équipe', 'Create my team'))));
        buttons.add(OutlinedButton(onPressed: _busy ? null : _joinTeam, child: Text(tr('J\'ai un code', 'I have a code'))));
      } else {
        buttons.add(FilledButton(onPressed: _busy ? null : () => _register(t), child: Text(tr('S\'inscrire', 'Register'))));
      }
    }
    if ((open || status == 'ready') && registered) {
      buttons.add(OutlinedButton(onPressed: _busy ? null : () => _leave(t), child: Text(tr('Me désinscrire', 'Leave'))));
    }
    if (_admin && (open || status == 'ready' || status == 'cancelled')) {
      buttons.add(TextButton(
        onPressed: _busy ? null : () => _adminCancel(t),
        child: Text(tr('Annuler (admin)', 'Cancel (admin)')),
      ));
    }

    return Card(
      color: Colors.white.withOpacity(0.96),
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🏆 ${t['title']}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(statusTxt, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1E6BFF))),
            const SizedBox(height: 8),
            Text('📅 ${_fmtDate(t['startAt'] as int)}'),
            Text('⏳ ${tr('Clôture des inscriptions', 'Registration closes')} : ${_fmtDate(t['regDeadline'] as int)}'),
            Text('💳 ${tr('Inscription', 'Entry')} : ${_fcfa(fee)} ${isTeam ? tr('par joueur', 'per player') : ''}'),
            Text(isTeam
                ? '👥 ${tr('Joueurs payés', 'Players paid')} : $paid / $cap  (${tr('places réservées', 'reserved')} $taken)'
                : '👥 ${tr('Inscrits', 'Registered')} : $paid / $cap'),
            const SizedBox(height: 6),
            Text(tr(isTeam ? 'Gains par équipe :' : 'Gains :', isTeam ? 'Prizes per team:' : 'Prizes:'),
                style: const TextStyle(fontWeight: FontWeight.w800)),
            for (var i = 0; i < prizes.length && i < 4; i++) Text('${labels[i]} : ${_fcfa(prizes[i])}'),
            if (registered) ...[
              const Divider(),
              Text('✅ ${tr('Tu es inscrit', 'You are registered')}', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF22B14C))),
              if (team != null && team.isNotEmpty) ...[
                Text('${tr('Équipe', 'Team')} : ${team['name']} (${(team['names'] as List).join(' + ')})'),
                if (team['status'] == 'pending')
                  Text(tr('⏳ En attente de ton partenaire', '⏳ Waiting for your partner')),
                if ((team['code'] as String? ?? '').isNotEmpty)
                  Row(
                    children: [
                      Text('${tr('Code partenaire', 'Partner code')} : ',),
                      Text(team['code'] as String, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: 2)),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: team['code'] as String));
                          _snack(tr('Code copié', 'Code copied'));
                        },
                      ),
                    ],
                  ),
              ],
            ],
            ..._matchInfo(t),
            if (buttons.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 4, children: buttons),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    Expanded(
                      child: Text(
                        tr('🏆 Tournois', '🏆 Tournaments'),
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(onPressed: _rules, icon: const Icon(Icons.info_outline, color: _gold)),
                    IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh, color: Colors.white)),
                    if (_admin)
                      IconButton(onPressed: _busy ? null : _adminCreate, icon: const Icon(Icons.add_circle, color: _gold)),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: _gold))
                    : _error != null
                        ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!, style: const TextStyle(color: Colors.white))))
                        : _list.isEmpty
                            ? Center(child: Text(tr('Aucun tournoi pour le moment.', 'No tournament for now.'), style: const TextStyle(color: Colors.white)))
                            : ListView(
                                padding: const EdgeInsets.all(14),
                                children: [for (final t in _list) _card(t)],
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
