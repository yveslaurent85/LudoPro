import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:url_launcher/url_launcher.dart';

import 'accounts.dart';
import 'admin_manual.dart';
import 'courses_screen.dart';
import 'lang.dart';
import 'promo_screen.dart';

/// Rôle du compte connecté (mémorisé pour éviter de le redemander).
class StaffRole {
  static bool cashier = false;
  static bool admin = false;

  static Future<void> refresh() async {
    try {
      final r = await Wallet.myRole();
      cashier = r['cashier'] == true;
      admin = r['admin'] == true;
    } catch (_) {}
  }
}

/// Entoure l'accueil : une caissière ne voit que son espace.
class CashierGate extends StatefulWidget {
  const CashierGate({super.key, required this.child});
  final Widget child;

  @override
  State<CashierGate> createState() => _CashierGateState();
}

class _CashierGateState extends State<CashierGate> {
  bool _cashier = false;
  String? _uid;

  @override
  void initState() {
    super.initState();
    try {
      FirebaseAuth.instance.authStateChanges().listen((u) async {
        if (u == null) {
          StaffRole.cashier = false;
          StaffRole.admin = false;
          if (mounted) setState(() {
            _cashier = false;
            _uid = null;
          });
          return;
        }
        if (u.uid == _uid) return;
        _uid = u.uid;
        await StaffRole.refresh();
        if (mounted) setState(() => _cashier = StaffRole.cashier);
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) =>
      _cashier ? const CashierHome() : widget.child;
}

/// Espace caissière : courses (paris + tickets), recharges/retraits, code promo.
class CashierHome extends StatelessWidget {
  const CashierHome({super.key});

  static const Color _gold = Color(0xFFFFC21A);

  Widget _tile(BuildContext c, String emoji, String title, String sub, Widget page) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => page)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Text(emoji, style: const TextStyle(fontSize: 30)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                  Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ]),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B3D2E),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(children: [
              const Expanded(
                child: Text('Espace caissière',
                    style: TextStyle(color: _gold, fontSize: 22, fontWeight: FontWeight.w900)),
              ),
              const LanguageSwitcher(),
              IconButton(
                tooltip: tr('Déconnexion', 'Log out'),
                icon: const Icon(Icons.logout, color: Colors.white),
                onPressed: () async {
                  StaffRole.cashier = false;
                  await FirebaseAuth.instance.signOut();
                },
              ),
            ]),
            const SizedBox(height: 6),
            StreamBuilder<int>(
              stream: Wallet.watch(FirebaseAuth.instance.currentUser?.uid ?? ''),
              builder: (c, s) => Text(
                tr('Solde : ${s.data ?? 0} FCFA', 'Balance: ${s.data ?? 0} FCFA'),
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 16),
            _tile(context, '🏇', tr('Paris courses', 'Race bets'),
                tr('Placer un pari et imprimer le ticket', 'Place a bet and print the ticket'), const CoursesPage()),
            _tile(context, '💵', tr('Recharges et retraits', 'Deposits & withdrawals'),
                tr('Valider après vérification', 'Validate after checking'), const AdminManualScreen()),
            _tile(context, '🎁', tr('Mon code promo', 'My promo code'),
                tr('Mon code et mon lien de redirection', 'My code and referral link'), const PromoScreen()),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => launchUrl(
                Uri.parse('https://play.google.com/store/apps/details?id=ru.a402d.rawbtprinter'),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.print, color: Colors.white70),
              label: Text(
                tr('Imprimante : installer l\'appli RawBT', 'Printer: install the RawBT app'),
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
