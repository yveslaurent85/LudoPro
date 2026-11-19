import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'accounts.dart';
import 'lang.dart';

/// KATIKA PES : défis PES 2016 à deux, en ligne (rubrique Paris par derrière).
/// Katika organise le défi ; le match se joue dans PES 2016. Le résultat vient des
/// joueurs (score + capture) et, quand il y a de l'argent en jeu, il est validé par l'administration.

const Color _gold = Color(0xFFFFC21A);
const Color _green = Color(0xFF7CFFB0);

const Map<String, String> kPesPlatforms = {
  'ps4': 'PS4',
  'ps3': 'PS3',
  'xbox': 'Xbox',
  'pc': 'PC',
  'android': 'Android',
};

String _fc(int n) {
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return '$b FCFA';
}

BoxDecoration get _bg => const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF1F5BFF), Color(0xFF0B2FA6), Color(0xFF061A66)],
      ),
    );

String _statusLabel(String s) {
  switch (s) {
    case 'open':
      return tr('En attente d\'un adversaire', 'Waiting for an opponent');
    case 'accepted':
      return tr('Match prêt : à jouer', 'Match ready: play it');
    case 'reporting':
      return tr('Résultat en cours d\'envoi', 'Result being sent');
    case 'review':
      return tr('En validation par Katika', 'Being validated by Katika');
    case 'disputed':
      return tr('Litige : arbitrage Katika', 'Dispute: Katika arbitration');
    case 'done':
      return tr('Terminé', 'Finished');
    case 'refunded':
      return tr('Mises rendues', 'Stakes refunded');
    case 'cancelled':
      return tr('Annulé', 'Cancelled');
    case 'suspended':
      return tr('Suspendu', 'Suspended');
  }
  return s;
}

Color _statusColor(String s) {
  switch (s) {
    case 'open':
      return const Color(0xFF90CAF9);
    case 'accepted':
    case 'reporting':
      return _gold;
    case 'review':
      return const Color(0xFFFFB74D);
    case 'disputed':
    case 'suspended':
      return const Color(0xFFFF8A80);
    case 'done':
      return _green;
  }
  return Colors.white60;
}

Widget _chip(String s) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: _statusColor(s).withOpacity(0.18), borderRadius: BorderRadius.circular(10), border: Border.all(color: _statusColor(s))),
      child: Text(_statusLabel(s), style: TextStyle(color: _statusColor(s), fontSize: 11, fontWeight: FontWeight.w800)),
    );

Future<String> _savedEf() async {
  try {
    final p = await SharedPreferences.getInstance();
    return p.getString('pesEf') ?? '';
  } catch (_) {
    return '';
  }
}

Future<void> _saveEf(String v) async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString('pesEf', v);
  } catch (_) {}
}

// ----------------------------------------------------------------------
// Accueil KATIKA PES
// ----------------------------------------------------------------------

class PesHomeScreen extends StatefulWidget {
  const PesHomeScreen({super.key});

  @override
  State<PesHomeScreen> createState() => _PesHomeScreenState();
}

class _PesHomeScreenState extends State<PesHomeScreen> {
  Map<String, dynamic>? _d;
  String? _err;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Wallet.pesList();
      if (mounted) {
        setState(() {
          _d = d;
          _err = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _err = Wallet.errorText(e));
    }
  }

  List<Map<String, dynamic>> _rows(String k) => [for (final x in (_d?[k] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
  bool get _paid => (_d?['config'] as Map?)?['paid'] == true;

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _openMatch(String id) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PesMatchScreen(id: id)));
    _load();
  }

