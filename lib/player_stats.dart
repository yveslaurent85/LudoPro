import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'accounts.dart';

/// Statistiques d'un joueur : solde, inscription, parties, montants.
/// Les compteurs viennent du serveur (users/{uid}) et sont mis à jour à la
/// fin de chaque partie terminée avec un gagnant (en ligne et en présentiel).
class PlayerStats {
  PlayerStats({
    required this.name,
    this.balance = 0,
    this.createdAt,
    this.played = 0,
    this.won = 0,
    this.lost = 0,
    this.staked = 0,
    this.wonAmt = 0,
    this.lostAmt = 0,
  });

  final String name;
  final int balance;
  final DateTime? createdAt;
  final int played; // parties jouées
  final int won; // parties gagnées
  final int lost; // parties perdues
  final int staked; // total des mises jouées
  final int wonAmt; // total gagné (gains reçus)
  final int lostAmt; // total perdu (mises perdues)

  /// Pourcentage de victoires (une décimale).
  double get winRate => played > 0 ? (won * 1000 ~/ played) / 10 : 0;

  static int _i(dynamic v) => v is num ? v.toInt() : 0;

  static DateTime? _date(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    return null;
  }

  /// Ligne renvoyée par le serveur (tableau de bord administrateur).
  factory PlayerStats.fromRow(Map<String, dynamic> r) {
    final pseudo = '${r['pseudo'] ?? ''}'.trim();
    final uid = '${r['uid'] ?? ''}';
    return PlayerStats(
      name: pseudo.isNotEmpty
          ? pseudo
          : (uid.length > 8 ? '${uid.substring(0, 8)}…' : uid),
      balance: _i(r['balance']),
      createdAt: _date(r['createdAt']),
      played: _i(r['played']),
      won: _i(r['won']),
      lost: _i(r['lost']),
      staked: _i(r['staked']),
      wonAmt: _i(r['wonAmt']),
      lostAmt: _i(r['lostAmt']),
    );
  }

  /// Document users/{uid} lu directement (menu du joueur).
  factory PlayerStats.fromUserDoc(Map<String, dynamic>? d, User? u) {
    final m = d ?? const <String, dynamic>{};
    final pseudo = '${m['pseudo'] ?? u?.displayName ?? ''}'.trim();
    return PlayerStats(
      name: pseudo.isNotEmpty ? pseudo : (u?.email ?? 'Joueur'),
      balance: _i(m['balance']),
      createdAt: _date(m['createdAt']) ?? u?.metadata.creationTime,
      played: _i(m['statPlayed']),
      won: _i(m['statWon']),
      lost: _i(m['statLost']),
      staked: _i(m['statStaked']),
      wonAmt: _i(m['statWonAmt']),
      lostAmt: _i(m['statLostAmt']),
    );
  }
}

String _two(int n) => n < 10 ? '0$n' : '$n';

String statDate(DateTime? d) =>
    d == null ? 'inconnue' : '${_two(d.day)}/${_two(d.month)}/${d.year}';

String statDateTime(DateTime? d) => d == null
    ? 'inconnue'
    : '${_two(d.day)}/${_two(d.month)}/${d.year} ${_two(d.hour)}:${_two(d.minute)}';

/// Cartes de détails d'un joueur (utilisées dans le menu et par l'admin).
class PlayerStatsView extends StatelessWidget {
  const PlayerStatsView({super.key, required this.stats});

  final PlayerStats stats;

  static const Color _gold = Color(0xFFFFC21A);

  Widget _tile(String label, String value, {Color color = Colors.white}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withOpacity(0.12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final rate = s.winRate == s.winRate.roundToDouble()
        ? '${s.winRate.toInt()} %'
        : '${s.winRate.toStringAsFixed(1)} %';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white.withOpacity(0.12),
            border: Border.all(color: _gold, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Solde',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  Wallet.format(s.balance),
                  style: const TextStyle(
                    color: _gold,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Inscrit le ${statDate(s.createdAt)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.3,
          children: [
            _tile('Parties jouées', '${s.played}'),
            _tile('Pourcentage de victoires', rate, color: _gold),
            _tile('Parties gagnées', '${s.won}',
                color: const Color(0xFF7CFFB0)),
            _tile('Parties perdues', '${s.lost}',
                color: const Color(0xFFFF8A80)),
            _tile('Total montant joué', Wallet.format(s.staked)),
            _tile('Total montant gagné', Wallet.format(s.wonAmt),
                color: const Color(0xFF7CFFB0)),
            _tile('Total montant perdu', Wallet.format(s.lostAmt),
                color: const Color(0xFFFF8A80)),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'Compteurs mis à jour à la fin de chaque partie terminée avec un '
          'gagnant (en ligne et en présentiel). Total joué = mises engagées ; '
          'total gagné = gains reçus ; total perdu = mises des parties perdues.',
          style: TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ],
    );
  }
}

BoxDecoration _bg() => const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF1F5BFF), Color(0xFF0B2FA6), Color(0xFF061A66)],
      ),
    );

