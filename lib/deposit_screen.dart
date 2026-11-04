import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'accounts.dart';
import 'lang.dart';

/// Recharge par le code marchand Orange Money : le joueur compose le code
/// USSD, confirme le paiement, puis envoie l'identifiant de la transaction.
/// L'administrateur vérifie et confirme : le solde est alors crédité.
class DepositScreen extends StatefulWidget {
  const DepositScreen({super.key});

  @override
  State<DepositScreen> createState() => _DepositScreenState();
}

class _DepositScreenState extends State<DepositScreen> {
  static const Color _gold = Color(0xFFFFC21A);
  static const List<int> _presets = [100, 500, 1000, 2000, 5000, 10000];

  final TextEditingController amountCtrl = TextEditingController();
  final TextEditingController phoneCtrl = TextEditingController();
  final TextEditingController refCtrl = TextEditingController();

  String code = '0529831';
  String ussdTemplate = '#150*47*0529831*{amount}*2#';
  int minAmount = 100;
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
    refCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final info = await Wallet.manualInfo();
      if (mounted) {
        setState(() {
          code = '${info['code'] ?? code}';
          ussdTemplate = '${info['ussd'] ?? ussdTemplate}';
          minAmount = (info['depositMin'] as num?)?.toInt() ?? minAmount;
          maxAmount = (info['depositMax'] as num?)?.toInt() ?? maxAmount;
        });
      }
    } catch (_) {}
    await _loadMine();
  }

  Future<void> _loadMine() async {
    try {
      final r = await Wallet.manualMine();
      final l = ((r['deposits'] as List?) ?? const [])
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

  String get _ussd =>
      ussdTemplate.replaceAll('{amount}', _amount > 0 ? '$_amount' : 'MONTANT');

  Future<void> _dial() async {
    if (_amount < minAmount || _amount > maxAmount) {
      setState(() => error = tr(
          'Entre d\'abord un montant entre ${_fmt(minAmount)} et ${_fmt(maxAmount)} FCFA.',
          'First enter an amount between ${_fmt(minAmount)} and ${_fmt(maxAmount)} FCFA.'));
      return;
    }
    try {
      final ok = await launchUrl(
        Uri.parse('tel:${Uri.encodeComponent(_ussd)}'),
      );
      if (ok) return;
    } catch (_) {}
    await Clipboard.setData(ClipboardData(text: _ussd));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr('Code copié : colle-le dans le composeur du téléphone.',
            'Code copied: paste it in the phone dialer.')),
      ),
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _ussd));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr('Code copié', 'Code copied'))),
    );
  }

  Future<void> _send() async {
    if (sending) return;
    final phone = phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    final ref = refCtrl.text.trim();
    if (_amount < minAmount || _amount > maxAmount) {
      setState(() => error = tr(
          'Montant entre ${_fmt(minAmount)} et ${_fmt(maxAmount)} FCFA.',
          'Amount between ${_fmt(minAmount)} and ${_fmt(maxAmount)} FCFA.'));
      return;
    }
    if (!RegExp(r'^(237)?6\d{8}$').hasMatch(phone)) {
      setState(() => error = tr('Numéro Orange invalide (ex : 690000000).',
          'Invalid Orange number (e.g. 690000000).'));
      return;
    }
    if (ref.replaceAll(RegExp(r'[^A-Za-z0-9.]'), '').length < 6) {
      setState(() => error = tr(
          "Entre l'identifiant de la transaction reçu par SMS.",
          'Enter the transaction ID you received by SMS.'));
      return;
    }
    setState(() {
      sending = true;
      error = null;
      done = null;
    });
    try {
      await Wallet.manualDeposit(amount: _amount, phone: phone, txRef: ref);
      if (!mounted) return;
      setState(() {
        done = tr(
            '✅ Demande envoyée. Ton solde sera crédité dès que ta transaction '
                'sera confirmée.',
            '✅ Request sent. Your balance will be credited as soon as your '
                'transaction is confirmed.');
        amountCtrl.clear();
        refCtrl.clear();
      });
      await _loadMine();
    } catch (e) {
      if (mounted) setState(() => error = Wallet.errorText(e));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  /// 250000 -> « 250 000 ».
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

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(
          s,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      );

  Widget _balance() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    return _card([
      Text(
        tr('Ton solde', 'Your balance'),
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
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
    ]);
  }

  Widget _steps() {
    Widget step(String n, String t) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration:
                    const BoxDecoration(shape: BoxShape.circle, color: _gold),
                child: Text(n,
                    style: const TextStyle(
                        color: Colors.black,
                        fontSize: 12,
                        fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(t,
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
              ),
            ],
          ),
        );
    return _card([
      Text(
        tr('Recharger par Orange Money', 'Top up with Orange Money'),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        tr('Orange Money uniquement. 1 FCFA = 1 jeton.',
            'Orange Money only. 1 FCFA = 1 token.'),
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
      const SizedBox(height: 12),
      step('1', tr('Écris le montant ci-dessous.', 'Enter the amount below.')),
      step(
          '2',
          tr('Touche « Composer le code » (ou copie-le) et confirme la '
              'transaction avec ton code secret.',
              'Tap "Dial the code" (or copy it) and confirm the transaction '
              'with your PIN.')),
      step(
          '3',
          tr('Tu reçois un SMS avec l\'identifiant de la transaction : recopie-le '
              'ici et envoie ta demande.',
              'You get an SMS with the transaction ID: copy it here and send '
              'your request.')),
      step(
          '4',
          tr('Dès que c\'est confirmé, ton solde est crédité.',
              'As soon as it is confirmed, your balance is credited.')),
    ]);
  }

  Widget _form() {
    return _card([
      _label(tr('Montant à déposer', 'Amount to deposit')),
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
        decoration: _dec(tr('Écris ton montant', 'Enter your amount'),
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
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final p in _presets)
            ActionChip(
              label: Text(_fmt(p)),
              onPressed: sending
                  ? null
                  : () => setState(() {
                        amountCtrl.text = '$p';
                        error = null;
                      }),
            ),
        ],
      ),
      _label(tr('Code à composer', 'Code to dial')),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.black26,
          border: Border.all(color: _gold, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              _ussd,
              style: const TextStyle(
                color: _gold,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tr('Code marchand : $code', 'Merchant code: $code'),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF7900),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _dial,
                    icon: const Icon(Icons.phone),
                    label: Text(tr('Composer le code', 'Dial the code')),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: tr('Copier', 'Copy'),
                  onPressed: _copy,
                  icon: const Icon(Icons.copy, color: Colors.white),
                ),
              ],
            ),
          ],
        ),
      ),
      _label(tr('Ton numéro Orange Money', 'Your Orange Money number')),
      TextField(
        controller: phoneCtrl,
        enabled: !sending,
        keyboardType: TextInputType.phone,
        style: const TextStyle(color: Colors.white),
        decoration: _dec(tr('Numéro (ex : 690000000)', 'Number (e.g. 690000000)'),
            Icons.phone_android),
      ),
      _label(tr('Identifiant de la transaction (SMS)',
          'Transaction ID (from the SMS)')),
      TextField(
        controller: refCtrl,
        enabled: !sending,
        textCapitalization: TextCapitalization.characters,
        style: const TextStyle(color: Colors.white),
        decoration: _dec(tr('Ex : MP260101.1234.A12345', 'e.g. MP260101.1234.A12345'),
            Icons.receipt_long),
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
            backgroundColor: const Color(0xFF22B14C),
            foregroundColor: Colors.white,
          ),
          onPressed: sending ? null : _send,
          child: Text(
            sending
                ? '...'
                : tr('J\'ai payé · envoyer ma demande', 'I paid · send my request'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ),
      ),
    ]);
  }

  String _statusText(String st) {
    switch (st) {
      case 'credited':
        return tr('✅ Crédité', '✅ Credited');
      case 'rejected':
        return tr('❌ Refusé', '❌ Rejected');
    }
    return tr('⏳ En attente de confirmation', '⏳ Waiting for confirmation');
  }

  Widget _history() {
    return _card([
      Row(
        children: [
          Expanded(
            child: Text(
              tr('Mes demandes de recharge', 'My top-up requests'),
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
          tr('Aucune demande pour le moment.', 'No requests yet.'),
          style: const TextStyle(color: Colors.white70),
        ),
      for (final d in mine)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_fmt((d['amount'] as num?)?.toInt() ?? 0)} FCFA · ${d['txRef']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _statusText('${d['status']}'),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
    ]);
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
                        tr('💰 Déposer', '💰 Deposit'),
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
                    _balance(),
                    _steps(),
                    _form(),
                    _history(),
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
