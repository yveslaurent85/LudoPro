import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'accounts.dart';

/// Historique des parties du joueur connecté (écrit par le serveur
/// à la fin de chaque partie : users/{uid}/history).
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  static String _two(int n) => n < 10 ? '0$n' : '$n';

  static String _date(dynamic t) {
    if (t is! Timestamp) return '';
    final d = t.toDate();
    return '${_two(d.day)}/${_two(d.month)}/${d.year} '
        '${_two(d.hour)}:${_two(d.minute)}';
  }

  Widget _stat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withOpacity(0.12),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
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
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    const Text(
                      'Historique des parties',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: uid == null
                    ? const Center(
                        child: Text(
                          'Connecte-toi pour voir ton historique.',
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .collection('history')
                            .orderBy('createdAt', descending: true)
                            .limit(50)
                            .snapshots(),
                        builder: (context, snap) {
                          if (snap.hasError) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  "Impossible de charger l'historique. "
                                  'Vérifie les règles Firestore.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Color(0xFFFF8A80)),
                                ),
                              ),
                            );
                          }
                          if (!snap.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final docs = snap.data!.docs;
                          if (docs.isEmpty) {
                            return const Center(
                              child: Text(
                                "Aucune partie terminée pour l'instant.",
                                style: TextStyle(color: Colors.white70),
                              ),
                            );
                          }

                          int wins = 0;
                          int net = 0;
                          for (final d in docs) {
                            final x = d.data();
                            if (x['won'] == true) wins++;
                            net += (x['net'] as num?)?.toInt() ?? 0;
                          }

                          return ListView(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                            children: [
                              Row(
                                children: [
                                  _stat('Parties', '${docs.length}',
                                      Colors.white),
                                  _stat('Victoires', '$wins',
                                      const Color(0xFF55E05A)),
                                  _stat(
                                    'Bilan',
                                    '${net >= 0 ? '+' : ''}$net',
                                    net >= 0
                                        ? const Color(0xFFFFE082)
                                        : const Color(0xFFFF8A80),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              for (final doc in docs) _entry(doc.data()),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _entry(Map<String, dynamic> x) {
    final won = x['won'] == true;
    final net = (x['net'] as num?)?.toInt() ?? 0;
    final jackpot = (x['jackpot'] as num?)?.toInt() ?? 0;
    final stake = (x['stake'] as num?)?.toInt() ?? 0;
    final players = ((x['players'] as List?) ?? const []).join(' • ');
    final color = won ? const Color(0xFF55E05A) : const Color(0xFFFF8A80);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.8), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(won ? '🏆' : '❌', style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  won ? 'Victoire' : 'Défaite',
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_date(x['createdAt'])} • '
                  '${x['mode'] == 'online' ? 'En ligne' : 'Présentiel'}'
                  '${x['team'] == true ? ' • 2v2' : ''}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                if (players.isNotEmpty)
                  Text(
                    players,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                Text(
                  stake == 0 ? 'Partie gratuite' : 'Mise : ${Wallet.format(stake)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                if (jackpot > 0)
                  Text(
                    '🎰 Jackpot : +${Wallet.format(jackpot)}',
                    style: const TextStyle(
                      color: Color(0xFFFFE082),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            '${net >= 0 ? '+' : ''}$net',
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
