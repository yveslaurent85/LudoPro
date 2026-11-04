import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import 'accounts.dart';
import 'lang.dart';

/// Administrateur : recharges et retraits par code marchand Orange Money.
/// Recharge : compare l'identifiant avec ton SMS / historique Orange Money,
/// puis « Confirmer » (le solde est crédité) ou « Refuser ».
/// Retrait : envoie l'argent au numéro indiqué, puis « Payé ».
class AdminManualScreen extends StatefulWidget {
  const AdminManualScreen({super.key});

  @override
  State<AdminManualScreen> createState() => _AdminManualScreenState();
}

class _AdminManualScreenState extends State<AdminManualScreen> {
  static const Color _gold = Color(0xFFFFC21A);

  List<Map<String, dynamic>> deposits = [];
  List<Map<String, dynamic>> withdrawals = [];
  List<Map<String, dynamic>> recent = [];
  bool loading = true;
  String? error;
  String? busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _list(dynamic v) => ((v as List?) ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final r = await Wallet.adminManualList();
      if (!mounted) return;
      setState(() {
        deposits = _list(r['deposits']);
        withdrawals = _list(r['withdrawals']);
        recent = _list(r['recent']);
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = Wallet.errorText(e);
        });
      }
    }
  }

  String _fmt(dynamic v) {
    final n = v is num ? v.toInt() : 0;
    final s = n.toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return b.toString();
  }

  String _date(dynamic v) {
    final d = v is String ? DateTime.tryParse(v)?.toLocal() : null;
    if (d == null) return '';
    String two(int n) => n < 10 ? '0$n' : '$n';
    return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _decide(Map<String, dynamic> r, bool approve) async {
    final kind = '${r['kind']}';
    final isDep = kind == 'deposit';
    final title = approve
        ? (isDep ? tr('Confirmer la recharge ?', 'Confirm the top-up?')
            : tr('Marquer comme payé ?', 'Mark as paid?'))
        : tr('Refuser cette demande ?', 'Reject this request?');
    final body = approve
        ? (isDep
            ? tr('${_fmt(r['amount'])} FCFA seront crédités à ${r['name']}. '
                'Vérifie que tu as bien reçu la transaction ${r['txRef']}.',
                '${_fmt(r['amount'])} FCFA will be credited to ${r['name']}. '
                'Check that you really received transaction ${r['txRef']}.')
            : tr('Confirme que tu as envoyé ${_fmt(r['amount'])} FCFA au ${r['phone']}.',
                'Confirm you sent ${_fmt(r['amount'])} FCFA to ${r['phone']}.'))
        : (isDep
            ? tr('Le solde ne sera pas crédité.', 'The balance will not be credited.')
            : tr('Le joueur sera remboursé de ${_fmt(r['amount'])} FCFA.',
                'The player will be refunded ${_fmt(r['amount'])} FCFA.'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('Annuler', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr('Oui', 'Yes')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => busyId = '${r['id']}');
    try {
      await Wallet.adminManualDecide(
        kind: kind,
        id: '${r['id']}',
        approve: approve,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Wallet.errorText(e))),
        );
      }
      await _load();
    } finally {
      if (mounted) setState(() => busyId = null);
    }
  }

  Widget _request(Map<String, dynamic> r) {
    final isDep = r['kind'] == 'deposit';
    final busy = busyId == '${r['id']}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withOpacity(0.12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${r['name']}'.isEmpty ? tr('Joueur', 'Player') : '${r['name']}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${_fmt(r['amount'])} FCFA',
                style: const TextStyle(
                  color: _gold,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '📱 ${r['phone']}   ·   ${_date(r['createdAt'])}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (isDep)
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr('Transaction : ${r['txRef']}', 'Transaction: ${r['txRef']}'),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: '${r['txRef']}'));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(tr('Copié', 'Copied'))),
                    );
                  },
                  icon: const Icon(Icons.copy, color: Colors.white70, size: 18),
                ),
              ],
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22B14C),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: busy ? null : () => _decide(r, true),
                  child: Text(isDep
                      ? tr('Confirmer', 'Confirm')
                      : tr('Payé', 'Paid')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF8A80),
                    side: const BorderSide(color: Color(0xFFFF8A80)),
                  ),
                  onPressed: busy ? null : () => _decide(r, false),
                  child: Text(tr('Refuser', 'Reject')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _resetAll() async {
    for (int step = 0; step < 2; step++) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(step == 0
              ? tr('Tout remettre à zéro ?', 'Reset everything to zero?')
              : tr('Dernière confirmation', 'Last confirmation')),
          content: Text(step == 0
              ? tr('Le solde de TOUS les joueurs passera à 0 FCFA. '
                  'Traite d\'abord les retraits en attente.',
                  'EVERY player balance will become 0 FCFA. '
                  'Handle pending withdrawals first.')
              : tr('Action irréversible. Continuer ?',
                  'This cannot be undone. Continue?')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(tr('Annuler', 'Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(tr('Oui', 'Yes')),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      final n = await Wallet.adminResetBalances();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('$n soldes remis à zéro.', '$n balances reset to zero.'))),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Wallet.errorText(e))),
        );
      }
    }
  }

  Widget _title(String s) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Text(
          s,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      );

  Widget _recentRow(Map<String, dynamic> r) {
    final isDep = r['kind'] == 'deposit';
    final st = '${r['status']}';
    final good = st == 'credited' || st == 'paid';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${isDep ? '⬇️' : '⬆️'} ${r['name']} · ${_fmt(r['amount'])} FCFA',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          Text(
            '${good ? '✅' : '❌'} ${_date(r['closedAt'])}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
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
                    Expanded(
                      child: Text(
                        tr('Recharges et retraits', 'Top-ups and withdrawals'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
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
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                        children: [
                          if (error != null)
                            Text(error!,
                                style: const TextStyle(
                                    color: Color(0xFFFF8A80),
                                    fontWeight: FontWeight.w700)),
                          _title(tr('⬇️ Recharges à confirmer (${deposits.length})',
                              '⬇️ Top-ups to confirm (${deposits.length})')),
                          if (deposits.isEmpty)
                            Text(tr('Aucune recharge en attente.',
                                'No pending top-ups.'),
                                style: const TextStyle(color: Colors.white70)),
                          for (final r in deposits) _request(r),
                          _title(tr('⬆️ Retraits à payer (${withdrawals.length})',
                              '⬆️ Withdrawals to pay (${withdrawals.length})')),
                          if (withdrawals.isEmpty)
                            Text(tr('Aucun retrait en attente.',
                                'No pending withdrawals.'),
                                style: const TextStyle(color: Colors.white70)),
                          for (final r in withdrawals) _request(r),
                          _title(tr('Derniers traités', 'Recently handled')),
                          if (recent.isEmpty)
                            Text(tr('Rien pour le moment.', 'Nothing yet.'),
                                style: const TextStyle(color: Colors.white70)),
                          for (final r in recent) _recentRow(r),
                          const SizedBox(height: 24),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFFF8A80),
                              side: const BorderSide(color: Color(0xFFFF8A80)),
                            ),
                            onPressed: _resetAll,
                            child: Text(tr('Remettre tous les soldes à zéro',
                                'Reset all balances to zero')),
                          ),
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
