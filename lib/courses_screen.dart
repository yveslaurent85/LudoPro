import 'package:flutter/material.dart' hide Text;

import 'accounts.dart';
import 'lang.dart';

// ======================================================================
// PARIS PAR DERRIÈRE : COURSES (pari mutuel, ticket de 100 FCFA × coefficient)
// L'ordre d'arrivée n'importe pas : Couplé (2 parmi les 3 premiers), 2/4 (2 parmi les 4 premiers),
// Tiercé (les 3 premiers), Quinté (les 5 premiers), Super 6 (les 6 premiers).
// ======================================================================

const Color _gold = Color(0xFFFFC21A);
const BoxDecoration _bg = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF3A1456), Color(0xFF220B35), Color(0xFF12061D)],
  ),
);

const List<String> _mois = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
String _two(int n) => n < 10 ? '0$n' : '$n';
String _date(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.day} ${_mois[d.month - 1]} · ${_two(d.hour)}h${_two(d.minute)}';
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

class _Formula {
  const _Formula(this.key, this.picks, this.fr, this.en, this.descFr, this.descEn);
  final String key;
  final int picks;
  final String fr;
  final String en;
  final String descFr;
  final String descEn;
}

const List<_Formula> _formulas = [
  _Formula('couple', 2, 'Couplé', 'Couple', '2 numéros parmi les 3 premiers', '2 numbers among the first 3'),
  _Formula('deux4', 2, '2/4', '2/4', '2 numéros parmi les 4 premiers', '2 numbers among the first 4'),
  _Formula('tierce', 3, 'Tiercé', 'Tierce', 'Les 3 premiers, dans le désordre', 'The first 3, any order'),
  _Formula('quinte', 5, 'Quinté', 'Quinte', 'Les 5 premiers, dans le désordre', 'The first 5, any order'),
  _Formula('super6', 6, 'Super 6', 'Super 6', 'Les 6 premiers, dans le désordre', 'The first 6, any order'),
];

String _fname(String key) {
  for (final f in _formulas) {
    if (f.key == key) return tr(f.fr, f.en);
  }
  return key;
}

class CoursesPage extends StatefulWidget {
  const CoursesPage({super.key});

  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<CoursesPage> with TickerProviderStateMixin {
  Map<String, dynamic>? _d;
  String? _err;
  bool _busy = false;
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  bool get _admin => _d != null && _d!['admin'] == true;

  void _apply(Map<String, dynamic> r) {
    if (r['admin'] == true && _tabs.length != 3) {
      final old = _tabs;
      _tabs = TabController(length: 3, vsync: this);
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    _d = r;
    _err = null;
  }

  Future<void> _load() async {
    try {
      final r = await Wallet.racesList();
      if (mounted) setState(() => _apply(r));
    } catch (e) {
      if (mounted) setState(() => _err = Wallet.errorText(e));
    }
  }

  Future<void> _do(Future<Map<String, dynamic>> Function() f, {String? ok}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await f();
      if (mounted) {
        setState(() => _apply(r));
        if (ok != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Wallet.errorText(e))));
    }
    if (mounted) setState(() => _busy = false);
  }

  List<Map<String, dynamic>> get _races =>
      [for (final r in (_d?['races'] as List? ?? const [])) Map<String, dynamic>.from(r as Map)];

  String _raceName(String id) {
    for (final r in _races) {
      if (r['id'] == id) return '${r['name']}';
    }
    return '';
  }