  Future<void> _create() async {
    final cfg = Map<String, dynamic>.from((_d?['config'] as Map?) ?? const {});
    final ef = TextEditingController(text: await _savedEf());
    final stake = TextEditingController(text: '0');
    final rules = TextEditingController();
    var platform = 'ps4';
    if (!mounted) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B2FA6),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Créer un défi PES 2016', 'Create a PES 2016 challenge'),
                  style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Text(tr('Ta plateforme (ton adversaire doit être sur la même)', 'Your platform (your opponent must be on the same)'),
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Wrap(spacing: 8, children: [
                for (final e in kPesPlatforms.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: platform == e.key,
                    selectedColor: _gold,
                    onSelected: (_) => setS(() => platform = e.key),
                  ),
              ]),
              TextField(
                controller: ef,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: tr('Identifiant PES 2016 (facultatif)', 'PES 2016 ID (optional)'),
                  helperText: tr('Laisse vide : tu joues avec ton compte Katika.', 'Leave empty: you play with your Katika account.'),
                  helperStyle: const TextStyle(color: Colors.white54),
                  labelStyle: const TextStyle(color: Colors.white70),
                ),
              ),
              if (_paid)
                TextField(
                  controller: stake,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: tr('Mise (FCFA) — 0 = gratuit', 'Stake (FCFA) — 0 = free'),
                    helperText: tr('Commission Katika : ${cfg['commission']} %', 'Katika commission: ${cfg['commission']} %'),
                    helperStyle: const TextStyle(color: Colors.white54),
                    labelStyle: const TextStyle(color: Colors.white70),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    tr('Mode gratuit : les défis avec mise seront ouverts après validation des autorisations.',
                        'Free mode: challenges with a stake will open once the required authorizations are validated.'),
                    style: const TextStyle(color: _gold, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              TextField(
                controller: rules,
                maxLength: 200,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: tr('Conditions (durée des mi-temps, équipes…)', 'Conditions (half length, teams…)'),
                  labelStyle: const TextStyle(color: Colors.white70),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(tr('Publier le défi', 'Publish the challenge'), style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    final efv = ef.text.trim();
    final st = int.tryParse(stake.text.trim()) ?? 0;
    final rl = rules.text.trim();
    ef.dispose();
    stake.dispose();
    rules.dispose();
    if (ok != true || _busy) return;
    setState(() => _busy = true);
    try {
      await _saveEf(efv);
      final r = await Wallet.pesCreate(stake: _paid ? st : 0, efId: efv, rules: rl, platform: platform);
      final c = Map<String, dynamic>.from(r['challenge'] as Map);
      if (mounted) setState(() => _busy = false);
      await _openMatch('${c['id']}');
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _snack(Wallet.errorText(e));
    }
  }

  Future<void> _accept(Map<String, dynamic> c) async {
    final ef = TextEditingController(text: await _savedEf());
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0B2FA6),
        title: Text(tr('Relever ce défi', 'Accept this challenge'), style: const TextStyle(color: Color(0xFFFFE082), fontWeight: FontWeight.w900)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${c['hostName']} · ${kPesPlatforms['${c['platform']}'] ?? ''}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          Text((c['stake'] as num) > 0 ? '${tr('Mise', 'Stake')} : ${_fc((c['stake'] as num).toInt())}' : tr('Défi gratuit', 'Free challenge'),
              style: const TextStyle(color: _gold, fontWeight: FontWeight.w800)),
          if ('${c['rules']}'.isNotEmpty) Text('${c['rules']}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 8),
          TextField(
            controller: ef,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
                labelText: tr('Identifiant PES 2016 (facultatif)', 'PES 2016 ID (optional)'),
                helperText: tr('Laisse vide : tu joues avec ton compte Katika.', 'Leave empty: you play with your Katika account.'),
                helperStyle: const TextStyle(color: Colors.white54),
                labelStyle: const TextStyle(color: Colors.white70)),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Annuler', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Relever', 'Accept'))),
        ],
      ),
    );
    final efv = ef.text.trim();
    ef.dispose();
    if (ok != true || _busy) return;
    setState(() => _busy = true);
    try {
      await _saveEf(efv);
      await Wallet.pesAccept('${c['id']}', efv);
      if (mounted) setState(() => _busy = false);
      await _openMatch('${c['id']}');
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _snack(Wallet.errorText(e));
      _load();
    }
  }

  Widget _card(Map<String, dynamic> c, {required bool mine}) {
    final stake = (c['stake'] as num?)?.toInt() ?? 0;
    final st = '${c['status']}';
    final role = '${c['role']}';
    final opp = role == 'host' ? '${c['guestName']}' : '${c['hostName']}';
    return GestureDetector(
      onTap: () => mine ? _openMatch('${c['id']}') : _accept(c),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white24)),
        child: Row(children: [
          const Text('⚽', style: TextStyle(fontSize: 26)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(mine ? (opp.isEmpty ? tr('En attente d\'un adversaire', 'Waiting for an opponent') : 'vs $opp') : '${c['hostName']}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
              Text('${kPesPlatforms['${c['platform']}'] ?? ''} · ${stake > 0 ? _fc(stake) : tr('gratuit', 'free')}'
                  '${'${c['rules']}'.isEmpty ? '' : ' · ${c['rules']}'}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
          if (mine) _chip(st) else Text(tr('Relever ›', 'Accept ›'), style: const TextStyle(color: _green, fontWeight: FontWeight.w900)),
        ]),
      ),
    );
  }

  Widget _list(List<Map<String, dynamic>> rows, {required bool mine, String empty = ''}) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 90), children: [
        if (rows.isEmpty) Padding(padding: const EdgeInsets.only(top: 30), child: Center(child: Text(empty, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)))),
        for (final c in rows) _card(c, mine: mine),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mine = _rows('mine');
    final live = mine.where((c) => ['open', 'accepted', 'reporting', 'review', 'disputed'].contains('${c['status']}')).toList();
    final past = mine.where((c) => !['open', 'accepted', 'reporting', 'review', 'disputed'].contains('${c['status']}')).toList();
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        body: Container(
          decoration: _bg,
          width: double.infinity,
          height: double.infinity,
          child: SafeArea(
            child: Column(children: [
              Row(children: [
                IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back, color: Colors.white)),
                const Expanded(
                  child: Text('⚽ KATIKA PES', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                ),
                IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh, color: Colors.white)),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _d == null
                        ? 'PES 2016 · 1 contre 1 en ligne'
                        : (_paid ? tr('PES 2016 · défis gratuits ou avec mise', 'PES 2016 · free or stake challenges') : tr('PES 2016 · mode gratuit', 'PES 2016 · free mode')),
                    style: const TextStyle(color: _gold, fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ),
              ),
              TabBar(
                isScrollable: true,
                indicatorColor: _gold,
                labelColor: _gold,
                unselectedLabelColor: Colors.white70,
                tabs: [
                  Tab(text: tr('Défis', 'Challenges')),
                  Tab(text: tr('Mes matchs', 'My matches')),
                  Tab(text: tr('Historique', 'History')),
                  Tab(text: tr('Règlement', 'Rules')),
                ],
              ),
              Expanded(
                child: _d == null
                    ? Center(
                        child: _err != null
                            ? Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  Text(_err!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFF8A80))),
                                  TextButton(onPressed: _load, child: Text(tr('Réessayer', 'Retry'))),
                                ]))
                            : const CircularProgressIndicator(color: _gold))
                    : TabBarView(children: [
                        _list(_rows('open'), mine: false, empty: tr('Aucun défi disponible.\nCrée le premier !', 'No challenge available.\nCreate the first one!')),
                        _list(live, mine: true, empty: tr('Aucun match en cours.', 'No match in progress.')),
                        _list(past, mine: true, empty: tr('Aucun match terminé.', 'No finished match.')),
                        const PesRulesView(),
                      ]),
              ),
            ]),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: const Color(0xFFE5262B),
          foregroundColor: Colors.white,
          onPressed: _busy || _d == null ? null : _create,
          icon: const Icon(Icons.add),
          label: Text(tr('Créer un défi', 'Create a challenge'), style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
      ),
    );
  }
}

