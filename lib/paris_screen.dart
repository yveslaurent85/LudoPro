import 'package:flutter/material.dart' hide Text;

import 'accounts.dart';
import 'lang.dart';

// ======================================================================
// PARIS PAR DERRIÈRE : SPORTS (paris P2P, 7,5 % de commission) et COURSES (bientôt)
// ======================================================================

const Color _ink = Color(0xFF0B1B3A);
const Color _gold = Color(0xFFFFC21A);
const BoxDecoration _bg = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF14295C), Color(0xFF0B1B3A), Color(0xFF060F24)],
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

/// Page d'accueil de la rubrique : Sports et Courses.
class ParisParDerrierePage extends StatelessWidget {
  const ParisParDerrierePage({super.key});

  Widget _card(BuildContext c,
      {required IconData icon,
      required String title,
      required String sub,
      required Color color,
      VoidCallback? onTap,
      String? badge}) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.65 : 1,
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(colors: [color, color.withOpacity(0.7)]),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 5))],
          ),
          child: Row(children: [
            Icon(icon, color: Colors.white, size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ]),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(10)),
                child: Text(badge, style: const TextStyle(color: Color(0xFF1A1200), fontSize: 10, fontWeight: FontWeight.w900)),
              ),
          ]),
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
        decoration: _bg,
        child: SafeArea(
          child: Column(children: [
            Row(children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
              Expanded(
                child: Text(tr('PARIS PAR DERRIÈRE', 'SIDE BETS'),
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
              ),
            ]),
            Expanded(
              child: ListView(padding: const EdgeInsets.all(16), children: [
                _card(
                  context,
                  icon: Icons.sports_soccer,
                  title: tr('SPORTS', 'SPORTS'),
                  sub: tr('Défie un autre joueur sur un match · commission 7,5 %',
                      'Challenge another player on a match · 7.5% fee'),
                  color: const Color(0xFF1B8A3A),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SportsPage())),
                ),
                _card(
                  context,
                  icon: Icons.emoji_events,
                  title: tr('COURSES', 'RACES'),
                  sub: tr('Pari mutuel : Couplé, 2/4, Tiercé, Quinté, Super 6',
                      'Pari-mutuel: Couple, 2/4, Tierce, Quinte, Super 6'),
                  color: const Color(0xFF7B1FA2),
                  badge: tr('BIENTÔT', 'SOON'),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    tr('Ces paris utilisent ton portefeuille Katika. Joue avec modération.',
                        'These bets use your Katika wallet. Play responsibly.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Sports P2P
// ----------------------------------------------------------------------

class SportsPage extends StatefulWidget {
  const SportsPage({super.key});

  @override
  State<SportsPage> createState() => _SportsPageState();
}

class _SportsPageState extends State<SportsPage> with TickerProviderStateMixin {
  Map<String, dynamic>? _d;
  String? _err;
  bool _busy = false;
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  bool get _admin => _d != null && _d!['admin'] == true;

  Future<void> _load() async {
    try {
      final r = await Wallet.sportsList();
      if (!mounted) return;
      if (r['admin'] == true && _tabs.length != 4) {
        final old = _tabs;
        _tabs = TabController(length: 4, vsync: this);
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
      setState(() {
        _d = r;
        _err = null;
      });
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
        setState(() => _d = r);
        if (ok != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Wallet.errorText(e))));
    }
    if (mounted) setState(() => _busy = false);
  }

  List<Map<String, dynamic>> _events(String category) {
    final l = (_d?['events'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map));
    return [for (final e in l) if (e['category'] == category && e['status'] != 'cancelled') e];
  }

  String _teamName(String eventId, String side) {
    for (final e in (_d?['events'] as List? ?? const [])) {
      final m = e as Map;
      if (m['id'] == eventId) return '${side == 'a' ? m['teamA'] : m['teamB']}';
    }
    return '?';
  }

  String _eventTitle(String eventId) {
    for (final e in (_d?['events'] as List? ?? const [])) {
      final m = e as Map;
      if (m['id'] == eventId) return '${m['teamA']} vs ${m['teamB']}';
    }
    return '';
  }

  // ------------------------------------------------------------ créer un pari
  Future<void> _newBet(Map<String, dynamic> e) async {
    final ctrl = TextEditingController(text: '1000');
    String side = 'a';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B1B3A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final amount = int.tryParse(ctrl.text.trim()) ?? 0;
        final gain = amount > 0 ? (amount * 2 * 925 ~/ 1000) : 0;
        return Padding(
          padding: EdgeInsets.fromLTRB(18, 16, 18, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${e['teamA']} vs ${e['teamB']}',
                  style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(tr('Ton pari reste en attente jusqu\'à ce qu\'un joueur relève le défi sur l\'autre équipe, à mise égale.',
                  'Your bet waits until a player takes the other side with an equal stake.'),
                  style: const TextStyle(color: Colors.white60, fontSize: 12)),
              const SizedBox(height: 12),
              Text(tr('Je parie sur :', 'I bet on:'), style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: ChoiceChip(
                    label: Text('${e['teamA']}', overflow: TextOverflow.ellipsis),
                    selected: side == 'a',
                    selectedColor: _gold,
                    onSelected: (_) => setS(() => side = 'a'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: Text('${e['teamB']}', overflow: TextOverflow.ellipsis),
                    selected: side == 'b',
                    selectedColor: _gold,
                    onSelected: (_) => setS(() => side = 'b'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => setS(() {}),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                decoration: InputDecoration(
                  labelText: tr('Mise (FCFA)', 'Stake (FCFA)'),
                  labelStyle: const TextStyle(color: Colors.white60),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr('Gain si tu gagnes : ${_fcfa(gain)} (commission 7,5 % déduite)',
                    'Win: ${_fcfa(gain)} (7.5% fee deducted)'),
                style: const TextStyle(color: Color(0xFF7CFFB0), fontWeight: FontWeight.w800),
              ),
              Text(
                tr('Match nul ou annulé : mises remboursées, sans frais.', 'Draw or cancelled: stakes refunded, no fee.'),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
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
                  onPressed: amount < Wallet.minStake
                      ? null
                      : () {
                          Navigator.of(ctx).pop();
                          _do(() => Wallet.sportBetCreate(eventId: '${e['id']}', side: side, amount: amount),
                              ok: tr('Pari placé, en attente d\'un challenger.', 'Bet placed, waiting for a challenger.'));
                        },
                  child: Text(tr('Placer le pari', 'Place the bet'), style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ]),
          ),
        );
      }),
    );
    ctrl.dispose();
  }

  // ------------------------------------------------------------ carte d'un match
  Widget _eventCard(Map<String, dynamic> e) {
    final now = (_d?['now'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    final starts = (e['startsAt'] as num).toInt();
    final status = '${e['status']}';
    final closed = status != 'upcoming' || now >= starts;
    final open = [for (final b in (e['open'] as List? ?? const [])) Map<String, dynamic>.from(b as Map)];
    String chip;
    Color chipColor;
    if (status == 'finished') {
      chip = tr('Terminé', 'Finished');
      chipColor = Colors.white38;
    } else if (status == 'cancelled') {
      chip = tr('Annulé', 'Cancelled');
      chipColor = Colors.redAccent;
    } else if (closed) {
      chip = tr('Paris clos', 'Bets closed');
      chipColor = Colors.orangeAccent;
    } else {
      chip = tr('Paris ouverts', 'Bets open');
      chipColor = const Color(0xFF7CFFB0);
    }
    String? resultText;
    if (status == 'finished') {
      final r = '${e['result']}';
      resultText = r == 'draw'
          ? tr('Match nul · mises remboursées', 'Draw · stakes refunded')
          : '${tr('Vainqueur', 'Winner')} : ${r == 'a' ? e['teamA'] : e['teamB']}';
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
          Expanded(
            child: Text('${e['subcategory']}'.isEmpty ? (e['category'] == 'football' ? 'Football' : tr('Combats', 'Fights')) : '${e['subcategory']}',
                style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: chipColor.withOpacity(0.18), borderRadius: BorderRadius.circular(10)),
            child: Text(chip, style: TextStyle(color: chipColor, fontSize: 11, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Text('${e['teamA']}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('VS', style: TextStyle(color: _gold, fontWeight: FontWeight.w900)),
          ),
          Expanded(
            child: Text('${e['teamB']}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
          ),
        ]),
        const SizedBox(height: 4),
        Center(
          child: Text(
            '${tr('Paris jusqu\'à', 'Bets until')} ${_date(starts)}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
        if (resultText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Center(child: Text(resultText, style: const TextStyle(color: _gold, fontWeight: FontWeight.w800))),
          ),
        if (!closed) ...[
          const SizedBox(height: 10),
          if (open.isNotEmpty)
            Text(tr('Défis en attente de challenger', 'Challenges waiting for a taker'),
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 12)),
          for (final b in open)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      '${b['mine'] == true ? tr('Toi', 'You') : b['proposerName']} · ${b['side'] == 'a' ? e['teamA'] : e['teamB']} · ${_fcfa((b['amount'] as num).toInt())}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    Text(
                      b['mine'] == true
                          ? tr('Gain potentiel ${_fcfa((b['prize'] as num).toInt())}', 'Potential win ${_fcfa((b['prize'] as num).toInt())}')
                          : tr('Relève sur ${b['side'] == 'a' ? e['teamB'] : e['teamA']} · gain ${_fcfa((b['prize'] as num).toInt())}',
                              'Take ${b['side'] == 'a' ? e['teamB'] : e['teamA']} · win ${_fcfa((b['prize'] as num).toInt())}'),
                      style: const TextStyle(color: Color(0xFF7CFFB0), fontSize: 11),
                    ),
                  ]),
                ),
                if (b['mine'] == true)
                  TextButton(
                    onPressed: _busy ? null : () => _do(() => Wallet.sportBetCancel('${b['id']}')),
                    child: Text(tr('Annuler', 'Cancel')),
                  )
                else
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF22B14C)),
                    onPressed: _busy
                        ? null
                        : () => _do(() => Wallet.sportBetAccept('${b['id']}'),
                            ok: tr('Défi relevé ! La mise est bloquée jusqu\'au résultat.', 'Challenge accepted! Stake held until the result.')),
                    child: Text(tr('Relever', 'Accept'), style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
              ]),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE5262B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _busy ? null : () => _newBet(e),
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text(tr('Lancer un pari', 'Start a bet'), style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _eventsTab(String category) {
    final all = _events(category);
    final l = [for (final e in all) if (e['status'] != 'finished') e];
    final done = [for (final e in all) if (e['status'] == 'finished') e].reversed.take(5).toList();
    if (l.isEmpty && done.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            tr('Aucun match pour le moment. Reviens bientôt !', 'No matches right now. Come back soon!'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(14), children: [
        for (final e in l) _eventCard(e),
        if (done.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(tr('Derniers résultats', 'Latest results'),
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800)),
          ),
        for (final e in done) _eventCard(e),
      ]),
    );
  }

  // ------------------------------------------------------------ mes paris
  Widget _mineTab() {
    final l = [for (final b in (_d?['myBets'] as List? ?? const [])) Map<String, dynamic>.from(b as Map)];
    if (l.isEmpty) {
      return Center(
        child: Text(tr('Tu n\'as pas encore de pari.', 'You have no bets yet.'),
            style: const TextStyle(color: Colors.white70)),
      );
    }
    String statusText(Map<String, dynamic> b) {
      switch ('${b['status']}') {
        case 'open':
          return tr('En attente de challenger', 'Waiting for a challenger');
        case 'matched':
          return tr('Défi accepté · résultat à venir', 'Matched · result pending');
        case 'settled':
          return b['won'] == true
              ? tr('Gagné ! + ${_fcfa((b['prize'] as num).toInt())}', 'Won! + ${_fcfa((b['prize'] as num).toInt())}')
              : tr('Perdu', 'Lost');
        case 'cancelled':
          return tr('Annulé · remboursé', 'Cancelled · refunded');
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
                Text(_eventTitle('${b['eventId']}'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                Text(
                  '${tr('Sur', 'On')} ${_teamName('${b['eventId']}', '${b['mySide']}')} · ${_fcfa((b['amount'] as num).toInt())}'
                  '${'${b['opponentName']}'.isEmpty ? '' : ' · ${tr('contre', 'vs')} ${b['opponentName']}'}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ]),
            ),
            Text(statusText(b),
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: b['won'] == true ? const Color(0xFF7CFFB0) : Colors.white70,
                    fontWeight: FontWeight.w800,
                    fontSize: 12)),
          ]),
        ),
    ]);
  }

  // ------------------------------------------------------------ administration
  Future<void> _newEvent() async {
    String category = 'football';
    final sub = TextEditingController();
    final ta = TextEditingController();
    final tb = TextEditingController();
    DateTime when = DateTime.now().add(const Duration(hours: 3));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B1B3A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        InputDecoration dec(String l) => InputDecoration(
              labelText: l,
              labelStyle: const TextStyle(color: Colors.white60),
              filled: true,
              fillColor: Colors.white.withOpacity(0.1),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            );
        return Padding(
          padding: EdgeInsets.fromLTRB(18, 16, 18, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Nouveau match', 'New match'),
                  style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                ChoiceChip(
                  label: Text('Football'),
                  selected: category == 'football',
                  selectedColor: _gold,
                  onSelected: (_) => setS(() => category = 'football'),
                ),
                ChoiceChip(
                  label: Text(tr('Combats', 'Fights')),
                  selected: category == 'combats',
                  selectedColor: _gold,
                  onSelected: (_) => setS(() => category = 'combats'),
                ),
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: sub,
                style: const TextStyle(color: Colors.white),
                decoration: dec(tr('Compétition (ex. Ligue des champions, Boxe, MMA)', 'Competition (e.g. Champions League, Boxing)')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ta,
                style: const TextStyle(color: Colors.white),
                decoration: dec(category == 'football' ? tr('Équipe A', 'Team A') : tr('Combattant A', 'Fighter A')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: tb,
                style: const TextStyle(color: Colors.white),
                decoration: dec(category == 'football' ? tr('Équipe B', 'Team B') : tr('Combattant B', 'Fighter B')),
              ),
              const SizedBox(height: 10),
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
                      () => Wallet.adminSportEventSave(
                        category: category,
                        subcategory: sub.text,
                        teamA: ta.text,
                        teamB: tb.text,
                        startsAt: when.millisecondsSinceEpoch,
                      ),
                      ok: tr('Match créé.', 'Match created.'),
                    );
                  },
                  child: Text(tr('Créer le match', 'Create the match'), style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ]),
          ),
        );
      }),
    );
    sub.dispose();
    ta.dispose();
    tb.dispose();
  }

  Future<void> _result(Map<String, dynamic> e) async {
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${e['teamA']} vs ${e['teamB']}'),
        content: Text(tr('Quel est le résultat officiel ? Les gains sont versés tout de suite.',
            'What is the official result? Winnings are paid immediately.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'a'), child: Text('${e['teamA']}')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'draw'), child: Text(tr('Nul', 'Draw'))),
          TextButton(onPressed: () => Navigator.pop(ctx, 'b'), child: Text('${e['teamB']}')),
        ],
      ),
    );
    if (r == null) return;
    _do(() => Wallet.adminSportEventResult('${e['id']}', r), ok: tr('Résultat enregistré, paris réglés.', 'Result saved, bets settled.'));
  }

  Future<void> _cancelEvent(Map<String, dynamic> e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Annuler ce match ?', 'Cancel this match?')),
        content: Text(tr('Toutes les mises seront remboursées à 100 %.', 'All stakes will be refunded in full.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Non', 'No'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Oui, annuler', 'Yes, cancel'))),
        ],
      ),
    );
    if (ok != true) return;
    _do(() => Wallet.adminSportEventCancel('${e['id']}'), ok: tr('Match annulé, mises remboursées.', 'Match cancelled, stakes refunded.'));
  }

  Widget _adminTab() {
    final l = (_d?['events'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return ListView(padding: const EdgeInsets.all(14), children: [
      SizedBox(
        height: 50,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE5262B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: _busy ? null : _newEvent,
          icon: const Icon(Icons.add),
          label: Text(tr('Nouveau match', 'New match'), style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
      ),
      const SizedBox(height: 12),
      for (final e in l)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${e['teamA']} vs ${e['teamB']}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            Text(
              '${e['subcategory']} · ${_date((e['startsAt'] as num).toInt())} · ${e['status']}'
              '${e['status'] == 'upcoming' ? ' · ${(e['open'] as List).length} ${tr('en attente', 'waiting')}, ${e['matched']} ${tr('acceptés', 'matched')}' : ''}',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            if (e['status'] == 'upcoming')
              Row(children: [
                TextButton(
                  onPressed: _busy ? null : () => _result(e),
                  child: Text(tr('Saisir le résultat', 'Enter result'), style: const TextStyle(color: Color(0xFF7CFFB0))),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _cancelEvent(e),
                  child: Text(tr('Annuler le match', 'Cancel match'), style: const TextStyle(color: Color(0xFFFF8A80))),
                ),
              ]),
          ]),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final admin = _admin;
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: _bg,
        child: SafeArea(
          child: Column(children: [
            Row(children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
              Expanded(
                child: Text(tr('SPORTS · Paris entre joueurs', 'SPORTS · Player vs player bets'),
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
                isScrollable: true,
                indicatorColor: _gold,
                labelColor: _gold,
                unselectedLabelColor: Colors.white60,
                tabs: [
                  const Tab(text: 'Football'),
                  Tab(text: tr('Combats', 'Fights')),
                  Tab(text: tr('Mes paris', 'My bets')),
                  if (admin) const Tab(text: 'Admin'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _eventsTab('football'),
                    _eventsTab('combats'),
                    _mineTab(),
                    if (admin) _adminTab(),
                  ],
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
