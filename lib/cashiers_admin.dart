import 'package:flutter/material.dart' hide Text;

import 'accounts.dart';
import 'lang.dart';

/// Administrateur : créer / retirer les comptes caissières.
/// La caissière s'inscrit d'abord comme un joueur ; l'admin saisit son code
/// promo (son pseudo) ici pour activer son espace caissière.
class CashiersAdminScreen extends StatefulWidget {
  const CashiersAdminScreen({super.key});

  @override
  State<CashiersAdminScreen> createState() => _CashiersAdminScreenState();
}

class _CashiersAdminScreenState extends State<CashiersAdminScreen> {
  final TextEditingController _code = TextEditingController();
  List<Map<String, dynamic>> _list = [];
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Wallet.adminCashiers();
      if (!mounted) return;
      setState(() {
        _list = [for (final c in (r['cashiers'] as List? ?? const [])) Map<String, dynamic>.from(c as Map)];
        _err = null;
      });
    } catch (e) {
      if (mounted) setState(() => _err = Wallet.errorText(e));
    }
  }

  Future<void> _set(String code, bool on) async {
    if (_busy || code.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await Wallet.adminSetCashier(code.trim(), on);
      if (mounted) {
        _code.clear();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(on ? tr('Caissière activée.', 'Cashier enabled.') : tr('Caissière retirée.', 'Cashier removed.')),
        ));
      }
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Wallet.errorText(e))));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Caissières')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            tr("La caissière crée d'abord son compte joueur. Saisis ici son code promo (pseudo) pour activer son espace : paris courses, tickets, recharges et retraits.",
                'The cashier signs up as a player first. Enter her promo code (username) to enable her cashier area.'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            decoration: InputDecoration(
              labelText: tr('Code promo de la caissière', "Cashier's promo code"),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _busy ? null : () => _set(_code.text, true),
              child: Text(tr('Activer la caissière', 'Enable cashier')),
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CashierLogScreen()),
            ),
            icon: const Icon(Icons.history),
            label: Text(tr('Journal des validations', 'Validation log')),
          ),
          const SizedBox(height: 12),
          if (_err != null) Text(_err!, style: const TextStyle(color: Colors.red)),
          for (final c in _list)
            Card(
              child: ListTile(
                title: Text('${c['name']}'),
                subtitle: Text('Code : ${c['code']} · Solde : ${c['balance']} FCFA'),
                trailing: IconButton(
                  icon: const Icon(Icons.person_remove),
                  tooltip: tr('Retirer', 'Remove'),
                  onPressed: _busy ? null : () => _set('${c['code']}', false),
                ),
              ),
            ),
          if (_list.isEmpty && _err == null) Text(tr('Aucune caissière.', 'No cashier yet.')),
        ],
      ),
    );
  }
}


/// Journal : qui a validé quoi (recharges et retraits), le plus récent d'abord.
class CashierLogScreen extends StatefulWidget {
  const CashierLogScreen({super.key});

  @override
  State<CashierLogScreen> createState() => _CashierLogScreenState();
}

class _CashierLogScreenState extends State<CashierLogScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Wallet.adminCashierLog();
      if (!mounted) return;
      setState(() {
        _items = [for (final e in (r['items'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)];
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _err = Wallet.errorText(e);
        _loading = false;
      });
    }
  }

  String _date(dynamic v) {
    final d = v is String ? DateTime.tryParse(v)?.toLocal() : null;
    if (d == null) return '';
    String t(int n) => n < 10 ? '0$n' : '$n';
    return '${t(d.day)}/${t(d.month)} ${t(d.hour)}:${t(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Journal des validations', 'Validation log'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _err != null
              ? Center(child: Text(_err!))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (_items.isEmpty) Text(tr('Aucune validation.', 'No entries.')),
                    for (final i in _items)
                      Card(
                        child: ListTile(
                          leading: Icon(i['kind'] == 'deposit' ? Icons.south_west : Icons.north_east),
                          title: Text(
                            '${i['by']} (${i['role'] == 'admin' ? 'admin' : 'caissière'}) · ${i['kind'] == 'deposit' ? 'recharge' : 'retrait'}',
                          ),
                          subtitle: Text('${i['player']} · ${i['amount']} FCFA · ${i['action']}\n${_date(i['at'])}'),
                          isThreeLine: true,
                        ),
                      ),
                  ],
                ),
    );
  }
}
