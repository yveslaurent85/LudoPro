import 'package:flutter/material.dart';

import 'accounts.dart';
import 'admin_dashboard.dart';
import 'admin_manual.dart';
import 'cashiers_admin.dart';
import 'hostess_screen.dart';
import 'paris_screen.dart';
import 'player_stats.dart';
import 'tournaments_screen.dart';
import 'zone_screens.dart' show AdminZonesScreen;

/// Entrée de l'administration : si le compte est administrateur, on ouvre le
/// nouvel accueil par modules ; sinon (partenaire, hôtesse…) l'ancien écran,
/// qui sait déjà afficher la bonne vue.
class AdminGate extends StatefulWidget {
  const AdminGate({super.key});

  @override
  State<AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<AdminGate> {
  Map<String, dynamic>? _data;
  bool _fallback = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Wallet.adminStats(limit: 60);
      if (mounted) setState(() => _data = r);
    } catch (_) {
      if (mounted) setState(() => _fallback = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_fallback) return const AdminDashboard();
    final d = _data;
    if (d == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFF3F6FF),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return AdminHome(data: d, onRefresh: _load);
  }
}

/// Nouvel accueil administrateur : indicateurs réels + modules.
/// Rien n'est inventé : seuls les chiffres déjà fournis par le serveur sont affichés.
class AdminHome extends StatefulWidget {
  const AdminHome({super.key, required this.data, required this.onRefresh});

  final Map<String, dynamic> data;
  final Future<void> Function() onRefresh;

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  bool _dark = false;

  Color get _bg => _dark ? const Color(0xFF0B1230) : const Color(0xFFF3F6FF);
  Color get _card => _dark ? const Color(0xFF141C40) : Colors.white;
  Color get _ink => _dark ? const Color(0xFFF4F6FF) : const Color(0xFF12183A);
  Color get _muted => _dark ? const Color(0xFFA7B0D6) : const Color(0xFF56608A);
  Color get _line => _dark ? const Color(0xFF26305F) : const Color(0xFFD5DEF5);
  static const Color _navy = Color(0xFF0B1F5C);
  static const Color _blue = Color(0xFF1F5BFF);
  static const Color _green = Color(0xFF17883F);
  static const Color _orange = Color(0xFFE07B00);
  static const Color _red = Color(0xFFD32F2F);

  int _i(dynamic v) => v is num ? v.toInt() : 0;

  String _money(int v) {
    final s = v.abs().toString();
    final b = StringBuffer(v < 0 ? '-' : '');
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return '$b FCFA';
  }