/// Règlement PES 2016.
class PesRulesView extends StatelessWidget {
  const PesRulesView({super.key});

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      tr('KATIKA PES organise des défis 1 contre 1 sur PES 2016. Le match se joue dans le jeu : Katika n\'en contrôle ni le déroulement ni le score.',
          'KATIKA PES organizes 1v1 challenges on PES 2016. The match is played in the game: Katika controls neither its course nor its score.'),
      tr('1. Les deux joueurs doivent être sur la même plateforme (PS4, PC, Xbox…) et avoir un compte Katika.', '1. Both players must be on the same platform and have a Katika account.'),
      tr('2. Le joueur 1 crée un salon / match en ligne entre amis dans PES 2016 et donne le numéro du salon dans Katika. Le joueur 2 le rejoint.', '2. Player 1 creates an online room in PES 2016 and shares its number in Katika. Player 2 joins it.'),
      tr('3. Les conditions du défi (durée, équipes) sont celles affichées dans le défi. Elles ne peuvent pas être changées après l\'acceptation.', '3. The conditions shown in the challenge apply and cannot be changed after acceptance.'),
      tr('4. À la fin, chaque joueur envoie le score final avec une capture d\'écran de l\'écran de résultat (équipes, score, prolongations, tirs au but).', '4. At the end, each player sends the final score with a screenshot of the result screen.'),
      tr('5. Si les deux résultats concordent, ils sont validés par Katika avant tout versement. S\'ils sont différents, l\'administration arbitre.', '5. If both results match, Katika validates them before any payout. If they differ, the administration arbitrates.'),
      tr('6. Une capture n\'est pas une preuve automatique : Katika peut la refuser et demander des précisions.', '6. A screenshot is not automatic proof: Katika may refuse it and ask for details.'),
      tr('7. Déconnexion : elle ne donne pas la victoire automatiquement. Signale le problème : le dossier passe en arbitrage (rejeu, mises rendues ou décision de l\'administration).', '7. A disconnection does not give an automatic win. Report it: the case goes to arbitration.'),
      tr('8. Match nul : prolongations et tirs au but si prévus. Sinon, arbitrage.', '8. Draw: extra time and penalties if applicable. Otherwise, arbitration.'),
      tr('9. Un défi non relevé au bout de 24 h est annulé et la mise rendue.', '9. A challenge nobody accepts within 24 h is cancelled and the stake refunded.'),
      tr('10. Toute triche, fausse capture ou contestation abusive peut entraîner le blocage du compte.', '10. Cheating, fake screenshots or abusive disputes may lead to account suspension.'),
      tr('11. Les défis avec mise ne sont ouverts qu\'après validation des autorisations applicables et des conditions d\'utilisation. Jeu responsable : réservé aux 18 ans et plus.', '11. Stake challenges open only after the applicable authorizations are validated. Responsible play: 18+ only.'),
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 90), children: [
      for (final l in lines) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(l, style: const TextStyle(color: Colors.white, height: 1.35))),
    ]);
  }
}

