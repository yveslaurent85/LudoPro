import 'package:flutter/material.dart' hide Text;

import 'accounts.dart';
import 'lang.dart';

/// Historique des transactions : recharges, retraits et transferts.
/// Sans [uid] : mon historique. Avec [uid] : celui d'un joueur (administrateur).
class TxHistoryScreen extends StatefulWidget {
  const TxHistoryScreen({super.key, this.uid, this.name});

  final String? uid;
  final String? name;

  @override
  State<TxHistoryScreen> createState() => _TxHistoryScreenState();
}

class _TxHistoryScreenState extends State<TxHistoryScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _err;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final r = await Wallet.txHistory(uid: widget.uid);
      if (!mounted) return;
      setState(() {
        _items = [for (final e in (r['items'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)];
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = Wallet.errorText(e);
          _loading = false;
        });
      }
    }
  }

  static String _two(int n) => n < 10 ? '0$n' : '$n';

  static String _date(dynamic v) {
    final d = v is String ? DateTime.tryParse(v)?.toLocal() : null;
    if (d == null) return '';
    return '${_two(d.day)}/${_two(d.month)}/${d.year} ${_two(d.hour)}:${_two(d.minute)}';
  }

  static String _fcfa(int n) {
    final s = n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ' ');
    return '$s FCFA';
  }

  (String, Color) _status(String s) {
    switch (s) {
      case 'credited':
      case 'approved':
      case 'paid':
      case 'done':
        return (tr('Validé', 'Done'), const Color(0xFF4CAF50));
      case 'rejected':
      case 'failed':
      case 'cancelled':
      case 'expired':
        return (tr('Refusé / échoué', 'Rejected / failed'), const Color(0xFFFF6B6B));
      default:
        return (tr('En attente', 'Pending'), const Color(0xFFFFC21A));
    }
  }

  Widget _chip(String label, String key) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: _filter == key,
          onSelected: (_) => setState(() => _filter = key),
        ),
      );

  Widget _tile(Map<String, dynamic> t) {
    final kind = '${t['kind']}';
    final amount = (t['amount'] as num?)?.toInt() ?? 0;
    final plus = kind == 'deposit' || kind == 'transfer_in';
    final (stLabel, stColor) = _status('${t['status']}');
    final other = '${t['other'] ?? ''}';
    final icon = kind == 'deposit'
        ? Icons.south_west
        : kind == 'withdrawal'
            ? Icons.north_east
            : Icons.swap_horiz;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withOpacity(0.1),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(children: [
        CircleAvatar(
          backgroundColor: (plus ? const Color(0xFF22B14C) : const Color(0xFFE5262B)).withOpacity(0.25),
          child: Icon(icon, color: plus ? const Color(0xFF7CFC9A) : const Color(0xFFFF8A80)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${t['label']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            if (other.isNotEmpty)
              Text(
                kind == 'transfer_in'
                    ? tr('De : $other', 'From: $other')
                    : kind == 'transfer_out'
                        ? tr('Vers : $other', 'To: $other')
                        : other,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            Text(_date(t['at']), style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            '${plus ? '+' : '-'}${_fcfa(amount)}',
            style: TextStyle(
              color: plus ? const Color(0xFF7CFC9A) : const Color(0xFFFF8A80),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: stColor.withOpacity(0.2),
              border: Border.all(color: stColor),
            ),
            child: Text(stLabel, style: const TextStyle(color: Colors.white, fontSize: 10)),
          ),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _items.where((t) {
      final k = '${t['kind']}';
      if (_filter == 'all') return true;
      if (_filter == 'deposit') return k == 'deposit';
      if (_filter == 'withdrawal') return k == 'withdrawal';
      return k.startsWith('transfer');
    }).toList();
    final title = widget.name == null
        ? tr('Historique des transactions', 'Transaction history')
        : tr('Transactions de ${widget.name}', "${widget.name}'s transactions");
    return Scaffold(
      backgroundColor: const Color(0xFF0B3D2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B3D2E),
        foregroundColor: Colors.white,
        title: Text(title),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _err != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_err!, style: const TextStyle(color: Color(0xFFFF8A80)), textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        _chip(tr('Tout', 'All'), 'all'),
                        _chip(tr('Recharges', 'Deposits'), 'deposit'),
                        _chip(tr('Retraits', 'Withdrawals'), 'withdrawal'),
                        _chip(tr('Transferts', 'Transfers'), 'transfer'),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: Center(
                          child: Text(tr('Aucune transaction.', 'No transactions.'),
                              style: const TextStyle(color: Colors.white70)),
                        ),
                      ),
                    for (final t in shown) _tile(t),
                  ],
                ),
    );
  }
}
