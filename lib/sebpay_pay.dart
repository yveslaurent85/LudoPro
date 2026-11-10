import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'accounts.dart';
import 'lang.dart';

/// Recharge et retrait AUTOMATIQUES par SebPay (Orange Money / MTN MoMo).
/// Le joueur choisit l'opérateur, saisit son numéro et le montant ; il valide
/// sur son téléphone et le solde est crédité tout seul.

const Color _gold = Color(0xFFFFC21A);

String _fmt(int v) {
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

/// Bascule « Automatique (SebPay) » / « Manuel (Orange Money) ».
class PayModeSwitch extends StatelessWidget {
  const PayModeSwitch({
    super.key,
    required this.auto,
    required this.onChanged,
    this.disableInternational = false,
  });

  /// Grise le choix « International » (non utilisable pour le moment).
  final bool disableInternational;
  final bool auto;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, bool value) {
      final locked = disableInternational && value;
      final on = !locked && auto == value;
      return Expanded(
        child: GestureDetector(
          onTap: locked ? null : () => onChanged(value),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: on ? _gold : Colors.transparent,
            ),
            child: Opacity(
              opacity: locked ? 0.35 : 1,
              child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: on ? Colors.black : Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withOpacity(0.12),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          chip(tr('🌍 International', '🌍 International'), true),
          const SizedBox(width: 4),
          chip(tr('🇨🇲 Local Cameroun (OM · MoMo)', '🇨🇲 Local Cameroon (OM · MoMo)'), false),
        ],
      ),
    );
  }
}

String _statusText(String st, {required bool deposit}) {
  switch (st) {
    case 'credited':
      return tr('✅ Crédité', '✅ Credited');
    case 'paid':
      return tr('✅ Payé', '✅ Paid');
    case 'failed':
      return deposit
          ? tr('❌ Échoué', '❌ Failed')
          : tr('❌ Échoué (remboursé)', '❌ Failed (refunded)');
    case 'mismatch':
      return tr('⚠️ À vérifier', '⚠️ To check');
  }
  return tr('⏳ En cours', '⏳ In progress');
}

// ----------------------------------------------------------------------
// Recharge
// ----------------------------------------------------------------------
class SebpayDepositPanel extends StatefulWidget {
  const SebpayDepositPanel({super.key});

  @override
  State<SebpayDepositPanel> createState() => _SebpayDepositPanelState();
}

class _SebpayDepositPanelState extends State<SebpayDepositPanel> {
  static const List<int> _presets = [100, 500, 1000, 2000, 5000, 10000];

  final TextEditingController amountCtrl = TextEditingController();
  final TextEditingController phoneCtrl = TextEditingController();

  List<Map<String, String>> operators = [
    {'id': 'orange', 'label': 'Orange Money'},
    {'id': 'mtn', 'label': 'MTN MoMo'},
  ];
  String operator = 'orange';
  int minAmount = 100;
  int maxAmount = 250000;

