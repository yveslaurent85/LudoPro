import 'package:flutter/material.dart';

import 'accounts.dart';
import 'deux_des.dart';
import 'online.dart';

/// Tableau de bord administrateur : toutes les parties (Ludo et Deux dés,
/// en ligne et en présentiel), les commissions, les jackpots.
/// Données fournies par la fonction « adminStats » du Worker.
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  static const Color _gold = Color(0xFFFFC21A);

  bool loading = true;
  String? error;
  List<Map<String, dynamic>> rows = [];
  int pool = 0;
  int? users;
  int limit = 150;
  Map<String, dynamic> fetched = {};

  // Commissions de Katika (compte retirable vers le solde de l'admin)
  int houseAvailable = 0;
  int houseEarned = 0;
  int houseWithdrawn = 0;
  int houseMin = 2500;
  bool houseCan = false;
  bool houseBusy = false;

  // Comptes partenaires
  List<Map<String, dynamic>> partners = [];
  int partnerPercent = 60;
  final TextEditingController partnerCtrl = TextEditingController();
  bool partnerBusy = false;

  // Vue partenaire (compte non administrateur ayant le statut de partenaire)
  bool partnerView = false;
  Map<String, dynamic> pStats = {};
  bool pBusy = false;

  // Filtres
  String kind = 'all'; // all | ludo | deuxdes
  String mode = 'all'; // all | online | local
  int days = 0; // 0 = tout, 1 = aujourd'hui, 7, 30

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    partnerCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final res = await Wallet.adminStats(limit: limit);
      final list = (res['rows'] as List?) ?? const [];
      if (!mounted) return;
      setState(() {
        rows = [for (final r in list) Map<String, dynamic>.from(r as Map)];
        pool = _i(res['pool']);
        users = res['users'] is num ? (res['users'] as num).toInt() : null;
        fetched = res['fetched'] is Map
            ? Map<String, dynamic>.from(res['fetched'] as Map)
            : {};
        final h = res['house'] is Map
            ? Map<String, dynamic>.from(res['house'] as Map)
            : <String, dynamic>{};
        houseAvailable = _i(h['available']);
        houseEarned = _i(h['earned']);
        houseWithdrawn = _i(h['withdrawn']);
        houseMin = _i(h['min']) > 0 ? _i(h['min']) : 2500;
        houseCan = h['canWithdraw'] == true || houseAvailable >= houseMin;
        partnerView = false;
        loading = false;
      });
      _loadPartners();
    } catch (e) {
      if (!mounted) return;
      // Pas administrateur : peut-être un compte partenaire.
      try {
        final ps = await Wallet.partnerStats();
        if (!mounted) return;
        setState(() {
          partnerView = true;
          pStats = ps;
          error = null;
          loading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          error = Wallet.errorText(e);
          loading = false;
        });
      }
    }
  }

  Future<void> _loadPartners() async {
    try {
      final res = await Wallet.adminPartners();
      if (!mounted) return;
      setState(() {
        partnerPercent = _i(res['percent']) > 0 ? _i(res['percent']) : 60;
        partners = [
          for (final p in (res['partners'] as List? ?? const []))
            Map<String, dynamic>.from(p as Map),
        ];
      });
    } catch (_) {}
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  /// Administrateur : ajoute ou retire un partenaire grâce à son code promo.
  Future<void> _setPartner(String code, bool on) async {
    final c = code.trim();
    if (c.isEmpty || partnerBusy) return;
    setState(() => partnerBusy = true);
    try {
      await Wallet.adminSetPartner(c, on);
      if (on) partnerCtrl.clear();
      _snack(on ? 'Partenaire ajouté.' : 'Partenaire retiré.');
      await _loadPartners();
    } catch (e) {
      _snack(Wallet.errorText(e));
    } finally {
      if (mounted) setState(() => partnerBusy = false);
    }
  }

  /// Partenaire : transfère ses gains vers son solde principal.
  Future<void> _partnerWithdraw() async {
    if (pBusy) return;
    setState(() => pBusy = true);
    try {
      final r = await Wallet.partnerWithdraw();
      _snack('${_money(_i(r['amount']))} ajoutés à ton solde !');
      final ps = await Wallet.partnerStats();
      if (mounted) setState(() => pStats = ps);
    } catch (e) {
      _snack(Wallet.errorText(e));
    } finally {
      if (mounted) setState(() => pBusy = false);
    }
  }

  /// Transfère les commissions de Katika vers le solde de l'administrateur.
  Future<void> _withdrawHouse() async {
    if (houseBusy) return;
    setState(() => houseBusy = true);
    try {
      final res = await Wallet.adminHouseWithdraw();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_money(_i(res['amount']))} ajoutés à ton solde !'),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Wallet.errorText(e))),
      );
    } finally {
      if (mounted) setState(() => houseBusy = false);
    }
  }

  // --- Outils ----------------------------------------------------------

  int _i(dynamic v) => v is num ? v.toInt() : 0;

  String _money(int v) {
    final s = v.abs().toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return '${v < 0 ? '-' : ''}$b ${Wallet.currency}';
  }

  DateTime? _date(Map<String, dynamic> r) {
    final s = r['createdAt'];
    return s is String ? DateTime.tryParse(s)?.toLocal() : null;
  }

  String _dateText(Map<String, dynamic> r) {
    final d = _date(r);
    if (d == null) return 'date inconnue';
    String two(int n) => n < 10 ? '0$n' : '$n';
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  bool _keep(Map<String, dynamic> r) {
    if (kind != 'all' && r['kind'] != kind) return false;
    if (mode != 'all' && r['mode'] != mode) return false;
    if (days > 0) {
      final d = _date(r);
      if (d == null) return false;
      final now = DateTime.now();
      final since = days == 1
          ? DateTime(now.year, now.month, now.day)
          : now.subtract(Duration(days: days));
      if (d.isBefore(since)) return false;
    }
    return true;
  }

  String _kindLabel(String k) =>
      k == 'ludo' ? 'Ludo' : (k == 'deuxdes' ? 'Deux dés' : 'Autre');

  String _modeLabel(String m) => m == 'online' ? 'En ligne' : 'Présentiel';

  // --- Éléments d'interface ----------------------------------------------

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }

  Widget _filterRow(String title, List<Widget> chips) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Wrap(spacing: 8, runSpacing: 2, children: chips),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, {Color color = Colors.white}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withOpacity(0.12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Commissions de Katika : montant disponible et bouton « Retirer »
  /// (actif à partir de houseMin).
  Widget _houseCard() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withOpacity(0.12),
        border: Border.all(color: _gold, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '💰 Commissions de Katika',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Disponibles à retirer',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _money(houseAvailable),
              style: const TextStyle(
                color: _gold,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Total gagné ${_money(houseEarned)} · déjà retiré '
            '${_money(houseWithdrawn)}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22B14C),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.white24,
                disabledForegroundColor: Colors.white54,
              ),
              onPressed: houseCan && !houseBusy ? _withdrawHouse : null,
              icon: const Icon(Icons.account_balance_wallet),
              label: Text(
                houseBusy ? '...' : 'Retirer vers mon compte',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          if (!houseCan)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                "Le bouton s'active à partir de ${_money(houseMin)}.",
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          const SizedBox(height: 6),
          const Text(
            'Part nette de Katika : commission moins la part des parrains et '
            'des partenaires, sur les parties terminées depuis '
            "l'activation de ce compte.",
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  /// Comptes partenaires : ajout par code promo, gains de chacun.
  Widget _partnersCard() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withOpacity(0.12),
        border: Border.all(color: Colors.white38),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🤝 Partenaires',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Un partenaire touche $partnerPercent % de la commission de '
            'Katika (après la part du parrain) sur les parties de ses '
            'filleuls.',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: partnerCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Code promo du partenaire',
                    hintStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22B14C),
                  foregroundColor: Colors.white,
                ),
                onPressed:
                    partnerBusy ? null : () => _setPartner(partnerCtrl.text, true),
                child: const Text('Ajouter'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (partners.isEmpty)
            const Text(
              'Aucun partenaire pour le moment.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          for (final p in partners)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withOpacity(0.1),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${p['code']}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Gagné ${_money(_i(p['earned']))} · à retirer '
                          '${_money(_i(p['available']))}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: partnerBusy
                        ? null
                        : () => _setPartner('${p['code']}', false),
                    child: const Text(
                      'Retirer',
                      style: TextStyle(color: Color(0xFFFF8A80)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Vue d'un compte partenaire : ses gains, ses filleuls, son historique.
  Widget _partnerBody() {
    final available = _i(pStats['available']);
    final can = pStats['canWithdraw'] == true;
    final min = _i(pStats['min']) > 0 ? _i(pStats['min']) : 100;
    final recent = (pStats['recent'] as List?) ?? const [];
    String when(dynamic s) {
      final d = s is String ? DateTime.tryParse(s)?.toLocal() : null;
      if (d == null) return '';
      String two(int n) => n < 10 ? '0$n' : '$n';
      return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white.withOpacity(0.12),
              border: Border.all(color: _gold, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🤝 Compte partenaire',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Gains disponibles',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _money(available),
                    style: const TextStyle(
                      color: _gold,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF22B14C),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.white24,
                      disabledForegroundColor: Colors.white54,
                    ),
                    onPressed: can && !pBusy ? _partnerWithdraw : null,
                    icon: const Icon(Icons.account_balance_wallet),
                    label: Text(
                      pBusy ? '...' : 'Retirer vers mon compte',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                if (!can)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      "Le bouton s'active à partir de ${_money(min)}.",
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          _title('Résumé'),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.3,
            children: [
              _stat('Total gagné', _money(_i(pStats['earned'])), color: _gold),
              _stat('Déjà retiré', _money(_i(pStats['withdrawn']))),
              _stat('Mes filleuls', '${_i(pStats['referrals'])}'),
              _stat('Parties comptées', '${_i(pStats['games'])}'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Tu touches ${_i(pStats['percent'])} % de la commission de Katika '
            '(après la part du parrain) sur les parties de tes filleuls. '
            'Ton code : ${pStats['code']}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          _title('Derniers gains'),
          if (recent.isEmpty)
            const Text(
              'Aucun gain pour le moment.',
              style: TextStyle(color: Colors.white70),
            ),
          for (final e in recent)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withOpacity(0.1),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${when((e as Map)['createdAt'])} · '
                      '${e['mode'] == 'local' ? 'Présentiel' : 'En ligne'}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  Text(
                    '+${_money(_i(e['amount']))}',
                    style: const TextStyle(
                      color: _gold,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(
          t,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      );

  Color _stateColor(String s) {
    switch (s) {
      case 'done':
        return const Color(0xFF22B14C);
      case 'playing':
        return const Color(0xFFFFA000);
      case 'refund':
        return const Color(0xFF1E6BFF);
      default:
        return Colors.white54;
    }
  }

  String _stateLabel(String s) {
    switch (s) {
      case 'done':
        return 'Terminée';
      case 'playing':
        return 'En cours';
      case 'refund':
        return 'Remboursée';
      default:
        return 'En attente';
    }
  }

  /// Revoir une partie en ligne (lecture seule) : plateau de Ludo ou
  /// scores de Deux dés. Les parties en présentiel n'ont pas de plateau
  /// enregistré.
  void _review(Map<String, dynamic> r) {
    final id = '${r['id']}';
    if (r['mode'] != 'online') {
      _snack('Les parties en présentiel ne peuvent pas être revues.');
      return;
    }
    if (r['state'] == 'waiting') {
      _snack("Cette partie n'a pas encore commencé.");
      return;
    }
    final Widget page = r['kind'] == 'deuxdes'
        ? DeuxDesSpectator(roomId: id)
        : OnlineGameRoom(gameId: id, spectate: true, adminView: true);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Widget _gameTile(Map<String, dynamic> r) {
    final state = '${r['state']}';
    final stake = _i(r['stake']);
    final names = ((r['names'] as List?) ?? const []).map((e) => '$e').toList();
    final commission = _i(r['commission']) + _i(r['betCommission']);
    final isDice = r['kind'] == 'deuxdes';

    return GestureDetector(
      onTap: () => _review(r),
      child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withOpacity(0.1),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isDice ? Icons.casino : Icons.grid_view,
                color: _gold,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_kindLabel('${r['kind']}')} · ${_modeLabel('${r['mode']}')}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: _stateColor(state).withOpacity(0.25),
                  border: Border.all(color: _stateColor(state)),
                ),
                child: Text(
                  _stateLabel(state),
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            names.isEmpty ? 'Joueurs inconnus' : names.join(' • '),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Text(
            _dateText(r),
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  stake > 0
                      ? 'Mise ${_money(stake)} · cagnotte ${_money(_i(r['pot']))}'
                      : 'Partie gratuite',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              if (commission > 0)
                Text(
                  '+${_money(commission)}',
                  style: const TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
        ],
      ),
      ),
    );
  }

  Widget _body() {
    if (loading && rows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(
                error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 15),
              ),
              const SizedBox(height: 14),
              ElevatedButton(onPressed: _load, child: const Text('Réessayer')),
            ],
          ),
        ),
      );
    }

    if (partnerView) return _partnerBody();

    final shown = rows.where(_keep).toList();

    int gameCommission = 0, betCommission = 0, potPlayed = 0;
    int referrals = 0, partnerPaid = 0;
    int done = 0, playing = 0, waiting = 0, refunds = 0;
    final groups = <String, List<int>>{}; // clé -> [parties, commission]

    for (final r in shown) {
      final c = _i(r['commission']);
      final b = _i(r['betCommission']);
      gameCommission += c;
      betCommission += b;
      referrals += _i(r['referralPaid']);
      partnerPaid += _i(r['partnerPaid']);
      switch ('${r['state']}') {
        case 'done':
          done++;
          potPlayed += _i(r['pot']);
          break;
        case 'playing':
          playing++;
          break;
        case 'refund':
          refunds++;
          break;
        default:
          waiting++;
      }
      final key = '${_kindLabel('${r['kind']}')} · ${_modeLabel('${r['mode']}')}';
      final g = groups.putIfAbsent(key, () => [0, 0]);
      g[0] += 1;
      g[1] += c + b;
    }
    final total = gameCommission + betCommission;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
        children: [
          _houseCard(),
          _partnersCard(),
          _title('Filtres'),
          _filterRow('Jeu', [
            _chip('Tous', kind == 'all', () => setState(() => kind = 'all')),
            _chip('Ludo', kind == 'ludo', () => setState(() => kind = 'ludo')),
            _chip('Deux dés', kind == 'deuxdes',
                () => setState(() => kind = 'deuxdes')),
          ]),
          _filterRow('Mode', [
            _chip('Tous', mode == 'all', () => setState(() => mode = 'all')),
            _chip('En ligne', mode == 'online',
                () => setState(() => mode = 'online')),
            _chip('Présentiel', mode == 'local',
                () => setState(() => mode = 'local')),
          ]),
          _filterRow('Période', [
            _chip('Tout', days == 0, () => setState(() => days = 0)),
            _chip("Aujourd'hui", days == 1, () => setState(() => days = 1)),
            _chip('7 jours', days == 7, () => setState(() => days = 7)),
            _chip('30 jours', days == 30, () => setState(() => days = 30)),
          ]),
          _title('Résumé'),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.3,
            children: [
              _stat('Commissions totales', _money(total), color: _gold),
              _stat('Commissions des parties', _money(gameCommission)),
              _stat('Commissions des paris', _money(betCommission)),
              _stat('Cagnottes jouées', _money(potPlayed)),
              _stat('Versé aux parrains', _money(referrals)),
              _stat('Versé aux partenaires', _money(partnerPaid)),
              _stat('Parties affichées', '${shown.length}'),
              _stat('Joueurs inscrits', users == null ? '?' : '$users'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Terminées : $done · En cours : $playing · En attente : $waiting · '
            'Remboursées : $refunds',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          _title('Commissions par catégorie'),
          if (groups.isEmpty)
            const Text(
              'Aucune partie pour ces filtres.',
              style: TextStyle(color: Colors.white70),
            ),
          for (final e in groups.entries)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withOpacity(0.1),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${e.key} (${e.value[0]} parties)',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  Text(
                    _money(e.value[1]),
                    style: const TextStyle(
                      color: _gold,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          _title('Toutes les parties'),
          const Text(
            'Touche une partie en ligne pour la revoir.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 6),
          for (final r in shown) _gameTile(r),
          if (shown.isEmpty)
            const Text(
              'Aucune partie pour ces filtres.',
              style: TextStyle(color: Colors.white70),
            ),
          if (limit < 500 &&
              (_i(fetched['ludo']) >= limit ||
                  _i(fetched['deuxdes']) >= limit ||
                  _i(fetched['local']) >= limit))
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
                onPressed: () {
                  limit = (limit + 150).clamp(150, 500).toInt();
                  _load();
                },
                child: const Text('Charger des parties plus anciennes'),
              ),
            ),
        ],
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
                    const Expanded(
                      child: Text(
                        partnerView ? '👑 Espace partenaire' : '👑 Tableau de bord',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: loading ? null : _load,
                      icon: const Icon(Icons.refresh, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }
}