  void _open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  Widget _kpi(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 19),
          ),
          const Spacer(),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _ink, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(label, maxLines: 2, style: TextStyle(color: _muted, fontSize: 11.5)),
        ],
      ),
    );
  }

  Widget _module(IconData icon, String title, String sub, Color color, VoidCallback? f) {
    final off = f == null;
    return Opacity(
      opacity: off ? 0.55 : 1,
      child: Material(
        color: _card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: f,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(13)),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: 15)),
                      Text(sub, style: TextStyle(color: _muted, fontSize: 12)),
                    ],
                  ),
                ),
                Icon(off ? Icons.lock_clock : Icons.chevron_right, color: _muted, size: off ? 18 : 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 20, 2, 10),
        child: Text(t, style: TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w900)),
      );

  Widget _gap(Widget w) => Padding(padding: const EdgeInsets.only(bottom: 10), child: w);

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final rows = [
      for (final r in ((d['rows'] as List?) ?? const [])) Map<String, dynamic>.from(r as Map),
    ];
    int playing = 0, waiting = 0, done = 0, commission = 0;
    for (final r in rows) {
      commission += _i(r['commission']) + _i(r['betCommission']);
      switch ('${r['state']}') {
        case 'done':
          done++;
          break;
        case 'playing':
          playing++;
          break;
        case 'refund':
          break;
        default:
          waiting++;
      }
    }
    final house = d['house'] is Map ? Map<String, dynamic>.from(d['house'] as Map) : <String, dynamic>{};
    final users = d['users'] is num ? (d['users'] as num).toInt() : null;

    return Scaffold(
      backgroundColor: _bg,
      body: RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(8, MediaQuery.of(context).padding.top + 8, 12, 18),
              decoration: const BoxDecoration(
                color: _navy,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Retour',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      const Expanded(
                        child: Text('KATIKA · Administration',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                      ),
                      IconButton(
                        tooltip: _dark ? 'Mode clair' : 'Mode sombre',
                        onPressed: () => setState(() => _dark = !_dark),
                        icon: Icon(_dark ? Icons.light_mode : Icons.dark_mode, color: Colors.white),
                      ),
                      IconButton(
                        tooltip: 'Actualiser',
                        onPressed: widget.onRefresh,
                        icon: const Icon(Icons.refresh, color: Colors.white),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 4, 0),
                    child: Text('Solde de la maison disponible',
                        style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
                    child: Text(_money(_i(house['available'])),
                        style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _section('Vue d\'ensemble'),
                  GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.45,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _kpi('Joueurs inscrits', users == null ? '—' : '$users', _blue, Icons.people_alt_outlined),
                      _kpi('Commissions (${rows.length} dernières parties)', _money(commission), _green, Icons.paid_outlined),
                      _kpi('Parties en cours', '$playing', _orange, Icons.sports_esports_outlined),
                      _kpi('Parties en attente', '$waiting', _orange, Icons.hourglass_empty),
                      _kpi('Parties terminées (récentes)', '$done', _green, Icons.check_circle_outline),
                      _kpi('Gains de la maison cumulés', _money(_i(house['earned'])), _blue, Icons.account_balance_outlined),
                    ],
                  ),
                  _section('Jeux et finances'),
                  _gap(_module(Icons.receipt_long, 'Parties et commissions',
                      'Toutes les parties, filtres, remboursements, caisse de la maison', _blue,
                      () => _open(const AdminDashboard()))),
                  _gap(_module(Icons.swap_vert, 'Recharges et retraits', 'Demandes à valider (Orange Money…)', _green,
                      () => _open(const AdminManualScreen()))),
                  _section('Joueurs'),
                  _gap(_module(Icons.people_alt_outlined, 'Joueurs', 'Liste, profils, soldes, historique', _blue,
                      () => _open(const AdminPlayersScreen()))),
                  _section('Partenaires et équipes'),
                  _gap(_module(Icons.map_outlined, 'Zones et partenaires', 'Villes, partenaires de zone, commissions', _orange,
                      () => _open(const AdminZonesScreen()))),
                  _gap(_module(Icons.support_agent, 'Hôtesses', 'Inscriptions apportées', _orange,
                      () => _open(const HostessScreen(admin: true)))),
                  _gap(_module(Icons.point_of_sale, 'Caissières', 'Comptes et journal de caisse', _orange,
                      () => _open(const CashiersAdminScreen()))),
                  _section('Compétitions et paris'),
                  _gap(_module(Icons.emoji_events_outlined, 'Tournois', 'Katika Tournament · Mondly', _blue,
                      () => _open(const TournamentsScreen()))),
                  _gap(_module(Icons.sports_soccer, 'Paris par derrière', 'Sports, courses, résultats', _blue,
                      () => _open(const ParisParDerrierePage()))),
                  _section('Bientôt'),
                  _gap(_module(Icons.campaign_outlined, 'Notifications aux joueurs', 'Non disponible pour le moment', _muted, null)),
                  _gap(_module(Icons.bar_chart, 'Rapports et exports', 'Non disponible pour le moment', _muted, null)),
                  _gap(_module(Icons.admin_panel_settings_outlined, 'Comptes et droits des administrateurs',
                      'Non disponible pour le moment', _muted, null)),
                  _gap(_module(Icons.settings_outlined, 'Paramètres généraux', 'Non disponible pour le moment', _muted, null)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
