import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:url_launcher/url_launcher.dart';

import 'accounts.dart';
import 'promo_link.dart';

/// Code promo : chaque joueur a son pseudo comme code. Quand un joueur entre
/// le code d'un parrain, le parrain touche une part de la commission que
/// Katika prélève sur les parties de son filleul.
class PromoScreen extends StatefulWidget {
  const PromoScreen({super.key});

  @override
  State<PromoScreen> createState() => _PromoScreenState();
}

class _PromoScreenState extends State<PromoScreen> {
  static const Color _gold = Color(0xFFFFC21A);

  bool loading = true;
  bool withdrawing = false;
  String? error;
  Map<String, dynamic> info = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  int _i(dynamic v) => v is num ? v.toInt() : 0;

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final res = await Wallet.referralInfo();
      if (!mounted) return;
      setState(() {
        info = res;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = Wallet.errorText(e);
        loading = false;
      });
    }
  }

  /// Transfère les gains de parrainage vers le solde principal.
  Future<void> _withdraw() async {
    if (withdrawing) return;
    setState(() => withdrawing = true);
    try {
      final res = await Wallet.referralWithdraw();
      if (!mounted) return;
      final amount = res is Map ? _i(res['amount']) : 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            amount > 0
                ? '${Wallet.format(amount)} ajoutés à ton solde !'
                : 'Gains ajoutés à ton solde !',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Wallet.errorText(e))),
      );
    } finally {
      if (mounted) setState(() => withdrawing = false);
    }
  }

  Widget _card(List<Widget> children) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFFE3EAFF),
        border: Border.all(color: Color(0xFFD5DEF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _myCode() {
    final code = info['code'] as String?;
    final reason = info['reason'] as String?;
    final pv = info['percent'];
    final percentNum = pv is num && pv > 0 ? pv.toDouble() : 12.5;
    final percent = percentNum == percentNum.roundToDouble() ? percentNum.toStringAsFixed(0) : percentNum.toString().replaceAll('.', ',');
    final tiers = [for (final t in (info['tiers'] as List? ?? const [])) Map<String, dynamic>.from(t as Map)];
    final kids = _i(info['referrals']);

    return _card([
      const Text(
        'Ton code promo',
        style: TextStyle(
          color: Color(0xFF12183A),
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 10),
      if (code != null)
        Row(
          children: [
            Expanded(
              child: Text(
                code.toUpperCase(),
                style: const TextStyle(
                  color: _gold,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy, color: Color(0xFF12183A)),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Code copié')),
                );
              },
            ),
          ],
        )
      else
        Text(
          reason == 'taken'
              ? 'Ton pseudo est déjà utilisé comme code promo par un autre joueur.'
              : "Tu n'as pas encore de pseudo : ton code promo est ton pseudo.",
          style: const TextStyle(color: Color(0xFFD32F2F), fontSize: 14),
        ),
      if (code != null) ...[
        const SizedBox(height: 10),
        const Text(
          'Ton lien promo',
          style: TextStyle(color: Color(0xFF12183A), fontSize: 14, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(
            PromoLink.linkFor(code),
            style: const TextStyle(color: Color(0xFF12183A), fontSize: 13),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF12183A),
                  side: const BorderSide(color: Color(0xFF68729A)),
                ),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: PromoLink.linkFor(code)));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Lien copié')),
                  );
                },
                icon: const Icon(Icons.link),
                label: const Text('Copier le lien'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                onPressed: () {
                  final msg = 'Rejoins-moi sur Katika et joue pour de vrai ! '
                      'Crée ton compte avec mon lien : ${PromoLink.linkFor(code)}';
                  launchUrl(
                    Uri.parse('https://wa.me/?text=${Uri.encodeComponent(msg)}'),
                    mode: LaunchMode.externalApplication,
                  );
                },
                icon: const Icon(Icons.share),
                label: const Text('WhatsApp'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Quand quelqu\'un ouvre ou installe le site avec ton lien, ton code est déjà rempli : il devient ton filleul à la création de son compte.',
          style: TextStyle(color: Color(0xFF68729A), fontSize: 12),
        ),
      ],
      const SizedBox(height: 8),
      Text(
        'Partage ton code. Quand un joueur le saisit, tu reçois $percent % de '
        'la commission que Katika prélève sur ses parties.',
        style: const TextStyle(color: Color(0xFF56608A), fontSize: 13),
      ),
      if (tiers.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(
          'Ta commission monte avec le nombre de joueurs inscrits (tu en as $kids) :',
          style: const TextStyle(color: Color(0xFF12183A), fontSize: 13, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        for (final t in tiers)
          Builder(builder: (_) {
            final from = _i(t['from']);
            final to = _i(t['to']);
            final p = (t['percent'] as num).toDouble();
            final ps = p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toString().replaceAll('.', ',');
            final here = kids >= from && (to == 0 || kids <= to);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(
                '${here ? '👉 ' : '•  '}${to == 0 ? 'Plus de ${from - 1}' : 'De $from à $to'} joueurs : $ps %',
                style: TextStyle(
                  color: here ? const Color(0xFFFFC21A) : Color(0xFF56608A),
                  fontSize: 12.5,
                  fontWeight: here ? FontWeight.w900 : FontWeight.w500,
                ),
              ),
            );
          }),
      ],
    ]);
  }

  Widget _stats() {
    return _card([
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Filleuls',
                  style: TextStyle(color: Color(0xFF56608A), fontSize: 12),
                ),
                Text(
                  '${_i(info['referrals'])}',
                  style: const TextStyle(
                    color: Color(0xFF12183A),
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Gains de parrainage',
                  style: TextStyle(color: Color(0xFF56608A), fontSize: 12),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    Wallet.format(_i(info['earned'])),
                    style: const TextStyle(
                      color: _gold,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ]);
  }

  /// Gains retirables : le bouton apparaît quand ils atteignent le minimum.
  Widget _withdrawCard() {
    final available = _i(info['available']);
    final min = _i(info['minWithdraw']) == 0 ? 500 : _i(info['minWithdraw']);
    final can = info['canWithdraw'] == true || available >= min;

    return _card([
      const Text(
        'Gains à retirer',
        style: TextStyle(color: Color(0xFF56608A), fontSize: 12),
      ),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          Wallet.format(available),
          style: const TextStyle(
            color: _gold,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      const SizedBox(height: 10),
      if (can)
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22B14C),
              foregroundColor: Colors.white,
            ),
            onPressed: withdrawing ? null : _withdraw,
            icon: const Icon(Icons.account_balance_wallet),
            label: Text(
              withdrawing ? '...' : 'Retirer les gains',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        )
      else
        Text(
          'Le bouton « Retirer les gains » apparaît à partir de '
          '${Wallet.format(min)}. Les gains sont ajoutés à ton solde.',
          style: const TextStyle(color: Color(0xFF56608A), fontSize: 12),
        ),
    ]);
  }

  Widget _sponsor() {
    final sponsor = info['sponsor'] as String?;
    if (sponsor != null) {
      return _card([
        const Text(
          'Ton parrain',
          style: TextStyle(color: Color(0xFF56608A), fontSize: 12),
        ),
        const SizedBox(height: 2),
        Text(
          sponsor,
          style: const TextStyle(
            color: Color(0xFF12183A),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ]);
    }
    return _card([
      const Text(
        'Code de parrain',
        style: TextStyle(color: Color(0xFF56608A), fontSize: 12),
      ),
      const SizedBox(height: 4),
      const Text(
        'Le code de parrain se saisit uniquement à la création du compte '
        '(facultatif). Il ne peut plus être ajouté après.',
        style: TextStyle(color: Color(0xFF56608A), fontSize: 12),
      ),
    ]);
  }

  Widget _body() {
    if (loading && info.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFD32F2F), fontSize: 15),
              ),
              const SizedBox(height: 14),
              ElevatedButton(onPressed: _load, child: const Text('Réessayer')),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _myCode(),
          _stats(),
          _withdrawCard(),
          _sponsor(),
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
            colors: [Color(0xFFF3F6FF), Color(0xFFF3F6FF)],
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
                      icon: const Icon(Icons.arrow_back, color: Color(0xFF12183A)),
                    ),
                    const Expanded(
                      child: Text(
                        '🎁 Code promo',
                        style: TextStyle(
                          color: Color(0xFF12183A),
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
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