Widget _header(BuildContext context, String title, {Widget? trailing}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
    child: Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (trailing != null) trailing,
      ],
    ),
  );
}

/// Menu → « Détails » : mes statistiques (mises à jour en direct).
class MyDetailsScreen extends StatelessWidget {
  const MyDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: _bg(),
        child: SafeArea(
          child: Column(
            children: [
              _header(context, '📊 Mes détails'),
              Expanded(
                child: user == null
                    ? const Center(
                        child: Text(
                          'Connecte-toi pour voir tes détails.',
                          style: TextStyle(color: Colors.white),
                        ),
                      )
                    : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(user.uid)
                            .snapshots(),
                        builder: (context, snap) {
                          if (!snap.hasData && !snap.hasError) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final stats = PlayerStats.fromUserDoc(
                            snap.data?.data(),
                            user,
                          );
                          return ListView(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                            children: [PlayerStatsView(stats: stats)],
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
}

/// Détails d'un joueur (ouvert depuis la liste de l'administrateur).
class PlayerDetailScreen extends StatelessWidget {
  const PlayerDetailScreen({super.key, required this.stats});

  final PlayerStats stats;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: _bg(),
        child: SafeArea(
          child: Column(
            children: [
              _header(context, '👤 Joueur'),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  children: [PlayerStatsView(stats: stats)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Administrateur : tous les joueurs inscrits. Toucher un joueur affiche
/// tous ses détails.
class AdminPlayersScreen extends StatefulWidget {
  const AdminPlayersScreen({super.key});

  @override
  State<AdminPlayersScreen> createState() => _AdminPlayersScreenState();
}

class _AdminPlayersScreenState extends State<AdminPlayersScreen> {
  static const Color _gold = Color(0xFFFFC21A);

  bool loading = true;
  String? error;
  List<PlayerStats> players = [];
  String sort = 'recent'; // recent | balance | played | won
  final TextEditingController searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final res = await Wallet.adminPlayers();
      final list = (res['players'] as List?) ?? const [];
      if (!mounted) return;
      setState(() {
        players = [
          for (final r in list)
            PlayerStats.fromRow(Map<String, dynamic>.from(r as Map)),
        ];
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

  List<PlayerStats> _shown() {
    final q = searchCtrl.text.trim().toLowerCase();
    final l = players
        .where((p) => q.isEmpty || p.name.toLowerCase().contains(q))
        .toList();
    int cmpDate(PlayerStats a, PlayerStats b) {
      final x = a.createdAt, y = b.createdAt;
      if (x == null && y == null) return 0;
      if (x == null) return 1;
      if (y == null) return -1;
      return y.compareTo(x);
    }

    switch (sort) {
      case 'balance':
        l.sort((a, b) => b.balance.compareTo(a.balance));
        break;
      case 'played':
        l.sort((a, b) => b.played.compareTo(a.played));
        break;
      case 'won':
        l.sort((a, b) => b.won.compareTo(a.won));
        break;
      default:
        l.sort(cmpDate);
    }
    return l;
  }

  Widget _chip(String label, String key) => ChoiceChip(
        label: Text(label),
        selected: sort == key,
        onSelected: (_) => setState(() => sort = key),
      );

  Widget _row(PlayerStats p) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlayerDetailScreen(stats: p),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withOpacity(0.1),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 18,
              backgroundColor: Color(0xFF22B14C),
              child: Icon(Icons.person, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Inscrit le ${statDate(p.createdAt)} · '
                    '${p.played} partie${p.played > 1 ? 's' : ''}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              Wallet.format(p.balance),
              style: const TextStyle(
                color: _gold,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown();
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: _bg(),
        child: SafeArea(
          child: Column(
            children: [
              _header(
                context,
                '👥 Joueurs inscrits',
                trailing: IconButton(
                  onPressed: loading ? null : _load,
                  icon: const Icon(Icons.refresh, color: Colors.white),
                ),
              ),
              Expanded(
                child: loading && players.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    error!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Color(0xFFFF8A80),
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  ElevatedButton(
                                    onPressed: _load,
                                    child: const Text('Réessayer'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding:
                                  const EdgeInsets.fromLTRB(16, 8, 16, 28),
                              children: [
                                TextField(
                                  controller: searchCtrl,
                                  onChanged: (_) => setState(() {}),
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: 'Rechercher un pseudo',
                                    hintStyle:
                                        const TextStyle(color: Colors.white54),
                                    prefixIcon: const Icon(Icons.search,
                                        color: Colors.white54),
                                    filled: true,
                                    fillColor: Colors.white.withOpacity(0.12),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    _chip('Récents', 'recent'),
                                    _chip('Solde', 'balance'),
                                    _chip('Parties', 'played'),
                                    _chip('Victoires', 'won'),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${shown.length} joueur'
                                  '${shown.length > 1 ? 's' : ''}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                for (final p in shown) _row(p),
                                if (shown.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 12),
                                    child: Text(
                                      'Aucun joueur trouvé.',
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                  ),
                              ],
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
