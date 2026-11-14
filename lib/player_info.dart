import 'package:flutter/material.dart' hide Text;

import 'accounts.dart';
import 'lang.dart';
import 'replay.dart';

/// Fiche admin d'un joueur : parties en cours, parrain, filleuls, gains de
/// parrainage, statut partenaire / hôtesse.
class PlayerInfoBox extends StatefulWidget {
  const PlayerInfoBox({super.key, required this.uid});

  final String uid;

  @override
  State<PlayerInfoBox> createState() => _PlayerInfoBoxState();
}

class _PlayerInfoBoxState extends State<PlayerInfoBox> {
  Map<String, dynamic>? _d;
  String? _err;
  bool _loading = true;

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
      final r = await Wallet.adminPlayerInfo(widget.uid);
      if (!mounted) return;
      setState(() {
        _d = r;
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
    return '${_two(d.day)}/${_two(d.month)}/${d.year}';
  }

  static String _dateTime(int ms) {
    if (ms <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    return '${_two(d.day)}/${_two(d.month)} ${_two(d.hour)}:${_two(d.minute)}';
  }

  static int _i(dynamic v) => v is num ? v.toInt() : 0;

  static String _fcfa(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return '$b FCFA';
  }

  Widget _box(String title, List<Widget> children, {Color? border}) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border ?? Colors.white24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      );

  Widget _line(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
                child: Text(k, style: const TextStyle(color: Colors.white70, fontSize: 13))),
            Text(v,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 20),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_err != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(_err!, style: const TextStyle(color: Colors.white70)),
      );
    }
    final d = _d!;
    final live = [for (final e in (d['live'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)];
    final kids = [for (final e in (d['referrals'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)];
    final ref = d['referrer'] is Map ? Map<String, dynamic>.from(d['referrer'] as Map) : null;
    final phone = '${d['phone'] ?? ''}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _box(
          live.isEmpty
              ? tr('⚪ Pas en partie en ce moment', '⚪ Not in a game right now')
              : tr('🟢 En partie en ce moment', '🟢 In a game right now'),
          [
            if (live.isEmpty)
              Text(tr('Aucune partie ouverte ou en cours.', 'No open or running game.'),
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            for (final g in live)
              GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => ReplayScreen(
                      kind: '${g['kind']}', id: '${g['id']}', title: rpKindName('${g['kind']}')),
                )),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22B14C).withOpacity(0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${rpKindName('${g['kind']}')} · ${g['status'] == 'waiting' ? tr('en attente', 'waiting') : tr('en cours', 'in progress')}'
                              '${_i(g['stake']) > 0 ? ' · ${_fcfa(_i(g['stake']))}' : ''}',
                              style: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                            ),
                            Text(
                              [for (final n in (g['names'] as List? ?? const [])) '$n'].join(' · '),
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            Text(_dateTime(_i(g['t'])),
                                style: const TextStyle(color: Colors.white54, fontSize: 11)),
                          ],
                        ),
                      ),
                      const Icon(Icons.play_circle_outline, color: Colors.white70),
                    ],
                  ),
                ),
              ),
          ],
          border: live.isEmpty ? null : const Color(0xFF22B14C),
        ),
        _box(tr('Compte', 'Account'), [
          if ('${d['promoCode']}'.isNotEmpty) _line(tr('Code promo', 'Promo code'), '${d['promoCode']}'),
          if (phone.isNotEmpty) _line(tr('Téléphone (dernier dépôt)', 'Phone (last deposit)'), phone),
          _line(tr('Total misé', 'Total wagered'), _fcfa(_i(d['wagered']))),
          if (d['partner'] == true) _line(tr('Statut', 'Status'), tr('Partenaire', 'Partner')),
          if (d['hostess'] == true) _line(tr('Statut', 'Status'), tr('Hôtesse', 'Hostess')),
        ]),
        _box(tr('Parrain', 'Sponsor'), [
          if (ref == null)
            Text(tr('Aucun parrain.', 'No sponsor.'),
                style: const TextStyle(color: Colors.white70, fontSize: 13))
          else ...[
            _line(tr('Pseudo', 'Name'), '${ref['pseudo']}'.isEmpty ? '—' : '${ref['pseudo']}'),
            if ('${ref['code']}'.isNotEmpty) _line(tr('Code utilisé', 'Code used'), '${ref['code']}'),
          ],
        ]),
        _box(tr('Filleuls (${kids.length})', 'Referrals (${kids.length})'), [
          _line(tr('Commissions gagnées', 'Commissions earned'), _fcfa(_i(d['referralEarned']))),
          _line(tr('Disponible au retrait', 'Available to withdraw'), _fcfa(_i(d['referralBalance']))),
          _line(tr('Déjà retiré', 'Already withdrawn'), _fcfa(_i(d['referralWithdrawn']))),
          if (d['partner'] == true) ...[
            _line(tr('Gains partenaire', 'Partner earnings'), _fcfa(_i(d['partnerEarned']))),
            _line(tr('Solde partenaire', 'Partner balance'), _fcfa(_i(d['partnerBalance']))),
          ],
          if (kids.isNotEmpty) const Divider(color: Colors.white24, height: 18),
          if (kids.isEmpty)
            Text(tr('Aucun filleul.', 'No referrals.'),
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          for (final k in kids)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${k['pseudo']}'.isEmpty ? '—' : '${k['pseudo']}',
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                        Text(
                          tr('inscrit le ${_date(k['createdAt'])}', 'joined ${_date(k['createdAt'])}'),
                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(tr('${_i(k['played'])} parties', '${_i(k['played'])} games'),
                          style: const TextStyle(color: Colors.white, fontSize: 12)),
                      Text(tr('misé ${_fcfa(_i(k['wagered']))}', 'wagered ${_fcfa(_i(k['wagered']))}'),
                          style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
        ]),
      ],
    );
  }
}
