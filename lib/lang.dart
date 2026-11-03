// ----------------------------------------------------------------------
// Langues de l'appli : français (par défaut) et anglais.
//
// Comment ça marche :
//  - `Text` ci-dessous remplace le Text de Flutter (les fichiers qui
//    l'utilisent importent material.dart avec « hide Text »). Il affiche le
//    texte français tel quel, ou sa traduction anglaise quand la langue est
//    « en ». La traduction se cherche dans le dictionnaire `_en` en bas.
//  - `tr('français', 'english')` sert pour les textes qui ne passent pas
//    par un Text (infobulles, étiquettes de champs...) ou qui contiennent
//    des valeurs (noms, montants).
// ----------------------------------------------------------------------

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as m show Text;
import 'package:shared_preferences/shared_preferences.dart';

/// Langue courante : fr ou en.
final ValueNotifier<String> appLang = ValueNotifier<String>('fr');

bool get isEnglish => appLang.value == 'en';

/// Récupère la langue enregistrée sur l'appareil.
Future<void> initAppLanguage() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('app_language') ?? 'fr';

  appLang.value = const ['fr', 'en'].contains(saved)
      ? saved
      : 'fr';
}

/// Change et mémorise la langue choisie.
Future<void> setAppLanguage(String code) async {
  if (!const ['fr', 'en'].contains(code)) return;

  appLang.value = code;

  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('app_language', code);
}

/// Texte dans la langue courante. Sans [en], la traduction est cherchée
/// dans le dictionnaire (ou dans les règles des messages de jeu).
String tr(String fr, [String? en]) {
  switch (appLang.value) {
    case 'en':
      return en ?? _en[fr] ?? _dynamicEn(fr) ?? fr;
    default:
      return fr;
  }
}

const List<String> _colorsFr = ['Rouge', 'Vert', 'Bleu', 'Jaune'];

/// Nom d'une couleur de joueur (0 Rouge, 1 Vert, 2 Bleu, 3 Jaune).
String colorLabel(int c) => tr(_colorsFr[c]);

/// Remplace le `Text` de Flutter : traduit automatiquement le texte.
class Text extends StatelessWidget {
  const Text(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.overflow,
    this.maxLines,
    this.softWrap,
  });

  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final TextOverflow? overflow;
  final int? maxLines;
  final bool? softWrap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: appLang,
      builder: (context, lang, _) {
        final shown = switch (lang) {
          'en' => _en[data] ?? _dynamicEn(data) ?? data,
          _ => data,
        };
        return m.Text(
          shown,
          style: style,
          textAlign: textAlign,
          overflow: overflow,
          maxLines: maxLines,
          softWrap: softWrap,
        );
      },
    );
  }
}

/// Petit sélecteur « Français | English » (affiché sur l'écran d'accueil).
class LanguageSwitcher extends StatelessWidget {
  const LanguageSwitcher({super.key});

  Widget _chip(String code, String label, String current) {
    final selected = code == current;
    return GestureDetector(
      onTap: () => setAppLanguage(code),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFC21A) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: m.Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF1A1F3A) : Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: appLang,
      builder: (context, lang, _) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white38),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 8, right: 4),
              child: Icon(Icons.language, color: Colors.white70, size: 18),
            ),
            _chip('fr', 'Français', lang),
            _chip('en', 'English', lang),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Messages du jeu avec des noms ou des chiffres dedans
// ----------------------------------------------------------------------

class _Rule {
  _Rule(this.re, this.build);
  final RegExp re;
  final String Function(Match) build;
}

String _verbEn(String? v) => v == 'a abandonné'
    ? 'has forfeited'
    : 'was declared forfeit (connection lost)';

final List<_Rule> _rules = [
  _Rule(
    RegExp(r'^(\d) ! Aucun déplacement possible\.$'),
    (x) => '${x[1]}! No move possible.',
  ),
  _Rule(
    RegExp(r'^Pilotage automatique : (\d)\.$'),
    (x) => 'Autopilot: ${x[1]}.',
  ),
  _Rule(
    RegExp(r'^🏆 (.+) remporte la partie !$'),
    (x) => '🏆 ${x[1]} wins the game!',
  ),
  _Rule(
    RegExp(
      r'^🏆 (.+) gagne : (.+) (a abandonné|est déclaré forfait \(connexion perdue\))\.$',
    ),
    (x) => '🏆 ${x[1]} wins: ${x[2]} ${_verbEn(x[3])}.',
  ),
  _Rule(
    RegExp(
      r'^(.+) (a abandonné|est déclaré forfait \(connexion perdue\))\. Au tour de (.+)\.$',
    ),
    (x) => "${x[1]} ${_verbEn(x[2])}. ${x[3]}'s turn.",
  ),
  _Rule(
    RegExp(r'^(.+) (a abandonné|est déclaré forfait \(connexion perdue\))\.$'),
    (x) => '${x[1]} ${_verbEn(x[2])}.',
  ),
];

String? _dynamicEn(String fr) {
  for (final r in _rules) {
    final hit = r.re.firstMatch(fr);
    if (hit != null) return r.build(hit);
  }
  return null;
}

// ----------------------------------------------------------------------
// Dictionnaire de traduction (Français vers Anglais)
// ----------------------------------------------------------------------

final Map<String, String> _en = {
  "Dés et Ludo by CKY": "Dice and Ludo by CKY",
  "Reprendre la partie": "Resume the game",
  "En présentiel": "In person",
  "En ligne": "Online",
  "Deux dés": "Two dice",
  "Refuser": "Decline",
  "Accepter": "Accept",
  "Inviter": "Invite",
  "Annuler": "Cancel",
  "Joueur": "Player",
  "Préparer la partie": "Set up the game",
  "Nombre de joueurs": "Number of players",
  "Lancer la partie": "Start the game",
  "Abandonner": "Forfeit",
  "Paramètres": "Settings",
  "Accueil": "Home",
  "Classement": "Ranking",
  "Fermer": "Close",
  "Rejouer": "Play again",
  "Retour": "Back",
  "Créer une partie": "Create a game",
  "Rejoindre": "Join",
  "Parties en ligne": "Online games",
  "Créer un compte": "Create an account",
  "Se connecter": "Sign in",
  "Pseudo": "Nickname",
  "E-mail": "Email",
  "Mot de passe": "Password",
  "Connecté": "Signed in",
  "Se déconnecter": "Sign out",
  "Mon solde": "My balance",
  "Recharge": "Top up",
  "Retrait": "Withdrawal",
  "Règles": "Rules",
  "Son": "Sound",
  "Nouvelle version disponible": "New version available",
  "Plus tard": "Later",
  "Télécharger": "Download",
  "Rouge": "Red",
  "Vert": "Green",
  "Bleu": "Blue",
  "Jaune": "Yellow",
};
