import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'accounts.dart';

/// Transfert d'argent de compte à compte : on saisit le pseudo (ou le code
/// promo) du destinataire et le montant. Le serveur débite et crédite.
class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key});

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  static const Color _gold = Color(0xFFFFC21A);
  static const int _min = 25;
  static const int _max = 250000;

  final TextEditingController toCtrl = TextEditingController();
  final TextEditingController amountCtrl = TextEditingController();

  bool sending = false;
  String? error;
  String? success;

  late final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void dispose() {
    toCtrl.dispose();
    amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (sending) return;
    final to = toCtrl.text.trim();
    final amount = int.tryParse(amountCtrl.text.trim()) ?? 0;
    if (to.isEmpty) {
      setState(() {
        error = 'Indique le pseudo ou le code promo du destinataire.';
        success = null;
      });
      return;
    }
    if (amount < _min || amount > _max) {
      setState(() {
        error = 'Montant entre $_min et $_max FCFA.';
        success = null;
      });
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Confirmer le transfert'),
        content: Text('Envoyer ${Wallet.format(amount)} à « $to » ?\n'
            'Cette opération est définitive.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(true),
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      sending = true;
      error = null;
      success = null;
    });
    try {
      final res = await Wallet.transfer(to, amount);
      if (!mounted) return;
      setState(() {
        success = '✅ ${Wallet.format(amount)} envoyés à ${res['toName']}.';
        toCtrl.clear();
        amountCtrl.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => error = Wallet.errorText(e));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: Colors.white.withOpacity(0.12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      );

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
                        '🔁 Transférer de l\'argent',
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
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        color: Colors.white.withOpacity(0.12),
                        border: Border.all(color: _gold),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Mon solde',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                          StreamBuilder<int>(
                            stream: Wallet.watch(uid),
                            builder: (context, snap) => Text(
                              '💰 ${Wallet.format(snap.data ?? 0)}',
                              style: const TextStyle(
                                color: _gold,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Destinataire',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: toCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: _dec('Pseudo ou code promo du joueur'),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Montant (FCFA)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: _dec('Entre $_min et $_max'),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF22B14C),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: sending ? null : _send,
                        child: Text(
                          sending ? 'Envoi...' : 'Envoyer',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          error!,
                          style: const TextStyle(
                            color: Color(0xFFFF8A80),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (success != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          success!,
                          style: const TextStyle(
                            color: Color(0xFFA5D6A7),
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    const Text(
                      'Le destinataire est retrouvé grâce à son pseudo ou à son '
                      'code promo. Vérifie bien l\'orthographe : un transfert '
                      'ne peut pas être annulé.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
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