  bool sending = false;
  bool waiting = false;
  String? error;
  String? done;
  List<Map<String, dynamic>> mine = [];
  bool loadingMine = true;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    amountCtrl.dispose();
    phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final info = await Wallet.sebpayInfo();
      final ops = ((info['operators'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map((e) => {'id': '${e['id']}', 'label': '${e['label']}'})
          .toList();
      if (mounted) {
        setState(() {
          if (ops.isNotEmpty) {
            operators = ops;
            if (!ops.any((o) => o['id'] == operator)) operator = ops.first['id']!;
          }
          minAmount = (info['depositMin'] as num?)?.toInt() ?? minAmount;
          maxAmount = (info['depositMax'] as num?)?.toInt() ?? maxAmount;
        });
      }
    } catch (_) {}
    await _loadMine();
  }

  Future<void> _loadMine() async {
    try {
      final r = await Wallet.sebpayMine();
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

  Future<void> _send() async {
    if (sending || waiting) return;
    final phone = phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (_amount < minAmount || _amount > maxAmount) {
      setState(() => error = tr(
          'Montant entre ${_fmt(minAmount)} et ${_fmt(maxAmount)} FCFA.',
          'Amount between ${_fmt(minAmount)} and ${_fmt(maxAmount)} FCFA.'));
      return;
    }
    if (!RegExp(r'^(237)?6\d{8}$').hasMatch(phone)) {
      setState(() => error = tr('Numéro invalide (ex : 690000000).',
          'Invalid number (e.g. 690000000).'));
      return;
    }
    setState(() {
      sending = true;
      error = null;
      done = null;
    });
    try {
      final r = await Wallet.sebpayDeposit(
          amount: _amount, phone: phone, operator: operator);
      final id = '${r['id']}';
      final link = r['providerLink'];
      if (link is String && link.isNotEmpty) {
        try {
          await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        waiting = true;
        done = tr(
            '📲 Demande envoyée. Valide le paiement sur ton téléphone '
                '(compose ton code secret). Ton solde sera crédité automatiquement.',
            '📲 Request sent. Confirm the payment on your phone (enter your '
                'PIN). Your balance will be credited automatically.');
      });
      _startPolling(id);
      await _loadMine();
    } catch (e) {
      if (mounted) setState(() => error = Wallet.errorText(e));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  void _startPolling(String id) {
    _poll?.cancel();
    int tries = 0;
    _poll = Timer.periodic(const Duration(seconds: 5), (t) async {
      tries++;
      try {
        final r = await Wallet.sebpayDepositStatus(id);
        final st = '${r['status']}';
        if (st == 'credited') {
          t.cancel();
          if (!mounted) return;
          setState(() {
            waiting = false;
            error = null;
            done = tr('✅ Recharge reçue, ton solde est crédité !',
                '✅ Payment received, your balance is credited!');
            amountCtrl.clear();
          });
          await _loadMine();
          return;
        }
        if (st == 'failed' || st == 'mismatch') {
          t.cancel();
          if (!mounted) return;
          setState(() {
            waiting = false;
            done = null;
            error = st == 'failed'
                ? tr('Le paiement a échoué ou a été annulé. Aucun montant débité.',
                    'The payment failed or was cancelled. Nothing was charged.')
                : tr('Montant différent de la demande : contacte le support.',
                    'Amount differs from the request: contact support.');
          });
          await _loadMine();
          return;
        }
      } catch (_) {}
      if (tries >= 36) {
        t.cancel();
        if (!mounted) return;
        setState(() {
          waiting = false;
          done = tr(
              'Toujours en attente. Si tu as validé, ton solde sera crédité '
                  'dès que l\'opérateur confirme (touche ↻ pour actualiser).',
              'Still pending. If you confirmed, your balance will be credited '
                  'as soon as the operator confirms (tap ↻ to refresh).');
        });
      }
    });
  }

  Widget _form() {
    return _card([
      Text(
        tr('Recharge International', 'International top-up'),
        style: const TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      Text(
        tr('Orange Money ou MTN MoMo. Tu valides sur ton téléphone, le solde est '
            'crédité tout seul. 1 FCFA = 1 jeton.',
            'Orange Money or MTN MoMo. You confirm on your phone and the balance '
            'is credited automatically. 1 FCFA = 1 token.'),
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
      _label(tr('Opérateur', 'Operator')),
      Wrap(
        spacing: 8,
        children: [
          for (final o in operators)
            ChoiceChip(
              label: Text(o['label']!),
              selected: operator == o['id'],
              onSelected: (sending || waiting)
                  ? null
                  : (_) => setState(() => operator = o['id']!),
            ),
        ],
      ),
      _label(tr('Ton numéro', 'Your number')),
      TextField(
        controller: phoneCtrl,
        enabled: !sending && !waiting,
        keyboardType: TextInputType.phone,
        style: const TextStyle(color: Colors.white),
        decoration: _dec(tr('Numéro (ex : 690000000)', 'Number (e.g. 690000000)'),
            Icons.phone_android),
      ),
      _label(tr('Montant à déposer', 'Amount to deposit')),
      TextField(
        controller: amountCtrl,
        enabled: !sending && !waiting,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) => setState(() => error = null),
        style: const TextStyle(
            color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
        decoration:
            _dec(tr('Écris ton montant', 'Enter your amount'), Icons.payments)
                .copyWith(
          suffixText: 'FCFA',
          suffixStyle:
              const TextStyle(color: _gold, fontWeight: FontWeight.w800),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        tr('Minimum : ${_fmt(minAmount)} FCFA   ·   Maximum : ${_fmt(maxAmount)} FCFA',
            'Minimum: ${_fmt(minAmount)} FCFA   ·   Maximum: ${_fmt(maxAmount)} FCFA'),
        style: const TextStyle(
            color: _gold, fontSize: 13, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final p in _presets)
            ActionChip(
              label: Text(_fmt(p)),
              onPressed: (sending || waiting)
                  ? null
                  : () => setState(() {
                        amountCtrl.text = '$p';
                        error = null;
                      }),
            ),
        ],
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(error!,
              style: const TextStyle(
                  color: Color(0xFFFF8A80), fontWeight: FontWeight.w700)),
        ),
      if (done != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(done!,
              style: const TextStyle(
                  color: Color(0xFF7CFFB0), fontWeight: FontWeight.w700)),
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
          onPressed: (sending || waiting) ? null : _send,
          child: Text(
            sending
                ? '...'
                : waiting
                    ? tr('En attente de ta validation…', 'Waiting for your confirmation…')
                    : tr('Payer maintenant', 'Pay now'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ),
      ),
    ]);
  }

  Widget _history() {
    return _card([
      Row(
        children: [
          Expanded(
            child: Text(
              tr('Mes recharges International', 'My International top-ups'),
              style: const TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
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
        Text(tr('Aucune recharge pour le moment.', 'No top-ups yet.'),
            style: const TextStyle(color: Colors.white70)),
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
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              Text(_statusText('${d['status']}', deposit: true),
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [_form(), _history()]);
  }
}

// ----------------------------------------------------------------------
// Retrait
// ----------------------------------------------------------------------
class SebpayWithdrawPanel extends StatefulWidget {
  const SebpayWithdrawPanel({super.key});

  @override
  State<SebpayWithdrawPanel> createState() => _SebpayWithdrawPanelState();
}

class _SebpayWithdrawPanelState extends State<SebpayWithdrawPanel> {
  final TextEditingController amountCtrl = TextEditingController();
  final TextEditingController phoneCtrl = TextEditingController();

  List<Map<String, String>> operators = [
    {'id': 'orange', 'label': 'Orange Money'},
    {'id': 'mtn', 'label': 'MTN MoMo'},
  ];
  String operator = 'orange';
  int minAmount = 500;
  int maxAmount = 100000;

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
      final info = await Wallet.sebpayInfo();
      final ops = ((info['operators'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map((e) => {'id': '${e['id']}', 'label': '${e['label']}'})
          .toList();
      if (mounted) {
        setState(() {
          if (ops.isNotEmpty) {
            operators = ops;
            if (!ops.any((o) => o['id'] == operator)) operator = ops.first['id']!;
          }
          minAmount = (info['withdrawMin'] as num?)?.toInt() ?? minAmount;
          maxAmount = (info['withdrawMax'] as num?)?.toInt() ?? maxAmount;
        });
      }
    } catch (_) {}
    await _loadMine();
  }

  Future<void> _loadMine() async {
    try {
      final r = await Wallet.sebpayMine();
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
      setState(() => error = tr('Numéro invalide (ex : 690000000).',
          'Invalid number (e.g. 690000000).'));
      return;
    }
    setState(() {
      sending = true;
      error = null;
      done = null;
    });
    try {
      await Wallet.sebpayWithdraw(
          amount: _amount, phone: phone, operator: operator);
      if (!mounted) return;
      setState(() {
        done = tr(
            '✅ Retrait lancé. L\'argent arrive sur ton téléphone dans quelques instants.',
            '✅ Withdrawal started. The money reaches your phone shortly.');
        amountCtrl.clear();
      });
      await _loadMine();
    } catch (e) {
      if (mounted) setState(() => error = Wallet.errorText(e));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Widget _form() {
    return _card([
      Text(
        tr('Retrait International', 'International withdrawal'),
        style: const TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      Text(
        tr('Le montant est retiré de ton solde et envoyé directement sur ton '
            'compte Orange Money ou MTN MoMo.',
            'The amount is taken from your balance and sent straight to your '
            'Orange Money or MTN MoMo account.'),
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
      _label(tr('Opérateur', 'Operator')),
      Wrap(
        spacing: 8,
        children: [
          for (final o in operators)
            ChoiceChip(
              label: Text(o['label']!),
              selected: operator == o['id'],
              onSelected:
                  sending ? null : (_) => setState(() => operator = o['id']!),
            ),
        ],
      ),
      _label(tr('Numéro qui reçoit l\'argent', 'Number receiving the money')),
      TextField(
        controller: phoneCtrl,
        enabled: !sending,
        keyboardType: TextInputType.phone,
        style: const TextStyle(color: Colors.white),
        decoration: _dec(tr('Numéro (ex : 690000000)', 'Number (e.g. 690000000)'),
            Icons.phone_android),
      ),
      _label(tr('Montant à retirer', 'Amount to withdraw')),
      TextField(
        controller: amountCtrl,
        enabled: !sending,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) => setState(() => error = null),
        style: const TextStyle(
            color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
        decoration:
            _dec(tr('Écris ton montant', 'Enter your amount'), Icons.payments)
                .copyWith(
          suffixText: 'FCFA',
          suffixStyle:
              const TextStyle(color: _gold, fontWeight: FontWeight.w800),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        tr('Minimum : ${_fmt(minAmount)} FCFA   ·   Maximum : ${_fmt(maxAmount)} FCFA',
            'Minimum: ${_fmt(minAmount)} FCFA   ·   Maximum: ${_fmt(maxAmount)} FCFA'),
        style: const TextStyle(
            color: _gold, fontSize: 13, fontWeight: FontWeight.w700),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(error!,
              style: const TextStyle(
                  color: Color(0xFFFF8A80), fontWeight: FontWeight.w700)),
        ),
      if (done != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(done!,
              style: const TextStyle(
                  color: Color(0xFF7CFFB0), fontWeight: FontWeight.w700)),
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
            sending ? '...' : tr('Retirer maintenant', 'Withdraw now'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ),
      ),
    ]);
  }

  Widget _history() {
    return _card([
      Row(
        children: [
          Expanded(
            child: Text(
              tr('Mes retraits International', 'My International withdrawals'),
              style: const TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
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
        Text(tr('Aucun retrait pour le moment.', 'No withdrawals yet.'),
            style: const TextStyle(color: Colors.white70)),
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
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              Text(_statusText('${d['status']}', deposit: false),
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [_form(), _history()]);
  }
}
