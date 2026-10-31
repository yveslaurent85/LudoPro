import 'package:flutter/material.dart';

import 'accounts.dart';

/// Hôtesses : leur code promo sert uniquement à compter les joueurs qu'elles
/// inscrivent (aucune commission).
///  - [admin] = true et sans [code] : l'administrateur gère les hôtesses et
///    voit le nombre d'inscrits de chacune pour la période choisie.
///  - sans [admin] : une hôtesse consulte ses propres inscrits.
///  - avec [code] : détail d'une hôtesse (ouvert par l'administrateur).
class HostessScreen extends StatefulWidget {
  const HostessScreen({super.key, this.admin = false, this.code});

  final bool admin;
  final String? code;

  @override
  State<HostessScreen> createState() => _HostessScreenState();
}

class _HostessScreenState extends State<HostessScreen> {
  static const Color _gold = Color(0xFFFFC21A);

  String preset = '7'; // today, 7, 30, all, custom
  DateTimeRange? custom;
  bool loading = true;
  bool busy = false;
  String? error;

  final TextEditingController codeCtrl = TextEditingController();
  List<Map<String, dynamic>> hostesses = [];
  Map<String, dynamic> stats = {};
  int periodCount = 0;

  bool get _listMode => widget.admin && widget.code == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    codeCtrl.dispose();
    super.dispose();
  }

  static int _i(dynamic v) => v is num ? v.toInt() : 0;

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _date(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';
  static String _time(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

  /// Début (inclus) et fin (exclue) de la période, en heure locale.
  List<DateTime?> _range() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    switch (preset) {
      case 'today':
        return [today, tomorrow];
      case '7':
        return [today.subtract(const Duration(days: 6)), tomorrow];
      case '30':
        return [today.subtract(const Duration(days: 29)), tomorrow];
      case 'custom':
        final c = custom;
        if (c == null) return [null, null];
        return [
          DateTime(c.start.year, c.start.month, c.start.day),
          DateTime(c.end.year, c.end.month, c.end.day + 1),
        ];
      default:
        return [null, null];
    }
  }

  String get _periodLabel {
    final r = _range();
    if (r[0] == null) return 'Depuis le début';
    final end = r[1]!.subtract(const Duration(days: 1));
    return r[0]!.isAtSameMomentAs(DateTime(end.year, end.month, end.day))
        ? _date(r[0]!)
        : 'Du ${_date(r[0]!)} au ${_date(end)}';
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    final r = _range();
    final from = r[0]?.toUtc().toIso8601String();
    final to = r[1]?.toUtc().toIso8601String();
    try {
      if (_listMode) {
        final res = await Wallet.adminHostesses(from: from, to: to);
        if (!mounted) return;
        setState(() {
          hostesses = [
            for (final h in (res['hostesses'] as List? ?? const []))
              Map<String, dynamic>.from(h as Map),
          ];
          periodCount = _i(res['count']);
          loading = false;
        });
      } else {
        final res =
            await Wallet.hostessStats(from: from, to: to, code: widget.code);
        if (!mounted) return;
        setState(() {
          stats = res;
          loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = Wallet.errorText(e);
        loading = false;
      });
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _setHostess(String code, bool on) async {
    final c = code.trim();
    if (c.isEmpty || busy) return;
    setState(() => busy = true);
    try {
      await Wallet.adminSetHostess(c, on);
      if (on) codeCtrl.clear();
      _snack(on ? 'Hôtesse ajoutée.' : 'Hôtesse retirée.');
      await _load();
    } catch (e) {
      _snack(Wallet.errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: now.add(const Duration(days: 1)),
      initialDateRange: custom,
    );
    if (r == null) return;
    setState(() {
      custom = r;
      preset = 'custom';
    });
    _load();
  }

  Widget _card(List<Widget> children) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withOpacity(0.12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _periodBar() {
    Widget chip(String id, String label, {VoidCallback? onTap}) {
      return ChoiceChip(
        label: Text(label),
        selected: preset == id,
        onSelected: (_) {
          if (onTap != null) {
            onTap();
            return;
          }
          setState(() => preset = id);
          _load();
        },
      );
    }

    return _card([
      const Text(
        'Période',
        style: TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          chip('today', "Aujourd'hui"),
          chip('7', '7 jours'),
          chip('30', '30 jours'),
          chip('all', 'Tout'),
          chip('custom', 'Choisir…', onTap: _pickCustom),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        _periodLabel,
        style: const TextStyle(color: _gold, fontWeight: FontWeight.w700),
      ),
    ]);
  }

  Widget _bigNumber(String label, int n) {
    return _card([
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      const SizedBox(height: 2),
      Text(
        '$n',
        style: const TextStyle(
          color: _gold,
          fontSize: 40,
          fontWeight: FontWeight.w900,
        ),
      ),
    ]);
  }

  // ---- Administrateur : liste des hôtesses -----------------------------
  Widget _adminList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _card([
          const Text(
            'Ajouter une hôtesse',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Elle doit avoir un compte. Son code promo (son pseudo) sert '
            'seulement à compter les joueurs qu\'elle inscrit : aucune '
            'commission.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: codeCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Code promo de l\'hôtesse',
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
                onPressed: busy ? null : () => _setHostess(codeCtrl.text, true),
                child: const Text('Ajouter'),
              ),
            ],
          ),
        ]),
        _periodBar(),
        _bigNumber('Joueurs inscrits par les hôtesses', periodCount),
        if (hostesses.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'Aucune hôtesse pour le moment.',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        for (final h in hostesses)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Colors.white.withOpacity(0.12),
              border: Border.all(color: Colors.white24),
            ),
            child: ListTile(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => HostessScreen(code: '${h['code']}'),
                ),
              ),
              title: Text(
                '${h['code']}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: Text(
                'Total depuis le début : ${_i(h['total'])}',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_i(h['count'])}',
                    style: const TextStyle(
                      color: _gold,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Retirer',
                    onPressed:
                        busy ? null : () => _setHostess('${h['code']}', false),
                    icon: const Icon(Icons.delete_outline,
                        color: Color(0xFFFF8A80)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ---- Une hôtesse : ses inscrits ---------------------------------------
  Widget _detail() {
    final members = [
      for (final m in (stats['members'] as List? ?? const []))
        Map<String, dynamic>.from(m as Map),
    ];
    // Regroupement par jour (heure locale)
    final byDay = <String, int>{};
    for (final m in members) {
      final at = DateTime.tryParse('${m['at']}')?.toLocal();
      if (at == null) continue;
      final k = _date(at);
      byDay[k] = (byDay[k] ?? 0) + 1;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _card([
          const Text('Ton code promo',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
          Text(
            '${stats['code'] ?? ''}',
            style: const TextStyle(
              color: _gold,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Chaque joueur qui crée son compte avec ce code est compté ici.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ]),
        _periodBar(),
        _bigNumber('Inscrits sur la période', _i(stats['count'])),
        _card([
          const Text('Depuis le début',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          Text(
            '${_i(stats['total'])} inscrits',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ]),
        if (byDay.isNotEmpty)
          _card([
            const Text(
              'Par jour',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            for (final e in byDay.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(e.key,
                          style: const TextStyle(color: Colors.white70)),
                    ),
                    Text(
                      '${e.value}',
                      style: const TextStyle(
                        color: _gold,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
          ]),
        if (members.isNotEmpty)
          _card([
            const Text(
              'Joueurs inscrits',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            for (final m in members)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${m['pseudo']}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    Text(
                      () {
                        final at = DateTime.tryParse('${m['at']}')?.toLocal();
                        return at == null ? '' : '${_date(at)} ${_time(at)}';
                      }(),
                      style:
                          const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
          ]),
      ],
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
                        _listMode ? '💁 Hôtesses' : '💁 Mes inscriptions',
                        style: const TextStyle(
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
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  children: [
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          error!,
                          style: const TextStyle(
                            color: Color(0xFFFF8A80),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (loading && error == null && hostesses.isEmpty && stats.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(30),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_listMode)
                      _adminList()
                    else if (stats.isNotEmpty)
                      _detail(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
