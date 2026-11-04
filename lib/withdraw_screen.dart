import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import 'accounts.dart';
import 'lang.dart';

/// Retrait : le joueur demande un montant et son numéro Orange Money. Le
/// montant est retiré de son solde ; l'administrateur envoie l'argent puis
/// confirme. Si la demande est refusée, le solde est remboursé.
class WithdrawScreen extends StatefulWidget {
  const WithdrawScreen({super.key});

  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen> {
  static const Color _gold = Color(0xFFFFC21A);

  final TextEditingController amountCtrl = TextEditingController();
  final TextEditingController phoneCtrl = TextEditingController();

  int minAmount = 500;
  int maxAmount = 250000;
  bool sending = false;
  String? error;
  String? done;
  List<Map<String, dynamic>> mine = [];
  bool loadingMine = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    amountCtrl.dispose();
    phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final info = await Wallet.manualInfo();
      if (mounted) {
        setState(() {
          minAmount = (info['withdrawMin'] as num?)?.toInt() ?? minAmount;
          maxAmount = (info['withdrawMax'] as num?)?.toInt() ?? maxAmount;
        });
      }
    } catch (_) {}
    await _loadMine();
  }

  Future<void> _loadMine() async {
    try {
      final r = await Wallet.manualMine();
      final l = ((r['withdrawals'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (mounted) {
        setState(() {
          mine = l;
          loadingMine = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => loadingMine = false);
    }
  }

  int get _amount => int.tryParse(amountCtrl.text.trim()) ?? 0;

  Future<void> _send() async {
    if (sending) return;
    final phone = phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (_amount < minAmount || _amount > maxAmount) {
      setState(() => error = tr(
          'Montant entre ${_fmt(minAmount)} et ${_fmt(maxAmount)} FCFA.',
          'Amount between ${_fmt(minAmount)} and ${_fmt(maxAmount)} FCFA.'));
      return;
    }
    if (!RegExp(r'^(237)?6\d{8}$').hasMatch(phone)) {
      setState(() => error = tr('Numéro Orange Money invalide (ex : 690000000).',
          'Invalid Orange Money number (e.g. 690000000).'));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Confirmer le retrait ?', 'Confirm withdrawal?')),
        content: Text(tr(
            '${_fmt(_amount)} FCFA seront retirés de ton solde et envoyés au '
                '$phone dès que l\'administrateur aura traité ta demande.',
            '${_fmt(_amount)} FCFA will be taken from your balance and sent to '
                '$phone once the administrator has processed your request.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('Annuler', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr('Confirmer', 'Confirm')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      sending = true;
      error = null;
      done = null;
    });
    try {
      await Wallet.manualWithdraw(amount: _amount, phone: phone);
      if (!mounted) return;
      setState(() {
        done = tr(
            '✅ Demande envoyée. Tu seras payé dès qu\'elle sera traitée.',
            '✅ Request sent. You will be paid as soon as it is processed.');
        amountCtrl.clear();
      });
      await _loadMine();
    } catch (e) {
      if (mounted) setState(() => error = Wallet.errorText(e));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  static String _fmt(int v) {
    final s = v.toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return b.toString();
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

  InputDecoration _dec(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38),
      prefixIcon: Icon(icon, color: Colors.white70),
      filled: true,
      fillColor: Colors.white.withOpacity(0.12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }

  String _statusText(String st) {
    switch (st) {
      case 'paid':
        return tr('✅ Payé', '✅ Paid');
      case 'rejected':
        return tr('❌ Refusé (remboursé)', '❌ Rejected (refunded)');
    }
    return tr('⏳ En attente', '⏳ Pending');
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
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
                        tr('💸 Retrait', '💸 Withdrawal'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  children: [
                    if (uid != null)
                      _card([
                        Text(tr('Ton solde', 'Your balance'),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                        StreamBuilder<int>(
                          stream: Wallet.watch(uid),
                          builder: (context, snap) => FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              Wallet.format(snap.data ?? 0),
                              style: const TextStyle(
                                color: _gold,
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ]),
                    _card([
                      Text(
                        tr('Retirer vers Orange Money', 'Withdraw to Orange Money'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr('Le montant est retiré de ton solde tout de suite. '
                            'Tu es payé dès que l\'administrateur traite ta demande ; '
                            'si elle est refusée, tu es remboursé.',
                            'The amount is taken from your balance right away. '
                            'You are paid once the administrator processes your '
                            'request; if rejected, you are refunded.'),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: amountCtrl,
                        enabled: !sending,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (_) => setState(() => error = null),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                        decoration: _dec(
                                tr('Montant à retirer', 'Amount to withdraw'),
                                Icons.payments)
                            .copyWith(
                          suffixText: 'FCFA',
                          suffixStyle: const TextStyle(
                            color: _gold,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        tr('Minimum : ${_fmt(minAmount)} FCFA   ·   Maximum : ${_fmt(maxAmount)} FCFA',
                            'Minimum: ${_fmt(minAmount)} FCFA   ·   Maximum: ${_fmt(maxAmount)} FCFA'),
                        style: const TextStyle(
                          color: _gold,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: phoneCtrl,
                        enabled: !sending,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(color: Colors.white),
                        decoration: _dec(
                            tr('Ton numéro Orange Money (ex : 690000000)',
                                'Your Orange Money number (e.g. 690000000)'),
                            Icons.phone_android),
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            error!,
                            style: const TextStyle(
                              color: Color(0xFFFF8A80),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      if (done != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            done!,
                            style: const TextStyle(
                              color: Color(0xFF7CFFB0),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E6BFF),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: sending ? null : _send,
                          child: Text(
                            sending ? '...' : tr('Demander le retrait', 'Request withdrawal'),
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                        ),
                      ),
                    ]),
                    _card([
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              tr('Mes retraits', 'My withdrawals'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: tr('Actualiser', 'Refresh'),
                            onPressed: _loadMine,
                            icon: const Icon(Icons.refresh, color: Colors.white),
                          ),
                        ],
                      ),
                      if (loadingMine)
                        const Center(child: CircularProgressIndicator())
                      else if (mine.isEmpty)
                        Text(
                          tr('Aucun retrait pour le moment.', 'No withdrawals yet.'),
                          style: const TextStyle(color: Colors.white70),
                        ),
                      for (final d in mine)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${_fmt((d['amount'] as num?)?.toInt() ?? 0)} FCFA · ${d['phone']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 13),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _statusText('${d['status']}'),
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                    ]),
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
