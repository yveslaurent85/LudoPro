import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'accounts.dart';

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
  bool sending = false;
  bool withdrawing = false;
  String? error;
  String? sponsorError;
  String? withdrawError;
  Map<String, dynamic> info = {};
  final TextEditingController codeCtrl = TextEditingController();

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

  Future<void> _apply() async {
    final code = codeCtrl.text.trim();
    if (code.isEmpty || sending) return;
    setState(() {
      sending = true;
      sponsorError = null;
    });
    try {
      await Wallet.applyPromo(code);
      if (!mounted) return;
      codeCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Code promo validé !')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => sponsorError = Wallet.errorText(e));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  /// Transfère les gains de parrainage vers le solde principal.
  Future<void> _withdraw() async {
    if (withdrawing) return;
    setState(() {
      withdrawing = true;
      withdrawError = null;
    });
    try {
      final res = await Wallet.referralWithdraw();
      if (!mounted) return;
      final amount = _i(res['amount']);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${Wallet.format(amount)} ajoutés à ton solde')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => withdrawError = Wallet.errorText(e));
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
        color: Colors.white.withOpacity(0.12),
        border: Border.all(color: Colors.white24),
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
    final percent = _i(info['percent']) == 0 ? 10 : _i(info['percent']);

    return _card([
      const Text(
        'Ton code promo',
        style: TextStyle(
          color: Colors.white,
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
              icon: const Icon(Icons.copy, color: Colors.white),
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
          style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 14),
        ),
      const SizedBox(height: 8),
      Text(
        'Partage ton code. Quand un joueur le saisit, tu reçois $percent % de '
        'la commission que Katika prélève sur ses parties.',
        style: const TextStyle(color: Colors.white70, fontSize: 13),
      ),
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
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  '${_i(info['referrals'])}',
                  style: const TextStyle(
                    color: Colors.white,
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
                  style: TextStyle(color: Colors.white70, fontSize: 12),
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
    /// Gains retirables + bouton « Retirer les gains » (dès 100 FCFA).
  Widget _withdrawCard() {
    final available = _i(info['available']);
    final min = _i(info['minWithdraw']) == 0 ? 100 : _i(info['minWithdraw']);
    final can = info['canWithdraw'] == true;

    return _card([
      const Text(
        'Gains à retirer',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 6),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          Wallet.format(available),
          style: const TextStyle(
            color: _gold,
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      const SizedBox(height: 10),
      if (can)
        SizedBox(
          width: double.infinity,
          height: 50,
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
          'Le retrait est possible dès ${Wallet.format(min)} de gains.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      if (withdrawError != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            withdrawError!,
            style: const TextStyle(
              color: Color(0xFFFF8A80),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      const SizedBox(height: 6),
      const Text(
        'Les gains retirés sont ajoutés à ton solde principal.',
        style: TextStyle(color: Colors.white54, fontSize: 12),
      ),
    ]);
  }

  Widget _sponsor() {
    final sponsor = info['sponsor'] as String?;
    if (sponsor != null) {
      return _card([
        const Text(
          'Ton parrain',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 2),
        Text(
          sponsor,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ]);
    }
    return _card([
      const Text(
        "J'ai un code de parrain",
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 4),
      const Text(
        'Entre le pseudo de la personne qui t\'a invité. Tu ne peux le faire '
        "qu'une seule fois.",
        style: TextStyle(color: Colors.white70, fontSize: 12),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: codeCtrl,
              enabled: !sending,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Pseudo du parrain',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withOpacity(0.12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22B14C),
                foregroundColor: Colors.white,
              ),
              onPressed: sending ? null : _apply,
              child: Text(sending ? '...' : 'Valider'),
            ),
          ),
        ],
      ),
      if (sponsorError != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            sponsorError!,
            style: const TextStyle(
              color: Color(0xFFFF8A80),
              fontWeight: FontWeight.w700,
            ),
          ),
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
                style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 15),
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
                        '🎁 Code promo',
                        style: TextStyle(
                          color: Colors.white,
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