// ----------------------------------------------------------------------
// Un match
// ----------------------------------------------------------------------

class PesMatchScreen extends StatefulWidget {
  const PesMatchScreen({super.key, required this.id});

  final String id;

  @override
  State<PesMatchScreen> createState() => _PesMatchScreenState();
}

class _PesMatchScreenState extends State<PesMatchScreen> {
  Map<String, dynamic>? _c;
  String? _err;
  bool _busy = false;
  Timer? _timer;
  final _room = TextEditingController();
  final _me = TextEditingController(text: '0');
  final _opp = TextEditingController(text: '0');
  final _pkMe = TextEditingController(text: '0');
  final _pkOpp = TextEditingController(text: '0');
  final _team = TextEditingController();
  String _extra = 'none';
  int _commission = 5;
  String? _proof; // data URL
  int _proofKb = 0;

  @override
  void initState() {
    super.initState();
    _load();
    // Lecture légère (1 document) toutes les 10 s tant que le match n'est pas terminé.
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      final st = '${_c?['status']}';
      if (_c == null || ['open', 'accepted', 'reporting', 'review', 'disputed'].contains(st)) _load(quiet: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in [_room, _me, _opp, _pkMe, _pkOpp, _team]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    try {
      final r = await Wallet.pesGet(widget.id);
      if (!mounted) return;
      setState(() {
        _c = Map<String, dynamic>.from(r['challenge'] as Map);
        final cm = (r['config'] as Map?)?['commission'];
        if (cm is num) _commission = cm.toInt();
        if (_room.text.isEmpty && '${_c!['room']}'.isNotEmpty) _room.text = '${_c!['room']}';
        _err = null;
      });
    } catch (e) {
      if (mounted && !quiet) setState(() => _err = Wallet.errorText(e));
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await f();
      if (r['challenge'] is Map && mounted) setState(() => _c = Map<String, dynamic>.from(r['challenge'] as Map));
    } catch (e) {
      _snack(Wallet.errorText(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _pick() async {
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1100, imageQuality: 55);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      final lower = f.name.toLowerCase();
      final mime = lower.endsWith('.png') ? 'image/png' : lower.endsWith('.webp') ? 'image/webp' : 'image/jpeg';
      final b64 = base64Encode(bytes);
      if (b64.length > 410000) {
        _snack(tr('Capture trop lourde : choisis une image plus petite.', 'Screenshot too large: pick a smaller image.'));
        return;
      }
      if (mounted) {
        setState(() {
          _proof = 'data:$mime;base64,$b64';
          _proofKb = (bytes.length / 1024).round();
        });
      }
    } catch (e) {
      _snack(tr('Impossible de lire l\'image.', 'Could not read the image.'));
    }
  }

  Future<void> _send(Map<String, dynamic> c) async {
    final stake = (c['stake'] as num?)?.toInt() ?? 0;
    if (stake > 0 && _proof == null) {
      _snack(tr('Ajoute la capture d\'écran du résultat final.', 'Add the screenshot of the final result.'));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Envoyer ce résultat ?', 'Send this result?')),
        content: Text(tr('Toi ${_me.text} - ${_opp.text} ton adversaire.\nTu ne pourras plus le modifier.',
            'You ${_me.text} - ${_opp.text} your opponent.\nYou will not be able to change it.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Non', 'No'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Envoyer', 'Send'))),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => Wallet.pesReport(
          id: widget.id,
          scoreMe: int.tryParse(_me.text.trim()) ?? 0,
          scoreOpp: int.tryParse(_opp.text.trim()) ?? 0,
          extra: _extra,
          pkMe: int.tryParse(_pkMe.text.trim()) ?? 0,
          pkOpp: int.tryParse(_pkOpp.text.trim()) ?? 0,
          team: _team.text.trim(),
          proof: _proof,
        ));
  }

  Future<void> _dispute() async {
    final t = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Signaler un problème', 'Report a problem')),
        content: TextField(controller: t, maxLength: 300, maxLines: 3, decoration: InputDecoration(hintText: tr('Déconnexion, triche, désaccord…', 'Disconnection, cheating, disagreement…'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Annuler', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Envoyer à Katika', 'Send to Katika'))),
        ],
      ),
    );
    final reason = t.text.trim();
    t.dispose();
    if (ok == true && reason.isNotEmpty) await _run(() => Wallet.pesDispute(widget.id, reason));
  }

  Widget _box(Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(16)),
        child: child,
      );

