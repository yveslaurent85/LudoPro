import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'lang.dart';
import 'share_game.dart';

/// Bouton « Partager » d'une salle d'attente : WhatsApp, WhatsApp Business,
/// Telegram, SMS ou copie du lien. Le lien ouvre Katika et propose de
/// rejoindre la partie.
class ShareMenuButton extends StatelessWidget {
  const ShareMenuButton({super.key, required this.collection, required this.gameId});

  /// games (Ludo), deuxdes, songo, damier ou cards.
  final String collection;
  final String gameId;

  Future<void> _open(BuildContext context, String choice) async {
    final msg = await loadShareMessage(collection, gameId);
    if (!context.mounted) return;
    if (msg == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Partie introuvable.', 'Game not found.'))),
      );
      return;
    }
    final link = shareJoinLink(collection, gameId);
    final text = Uri.encodeComponent(msg);
    Future<bool> go(String url) async {
      try {
        return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    }

    switch (choice) {
      case 'wa':
        if (!await go('https://wa.me/?text=$text')) await Clipboard.setData(ClipboardData(text: msg));
        break;
      case 'wab':
        // WhatsApp Business (Android) ; sinon WhatsApp normal.
        final ok = await go('intent://send?text=$text#Intent;scheme=whatsapp;package=com.whatsapp.w4b;end');
        if (!ok) await go('https://wa.me/?text=$text');
        break;
      case 'tg':
        await go('https://t.me/share/url?url=${Uri.encodeComponent(link)}&text=${Uri.encodeComponent(msg.split('\n').first)}');
        break;
      case 'sms':
        await go('sms:?body=$text');
        break;
      case 'copy':
        await Clipboard.setData(ClipboardData(text: link));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr('Lien copié', 'Link copied'))),
          );
        }
        break;
    }
  }

  PopupMenuItem<String> _item(String v, IconData icon, Color c, String label) => PopupMenuItem<String>(
        value: v,
        child: Row(children: [
          Icon(icon, color: c),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 16)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (v) => _open(context, v),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      itemBuilder: (_) => [
        _item('wa', Icons.chat, const Color(0xFF25D366), 'WhatsApp'),
        _item('wab', Icons.business_center, const Color(0xFF128C7E), 'WhatsApp Business'),
        _item('tg', Icons.send, const Color(0xFF229ED9), 'Telegram'),
        _item('sms', Icons.sms, const Color(0xFF6A1B9A), 'SMS'),
        const PopupMenuDivider(),
        _item('copy', Icons.copy, const Color(0xFF1E6BFF), tr('Copier le lien', 'Copy link')),
      ],
      child: Container(
        height: 52,
        margin: const EdgeInsets.only(top: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF2F6BFF),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.share, color: Colors.white),
          const SizedBox(width: 10),
          Text(tr('Partager le lien de la partie', 'Share the game link'),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
        ]),
      ),
    );
  }
}
