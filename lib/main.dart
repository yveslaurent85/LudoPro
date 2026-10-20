​import 'dart:async';
import 'dart:math';
​import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
​import 'online.dart';
​/// Vrai si Firebase a démarré correctement (sinon : pas de jeu en ligne).
bool firebaseReady = false;
​Future<void> main() async {
WidgetsFlutterBinding.ensureInitialized();
try {
await Firebase.initializeApp();
firebaseReady = true;
} catch (_) {
// L'appli s'ouvre quand même : le mode présentiel reste jouable.
firebaseReady = false;
}
runApp(const LudoProApp());
}
​/// Éclaircit (amount > 0) ou assombrit (amount < 0) une couleur.
Color shade(Color color, double amount) {
final hsl = HSLColor.fromColor(color);
final lightness = (hsl.lightness + amount).clamp(0.0, 1.0).toDouble();
return hsl.withLightness(lightness).toColor();
}
​class LudoProApp extends StatelessWidget {
const LudoProApp({super.key});
​@override
Widget build(BuildContext context) {
return MaterialApp(
title: 'Katika',
debugShowCheckedModeBanner: false,
theme: ThemeData(
useMaterial3: true,
fontFamily: 'Roboto',
scaffoldBackgroundColor: const Color(0xFF061A66),
),
home: const HomeScreen(),
);
}
}
​// ----------------------------------------------------------------------
// Sons (désactivés pour l'instant)
// ----------------------------------------------------------------------
​/// Sons désactivés pour l'instant : aucune extension audio n'est nécessaire.
/// Les appels dans le jeu sont déjà en place, on pourra les brancher plus tard.
class Sfx {
bool enabled = true;
​void step() {}
void land() {}
void deny() {}
void capture() {}
void arrive() {}
void win() {}
void roll() {}
void dispose() {}
}
​// ----------------------------------------------------------------------
// Modèles
// ----------------------------------------------------------------------
​class Player {
final String display; // ex : Rouge
final Color color;
final Color lightColor;
final int start;
final IconData avatar;
List<int> pawns = [-1, -1, -1, -1];
​Player({
required this.display,
required this.color,
required this.lightColor,
required this.start,
required this.avatar,
});
​int get finished => pawns.where((p) => p == 56).length;
}
​class _PawnEntry {
final int p;
final int i;
final List<double> center;
_PawnEntry(this.p, this.i, this.center);
}
​// ----------------------------------------------------------------------
// Écran d'accueil : choix du mode de jeu
// ----------------------------------------------------------------------
​const BoxDecoration _appBackground = BoxDecoration(
gradient: LinearGradient(
begin: Alignment.topCenter,
end: Alignment.bottomCenter,
colors: [Color(0xFF1F5BFF), Color(0xFF0B2FA6), Color(0xFF061A66)],
),
);
​TextStyle _logoStyle(Color color, double size) {
return TextStyle(
color: color,
fontSize: size,
fontWeight: FontWeight.w900,
fontStyle: FontStyle.italic,
height: 1.0,
shadows: const [
Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 3)),
],
);
}
​class _ModeCard extends StatelessWidget {
final IconData icon;
final String title;
final String subtitle;
final Color color;
final VoidCallback onTap;
​const _ModeCard({
required this.icon,
required this.title,
required this.subtitle,
required this.color,
required this.onTap,
});
​@override
Widget build(BuildContext context) {
return GestureDetector(
onTap: onTap,
child: Container(
padding: const EdgeInsets.all(16),
decoration: BoxDecoration(
borderRadius: BorderRadius.circular(22),
gradient: LinearGradient(
begin: Alignment.topLeft,
end: Alignment.bottomRight,
colors: [shade(color, 0.08), shade(color, -0.12)],
),
border: Border.all(color: Colors.white54, width: 2),
boxShadow: [
BoxShadow(
color: Colors.black.withOpacity(0.35),
blurRadius: 10,
offset: const Offset(0, 5),
),
],
),
child: Row(
children: [
Container(
width: 52,
height: 52,
decoration: BoxDecoration(
shape: BoxShape.circle,
color: Colors.white.withOpacity(0.2),
),
child: Icon(icon, color: Colors.white, size: 30),
),
const SizedBox(width: 14),
Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(
title,
style: const TextStyle(
color: Colors.white,
fontSize: 18,
fontWeight: FontWeight.w800,
),
),
const SizedBox(height: 2),
Text(
subtitle,
style: const TextStyle(color: Colors.white70, fontSize: 12),
),
],
),
),
const Icon(Icons.chevron_right, color: Colors.white),
],
),
),
);
}
}
​class HomeScreen extends StatelessWidget {
const HomeScreen({super.key});
​@override
Widget build(BuildContext context) {
return Scaffold(
body: Container(
width: double.infinity,
height: double.infinity,
decoration: _appBackground,
child: SafeArea(
child: Padding(
padding: const EdgeInsets.symmetric(horizontal: 24),
child: Column(
children: [
const Spacer(flex: 2),
const Text('👑', style: TextStyle(fontSize: 44)),
RichText(
text: TextSpan(
children: [
TextSpan(
text: 'Kati',
style: _logoStyle(Colors.white, 52),
),
TextSpan(
text: 'ka',
style: _logoStyle(const Color(0xFFFFC21A), 52),
),
],
),
),
const SizedBox(height: 6),
const Text(
'Ludo et Dés',
style: TextStyle(
color: Colors.white70,
fontSize: 11,
letterSpacing: 1.2,
),
),
const Spacer(),
_ModeCard(
color: const Color(0xFF22B14C),
icon: Icons.groups,
title: 'En présentiel',
subtitle: 'Les joueurs jouent sur le même plateau',
onTap: () => Navigator.of(context).push(
MaterialPageRoute<void>(
builder: (context) => const SetupScreen(),
),
),
),
const SizedBox(height: 14),
_ModeCard(
color: const Color(0xFF1E6BFF),
icon: Icons.public,
title: 'En ligne',
subtitle: 'Crée un compte pour jouer à distance',
onTap: () => Navigator.of(context).push(
MaterialPageRoute<void>(
builder: (context) => const OnlineScreen(),
),
),
),
const Spacer(flex: 2),
],
),
),
),
),
);
}
}
​// ----------------------------------------------------------------------
// Préparation de la partie : nombre de joueurs et de pions
// ----------------------------------------------------------------------
​class SetupScreen extends StatefulWidget {
const SetupScreen({super.key});
​@override
State<SetupScreen> createState() => _SetupScreenState();
}
​class _SetupScreenState extends State<SetupScreen> {
int numPlayers = 4;
int pawnCount = 4;
bool doorSafe = true; // protection des portes (cases de départ)
bool starSafe = true; // protection des étoiles
​Widget _switch(String title, String subtitle, bool value,
void Function(bool) onChanged) {
return SwitchListTile(
contentPadding: EdgeInsets.zero,
activeColor: const Color(0xFFFFC21A),
title: Text(
title,
style: const TextStyle(
color: Colors.white,
fontSize: 15,
fontWeight: FontWeight.w800,
),
),
subtitle: Text(
subtitle,
style: const TextStyle(color: Colors.white70, fontSize: 12),
),
value: value,
onChanged: onChanged,
);
}
​Widget _picker(
String title,
List<int> values,
int current,
void Function(int) onPick,
) {
return Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(
title,
style: const TextStyle(
color: Colors.white,
fontSize: 16,
fontWeight: FontWeight.w800,
),
),
const SizedBox(height: 10),
Row(
children: [
for (final v in values)
Expanded(
child: Padding(
padding: const EdgeInsets.only(right: 8),
child: GestureDetector(
onTap: () => onPick(v),
child: Container(
padding: const EdgeInsets.symmetric(vertical: 14),
alignment: Alignment.center,
decoration: BoxDecoration(
borderRadius: BorderRadius.circular(14),
color: v == current
? const Color(0xFFFFC21A)
: Colors.white.withOpacity(0.12),
),
child: Text(
'$v',
style: TextStyle(
fontSize: 18,
fontWeight: FontWeight.w800,
color: v == current
? const Color(0xFF1A1F3A)
: Colors.white,
),
),
),
),
),
),
],
),
],
);
}
​@override
Widget build(BuildContext context) {
return Scaffold(
body: Container(
width: double.infinity,
height: double.infinity,
decoration: _appBackground,
child: SafeArea(
child: Padding(
padding: const EdgeInsets.all(20),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Row(
children: [
IconButton(
onPressed: () => Navigator.of(context).pop(),
icon: const Icon(Icons.arrow_back, color: Colors.white),
),
const Text(
'Préparer la partie',
style: TextStyle(
color: Colors.white,
fontSize: 22,
fontWeight: FontWeight.w800,
),
),
],
),
const SizedBox(height: 24),
_picker(
'Nombre de joueurs',
const [2, 3, 4],
numPlayers,
(v) => setState(() => numPlayers = v),
),
const SizedBox(height: 24),
_picker(
'Nombre de pions par joueur',
const [1, 2, 3, 4],
pawnCount,
(v) => setState(() => pawnCount = v),
),
const SizedBox(height: 10),
_switch(
'Protection des portes',
'Un pion sur une case de départ ne peut pas être capturé',
doorSafe,
(v) => setState(() => doorSafe = v),
),
_switch(
"Protection des étoiles",
'Un pion sur une étoile ne peut pas être capturé',
starSafe,
(v) => setState(() => starSafe = v),
),
const Spacer(),
SizedBox(
width: double.infinity,
height: 52,
child: ElevatedButton(
style: ElevatedButton.styleFrom(
backgroundColor: const Color(0xFF22B14C),
foregroundColor: Colors.white,
),
onPressed: () => Navigator.of(context).push(
MaterialPageRoute<void>(
builder: (context) => LudoGame(
numPlayers: numPlayers,
pawnCount: pawnCount,
doorSafe: doorSafe,
starSafe: starSafe,
),
),
),
child: const Text(
'Lancer la partie',
style: TextStyle(
fontSize: 17,
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
​// ----------------------------------------------------------------------
// Jeu en ligne : création de compte / connexion
// (comptes gérés par Firebase Authentication)
// ----------------------------------------------------------------------
​class OnlineScreen extends StatefulWidget {
const OnlineScreen({super.key});
​@override
State<OnlineScreen> createState() => _OnlineScreenState();
}
​class _OnlineScreenState extends State<OnlineScreen> {
final TextEditingController pseudoCtrl = TextEditingController();
final TextEditingController emailCtrl = TextEditingController();
final TextEditingController passCtrl = TextEditingController();
​bool creating = true;
bool hidePassword = true;
bool busy = false;
String? errorText;
User? user;
​@override
void initState() {
super.initState();
if (firebaseReady) {
user = FirebaseAuth.instance.currentUser;
}
}
​@override
void dispose() {
pseudoCtrl.dispose();
emailCtrl.dispose();
passCtrl.dispose();
super.dispose();
}
​String _errorMessage(String code) {
switch (code) {
case 'email-already-in-use':
return 'Cet e-mail est déjà utilisé.';
case 'invalid-email':
return 'E-mail invalide.';
case 'weak-password':
return 'Mot de passe trop faible (6 caractères minimum).';
case 'user-not-found':
case 'wrong-password':
case 'invalid-credential':
return 'E-mail ou mot de passe incorrect.';
case 'too-many-requests':
return "Trop d'essais. Réessaie dans quelques minutes.";
case 'network-request-failed':
return 'Pas de connexion internet.';
case 'operation-not-allowed':
return "La connexion par e-mail n'est pas activée dans Firebase.";
default:
return 'Erreur : $code';
}
}
​Future<void> _submit() async {
if (!firebaseReady) {
setState(() {
errorText = "Le serveur en ligne n'est pas configuré dans l'appli.";
});
return;
}
​final pseudo = pseudoCtrl.text.trim();
final email = emailCtrl.text.trim();
final password = passCtrl.text;
​if (creating && pseudo.isEmpty) {
setState(() => errorText = 'Choisis un pseudo.');
return;
}
if (!email.contains('@')) {
setState(() => errorText = 'E-mail invalide.');
return;
}
if (password.length < 6) {
setState(() => errorText = 'Mot de passe : 6 caractères minimum.');
return;
}
​setState(() {
busy = true;
errorText = null;
});
​try {
final auth = FirebaseAuth.instance;
if (creating) {
final cred = await auth.createUserWithEmailAndPassword(
email: email,
password: password,
);
await cred.user?.updateDisplayName(pseudo);
await cred.user?.reload();
} else {
await auth.signInWithEmailAndPassword(
email: email,
password: password,
);
}
if (!mounted) return;
setState(() {
user = auth.currentUser;
passCtrl.clear();
});
} on FirebaseAuthException catch (e) {
if (!mounted) return;
setState(() => errorText = errorMessage(e.code));
} catch () {
if (!mounted) return;
setState(() => errorText = 'Une erreur est survenue. Réessaie.');
} finally {
if (mounted) {
setState(() => busy = false);
}
}
}
​Future<void> _signOut() async {
await FirebaseAuth.instance.signOut();
if (!mounted) return;
setState(() {
user = null;
});
}
​InputDecoration _field(String label, IconData icon, {Widget? suffix}) {
return InputDecoration(
labelText: label,
labelStyle: const TextStyle(color: Colors.white70),
prefixIcon: Icon(icon, color: Colors.white70),
suffixIcon: suffix,
filled: true,
fillColor: Colors.white.withOpacity(0.12),
enabledBorder: OutlineInputBorder(
borderRadius: BorderRadius.circular(14),
borderSide: const BorderSide(color: Colors.white30),
),
focusedBorder: OutlineInputBorder(
borderRadius: BorderRadius.circular(14),
borderSide: const BorderSide(color: Color(0xFFFFC21A), width: 2),
),
);
}
​Widget _tab(String label, bool selected, VoidCallback onTap) {
return Expanded(
child: GestureDetector(
onTap: onTap,
child: Container(
padding: const EdgeInsets.symmetric(vertical: 11),
alignment: Alignment.center,
decoration: BoxDecoration(
borderRadius: BorderRadius.circular(14),
color: selected
? const Color(0xFFFFC21A)
: Colors.white.withOpacity(0.12),
),
child: Text(
label,
style: TextStyle(
color: selected ? const Color(0xFF1A1F3A) : Colors.white,
fontWeight: FontWeight.w800,
),
),
),
),
);
}
​Widget _banner(IconData icon, Color color, String text) {
return Container(
padding: const EdgeInsets.all(14),
decoration: BoxDecoration(
borderRadius: BorderRadius.circular(16),
color: Colors.black26,
border: Border.all(color: color, width: 1.5),
),
child: Row(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Icon(icon, color: color),
const SizedBox(width: 10),
Expanded(
child: Text(
text,
style: const TextStyle(color: Colors.white, fontSize: 13),
),
),
],
),
);
}
​Widget _primaryButton(String label, VoidCallback? onTap) {
final enabled = onTap != null;
return GestureDetector(
onTap: onTap,
child: Container(
height: 50,
alignment: Alignment.center,
decoration: BoxDecoration(
borderRadius: BorderRadius.circular(25),
gradient: LinearGradient(
begin: Alignment.topCenter,
end: Alignment.bottomCenter,
colors: enabled
? const [Color(0xFF55E05A), Color(0xFF1B9E2B)]
: const [Color(0xFF6B7396), Color(0xFF454C70)],
),
border: Border.all(
color: enabled ? const Color(0xFFFFD54F) : Colors.white24,
width: 2,
),
),
child: Text(
label,
style: const TextStyle(
color: Colors.white,
fontSize: 16,
fontWeight: FontWeight.w800,
),
),
),
);
}
​List<Widget> _signedInView(User current) {
final name =
(current.displayName != null && current.displayName!.isNotEmpty)
? current.displayName!
: (current.email ?? 'Joueur');
​return [
Container(
padding: const EdgeInsets.all(16),
decoration: BoxDecoration(
borderRadius: BorderRadius.circular(18),
color: Colors.white.withOpacity(0.12),
border: Border.all(color: Colors.white30),
),
child: Row(
children: [
const CircleAvatar(
radius: 26,
backgroundColor: Color(0xFF22B14C),
child: Icon(Icons.person, color: Colors.white, size: 30),
),
const SizedBox(width: 14),
Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
const Text(
'Connecté',
style: TextStyle(color: Colors.white70, fontSize: 12),
),
Text(
name,
style: const TextStyle(
color: Colors.white,
fontSize: 18,
fontWeight: FontWeight.w800,
),
),
if (current.email != null)
Text(
current.email!,
style: const TextStyle(color: Colors.white70, fontSize: 12),
),
],
),
),
],
),
),
const SizedBox(height: 16),
const SizedBox(height: 6),
_primaryButton(
'Jouer en ligne',
() => Navigator.of(context).push(
MaterialPageRoute<void>(
builder: (context) => const OnlineLobbyScreen(),
),
),
),
const SizedBox(height: 12),
_primaryButton('Se déconnecter', _signOut),
];
}
​List<Widget> _formView() {
return [
Row(
children: [
_tab('Créer un compte', creating, () {
setState(() {
creating = true;
errorText = null;
});
}),
const SizedBox(width: 10),
_tab('Se connecter', !creating, () {
setState(() {
creating = false;
errorText = null;
});
}),
],
),
const SizedBox(height: 18),
if (creating) ...[
TextField(
controller: pseudoCtrl,
enabled: !busy,
style: const TextStyle(color: Colors.white),
cursorColor: const Color(0xFFFFC21A),
decoration: _field('Pseudo', Icons.person),
),
const SizedBox(height: 12),
],
TextField(
controller: emailCtrl,
enabled: !busy,
style: const TextStyle(color: Colors.white),
cursorColor: const Color(0xFFFFC21A),
keyboardType: TextInputType.emailAddress,
decoration: _field('E-mail', Icons.email),
),
const SizedBox(height: 12),
TextField(
controller: passCtrl,
enabled: !busy,
style: const TextStyle(color: Colors.white),
cursorColor: const Color(0xFFFFC21A),
obscureText: hidePassword,
decoration: _field(
'Mot de passe',
Icons.lock,
suffix: IconButton(
onPressed: () => setState(() => hidePassword = !hidePassword),
icon: Icon(
hidePassword ? Icons.visibility : Icons.visibility_off,
color: Colors.white70,
),
),
),
),
if (errorText != null) ...[
const SizedBox(height: 12),
Text(
errorText!,
style: const TextStyle(
color: Color(0xFFFF8A80),
fontSize: 13,
fontWeight: FontWeight.w700,
),
),
],
const SizedBox(height: 22),
_primaryButton(
busy
? 'Patiente...'
: (creating ? 'Créer mon compte' : 'Me connecter'),
busy ? null : _submit,
),
];
}
​@override
Widget build(BuildContext context) {
final current = user;
​return Scaffold(
body: Container(
width: double.infinity,
height: double.infinity,
decoration: _appBackground,
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
icon: const Icon(Icons.arrow_back, color: Colors.white),
),
const Text(
'Jeu en ligne',
style: TextStyle(
color: Colors.white,
fontSize: 22,
fontWeight: FontWeight.w800,
),
),
],
),
const SizedBox(height: 12),
if (!firebaseReady)
_banner(
Icons.warning_amber_rounded,
const Color(0xFFFF8A65),
"Le serveur en ligne n'est pas configuré : Firebase n'a pas "
'démarré. Le mode présentiel reste disponible.',
)
else if (current == null)
_banner(
Icons.info_outline,
const Color(0xFFFFC21A),
'Crée un compte ou connecte-toi pour jouer en ligne.',
),
const SizedBox(height: 20),
if (current != null)
..._signedInView(current)
else
..._formView(),
],
),
),
),
),
);
}
}
​// ----------------------------------------------------------------------
// Le jeu (présentiel)
// ----------------------------------------------------------------------
​class LudoGame extends StatefulWidget {
const LudoGame({
super.key,
this.numPlayers = 4,
this.pawnCount = 4,
this.doorSafe = true,
this.starSafe = true,
this.online,
});
​final int numPlayers;
final int pawnCount;
final bool doorSafe; // portes (cases de départ) protégées
final bool starSafe; // étoiles protégées
final OnlineSession? online; // null = jeu en présentiel
​@override
State<LudoGame> createState() => _LudoGameState();
}
​class _LudoGameState extends State<LudoGame> with TickerProviderStateMixin {
// Cases étoiles (8 cases après chaque départ) et cases sûres (départs + étoiles)
static const Set<int> safeStars = {8, 21, 34, 47};
static const Set<int> doorCells = {0, 13, 26, 39};
​/// Cases protégées, selon les options choisies avant la partie.
Set<int> get safeCells => {
if (widget.doorSafe) ...doorCells,
if (widget.starSafe) ...safeStars,
};
​final Random random = Random();
late int numPlayers = widget.numPlayers;
late int pawnCount = widget.pawnCount;
​// --- Jeu en ligne ---------------------------------------------------
bool get isOnline => widget.online != null;
int get _myColor => isOnline ? activeIdx[widget.online!.mySeat] : -1;
bool get _isMyTurn => !isOnline || currentPlayer == _myColor;
​StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
bool _firstSnap = true;
​/// Nom affiché pour une couleur (pseudo en ligne, « Joueur Rouge » sinon).
String nameOf(int colorIndex) {
final o = widget.online;
if (o != null) {
final seat = activeIdx.indexOf(colorIndex);
if (seat >= 0 && seat < o.names.length) return o.names[seat];
}
return 'Joueur ${players[colorIndex].display}';
}
​/// Couleur du gagnant (null tant que la partie n'est pas finie).
int? get winnerColor {
if (!gameOver) return null;
for (final i in activeIdx) {
final pw = players[i].pawns;
if (pw.isNotEmpty && pw.every((p) => p == 56)) return i;
}
return null;
}
​/// Appelé chaque seconde : si le joueur ne fait rien pendant
/// [autoSeconds] secondes, le jeu joue à sa place.
void _tickAutopilot() {
if (!mounted || !autoPilot || gameOver) {
_idle = 0;
return;
}
final busyNow = isRolling || isMoving || flightPhase != 0 || diceDragging;
final sig = '$currentPlayer|hasRolled|'
'{players.map((p) => p.pawns.join(',')).join(';')}';
if (busyNow || sig != _lastSig || !_isMyTurn) {
_lastSig = sig;
_idle = 0;
return;
}
_idle++;
if (_idle >= autoSeconds) {
_idle = 0;
_autoPlay();
}
}
​/// Face aléatoire avec un 6 plus fréquent : 30 % de chances
/// (45 % si tous les pions du joueur sont encore à la base).
/// Pour régler la difficulté, change les deux pourcentages ci-dessous.
int _randomFace() {
final allHome = players[currentPlayer].pawns.every((x) => x == -1);
final sixChance = allHome ? 45 : 30;
if (random.nextInt(100) < sixChance) return 6;
return random.nextInt(5) + 1;
}
​/// Valeur du prochain lancer. À l'arrivée, quand il ne reste qu'un pion
/// à finir et qu'un seul lancer suffit, le joueur gagne en 5 lancers
/// maximum : le 5e lancer donne exactement le nombre qu'il faut.
int _rollValue() {
final cp = currentPlayer;
final left = players[cp].pawns.where((x) => x != 56).toList();
if (left.length == 1 && left.first >= 0) {
final remaining = 56 - left.first;
if (remaining >= 1 && remaining <= 6) {
if (finishThrows[cp] >= maxFinishThrows - 1) {
finishThrows[cp] = 0;
return remaining;
}
finishThrows[cp]++;
return _randomFace();
}
}
finishThrows[cp] = 0;
return _randomFace();
}
​void _autoPlay() {
if (!_isMyTurn || gameOver) return;
​if (canRollNow) {
// Le dé n'a pas été lancé : on le lance
throwDice(_toRoot(diceKeys[currentPlayer]));
return;
}
​if (hasRolled && !isRolling && !isMoving && flightPhase == 0) {
final legal = legalMoves();
if (legal.isEmpty) return;
​// Priorité : capture > arrivée > sortir un pion > pion le plus avancé
int score(int i) {
final pos = players[currentPlayer].pawns[i];
if (moveCaptures(i)) return 1000;
if (pos != -1 && pos + dice == 56) return 500;
if (pos == -1) return 300;
return pos;
}
​var best = legal.first;
for (final i in legal) {
if (score(i) > score(best)) best = i;
}
setState(() => message = 'Pilotage automatique : coup joué pour toi.');
movePawn(currentPlayer, best);
}
}
​void _listenOnline() {
final o = widget.online;
if (o == null || !firebaseReady) return;
_sub = FirebaseFirestore.instance
.collection('games')
.doc(o.gameId)
.snapshots()
.listen((snap) {
final d = snap.data();
if (d == null || !mounted) return;
if (snap.metadata.hasPendingWrites) return;
final first = _firstSnap;
_firstSnap = false;
if (!first && d['writer'] == o.uid) return; // c'est mon propre coup
_applyRemote(d);
});
}
​void _applyRemote(Map<String, dynamic> d) {
setState(() {
for (int i = 0; i < 4; i++) {
final l = d['p$i'];
if (l is List) {
players[i].pawns = l.map((e) => (e as num).toInt()).toList();
}
}
currentPlayer = (d['cur'] as num?)?.toInt() ?? currentPlayer;
hasRolled = d['hasRolled'] == true;
dice = (d['dice'] as num?)?.toInt() ?? dice;
final lr = d['lastRoll'];
if (lr is List && lr.length == 4) {
for (int i = 0; i < 4; i++) {
lastRoll[i] = (lr[i] as num).toInt();
}
}
message = (d['msg'] as String?) ?? message;
gameOver = d['over'] == true;
if (((d['rev'] as num?) ?? 0) > 0) gameStarted = true;
isRolling = false;
isMoving = false;
diceDragging = false;
flightPhase = 0;
});
}
​/// Envoie l'état du plateau aux autres joueurs.
Future<void> pushState() async {
final o = widget.online;
if (o == null || !firebaseReady) return;
try {
await FirebaseFirestore.instance.collection('games').doc(o.gameId).update({
for (int i = 0; i < 4; i++) 'p$i': players[i].pawns,
'cur': currentPlayer,
'hasRolled': hasRolled,
'dice': dice,
'lastRoll': lastRoll,
'msg': message,
'over': gameOver,
'writer': o.uid,
'rev': FieldValue.increment(1),
if (gameOver) 'status': 'finished',
});
} catch () {
// Connexion perdue : le prochain coup renverra l'état complet.
}
}
​/// Joueurs qui participent : 2 = Rouge + Bleu (face à face),
/// 3 = Rouge + Vert + Bleu, 4 = tous.
List<int> get activeIdx => numPlayers == 2
? [0, 2]
: (numPlayers == 3 ? [0, 1, 2] : [0, 1, 2, 3]);
​final Sfx sfx = Sfx();
late final AnimationController _pulse;
late final AnimationController _flight;
​final GlobalKey rootKey = GlobalKey();
final GlobalKey boardKey = GlobalKey();
final List<GlobalKey> diceKeys = List.generate(4, (_) => GlobalKey());
​// Ordre des tours (sens horaire) : Rouge, Vert, Bleu, Jaune
late final List<Player> players = [
Player(
display: 'Rouge',
color: const Color(0xFFE5262B),
lightColor: const Color(0xFFFFE3E5),
start: 0,
avatar: Icons.person,
),
Player(
display: 'Vert',
color: const Color(0xFF22B14C),
lightColor: const Color(0xFFDDF8E6),
start: 13,
avatar: Icons.face,
),
Player(
display: 'Bleu',
color: const Color(0xFF1E6BFF),
lightColor: const Color(0xFFDFEAFF),
start: 26,
avatar: Icons.face_3,
),
Player(
display: 'Jaune',
color: const Color(0xFFFFC21A),
lightColor: const Color(0xFFFFF3CC),
start: 39,
avatar: Icons.person_outline,
),
];
​int currentPlayer = 0;
int dice = 1; // valeur du dernier lancer validé
int pendingDice = 1; // valeur en cours de lancer
final List<int> lastRoll = [1, 1, 1, 1]; // face affichée sur le dé de chaque joueur
bool hasRolled = false;
bool isRolling = false;
bool isMoving = false;
bool gameOver = false;
bool soundOn = true;
bool forcedCapture = true; // capture obligatoire
bool autoPlay = true; // coup unique joué automatiquement
bool autoPilot = true; // pilotage automatique si le joueur tarde
final int autoSeconds = 10; // délai avant le pilotage automatique
bool gameStarted = false; // devient vrai au premier lancer de dé
final int maxFinishThrows = 5; // à l'arrivée : 5 lancers maximum
final List<int> finishThrows = [0, 0, 0, 0];
Timer? _autoTimer;
String _lastSig = '';
int _idle = 0;
int stepMs = 170; // vitesse des pions (ms par case)
DateTime? _lastBack; // dernier appui sur « retour » (double retour pour quitter)
​// Dé : glissement et lancer
bool diceDragging = false;
Offset dragPos = Offset.zero;
int flightPhase = 0; // 0 = au repos, 1 = lancer, 2 = posé / retour
Offset flightFrom = Offset.zero;
Offset flightTo = Offset.zero;
List<int> faceSeq = [1, 2, 3, 4, 5, 6];
​int _token = 0; // sert à annuler les animations en attente
String message = 'Touche ton dé ou glisse-le pour le lancer !';
​final List<List<int>> track = const [
[6, 1], [6, 2], [6, 3], [6, 4], [6, 5],
[5, 6], [4, 6], [3, 6], [2, 6], [1, 6],
[0, 6], [0, 7], [0, 8],
[1, 8], [2, 8], [3, 8], [4, 8], [5, 8],
[6, 9], [6, 10], [6, 11], [6, 12], [6, 13],
[6, 14], [7, 14], [8, 14],
[8, 13], [8, 12], [8, 11], [8, 10], [8, 9],
[9, 8], [10, 8], [11, 8], [12, 8], [13, 8],
[14, 8], [14, 7], [14, 6],
[13, 6], [12, 6], [11, 6], [10, 6], [9, 6],
[8, 5], [8, 4], [8, 3], [8, 2], [8, 1],
[8, 0], [7, 0], [6, 0],
];
​List<List<int>> homeLane(int player) {
switch (player) {
case 0:
return const [
[7, 1], [7, 2], [7, 3], [7, 4], [7, 5],
];
case 1:
return const [
[1, 7], [2, 7], [3, 7], [4, 7], [5, 7],
];
case 2:
return const [
[7, 13], [7, 12], [7, 11], [7, 10], [7, 9],
];
default:
return const [
[13, 7], [12, 7], [11, 7], [10, 7], [9, 7],
];
}
}
​@override
void initState() {
super.initState();
for (final p in players) {
p.pawns = List<int>.filled(pawnCount, -1);
}
_listenOnline();
autoTimer = Timer.periodic(
const Duration(seconds: 1),
() => _tickAutopilot(),
);
_pulse = AnimationController(
vsync: this,
duration: const Duration(milliseconds: 650),
)..repeat(reverse: true);
_flight = AnimationController(
vsync: this,
duration: const Duration(milliseconds: 1000),
);
}
​@override
void dispose() {
_sub?.cancel();
_autoTimer?.cancel();
_pulse.dispose();
_flight.dispose();
sfx.dispose();
super.dispose();
}
​// ---------------------------------------------------------------------
// Règles du jeu
// ---------------------------------------------------------------------
​/// Progression d'un joueur : somme des cases parcourues par ses pions,
/// sur un total de (nombre de pions) x 56 cases.
double progressOf(Player player) {
int total = 0;
for (final pos in player.pawns) {
if (pos > 0) total += pos;
}
return total / (pawnCount * 56.0);
}
​bool get canRollNow =>
_isMyTurn &&
!hasRolled &&
!gameOver &&
!isRolling &&
!isMoving &&
flightPhase == 0;
​bool canPawnMove(int position) {
if (position == -1) return dice == 6;
return position + dice <= 56;
}
​/// Ce coup capture-t-il un pion adverse ?
bool moveCaptures(int pawnIndex) {
final player = players[currentPlayer];
final from = player.pawns[pawnIndex];
if (!canPawnMove(from)) return false;
​final target = from == -1 ? 0 : from + dice;
if (target >= 51) return false;
​final absolutePosition = (player.start + target) % 52;
if (safeCells.contains(absolutePosition)) return false;
​for (int p = 0; p < players.length; p++) {
if (p == currentPlayer) continue;
for (final pos in players[p].pawns) {
if (pos >= 0 &&
pos < 51 &&
(players[p].start + pos) % 52 == absolutePosition) {
return true;
}
}
}
return false;
}
​/// Coups autorisés. Si une capture est possible, elle est obligatoire.
List<int> legalMoves() {
final player = players[currentPlayer];
final all = <int>[
for (int i = 0; i < player.pawns.length; i++)
if (canPawnMove(player.pawns[i])) i,
];
final captures = all.where(moveCaptures).toList();
return (forcedCapture && captures.isNotEmpty) ? captures : all;
}
​/// Retire les coups équivalents (pions au même endroit).
List<int> distinctMoves(List<int> legal) {
final player = players[currentPlayer];
final seen = <int>{};
final result = <int>[];
for (final i in legal) {
if (seen.add(player.pawns[i])) result.add(i);
}
return result;
}
​Offset _toRoot(GlobalKey key, [Offset local = Offset.zero]) {
final root = rootKey.currentContext!.findRenderObject() as RenderBox;
final box = key.currentContext!.findRenderObject() as RenderBox;
return root.globalToLocal(box.localToGlobal(local));
}
​// --- Dé : glisser puis lâcher, ou simplement toucher -------------------
​void onDicePanStart(int p) {
if (p != currentPlayer || !canRollNow) return;
final origin = _toRoot(diceKeys[p]);
setState(() {
diceDragging = true;
dragPos = origin;
});
}
​void onDicePanUpdate(DragUpdateDetails details) {
if (!diceDragging) return;
setState(() {
dragPos += details.delta;
});
}
​void onDicePanEnd() {
if (!diceDragging) return;
final from = dragPos;
setState(() {
diceDragging = false;
});
throwDice(from);
}
​Future<void> throwDice(Offset from) async {
if (!canRollNow) return;
​final newDice = _rollValue();
final rollToken = ++_token;
​const flyingSize = 64.0;
final boardBox = boardKey.currentContext!.findRenderObject() as RenderBox;
final boardCenter =
_toRoot(boardKey, boardBox.size.center(Offset.zero));
final jitter = Offset(
random.nextDouble() * 60 - 30,
random.nextDouble() * 60 - 30,
);
​setState(() {
gameStarted = true;
isRolling = true;
pendingDice = newDice;
faceSeq = List<int>.generate(6, (i) => i + 1)..shuffle(random);
flightPhase = 1;
flightFrom = from;
flightTo = boardCenter -
const Offset(flyingSize / 2, flyingSize / 2) +
jitter;
message = 'Le dé roule...';
});
sfx.roll();
​_flight.duration = const Duration(milliseconds: 1000);
await _flight.forward(from: 0);
if (!mounted || rollToken != _token) return;
​setState(() {
dice = newDice;
lastRoll[currentPlayer] = newDice;
isRolling = false;
hasRolled = true;
flightPhase = 2;
});
sfx.land();
​final legal = legalMoves();
final distinct = distinctMoves(legal);
final forced =
forcedCapture && legal.isNotEmpty && moveCaptures(legal.first);
​setState(() {
if (legal.isEmpty) {
message = '$dice ! Aucun déplacement possible.';
} else if (autoPlay && distinct.length == 1) {
message = forced
? 'Capture obligatoire ! Coup joué automatiquement.'
: 'Un seul coup possible : joué automatiquement.';
} else if (forced) {
message = 'Capture obligatoire : choisis le pion qui capture.';
} else if (dice == 6) {
message = 'Un 6 ! Sors un pion ou avance.';
} else {
message = 'Touche un pion pour le déplacer.';
}
});
_pushState();
​await Future.delayed(const Duration(milliseconds: 650));
if (!mounted || rollToken != _token) return;
​// Le dé retourne devant son joueur
setState(() {
flightFrom = _toRoot(diceKeys[currentPlayer]);
});
_flight.duration = const Duration(milliseconds: 380);
await _flight.reverse();
if (!mounted || rollToken != _token) return;
setState(() {
flightPhase = 0;
});
​if (legal.isEmpty) {
sfx.deny();
await Future.delayed(const Duration(milliseconds: 600));
if (!mounted || rollToken != _token || gameOver) return;
​// Règle demandée : un 6 donne un nouveau lancer, même si aucun
// pion ne peut sortir ou avancer. Pour les autres résultats,
// le tour passe normalement au joueur suivant.
if (dice == 6) {
setState(() {
hasRolled = false;
message = 'Un 6 ! Aucun déplacement possible, mais tu rejoues.';
});
_pushState();
} else {
nextTurn();
}
} else if (autoPlay && distinct.length == 1) {
// Un seul choix possible : le jeu joue à ta place
await Future.delayed(const Duration(milliseconds: 250));
if (!mounted || rollToken != _token) return;
movePawn(currentPlayer, distinct.first);
}
}
​void _advanceTurn() {
final act = activeIdx;
currentPlayer = act[(act.indexOf(currentPlayer) + 1) % act.length];
hasRolled = false;
message = 'Touche ton dé ou glisse-le pour le lancer !';
}
​void nextTurn() {
setState(_advanceTurn);
_pushState();
}
​Future<void> movePawn(int playerIndex, int pawnIndex) async {
if (!hasRolled ||
gameOver ||
isRolling ||
isMoving ||
flightPhase != 0 ||
diceDragging ||
playerIndex != currentPlayer ||
!_isMyTurn) {
return;
}
​final player = players[playerIndex];
final oldPosition = player.pawns[pawnIndex];
​if (oldPosition == 56) return;
​final legal = legalMoves();
if (!legal.contains(pawnIndex)) {
String reason;
if (oldPosition == -1 && dice != 6) {
reason = 'Il faut un 6 pour sortir ce pion.';
} else if (oldPosition >= 0 && oldPosition + dice > 56) {
reason = 'Ce pion ne peut pas finir avec ce lancer.';
} else {
reason = 'Capture obligatoire : prends un pion adverse !';
}
sfx.deny();
setState(() {
message = reason;
});
return;
}
​final token = _token;
setState(() {
isMoving = true;
});
​if (oldPosition == -1) {
sfx.step();
setState(() {
player.pawns[pawnIndex] = 0;
});
await Future.delayed(Duration(milliseconds: stepMs + 90));
if (!mounted || token != _token) return;
} else {
// Le pion avance case par case
for (int s = 1; s <= dice; s++) {
sfx.step();
setState(() {
player.pawns[pawnIndex] = oldPosition + s;
});
await Future.delayed(Duration(milliseconds: stepMs));
if (!mounted || token != _token) return;
}
}
​final newPosition = player.pawns[pawnIndex];
bool captured = false;
​// Capture possible uniquement sur le circuit commun (0..50), hors cases sûres
if (newPosition < 51) {
final absolutePosition = (player.start + newPosition) % 52;
​if (!safeCells.contains(absolutePosition)) {
for (int p = 0; p < players.length; p++) {
if (p == playerIndex) continue;
​for (int i = 0; i < players[p].pawns.length; i++) {
final opponentPosition = players[p].pawns[i];
​if (opponentPosition >= 0 &&
opponentPosition < 51 &&
(players[p].start + opponentPosition) % 52 ==
absolutePosition) {
players[p].pawns[i] = -1;
captured = true;
}
}
}
}
}
​final won = player.pawns.every((p) => p == 56);
​if (won) {
sfx.win();
} else if (captured) {
sfx.capture();
} else if (newPosition == 56) {
sfx.arrive();
}
​setState(() {
isMoving = false;
​if (won) {
gameOver = true;
message = '🏆 ${nameOf(playerIndex)} remporte la partie !';
} else if (dice == 6 || captured || newPosition == 56) {
hasRolled = false;
message = captured
? 'Capture ! Tu rejoues.'
: newPosition == 56
? 'Un pion est arrivé ! Tu rejoues.'
: 'Un 6 ! Tu rejoues.';
} else {
_advanceTurn();
}
});
_pushState();
}
​void restartGame() {
if (isOnline) {
setState(() => message = 'Pas de nouvelle partie en ligne.');
return;
}
_token++; // annule les animations en attente
_flight.stop();
_flight.value = 0;
setState(() {
for (final player in players) {
player.pawns = List<int>.filled(pawnCount, -1);
}
for (int i = 0; i < 4; i++) {
lastRoll[i] = 1;
finishThrows[i] = 0;
}
gameStarted = false;
currentPlayer = 0;
dice = 1;
hasRolled = false;
isRolling = false;
isMoving = false;
gameOver = false;
diceDragging = false;
flightPhase = 0;
message = 'Nouvelle partie ! Touche ton dé pour commencer.';
});
}
​// ---------------------------------------------------------------------
// Positions des pions (en unités de cases)
// ---------------------------------------------------------------------
​List<double> homeCenter(int p, int i) {
final rowStart = p < 2 ? 0 : 9;
final colStart = (p == 0 || p == 3) ? 0 : 9;
final r = i < 2 ? 1.75 : 4.25;
final c = i.isEven ? 1.75 : 4.25;
return [rowStart + r, colStart + c];
}
​List<double>? pawnCenter(int p, int i) {
final position = players[p].pawns[i];
if (position == 56) return null;
if (position == -1) return homeCenter(p, i);
​final cell = position >= 51
? homeLane(p)[position - 51]
: track[(players[p].start + position) % 52];
return [cell[0] + 0.5, cell[1] + 0.5];
}
​// Zone de toucher élargie : on joue le pion le plus proche du doigt
void onBoardTap(Offset pos, double c) {
if (!hasRolled ||
isRolling ||
isMoving ||
gameOver ||
flightPhase != 0 ||
diceDragging) {
return;
}
​final tapRow = pos.dy / c;
final tapCol = pos.dx / c;
final legal = legalMoves();
​int? best;
double bestDist = 1.8; // rayon en nombre de cases
int? nearest;
double nearestDist = 1.2;
​for (int i = 0; i < players[currentPlayer].pawns.length; i++) {
final center = pawnCenter(currentPlayer, i);
if (center == null) continue;
​final dr = center[0] - 0.2 - tapRow; // le pion est dessiné un peu plus haut
final dc = center[1] - tapCol;
final dist = sqrt(dr * dr + dc * dc);
​if (legal.contains(i) && dist < bestDist) {
bestDist = dist;
best = i;
}
if (dist < nearestDist) {
nearestDist = dist;
nearest = i;
}
}
​if (best != null) {
movePawn(currentPlayer, best);
} else if (nearest != null) {
movePawn(currentPlayer, nearest); // affiche le message d'explication
}
}
​// ---------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------
​List<Widget> buildPawns(double c) {
final legal = (_isMyTurn &&
hasRolled &&
!isRolling &&
!isMoving &&
!gameOver &&
flightPhase == 0)
? legalMoves()
: <int>[];
​final entries = <_PawnEntry>[];
for (final p in activeIdx) {
for (int i = 0; i < players[p].pawns.length; i++) {
final center = pawnCenter(p, i);
if (center != null) entries.add(_PawnEntry(p, i, center));
}
}
​final groups = <String, List<PawnEntry>>{};
for (final e in entries) {
groups
.putIfAbsent('${e.center[0]}${e.center[1]}', () => <_PawnEntry>[])
.add(e);
}
​// Les pions du bas sont dessinés par-dessus ceux du haut
entries.sort((a, b) => a.center[0].compareTo(b.center[0]));
​return entries.map((e) {
final group = groups['{e.center[0]}_{e.center[1]}']!;
final n = group.length;
final k = group.indexOf(e);
final position = players[e.p].pawns[e.i];
final atHome = position == -1;
final stacked = n > 1 && !atHome;
​final w = (atHome ? c * 1.5 : c * 1.0) * (stacked ? 0.8 : 1.0);
final h = w * 1.25;
final dx = stacked ? (k - (n - 1) / 2) * c * 0.3 : 0.0;
​final movable = e.p == currentPlayer && legal.contains(e.i);
​return AnimatedPositioned(
key: ValueKey('pawn_{e.p}_{e.i}'),
duration: Duration(milliseconds: min(140, stepMs)),
curve: Curves.easeOut,
left: e.center[1] * c - w / 2 + dx,
top: e.center[0] * c - h * 0.65,
width: w,
height: h,
child: IgnorePointer(
child: AnimatedBuilder(
animation: _pulse,
builder: (context, child) => Transform.translate(
offset: Offset(0, movable ? -_pulse.value * c * 0.25 : 0),
child: child,
),
child: CustomPaint(
painter: PawnPainter(
color: players[e.p].color,
highlight: movable,
),
),
),
),
);
}).toList();
}
​/// Couronne dans la base du gagnant + « Victoire » au centre du plateau.
List<Widget> buildVictory(double c) {
final w = winnerColor;
if (w == null) return const <Widget>[];
final winner = players[w];
​final rowStart = w < 2 ? 0 : 9;
final colStart = (w == 0 || w == 3) ? 0 : 9;
final crownBox = c * 3.2;
​return [
// Couronne dans la case (base) du gagnant
Positioned(
left: (colStart + 3) * c - crownBox / 2,
top: (rowStart + 3) * c - crownBox / 2,
width: crownBox,
height: crownBox,
child: IgnorePointer(
child: TweenAnimationBuilder<double>(
tween: Tween<double>(begin: 0.2, end: 1.0),
duration: const Duration(milliseconds: 700),
curve: Curves.elasticOut,
builder: (context, value, child) =>
Transform.scale(scale: value, child: child),
child: Center(
child: Text('👑', style: TextStyle(fontSize: c * 2.3)),
),
),
),
),
// Bandeau « Victoire » au milieu du plateau
Positioned(
left: 7.5 * c - c * 4.0,
top: 7.5 * c - c * 1.6,
width: c * 8.0,
height: c * 3.2,
child: IgnorePointer(
child: TweenAnimationBuilder<double>(
tween: Tween<double>(begin: 0.0, end: 1.0),
duration: const Duration(milliseconds: 500),
curve: Curves.easeOutBack,
builder: (context, value, child) =>
Transform.scale(scale: value, child: child),
child: Container(
decoration: BoxDecoration(
borderRadius: BorderRadius.circular(c * 0.7),
gradient: LinearGradient(
begin: Alignment.topLeft,
end: Alignment.bottomRight,
colors: [shade(winner.color, 0.1), shade(winner.color, -0.15)],
),
border: Border.all(color: Colors.white, width: 3),
boxShadow: [
BoxShadow(
color: Colors.black.withOpacity(0.45),
blurRadius: 14,
offset: const Offset(0, 6),
),
],
),
child: FittedBox(
fit: BoxFit.scaleDown,
child: Padding(
padding: const EdgeInsets.symmetric(horizontal: 10),
child: Column(
mainAxisSize: MainAxisSize.min,
children: [
Text(
'VICTOIRE',
style: TextStyle(
color: Colors.white,
fontSize: c * 1.15,
fontWeight: FontWeight.w900,
letterSpacing: 2,
shadows: const [
Shadow(color: Colors.black54, blurRadius: 4),
],
),
),
Text(
'Joueur ${winner.display}',
style: TextStyle(
color: Colors.white,
fontSize: c * 0.8,
fontWeight: FontWeight.w800,
),
),
const SizedBox(height: 2),
Text(
'Katika décharge les caisses',
style: TextStyle(
color: Colors.white,
fontSize: c * 0.6,
fontStyle: FontStyle.italic,
fontWeight: FontWeight.w700,
),
),
],
),
),
),
),
),
),
),
];
}
​Widget buildBoard(double size) {
return Container(
key: boardKey,
width: size,
height: size,
decoration: BoxDecoration(
color: Colors.white,
borderRadius: BorderRadius.circular(16),
boxShadow: [
BoxShadow(
color: Colors.black.withOpacity(0.5),
blurRadius: 20,
offset: const Offset(0, 10),
),
],
),
child: ClipRRect(
borderRadius: BorderRadius.circular(16),
child: LayoutBuilder(
builder: (context, constraints) {
final c = constraints.maxWidth / 15;
return GestureDetector(
behavior: HitTestBehavior.opaque,
onTapUp: (details) => onBoardTap(details.localPosition, c),
child: Stack(
children: [
Positioned.fill(
child: CustomPaint(
painter: BoardPainter(
colors: players.map((p) => p.color).toList(),
lights: players.map((p) => p.lightColor).toList(),
track: track,
lanes: [for (int p = 0; p < 4; p++) homeLane(p)],
starts: players.map((p) => p.start).toList(),
safeStars: widget.starSafe ? safeStars : const <int>{},
showDoorStars: widget.doorSafe,
),
),
),
...buildPawns(c),
...buildVictory(c),
],
),
);
},
),
),
);
}
​TextStyle logoStyle(Color color) {
return TextStyle(
color: color,
fontSize: 28,
fontWeight: FontWeight.w900,
fontStyle: FontStyle.italic,
height: 1.0,
shadows: const [
Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 3)),
],
);
}
​Widget buildHeader() {
return Padding(
padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
child: Row(
children: [
PopupMenuButton<String>(
color: const Color(0xFF14267A),
onSelected: (value) {
if (value == 'new') restartGame();
if (value == 'home') Navigator.of(context).pop();
},
itemBuilder: (context) => const [
PopupMenuItem<String>(
value: 'new',
child: Text(
'Nouvelle partie',
style: TextStyle(color: Colors.white),
),
),
PopupMenuItem<String>(
value: 'home',
child: Text(
"Retour à l'accueil",
style: TextStyle(color: Colors.white),
),
),
],
child: Container(
width: 40,
height: 40,
decoration: BoxDecoration(
shape: BoxShape.circle,
color: Colors.white.withOpacity(0.15),
border: Border.all(color: Colors.white54, width: 1.5),
),
child: const Icon(Icons.menu, color: Colors.white),
),
),
Expanded(
child: Column(
mainAxisSize: MainAxisSize.min,
children: [
const Text('👑', style: TextStyle(fontSize: 15)),
RichText(
text: TextSpan(
children: [
TextSpan(text: 'Kati', style: logoStyle(Colors.white)),
TextSpan(
text: 'ka',
style: logoStyle(const Color(0xFFFFC21A)),
),
],
),
),
const SizedBox(height: 2),
const Text(
'Ludo et Dés',
style: TextStyle(
color: Colors.white70,
fontSize: 9,
letterSpacing: 1.0,
),
),
],
),
),
Container(
padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
decoration: BoxDecoration(
borderRadius: BorderRadius.circular(14),
color: Colors.black26,
border: Border.all(color: const Color(0xFFFFC21A), width: 1.5),
),
child: Row(
mainAxisSize: MainAxisSize.min,
children: [
const Icon(
Icons.emoji_events,
color: Color(0xFFFFC21A),
size: 22,
),
const SizedBox(width: 4),
Column(
mainAxisSize: MainAxisSize.min,
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(
isOnline ? 'Mode : En ligne' : 'Mode : Présentiel',
style: TextStyle(
color: Colors.white,
fontSize: 9,
fontWeight: FontWeight.bold,
),
),
Text(
'$numPlayers Joueurs',
style: const TextStyle(
color: Color(0xFFFFC21A),
fontSize: 10,
fontWeight: FontWeight.bold,
),
),
],
),
],
),
),
],
),
);
}
​Widget playerBadge(int index, {required bool avatarOnRight}) {
if (!activeIdx.contains(index)) return const SizedBox(height: 52);
​final player = players[index];
final active = index == currentPlayer && !gameOver;
final remaining = pawnCount - player.finished;
final progress = progressOf(player);
final percent = (progress * 100).round();
​final avatar = Container(
width: 42,
height: 42,
decoration: BoxDecoration(
shape: BoxShape.circle,
gradient: LinearGradient(
begin: Alignment.topLeft,
end: Alignment.bottomRight,
colors: [shade(player.color, 0.15), shade(player.color, -0.12)],
),
border: Border.all(color: Colors.white, width: 2),
boxShadow: [
BoxShadow(
color: player.color.withOpacity(active ? 0.9 : 0.4),
blurRadius: active ? 12 : 4,
spreadRadius: active ? 2 : 0,
),
],
),
child: Icon(player.avatar, color: Colors.white, size: 26),
);
​// Anneau de progression autour de l'avatar
final avatarWithRing = SizedBox(
width: 52,
height: 52,
child: Stack(
alignment
