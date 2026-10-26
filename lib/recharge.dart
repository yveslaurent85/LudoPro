
import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'accounts.dart';

/// Recharge Katika via CamPay et le Cloudflare Worker.
/// Le serveur vérifie le paiement et crédite le compte dans Firestore.
class RechargeScreen extends StatefulWidget {
  const RechargeScreen({super.key});

  @override
  State<RechargeScreen> createState() => _RechargeScreenState();
}

class _RechargeScreenState extends State<RechargeScreen> {
  static const List<int> quick = [25, 1000, 2000, 5000];

  static const String workerUrl =
      'https://katika-api.ychachouang.workers.dev';

  final amountCtrl = TextEditingController(text: '1000');
  final phoneCtrl = TextEditingController();

  bool busy = false;
  bool waiting = false;
  String? info;
  String? error;

  Timer? poll;
  int tries = 0;
  bool checkingStatus = false;

  @override
  void dispose() {
    poll?.cancel();
    amountCtrl.dispose();
    phoneCtrl.dispose();
    super.dispose();
  }

  /// Envoie une requête authentifiée au Cloudflare Worker.
  Future<Map<String, dynamic>> _workerPost(
    String endpoint,
    Map<String, dynamic> payload,
  ) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception(
        'Connecte-toi à ton compte Katika avant de recharger.',
      );
    }

    final token = await user.getIdToken();

    if (token == null || token.isEmpty) {
      throw Exception(
        'Session expirée. Déconnecte-toi puis reconnecte-toi.',
      );
    }

    final response = await http
        .post(
          Uri.parse('$workerUrl/$endpoint'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 30));

    Map<String, dynamic> body;

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException('Réponse invalide');
      }
      body = Map<String, dynamic>.from(decoded);
    } catch (_) {
      throw Exception(
        'Réponse invalide du serveur Katika '
        '(HTTP ${response.statusCode}).',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = body['error']?.toString();
      throw Exception(
        message != null && message.isNotEmpty
            ? message
            : 'Erreur du serveur (HTTP ${response.statusCode}).',
      );
    }

    if (body['error'] != null) {
      throw Exception(body['error'].toString());
    }

    // Le Worker renvoie normalement {"data": {...}}.
    final result = body['data'] ?? body;

    if (result is! Map) {
      throw Exception('Les données reçues du serveur sont invalides.');
    }

    return Map<String, dynamic>.from(result);
  }

  String _errorMessage(Object e) {
    var message = e.toString();

    if (message.startsWith('Exception: ')) {
      message = message.substring('Exception: '.length);
    }

    if (message.contains('TimeoutException')) {
      return 'Le serveur tarde à répondre. Vérifie ta connexion et réessaie.';
    }

    if (message.contains('SocketException') ||
        message.contains('ClientException')) {
      return 'Connexion impossible au serveur. Vérifie Internet.';
    }

    return message;
  }

  Future<void> _start() async {
    FocusScope.of(context).unfocus();

    final amount = int.tryParse(amountCtrl.text.trim()) ?? 0;
    final phone = phoneCtrl.text.replaceAll(RegExp(r'\D'), '');

    if (amount < 25) {
      setState(() {
        error = 'Montant minimum : 25 FCFA.';
        info = null;
      });
      return;
    }

    if (amount > 500000) {
      setState(() {
        error = 'Montant maximum : 500 000 FCFA.';
        info = null;
      });
      return;
    }

    if (!(phone.length == 9 && phone.startsWith('6'))) {
      setState(() {
        error = 'Entre un numéro camerounais à 9 chiffres commençant par 6.';
        info = null;
      });
      return;
    }

    if (FirebaseAuth.instance.currentUser == null) {
      setState(() {
        error = 'Connecte-toi à ton compte Katika avant de recharger.';
        info = null;
      });
      return;
    }

    poll?.cancel();

    setState(() {
      busy = true;
      waiting = false;
      checkingStatus = false;
      error = null;
      info = null;
    });

    try {
      final result = await _workerPost(
        'campayDeposit',
        {
          'amount': amount,
          'phone': phone,
        },
      );

      final depositId = result['depositId']?.toString();

      if (depositId == null || depositId.isEmpty) {
        throw Exception(
          'Le serveur n’a pas retourné la référence de recharge.',
        );
      }

      if (!mounted) return;

      setState(() {
        busy = false;
        waiting = true;
        info = 'Demande envoyée. Valide le paiement sur ton téléphone '
            'si une notification CamPay apparaît. '
            'Nous vérifions ensuite la confirmation.';
      });

      _startPolling(depositId);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        busy = false;
        waiting = false;
        error = _errorMessage(e);
      });
    }
  }

  void _startPolling(String depositId) {
    tries = 0;
    checkingStatus = false;
    poll?.cancel();

    poll = Timer.periodic(const Duration(seconds: 4), (timer) async {
      if (!mounted || checkingStatus) return;

      tries++;

      if (tries > 30) {
        timer.cancel();

        if (!mounted) return;

        setState(() {
          waiting = false;
          info = null;
          error = 'La confirmation prend plus de temps que prévu. '
              'Ne relance pas immédiatement le paiement. '
              'Vérifie d’abord si ton compte Mobile Money a été débité, '
              'puis réessaie de vérifier plus tard.';
        });
        return;
      }

      checkingStatus = true;

      try {
        final result = await _workerPost(
          'campayDepositStatus',
          {'depositId': depositId},
        );

        final status = result['status']?.toString() ?? 'pending';

        if (status == 'pending' || status == 'unknown') {
          return;
        }

        timer.cancel();

        if (!mounted) return;

        setState(() {
          waiting = false;

          if (status == 'credited') {
            info = '✅ Recharge confirmée ! '
                'Ton solde a été mis à jour par le serveur.';
            error = null;
          } else if (status == 'mismatch') {
            info = null;
            error = 'Le montant ou la référence du paiement doit être vérifié. '
                'Contacte le support Katika avant de refaire un paiement.';
          } else if (status == 'failed') {
            info = null;
            error = 'Le paiement a échoué ou a été refusé. '
                'Vérifie ton compte Mobile Money avant de réessayer.';
          } else {
            info = null;
            error = 'Statut de paiement inattendu : $status. '
                'Contacte le support Katika si nécessaire.';
          }
        });
      } catch (_) {
        // Une erreur réseau temporaire ne doit pas annuler
        // la vérification. Le prochain passage réessaiera.
      } finally {
        checkingStatus = false;
      }
    });
  }

  InputDecoration _dec(
    String label,
    IconData icon, {
    String? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      suffixText: suffix,
      suffixStyle: const TextStyle(color: Colors.white70),
      labelStyle: const TextStyle(color: Colors.white70),
      prefixIcon: Icon(icon, color: Colors.white70),
      filled: true,
      fillColor: Colors.white.withOpacity(0.12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.white30),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: Color(0xFFFFC21A),
          width: 2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locked = busy || waiting;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1F5BFF),
              Color(0xFF0B2FA6),
              Color(0xFF061A66),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                      ),
                    ),
                    const Expanded(
                      child: Text(
                        'Recharger mon compte',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Orange Money ou MTN MoMo : l’opérateur est détecté '
                  'd’après ton numéro.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final q in quick)
                      ChoiceChip(
                        label: Text('$q'),
                        selected: amountCtrl.text == '$q',
                        onSelected: locked
                            ? null
                            : (_) {
                                setState(() {
                                  amountCtrl.text = '$q';
                                  error = null;
                                });
                              },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  enabled: !locked,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  onChanged: (_) => setState(() {}),
                  decoration: _dec(
                    'Montant',
                    Icons.payments,
                    suffix: Wallet.currency,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  enabled: !locked,
                  keyboardType: TextInputType.phone,
                  maxLength: 9,
                  style: const TextStyle(color: Colors.white),
                  decoration: _dec(
                    'Numéro Orange / MTN (9 chiffres)',
                    Icons.phone,
                  ).copyWith(
                    counterText: '',
                    prefixText: '+237 ',
                    prefixStyle: const TextStyle(color: Colors.white70),
                  ),
                ),
                if (info != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    info!,
                    style: const TextStyle(
                      color: Color(0xFFFFE082),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (waiting) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  const Text(
                    'Vérification automatique du paiement…',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    error!,
                    style: const TextStyle(
                      color: Color(0xFFFF8A80),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF22B14C),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: locked ? null : _start,
                    child: Text(
                      busy
                          ? 'Connexion au serveur…'
                          : waiting
                              ? 'En attente de confirmation…'
                              : 'Recharger',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
