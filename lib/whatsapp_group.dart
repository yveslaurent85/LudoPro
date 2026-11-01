import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Lien d'invitation du groupe WhatsApp des joueurs.
const String kWhatsAppGroupUrl =
    'https://chat.whatsapp.com/HH79GJT4HGXLQKVgcudvXb?s=cl&p=a&mlu=4&ilr=4&iam=2';

const Color _waGreen = Color(0xFF25D366);

bool _inviteShown = false; // l'invitation n'apparaît qu'une fois par lancement

/// Ouvre WhatsApp (ou le navigateur) sur le groupe des joueurs.
Future<void> openWhatsAppGroup(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final ok = await launchUrl(
      Uri.parse(kWhatsAppGroupUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Impossible d\'ouvrir WhatsApp.')),
      );
    }
  } catch (_) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('Impossible d\'ouvrir WhatsApp.')),
    );
  }
}

/// Bouton permanent « Rejoindre le groupe WhatsApp » (écran d'accueil).
class WhatsAppGroupButton extends StatelessWidget {
  const WhatsAppGroupButton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: _waGreen,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        onPressed: () => openWhatsAppGroup(context),
        icon: const Icon(Icons.chat),
        label: const Text(
          'Rejoindre le groupe WhatsApp des joueurs',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ),
    );
  }
}

/// Widget invisible à placer sur l'accueil : propose une seule fois par
/// lancement de rejoindre le groupe. Le joueur peut l'ignorer : le bouton de
/// l'accueil et l'entrée du menu restent toujours disponibles.
class WhatsAppInvite extends StatefulWidget {
  const WhatsAppInvite({super.key});

  @override
  State<WhatsAppInvite> createState() => _WhatsAppInviteState();
}

class _WhatsAppInviteState extends State<WhatsAppInvite> {
  @override
  void initState() {
    super.initState();
    if (!_inviteShown) {
      // Un peu après l'ouverture, pour ne pas gêner l'alerte de mise à jour.
      Future<void>.delayed(const Duration(seconds: 4), _show);
    }
  }

  Future<void> _show() async {
    if (!mounted || _inviteShown) return;
    _inviteShown = true;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0B2FA6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Groupe WhatsApp Katika',
          style: TextStyle(
            color: Color(0xFFFFE082),
            fontWeight: FontWeight.w900,
          ),
        ),
        content: const Text(
          'Rejoins le groupe des joueurs : parties, tournois, astuces et '
          'actualités. Tu pourras toujours le rejoindre depuis le bouton vert '
          'de l\'accueil.',
          style: TextStyle(color: Colors.white, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Plus tard',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _waGreen,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              openWhatsAppGroup(context);
            },
            child: const Text('Rejoindre'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
