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
//  - Pour ajouter un texte : ajouter une ligne « français »: « english » dans
//    le dictionnaire. Pour ajouter une 3e langue : même principe.
// ----------------------------------------------------------------------

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as m show Text;

/// Langue courante : 'fr' ou 'en'.
final ValueNotifier<String> appLang = ValueNotifier<String>('fr');

bool get isEnglish => appLang.value == 'en';

/// Texte dans la langue courante. Sans [en], la traduction est cherchée
/// dans le dictionnaire (ou dans les règles des messages de jeu).
String tr(String fr, [String? en]) {
  if (appLang.value != 'en') return fr;
  return en ?? _en[fr] ?? _dynamicEn(fr) ?? fr;
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
        final shown = lang == 'en' ? (_en[data] ?? _dynamicEn(data) ?? data) : data;
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
      onTap: () => appLang.value = code,
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
// (ils restent en français dans la partie en ligne pour que tous les
// joueurs reçoivent le même texte ; chacun les voit dans sa langue).
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
// Dictionnaire français -> anglais
// ----------------------------------------------------------------------

final Map<String, String> _en = {
  "Dés et Ludo by CKY": "Dice and Ludo by CKY",
  "Reprendre la partie": "Resume the game",
  "Le pilote automatique joue en attendant": "The autopilot plays in the meantime",
  "En présentiel": "In person",
  "Chaque joueur se connecte à son compte": "Each player signs in to their own account",
  "En ligne": "Online",
  "Crée un compte pour jouer à distance": "Create an account to play remotely",
  "Deux dés": "Two dice",
  "Lance deux dés": "Roll two dice",
  "Refuser": "Decline",
  "Accepter": "Accept",
  "Binômes": "Partners",
  "Inviter": "Invite",
  "Annuler": "Cancel",
  "Mise de chaque joueur (jetons)": "Each player's stake (tokens)",
  "Partie gratuite : aucun jeton en jeu, pas de jackpot.": "Free game: no tokens at stake, no jackpot.",
  "Rouge": "Red",
  "Vert": "Green",
  "Bleu": "Blue",
  "Jaune": "Yellow",
  "Joueur": "Player",
  "Ce compte joue déjà dans la partie.": "This account is already playing in the game.",
  "Choisis ton avatar": "Choose your avatar",
  "Préparer la partie": "Set up the game",
  "Nombre de joueurs": "Number of players",
  "Nombre de pions par joueur": "Pawns per player",
  "Joueurs (chacun se connecte à son compte)": "Players (everyone signs in to their own account)",
  "Joueurs (touche le rond pour changer d'avatar)": "Players (tap the circle to change avatar)",
  "Jouer en équipe (2 contre 2)": "Play in teams (2 vs 2)",
  "Les binômes ne se capturent pas. L'équipe gagne quand les deux ont fini.": "Partners can't capture each other. The team wins when both have finished.",
  "Protection des portes": "Door protection",
  "Un pion sur une case de départ ne peut pas être capturé": "A pawn on a starting square cannot be captured",
  "Protection des étoiles": "Star protection",
  "Un pion sur une étoile ne peut pas être capturé": "A pawn on a star cannot be captured",
  "Mise en cours...": "Placing stakes...",
  "Tous les joueurs doivent se connecter": "All players must sign in",
  "Forme les binômes": "Form the partners",
  "Lancer · partie gratuite": "Start · free game",
  "Lancer la partie": "Start the game",
  "Un 6 ! Tu rejoues.": "A 6! You roll again.",
  "Attends la fin du coup en cours.": "Wait for the current move to finish.",
  "Abandonner la partie ?": "Forfeit the game?",
  "Abandonner": "Forfeit",
  "Pilotage automatique : coup joué pour toi.": "Autopilot: move played for you.",
  "Touche ton dé ou glisse-le pour le lancer !": "Tap your die or drag it to roll!",
  "Le dé roule...": "The die is rolling...",
  "6 ! Aucun déplacement possible, mais tu rejoues.": "6! No move possible, but you roll again.",
  "Capture obligatoire ! Coup joué automatiquement.": "Capture is mandatory! Move played automatically.",
  "Un seul coup possible : joué automatiquement.": "Only one move possible: played automatically.",
  "Capture obligatoire : choisis le pion qui capture.": "Capture is mandatory: choose the pawn that captures.",
  "Un 6 ! Sors un pion ou avance.": "A 6! Bring out a pawn or move forward.",
  "Touche un pion pour le déplacer.": "Tap a pawn to move it.",
  "Il faut un 6 pour sortir ce pion.": "You need a 6 to bring this pawn out.",
  "Ce pion ne peut pas finir avec ce lancer.": "This pawn can't finish with this roll.",
  "Capture obligatoire : prends un pion adverse !": "Capture is mandatory: take an opponent pawn!",
  "Capture ! Tu rejoues.": "Capture! You roll again.",
  "Un pion est arrivé ! Tu rejoues.": "A pawn has arrived! You roll again.",
  "Pas de nouvelle partie en ligne.": "No new game online.",
  "VICTOIRE": "VICTORY",
  "Katika décharge les caisses": "Katika empties the tills",
  "Quitter la partie": "Leave the game",
  "Retour à l'accueil": "Back to home",
  "Abandonner la partie": "Forfeit the game",
  "Mode : Spectateur": "Mode: Spectator",
  "Mode : En ligne": "Mode: Online",
  "Mode : Équipes 2v2": "Mode: Teams 2v2",
  "Mode : Présentiel": "Mode: In person",
  "Lente": "Slow",
  "Normale": "Normal",
  "Rapide": "Fast",
  "Paramètres": "Settings",
  "Capture obligatoire": "Mandatory capture",
  "Tu dois prendre un pion adverse quand c'est possible": "You must take an opponent pawn when possible",
  "Coup unique automatique": "Automatic single move",
  "Le jeu joue à ta place quand il n'y a qu'un seul choix": "The game plays for you when there is only one choice",
  "Pilotage automatique": "Autopilot",
  "Vitesse des pions": "Pawn speed",
  "Changer ces deux réglages remet la partie à zéro.": "Changing these two settings resets the game.",
  "Mode : en ligne": "Mode: online",
  "Mode : équipes 2 contre 2 (même plateau)": "Mode: teams 2 vs 2 (same board)",
  "Mode : en présentiel (tous les joueurs sur le même plateau)": "Mode: in person (all players on the same board)",
  "Accueil": "Home",
  "Classement": "Ranking",
  "Fermer": "Close",
  "🏁 Partie terminée": "🏁 Game over",
  "Rejouer": "Play again",
  "Appuie encore sur retour pour aller à l'accueil": "Press back again to go to the home screen",
  "Cette partie n'existe plus.": "This game no longer exists.",
  "Cette partie est déjà complète.": "This game is already full.",
  "Impossible de rejoindre la partie.": "Couldn't join the game.",
  "Entre le code à 6 caractères.": "Enter the 6-character code.",
  "Aucune partie avec ce code.": "No game with this code.",
  "Impossible de chercher la partie.": "Couldn't look up the game.",
  "Impossible de créer la partie. Vérifie que Firestore est activé et que les règles autorisent les joueurs connectés.": "Couldn't create the game. Check that Firestore is enabled and that the rules allow signed-in players.",
  "Mes parties": "My games",
  "Ouvrir": "Open",
  "Reprendre": "Resume",
  "Impossible de charger les parties. Vérifie les règles Firestore.": "Couldn't load the games. Check the Firestore rules.",
  "Aucune partie ouverte pour le moment. Crée la tienne !": "No open games right now. Create your own!",
  "Rejoindre": "Join",
  "Impossible de charger les parties en cours.": "Couldn't load the ongoing games.",
  "Aucune partie en cours à regarder pour le moment.": "No ongoing games to watch right now.",
  "Regarder": "Watch",
  "Rejoindre avec un code": "Join with a code",
  "Parties en ligne": "Online games",
  "Créer une partie": "Create a game",
  "Les binômes se choisissent par invitation et ne se capturent pas": "Partners are chosen by invitation and cannot capture each other",
  "Partie privée": "Private game",
  "Invisible dans la liste : on la rejoint avec un code": "Hidden from the list: join it with a code",
  "Patiente...": "Please wait...",
  "Créer la partie": "Create the game",
  "Parties ouvertes": "Open games",
  "Parties en cours": "Ongoing games",
  "Retour": "Back",
  "Code de la salle privée": "Private room code",
  "Code de la salle": "Room code",
  "Code copié": "Code copied",
  "Action impossible. Réessaie.": "Action not possible. Try again.",
  "Binômes (2 contre 2)": "Partners (2 vs 2)",
  "Invitation envoyée · Annuler": "Invitation sent · Cancel",
  "Attends que d'autres joueurs rejoignent pour inviter un binôme.": "Wait for other players to join so you can invite a partner.",
  "Salle d'attente": "Waiting room",
  "La partie démarre quand les 4 joueurs sont là et que les binômes sont formés.": "The game starts when all 4 players are here and the partners are set.",
  "La partie démarre dès que tout le monde est là.": "The game starts as soon as everyone is here.",
  "Partie gratuite": "Free game",
  "Valider ma participation": "Confirm my participation",
  "En attente d'un joueur...": "Waiting for a player...",
  "Annuler la partie": "Cancel the game",
  "Tu dois être connecté.": "You must be signed in.",
  "Erreur de connexion à la partie.": "Error connecting to the game.",
  "Cette partie n'est pas (ou plus) en cours.": "This game is not (or no longer) in progress.",
  "Tu ne fais pas partie de cette partie.": "You're not part of this game.",
  "Cet e-mail est déjà utilisé.": "This email is already in use.",
  "E-mail invalide.": "Invalid email.",
  "Mot de passe trop faible (6 caractères minimum).": "Password too weak (6 characters minimum).",
  "E-mail ou mot de passe incorrect.": "Incorrect email or password.",
  "Trop d'essais. Réessaie dans quelques minutes.": "Too many attempts. Try again in a few minutes.",
  "Pas de connexion internet.": "No internet connection.",
  "La connexion par e-mail n'est pas activée dans Firebase.": "Email sign-in is not enabled in Firebase.",
  "Le serveur en ligne n'est pas configuré dans l'appli.": "The online server is not configured in the app.",
  "Choisis un pseudo.": "Choose a nickname.",
  "Mot de passe : 6 caractères minimum.": "Password: 6 characters minimum.",
  "Une erreur est survenue. Réessaie.": "An error occurred. Try again.",
  "Connecté": "Signed in",
  "Recharger mon compte": "Top up my account",
  "Jouer en ligne": "Play online",
  "Historique des parties": "Game history",
  "Se déconnecter": "Sign out",
  "Créer un compte": "Create an account",
  "Se connecter": "Sign in",
  "Pseudo": "Nickname",
  "E-mail": "Email",
  "Mot de passe": "Password",
  "Créer mon compte": "Create my account",
  "Me connecter": "Sign me in",
  "Connexion": "Sign in",
  "Jeu en ligne": "Online game",
  "Le serveur en ligne n'est pas configuré : Firebase n'a pas démarré. Le mode présentiel reste disponible.": "The online server is not configured: Firebase did not start. In-person mode is still available.",
  "Connecte-toi à ton compte avant de lancer une partie en présentiel.": "Sign in to your account before starting an in-person game.",
  "Crée un compte ou connecte-toi pour jouer en ligne.": "Create an account or sign in to play online.",
  "Gratuit": "Free",
  "Connexion requise.": "Sign-in required.",
  "Pas de connexion. Réessaie.": "No connection. Try again.",
  "E-mail ou mot de passe invalide.": "Invalid email or password.",
};
