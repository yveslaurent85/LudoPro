import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'accounts.dart';

/// Dépôt par Mobile Money (MTN / Orange) via Campay : le joueur saisit un
/// montant et son numéro, reçoit une demande de paiement sur son téléphone et
/// valide avec son code PIN. Le solde est crédité par le serveur.
class DepositScreen extends StatefulWidget {
  const DepositScreen({super.key});

  @override
  State<DepositScreen> createState() => _DepositScreenState();
}

class _DepositScreenState extends State<DepositScreen> {
  static const Color _gold = Color(0xFFFFC21A);
  static const int _min = 25;
  static const int _max = 250000;
  static const List<int> _presets = [25, 100, 500, 1000, 2000, 5000];

  final TextEditingController amountCtrl = TextEditingController();
  final TextEditingController phoneCtrl = TextEditingController();

  bool sending = false;
  String? error;
  String? depositId;
  int depositAmount = 0;

  /// '' = formulaire, sinon : pending, credited, failed, mismatch.
  String status = '';
  bool timedOut = false;

  Timer? _timer;
  int _ticks = 0;

  @override
  void dispose() {
    _timer?.cancel();
    amountCtrl.dispose();
    phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (sending) return;
    final amount = int.tryParse(amountCtrl.text.trim()) ?? 0;
    final phone = phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (amount < _min || amount > _max) {
      setState(() => error = 'Montant entre $_min et $_max FCFA.');
      return;
    }
    final okPhone = RegExp(r'^(237)?6\d{8}$').hasMatch(phone);
    if (!okPhone) {
      setState(() => error = 'Numéro MTN ou Orange invalide (ex : 670000000).');
      return;
    }
    setState(() {
      sending = true;
      error = null;
    });
    try {
      final res = await Wallet.campayDeposit(amount: amount, phone: phone);
      if (!mounted) return;
      setState(() {
        depositId = res['depositId'] as String?;
        depositAmount = amount;
        status = 'pending';
        timedOut = false;
      });
      _startPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() => error = Wallet.errorText(e));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  void _startPolling() {
    _timer?.cancel();
    _ticks = 0;
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _check());
  }

  Future<void> _check() async {
    final id = depositId;
    if (id == null) return;
    _ticks++;
    try {
      final res = await Wallet.campayDepositStatus(id);
      if (!mounted) return;
      final st = (res['status'] as String?) ?? 'pending';
      setState(() => status = st);
      if (st != 'pending') {
        _timer?.cancel();
        return;
      }
    } catch (_) {
      // Réseau coupé un instant : on réessaie au prochain tour.
    }
    if (_ticks >= 90) {
      // Environ 3 minutes : on arrête d'interroger. Le serveur créditera
      // quand même le solde dès que Campay confirme le paiement.
      _timer?.cancel();
      if (mounted) setState(() => timedOut = true);
    }
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      status = '';
      depositId = null;
      error = null;
      timedOut = false;
      amountCtrl.clear();
    });
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

  Widget _balance() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    return _card([
      const Text(
        'Ton solde',
        style: TextStyle(color: Colors.white70, fontSize: 12),
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

  Widget _form() {
    return _card([
      const Text(
        'Déposer par Mobile Money',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 4),
      const Text(
        'MTN ou Orange. 1 FCFA = 1 jeton. De 25 à 250000 FCFA.',
        style: TextStyle(color: Colors.white70, fontSize: 12),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final p in _presets)
            ActionChip(
              label: Text('$p'),
              onPressed: sending ? null : () => amountCtrl.text = '$p',
            ),
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        controller: amountCtrl,
        enabled: !sending,
        keyboardType: TextInputType.number,
        style: const TextStyle(color: Colors.white),
        decoration: _dec('Montant (FCFA)', Icons.payments),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: phoneCtrl,
        enabled: !sending,
        keyboardType: TextInputType.phone,
        style: const TextStyle(color: Colors.white),
        decoration: _dec('Numéro (ex : 670000000)', Icons.phone_android),
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
      const SizedBox(height: 14),
      SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF22B14C),
            foregroundColor: Colors.white,
          ),
          onPressed: sending ? null : _start,
          child: Text(
            sending ? '...' : 'Déposer',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ),
      ),
    ]);
  }

  Widget _result() {
    final Widget content;
    if (status == 'credited') {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '✅ Dépôt réussi !',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${Wallet.format(depositAmount)} ajoutés à ton solde.',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      );
    } else if (status == 'failed') {
      content = const Text(
        '❌ Le paiement a échoué ou a été refusé. Aucun montant n\'a été ajouté.',
        style: TextStyle(
          color: Color(0xFFFF8A80),
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      );
    } else if (status == 'mismatch') {
      content = const Text(
        '⚠️ Le montant reçu ne correspond pas à la demande. Contacte le support.',
        style: TextStyle(
          color: Color(0xFFFF8A80),
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!timedOut)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              if (!timedOut) const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Confirme le paiement sur ton téléphone',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            timedOut
                ? 'Toujours en attente. Si tu as validé, ton solde sera mis à '
                    'jour automatiquement.'
                : 'Tape ton code PIN Mobile Money pour valider '
                    '${Wallet.format(depositAmount)}.',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      );
    }
    return _card([
      content,
      if (status != 'pending' || timedOut) ...[
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton(
            onPressed: _reset,
            child: const Text('Nouveau dépôt'),
          ),
        ),
      ],
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
                    const Expanded(
                      child: Text(
                        '💰 Déposer',
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
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  children: [
                    _balance(),
                    if (status.isEmpty) _form() else _result(),
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