  Widget _num(TextEditingController c, String label) => SizedBox(
        width: 90,
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
          decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(color: Colors.white60, fontSize: 12)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      body: Container(
        decoration: _bg,
        width: double.infinity,
        height: double.infinity,
        child: SafeArea(
          child: Column(children: [
            Row(children: [
              IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back, color: Colors.white)),
              const Expanded(child: Text('⚽ Match PES 2016', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900))),
              IconButton(onPressed: _busy ? null : () => _load(), icon: const Icon(Icons.refresh, color: Colors.white)),
            ]),
            Expanded(
              child: c == null
                  ? Center(child: _err != null ? Padding(padding: const EdgeInsets.all(20), child: Text(_err!, style: const TextStyle(color: Color(0xFFFF8A80)))) : const CircularProgressIndicator(color: _gold))
                  : _body(c),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _body(Map<String, dynamic> c) {
    final st = '${c['status']}';
    final role = '${c['role']}';
    final stake = (c['stake'] as num?)?.toInt() ?? 0;
    final myRep = c['myReport'] is Map ? Map<String, dynamic>.from(c['myReport'] as Map) : null;
    final isHost = role == 'host';
    final oppName = isHost ? '${c['guestName']}' : '${c['hostName']}';
    final oppEf = isHost ? '${c['guestEf']}' : '${c['hostEf']}';
    final myEf = isHost ? '${c['hostEf']}' : '${c['guestEf']}';
    final canReport = (st == 'accepted' || st == 'reporting') && myRep == null && role != 'none';
    final commission = _commission;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 30), children: [
      _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(oppName.isEmpty ? tr('En attente d\'un adversaire…', 'Waiting for an opponent…') : '${tr('Toi', 'You')} vs $oppName',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900))),
          _chip(st),
        ]),
        const SizedBox(height: 6),
        Text('${kPesPlatforms['${c['platform']}'] ?? ''} · ${stake > 0 ? '${tr('Mise', 'Stake')} ${_fc(stake)} · ${tr('gain', 'prize')} ${_fc((stake * 2 * (100 - commission) / 100).floor())}*' : tr('Défi gratuit', 'Free challenge')}',
            style: const TextStyle(color: _gold, fontWeight: FontWeight.w800)),
        if (stake > 0) Text(tr('* après commission Katika (le taux exact est appliqué à la validation)', '* after Katika commission (exact rate applied at validation)'), style: const TextStyle(color: Colors.white38, fontSize: 10)),
        if ('${c['rules']}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${tr('Conditions', 'Conditions')} : ${c['rules']}', style: const TextStyle(color: Colors.white70, fontSize: 12))),
        if (role != 'none' && oppName.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('${tr('Ton ID', 'Your ID')} : $myEf   ·   ${tr('ID adversaire', 'Opponent ID')} : $oppEf', style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ),
        if ('${c['matchCode']}'.isNotEmpty)
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: '${c['matchCode']}'));
              _snack(tr('Code copié', 'Code copied'));
            },
            child: Padding(padding: const EdgeInsets.only(top: 6), child: Text('${tr('Match Katika', 'Katika match')} : ${c['matchCode']}  📋', style: const TextStyle(color: Colors.white54, fontSize: 12))),
          ),
      ])),
      if (st == 'open' && isHost)
        _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Ton défi est publié. Dès qu\'un joueur le relève, tu es prévenu. Il expire au bout de 24 h (mise rendue).', 'Your challenge is published. You will be notified when someone accepts. It expires after 24 h (stake refunded).'),
              style: const TextStyle(color: Colors.white70)),
          TextButton(
            onPressed: _busy ? null : () => _run(() async {
              await Wallet.pesCancel(widget.id);
              if (mounted) Navigator.of(context).maybePop();
              return <String, dynamic>{};
            }),
            child: Text(tr('Retirer mon défi', 'Withdraw my challenge')),
          ),
        ])),
      if (st == 'accepted' || st == 'reporting') ...[
        _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isHost ? tr('JOUEUR 1 : tu crées le salon', 'PLAYER 1: you create the room') : tr('JOUEUR 2 : tu rejoins le salon', 'PLAYER 2: you join the room'),
              style: const TextStyle(color: _gold, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          if (isHost) ...[
            Text(tr('1. Ouvre PES 2016.\n2. Va dans le mode En ligne et crée un salon (match entre amis).\n3. Invite ton adversaire (ID ci-dessus) et note le numéro du salon ci-dessous pour qu\'il le voie.',
                '1. Open PES 2016.\n2. Go to Online mode and create a room (friend match).\n3. Invite your opponent (ID above) and enter the room number below so they can see it.'),
                style: const TextStyle(color: Colors.white, height: 1.35)),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _room,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(hintText: tr('Numéro / nom du salon', 'Room number / name'), hintStyle: const TextStyle(color: Colors.white38)),
                ),
              ),
              TextButton(
                onPressed: _busy ? null : () => _run(() => Wallet.pesSetRoom(widget.id, _room.text.trim())),
                child: Text(tr('Envoyer', 'Send')),
              ),
            ]),
          ] else ...[
            Text(tr('1. Ouvre PES 2016.\n2. Va dans le mode En ligne et rejoins le salon de ton adversaire (invitation ou son ID ci-dessus).\n3. Le numéro du salon apparaît ici quand le joueur 1 l\'a créé.',
                '1. Open PES 2016.\n2. Go to Online mode and join your opponent\'s room (invitation or his ID above).\n3. The room number shows here once player 1 has created it.'),
                style: const TextStyle(color: Colors.white, height: 1.35)),
            if ('${c['room']}'.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text('${tr('Salon', 'Room')} : ${c['room']}', style: const TextStyle(color: _green, fontSize: 18, fontWeight: FontWeight.w900))),
          ],
          const SizedBox(height: 6),
          Text(tr('Les noms exacts des menus peuvent varier selon ta plateforme. Respecte les conditions du défi.', 'Exact menu names may vary by platform. Follow the challenge conditions.'),
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ])),
        if (canReport)
          _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Résultat du match', 'Match result'), style: const TextStyle(color: _gold, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_num(_me, tr('Toi', 'You')), const Text('-', style: TextStyle(color: Colors.white, fontSize: 24)), _num(_opp, oppName.isEmpty ? tr('Adversaire', 'Opponent') : oppName)]),
            Wrap(spacing: 8, children: [
              ChoiceChip(label: Text(tr('Temps réglementaire', 'Regular time')), selected: _extra == 'none', selectedColor: _gold, onSelected: (_) => setState(() => _extra = 'none')),
              ChoiceChip(label: Text(tr('Prolongations', 'Extra time')), selected: _extra == 'et', selectedColor: _gold, onSelected: (_) => setState(() => _extra = 'et')),
              ChoiceChip(label: Text(tr('Tirs au but', 'Penalties')), selected: _extra == 'pk', selectedColor: _gold, onSelected: (_) => setState(() => _extra = 'pk')),
            ]),
            if (_extra == 'pk')
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_num(_pkMe, tr('Tab toi', 'Pens you')), _num(_pkOpp, tr('Tab adv.', 'Pens opp.'))]),
            TextField(controller: _team, style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: tr('Équipe que tu as utilisée (facultatif)', 'Team you used (optional)'), labelStyle: const TextStyle(color: Colors.white60))),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.image_outlined),
              label: Text(_proof == null ? tr('Ajouter la capture du résultat', 'Add the result screenshot') : tr('Capture ajoutée (${_proofKb} Ko) · changer', 'Screenshot added (${_proofKb} KB) · change')),
            ),
            if (_proof != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(base64Decode(_proof!.split(',').last), height: 150, fit: BoxFit.cover)),
              ),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, height: 48, child: FilledButton(onPressed: _busy ? null : () => _send(c), child: Text(tr('Envoyer mon résultat', 'Send my result'), style: const TextStyle(fontWeight: FontWeight.w900)))),
          ])),
        if (myRep != null)
          _box(Text(tr('Ton résultat est envoyé (${myRep['a']} - ${myRep['b']}). En attente de ton adversaire.', 'Your result is sent (${myRep['a']} - ${myRep['b']}). Waiting for your opponent.'),
              style: const TextStyle(color: Colors.white70))),
      ],
      if (st == 'review')
        _box(Text(stake > 0 ? tr('Les deux résultats concordent. Katika vérifie les captures avant de verser le gain.', 'Both results match. Katika is checking the screenshots before paying out.') : '',
            style: const TextStyle(color: Colors.white70))),
      if (st == 'disputed')
        _box(Text('${tr('Litige', 'Dispute')} : ${c['disputeReason']}\n${tr('L\'administration va arbitrer. Tu seras prévenu.', 'The administration will arbitrate. You will be notified.')}', style: const TextStyle(color: Color(0xFFFFCDD2)))),
      if (st == 'done')
        _box(Text(
            '${c['won'] == true ? tr('🏆 Tu as gagné !', '🏆 You won!') : tr('Match terminé : ton adversaire a gagné.', 'Match finished: your opponent won.')}'
            '${'${c['note']}'.isEmpty ? '' : '\n${c['note']}'}',
            style: TextStyle(color: c['won'] == true ? _green : Colors.white70, fontWeight: FontWeight.w800))),
      if (st == 'refunded' || st == 'suspended' || st == 'cancelled')
        _box(Text('${_statusLabel(st)}${'${c['note']}'.isEmpty ? '' : ' · ${c['note']}'}', style: const TextStyle(color: Colors.white70))),
      if (['accepted', 'reporting', 'review'].contains(st) && role != 'none')
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy ? null : _dispute,
            icon: const Icon(Icons.flag_outlined, color: Color(0xFFFF8A80)),
            label: Text(tr('Signaler un problème / un adversaire', 'Report a problem / an opponent'), style: const TextStyle(color: Color(0xFFFF8A80))),
          ),
        ),
    ]);
  }
}