  // ------------------------------------------------------------ parier
  Future<void> _bet(Map<String, dynamic> race) async {
    final runners = (race['runners'] as num).toInt();
    final nets = Map<String, dynamic>.from(race['nets'] as Map);
    final pools = Map<String, dynamic>.from(race['pools'] as Map);
    var f = _formulas[2];
    final picks = <int>{};
    var coef = 1;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF220B35),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final ready = picks.length == f.picks;
        final stake = 100 * coef;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${race['name']}', style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final x in _formulas)
                  ChoiceChip(
                    label: Text(tr(x.fr, x.en)),
                    selected: f.key == x.key,
                    selectedColor: _gold,
                    onSelected: (_) => setS(() {
                      f = x;
                      picks.clear();
                    }),
                  ),
              ]),
              const SizedBox(height: 6),
              Text(tr(f.descFr, f.descEn), style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Text(
                tr('Cagnotte à partager : ${_fcfa((nets[f.key] as num).toInt())}', 'Pool to share: ${_fcfa((nets[f.key] as num).toInt())}'),
                style: const TextStyle(color: Color(0xFF7CFFB0), fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Text(
                tr('Choisis ${f.picks} numéros (${picks.length}/${f.picks}) · l\'ordre n\'importe pas',
                    'Pick ${f.picks} numbers (${picks.length}/${f.picks}) · order does not matter'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (var n = 1; n <= runners; n++)
                  GestureDetector(
                    onTap: () => setS(() {
                      if (picks.contains(n)) {
                        picks.remove(n);
                      } else if (picks.length < f.picks) {
                        picks.add(n);
                      }
                    }),
                    child: Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: picks.contains(n) ? _gold : Colors.white.withOpacity(0.12),
                        border: Border.all(color: picks.contains(n) ? _gold : Colors.white24),
                      ),
                      child: Text('$n',
                          style: TextStyle(
                              color: picks.contains(n) ? const Color(0xFF1A1200) : Colors.white,
                              fontWeight: FontWeight.w900)),
                    ),
                  ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Text(tr('Coefficient', 'Multiplier'), style: const TextStyle(color: Colors.white70)),
                const Spacer(),
                IconButton(
                  onPressed: coef > 1 ? () => setS(() => coef--) : null,
                  icon: const Icon(Icons.remove_circle, color: Colors.white),
                ),
                Text('× $coef', style: const TextStyle(color: _gold, fontSize: 20, fontWeight: FontWeight.w900)),
                IconButton(
                  onPressed: coef < 1000 ? () => setS(() => coef++) : null,
                  icon: const Icon(Icons.add_circle, color: Colors.white),
                ),
              ]),
              Wrap(spacing: 6, children: [
                for (final c in const [1, 5, 10, 25, 50])
                  ActionChip(label: Text('× $c'), onPressed: () => setS(() => coef = c)),
              ]),
              const SizedBox(height: 6),
              Text(
                tr('Ticket de base 100 FCFA · ta mise : ${_fcfa(stake)} · en jeu actuellement ${_fcfa((pools[f.key] as num).toInt())}',
                    'Base ticket 100 FCFA · your stake: ${_fcfa(stake)} · currently in play ${_fcfa((pools[f.key] as num).toInt())}'),
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              Text(
                tr('25 % de commission. Gain = cagnotte nette ÷ total des coefficients gagnants × ton coefficient. Sans gagnant, la cagnotte est reportée.',
                    '25% fee. Win = net pool ÷ total winning multipliers × your multiplier. No winner: the pool carries over.'),
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE5262B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: !ready
                      ? null
                      : () {
                          final p = picks.toList()..sort();
                          Navigator.of(ctx).pop();
                          _do(
                            () => Wallet.raceBetCreate(raceId: '${race['id']}', formula: f.key, picks: p, coef: coef),
                            ok: tr('Pari enregistré.', 'Bet placed.'),
                          );
                        },
                  child: Text(tr('Parier ${_fcfa(stake)}', 'Bet ${_fcfa(stake)}'), style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }

  // ------------------------------------------------------------ cartes de course
  Widget _raceCard(Map<String, dynamic> r) {
    final now = (_d?['now'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    final starts = (r['startsAt'] as num).toInt();
    final status = '${r['status']}';
    final closed = status != 'open' || now >= starts;
    final nets = Map<String, dynamic>.from(r['nets'] as Map);
    final carries = Map<String, dynamic>.from(r['carries'] as Map);
    final arrival = [for (final n in (r['arrival'] as List? ?? const [])) (n as num).toInt()];
    String chip;
    Color cc;
    if (status == 'finished') {
      chip = tr('Terminée', 'Finished');
      cc = Colors.white38;
    } else if (status == 'cancelled') {
      chip = tr('Annulée', 'Cancelled');
      cc = Colors.redAccent;
    } else if (closed) {
      chip = tr('Paris clos', 'Bets closed');
      cc = Colors.orangeAccent;
    } else {
      chip = tr('Paris ouverts', 'Bets open');
      cc = const Color(0xFF7CFFB0);
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.emoji_events, color: _gold),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${r['name']}', style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: cc.withOpacity(0.18), borderRadius: BorderRadius.circular(10)),
            child: Text(chip, style: TextStyle(color: cc, fontSize: 11, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          '${r['runners']} ${tr('partants', 'runners')} · ${tr('paris jusqu\'à', 'bets until')} ${_date(starts)}',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        if (arrival.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(tr('Arrivée officielle', 'Official result'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          Wrap(spacing: 6, children: [
            for (var i = 0; i < arrival.length; i++)
              CircleAvatar(
                radius: 15,
                backgroundColor: i < 3 ? _gold : Colors.white24,
                child: Text('${arrival[i]}',
                    style: TextStyle(color: i < 3 ? const Color(0xFF1A1200) : Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
              ),
          ]),
        ],
        if (status != 'cancelled') ...[
          const SizedBox(height: 10),
          for (final x in _formulas)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(children: [
                SizedBox(width: 70, child: Text(tr(x.fr, x.en), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))),
                Expanded(
                  child: Text(
                    '${tr('cagnotte', 'pool')} ${_fcfa((nets[x.key] as num).toInt())}'
                    '${(carries[x.key] as num) > 0 ? ' (${tr('dont report', 'incl. carry')} ${_fcfa((carries[x.key] as num).toInt())})' : ''}',
                    style: const TextStyle(color: Color(0xFF7CFFB0), fontSize: 12),
                  ),
                ),
              ]),
            ),
        ],
        if (!closed) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE5262B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _busy ? null : () => _bet(r),
              icon: const Icon(Icons.confirmation_number, color: Colors.white),
              label: Text(tr('Parier', 'Bet'), style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _racesTab() {
    final l = _races.where((r) => r['status'] != 'cancelled').toList();
    if (l.isEmpty) {
      return Center(
        child: Text(tr('Aucune course pour le moment.', 'No races right now.'), style: const TextStyle(color: Colors.white70)),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(14), children: [for (final r in l) _raceCard(r)]),
    );
  }

  Widget _mineTab() {
    final l = [for (final b in (_d?['myBets'] as List? ?? const [])) Map<String, dynamic>.from(b as Map)];
    if (l.isEmpty) {
      return Center(child: Text(tr('Tu n\'as pas encore de pari.', 'You have no bets yet.'), style: const TextStyle(color: Colors.white70)));
    }
    String st(Map<String, dynamic> b) {
      switch ('${b['status']}') {
        case 'active':
          return tr('En attente du résultat', 'Awaiting result');
        case 'won':
          return tr('Gagné ! + ${_fcfa((b['payout'] as num).toInt())}', 'Won! + ${_fcfa((b['payout'] as num).toInt())}');
        case 'lost':
          return tr('Perdu', 'Lost');
        case 'refunded':
          return tr('Remboursé', 'Refunded');
        default:
          return '${b['status']}';
      }
    }

    return ListView(padding: const EdgeInsets.all(14), children: [
      for (final b in l)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_raceName('${b['raceId']}')} · ${_fname('${b['formula']}')}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                Text(
                  '${(b['picks'] as List).join(' - ')} · × ${b['coef']} · ${_fcfa((b['stake'] as num).toInt())}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ]),
            ),
            Text(st(b),
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: b['status'] == 'won' ? const Color(0xFF7CFFB0) : Colors.white70,
                    fontWeight: FontWeight.w800,
                    fontSize: 12)),
          ]),
        ),
    ]);
  }

  // ------------------------------------------------------------ administration
  Future<void> _newRace() async {
    final name = TextEditingController();
    var runners = 12;
    var when = DateTime.now().add(const Duration(hours: 3));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF220B35),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return Padding(
          padding: EdgeInsets.fromLTRB(18, 16, 18, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Nouvelle course', 'New race'), style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              TextField(
                controller: name,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: tr('Nom (ex. Réunion 1 · Course 3)', 'Name (e.g. Meeting 1 · Race 3)'),
                  labelStyle: const TextStyle(color: Colors.white60),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Text(tr('Partants', 'Runners'), style: const TextStyle(color: Colors.white70)),
                const Spacer(),
                IconButton(onPressed: runners > 6 ? () => setS(() => runners--) : null, icon: const Icon(Icons.remove_circle, color: Colors.white)),
                Text('$runners', style: const TextStyle(color: _gold, fontSize: 20, fontWeight: FontWeight.w900)),
                IconButton(onPressed: runners < 20 ? () => setS(() => runners++) : null, icon: const Icon(Icons.add_circle, color: Colors.white)),
              ]),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: when,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (d == null || !ctx.mounted) return;
                  final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(when));
                  if (t == null) return;
                  setS(() => when = DateTime(d.year, d.month, d.day, t.hour, t.minute));
                },
                icon: const Icon(Icons.schedule),
                label: Text('${tr('Heure limite des paris', 'Betting deadline')} : ${_date(when.millisecondsSinceEpoch)}'),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE5262B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _do(
                      () => Wallet.adminRaceSave(name: name.text, runners: runners, startsAt: when.millisecondsSinceEpoch),
                      ok: tr('Course créée.', 'Race created.'),
                    );
                  },
                  child: Text(tr('Créer la course', 'Create the race'), style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ]),
          ),
        );
      }),
    );
    name.dispose();
  }

  Future<void> _arrival(Map<String, dynamic> r) async {
    final runners = (r['runners'] as num).toInt();
    final need = runners < 6 ? runners : 6;
    final order = <int>[];
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF220B35),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${r['name']}', style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(
                tr('Touche les numéros dans l\'ordre d\'arrivée : 1er, 2e, 3e… (${order.length}/$need)',
                    'Tap the numbers in finishing order: 1st, 2nd, 3rd… (${order.length}/$need)'),
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (var n = 1; n <= runners; n++)
                  GestureDetector(
                    onTap: () => setS(() {
                      if (order.contains(n)) {
                        order.remove(n);
                      } else if (order.length < need) {
                        order.add(n);
                      }
                    }),
                    child: Stack(clipBehavior: Clip.none, children: [
                      Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: order.contains(n) ? _gold : Colors.white.withOpacity(0.12),
                        ),
                        child: Text('$n',
                            style: TextStyle(color: order.contains(n) ? const Color(0xFF1A1200) : Colors.white, fontWeight: FontWeight.w900)),
                      ),
                      if (order.contains(n))
                        Positioned(
                          right: -4,
                          top: -4,
                          child: CircleAvatar(
                            radius: 9,
                            backgroundColor: const Color(0xFFE5262B),
                            child: Text('${order.indexOf(n) + 1}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
                          ),
                        ),
                    ]),
                  ),
              ]),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF22B14C),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: order.length == need ? () => Navigator.of(ctx).pop(true) : null,
                  child: Text(tr('Valider l\'arrivée et payer les gains', 'Confirm result and pay winners'),
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ]),
          ),
        );
      }),
    );
    if (go != true) return;
    _do(() => Wallet.adminRaceResult('${r['id']}', order), ok: tr('Arrivée enregistrée, gains versés.', 'Result saved, winnings paid.'));
  }

  Future<void> _cancelRace(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Annuler cette course ?', 'Cancel this race?')),
        content: Text(tr('Toutes les mises seront remboursées à 100 %.', 'All stakes will be refunded in full.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Non', 'No'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Oui, annuler', 'Yes, cancel'))),
        ],
      ),
    );
    if (ok != true) return;
    _do(() => Wallet.adminRaceCancel('${r['id']}'), ok: tr('Course annulée, mises remboursées.', 'Race cancelled, stakes refunded.'));
  }

  Widget _adminTab() {
    return ListView(padding: const EdgeInsets.all(14), children: [
      SizedBox(
        height: 50,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE5262B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: _busy ? null : _newRace,
          icon: const Icon(Icons.add),
          label: Text(tr('Nouvelle course', 'New race'), style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
      ),
      const SizedBox(height: 12),
      for (final r in _races)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${r['name']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            Text('${r['runners']} ${tr('partants', 'runners')} · ${_date((r['startsAt'] as num).toInt())} · ${r['status']}',
                style: const TextStyle(color: Colors.white60, fontSize: 12)),
            Text(
              [for (final x in _formulas) '${tr(x.fr, x.en)} ${_fcfa(((r['pools'] as Map)[x.key] as num).toInt())}'].join(' · '),
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            if (r['status'] == 'open' || r['status'] == 'settling')
              Row(children: [
                TextButton(
                  onPressed: _busy ? null : () => _arrival(r),
                  child: Text(tr('Saisir l\'arrivée', 'Enter result'), style: const TextStyle(color: Color(0xFF7CFFB0))),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _cancelRace(r),
                  child: Text(tr('Annuler', 'Cancel'), style: const TextStyle(color: Color(0xFFFF8A80))),
                ),
              ]),
          ]),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: _bg,
        child: SafeArea(
          child: Column(children: [
            Row(children: [
              IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back, color: Colors.white)),
              Expanded(
                child: Text(tr('COURSES · Pari mutuel', 'RACES · Pari-mutuel'),
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
              ),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh, color: Colors.white70)),
            ]),
            if (_d == null)
              Expanded(
                child: Center(
                  child: _err != null
                      ? Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(_err!, style: const TextStyle(color: Colors.white)),
                          TextButton(onPressed: _load, child: Text(tr('Réessayer', 'Retry'))),
                        ])
                      : const CircularProgressIndicator(color: _gold),
                ),
              )
            else ...[
              TabBar(
                controller: _tabs,
                indicatorColor: _gold,
                labelColor: _gold,
                unselectedLabelColor: Colors.white60,
                tabs: [
                  Tab(text: tr('Courses', 'Races')),
                  Tab(text: tr('Mes paris', 'My bets')),
                  if (_admin) const Tab(text: 'Admin'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [_racesTab(), _mineTab(), if (_admin) _adminTab()],
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