// ----------------------------------------------------------------------
// Administration : validation des résultats et arbitrage
// ----------------------------------------------------------------------

class PesAdminScreen extends StatefulWidget {
  const PesAdminScreen({super.key});

  @override
  State<PesAdminScreen> createState() => _PesAdminScreenState();
}

class _PesAdminScreenState extends State<PesAdminScreen> {
  Map<String, dynamic>? _d;
  String? _err;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Wallet.pesAdminList();
      if (mounted) {
        setState(() {
          _d = d;
          _err = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _err = Wallet.errorText(e));
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  List<Map<String, dynamic>> _rows(String k) => [for (final x in ((_d?['lists'] as Map?)?[k] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];

  Future<void> _proofs(Map<String, dynamic> c) async {
    try {
      final r = await Wallet.pesAdminProofs('${c['id']}');
      Widget img(String label, String data) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
              data.isEmpty ? const Text('Pas de capture.') : Image.memory(base64Decode(data.split(',').last), fit: BoxFit.contain),
            ]),
          );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Captures'),
          content: SingleChildScrollView(child: Column(children: [img('${c['hostName']} (joueur 1)', '${r['host']}'), img('${c['guestName']} (joueur 2)', '${r['guest']}')])),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer'))],
        ),
      );
    } catch (e) {
      _snack(Wallet.errorText(e));
    }
  }

  Future<void> _decide(Map<String, dynamic> c, String decision, String label) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${c['hostName']} vs ${c['guestName']} · ${(c['stake'] as num) > 0 ? _fc((c['stake'] as num).toInt()) : 'gratuit'}'),
          TextField(controller: note, maxLength: 300, decoration: const InputDecoration(labelText: 'Note (gardée dans le journal)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmer')),
        ],
      ),
    );
    final n = note.text.trim();
    note.dispose();
    if (ok != true || _busy) return;
    setState(() => _busy = true);
    try {
      final d = await Wallet.pesAdminResolve('${c['id']}', decision, n);
      if (mounted) setState(() => _d = d);
      _snack('Décision enregistrée.');
    } catch (e) {
      _snack(Wallet.errorText(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  String _rep(dynamic r) {
    if (r is! Map) return 'pas de résultat';
    final ex = r['extra'] == 'pk' ? ' (tab ${r['pkA']}-${r['pkB']})' : r['extra'] == 'et' ? ' (prol.)' : '';
    return '${r['a']}-${r['b']}$ex${'${r['team']}'.isEmpty ? '' : ' · ${r['team']}'}';
  }

  Widget _card(Map<String, dynamic> c, {bool actions = true}) {
    final stake = (c['stake'] as num?)?.toInt() ?? 0;
    final st = '${c['status']}';
    final canDecide = ['review', 'disputed', 'reporting', 'accepted', 'open'].contains(st);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: _statusColor(st))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${c['hostName']} vs ${'${c['guestName']}'.isEmpty ? '…' : c['guestName']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900))),
          _chip(st),
        ]),
        Text('${kPesPlatforms['${c['platform']}'] ?? ''} · ${stake > 0 ? _fc(stake) : 'gratuit'} · ID : ${c['hostEf']} / ${c['guestEf']}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
        Text('${c['hostName']} déclare : ${_rep(c['repH'])}', style: const TextStyle(color: Colors.white, fontSize: 12)),
        Text('${c['guestName']} déclare : ${_rep(c['repG'])}', style: const TextStyle(color: Colors.white, fontSize: 12)),
        if ('${c['disputeReason']}'.isNotEmpty) Text('Litige : ${c['disputeReason']}', style: const TextStyle(color: Color(0xFFFFCDD2), fontSize: 12)),
        if ('${c['proposedWinner']}'.isNotEmpty)
          Text('Gagnant proposé : ${'${c['proposedWinner']}' == '${c['hostUid']}' ? c['hostName'] : c['guestName']}', style: const TextStyle(color: _green, fontSize: 12, fontWeight: FontWeight.w800)),
        if (actions && canDecide)
          Wrap(spacing: 4, children: [
            TextButton(onPressed: () => _proofs(c), child: const Text('Voir les captures')),
            if ('${c['guestUid']}'.isNotEmpty) ...[
              TextButton(onPressed: _busy ? null : () => _decide(c, 'host', 'Valider : ${c['hostName']} gagne'), child: Text('Gagnant : ${c['hostName']}')),
              TextButton(onPressed: _busy ? null : () => _decide(c, 'guest', 'Valider : ${c['guestName']} gagne'), child: Text('Gagnant : ${c['guestName']}')),
              TextButton(onPressed: _busy ? null : () => _decide(c, 'refund', 'Rendre les mises'), child: const Text('Rembourser')),
            ],
            TextButton(onPressed: _busy ? null : () => _decide(c, 'cancel', 'Suspendre le défi (mises rendues)'), child: const Text('Suspendre', style: TextStyle(color: Color(0xFFFF8A80)))),
          ]),
      ]),
    );
  }

  Widget _section(String title, String k, {bool actions = true}) {
    final rows = _rows(k);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text('$title (${rows.length})', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
      ),
      for (final c in rows) _card(c, actions: actions),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      body: Container(
        decoration: _bg,
        width: double.infinity,
        height: double.infinity,
        child: SafeArea(
          child: Column(children: [
            Row(children: [
              IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back, color: Colors.white)),
              const Expanded(child: Text('⚽ PES : arbitrage', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800))),
              IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh, color: Colors.white)),
            ]),
            Expanded(
              child: d == null
                  ? Center(child: _err != null ? Padding(padding: const EdgeInsets.all(20), child: SelectableText(_err!, style: const TextStyle(color: Color(0xFFFF8A80)))) : const CircularProgressIndicator(color: _gold))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 30), children: [
                        Text(((d['config'] as Map?)?['paid'] == true) ? 'Défis avec mise : OUVERTS (variable PES_PAID = true)' : 'Défis avec mise : fermés (mode gratuit). Pour ouvrir : variable PES_PAID = true dans Cloudflare.',
                            style: const TextStyle(color: _gold, fontSize: 12, fontWeight: FontWeight.w700)),
                        _section('Résultats à valider', 'review'),
                        _section('Litiges', 'disputed'),
                        _section('Résultat en attente', 'reporting'),
                        _section('Matchs prêts', 'accepted'),
                        _section('Défis ouverts', 'open'),
                        _section('Derniers matchs terminés', 'done', actions: false),
                      ]),
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}
