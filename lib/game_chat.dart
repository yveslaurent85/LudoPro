import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'accounts.dart' show Wallet;
import 'lang.dart' show tr;

/// Chat d'une partie en ligne : les joueurs s'envoient des messages et des
/// emojis sans quitter la partie (la fenêtre s'ouvre par-dessus le jeu).
///
/// Les messages sont dans  {collection}/{gameId}/messages
///   { uid, name, text, createdAt }
/// Un emoji « tagué » sur un joueur ajoute un champ  to  (uid du joueur
/// visé) : il s'affiche alors devant ce joueur pendant quelques secondes.
/// [collection] = 'games' (Ludo) ou 'deuxdes'.
/// Seuls les joueurs de la partie peuvent lire et écrire (règles Firestore).
class GameChat extends StatefulWidget {
  const GameChat({
    super.key,
    required this.collection,
    required this.gameId,
    required this.myName,
  });

  final String collection;
  final String gameId;
  final String myName;

  @override
  State<GameChat> createState() => _GameChatState();
}

class _GameChatState extends State<GameChat> {
  static const List<String> _emojis = [
    '😀', '😂', '😍', '😎', '😡', '😭', '🤔', '😱',
    '👍', '👏', '🔥', '🎲', '🎉', '🙏', '💪', '🤝',
  ];

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  bool _first = true;
  bool _open = false;
  int _unread = 0;
  DateTime _lastSend = DateTime.fromMillisecondsSinceEpoch(0);

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  CollectionReference<Map<String, dynamic>> get _col => FirebaseFirestore
      .instance
      .collection(widget.collection)
      .doc(widget.gameId)
      .collection('messages');

  @override
  void initState() {
    super.initState();
    // On écoute le dernier message pour signaler les nouveaux (pastille +
    // petit message en bas de l'écran quand la fenêtre est fermée).
    _sub = _col
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .listen(_onSnap, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onSnap(QuerySnapshot<Map<String, dynamic>> snap) {
    if (_first) {
      _first = false; // les anciens messages ne comptent pas comme nouveaux
      return;
    }
    for (final c in snap.docChanges) {
      if (c.type != DocumentChangeType.added) continue;
      final d = c.doc.data();
      if (d == null || d['uid'] == _uid) continue;
      // Les emojis envoyés à un joueur s'affichent devant lui : pas de
      // pastille ni de message en bas de l'écran.
      if (d['to'] != null) continue;
      if (_open || !mounted) continue;
      setState(() => _unread++);
      final name = '${d['name'] ?? 'Joueur'}';
      final text = '${d['text'] ?? ''}';
      final m = ScaffoldMessenger.maybeOf(context);
      m?.hideCurrentSnackBar();
      m?.showSnackBar(
        SnackBar(
          content: Text('💬 $name : $text'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Envoie un message (limité à un toutes les 0,8 s et 200 caractères).
  void _send(String text) {
    final t = text.trim();
    if (t.isEmpty || _uid.isEmpty) return;
    final now = DateTime.now();
    if (now.difference(_lastSend) < const Duration(milliseconds: 800)) return;
    _lastSend = now;
    final name = widget.myName.trim().isEmpty ? 'Joueur' : widget.myName.trim();
    _col.add({
      'uid': _uid,
      'name': name.length > 40 ? name.substring(0, 40) : name,
      'text': t.length > 200 ? t.substring(0, 200) : t,
      'createdAt': FieldValue.serverTimestamp(),
    }).then((_) {}, onError: (Object _) {});
  }

  void _openSheet() {
    setState(() {
      _open = true;
      _unread = 0;
    });
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14267A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ChatSheet(
        col: _col,
        myUid: _uid,
        emojis: _emojis,
        onSend: _send,
      ),
    ).whenComplete(() {
      if (mounted) {
        setState(() {
          _open = false;
          _unread = 0;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openSheet,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(top: 2, right: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.15),
                border: Border.all(color: Colors.white54, width: 1.5),
              ),
              child: const Icon(Icons.chat_bubble, color: Colors.white, size: 20),
            ),
            if (_unread > 0)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5262B),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _unread > 9 ? '9+' : '$_unread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Fenêtre du chat : liste des messages, emojis rapides et zone de saisie.
class _ChatSheet extends StatefulWidget {
  const _ChatSheet({
    required this.col,
    required this.myUid,
    required this.emojis,
    required this.onSend,
  });

  final CollectionReference<Map<String, dynamic>> col;
  final String myUid;
  final List<String> emojis;
  final void Function(String) onSend;

  @override
  State<_ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<_ChatSheet> {
  final TextEditingController ctrl = TextEditingController();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream = widget.col
      .orderBy('createdAt', descending: true)
      .limit(40)
      .snapshots();

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final t = ctrl.text;
    if (t.trim().isEmpty) return;
    widget.onSend(t);
    ctrl.clear();
  }

  Widget _bubble(Map<String, dynamic> d) {
    final mine = d['uid'] == widget.myUid;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: mine
              ? const Color(0xFFFFC21A)
              : Colors.white.withOpacity(0.15),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!mine)
              Text(
                '${d['name'] ?? 'Joueur'}',
                style: const TextStyle(
                  color: Color(0xFFFFE082),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            Text(
              '${d['text'] ?? ''}',
              style: TextStyle(
                color: mine ? Colors.black : Colors.white,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            // Titre + croix pour fermer la messagerie
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 4, 0),
              child: Row(
                children: [
                  const SizedBox(width: 48),
                  const Expanded(
                    child: Text(
                      '💬 Discussion de la partie',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fermer',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _stream,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return const Center(
                      child: Text(
                        'Chat indisponible pour le moment.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    );
                  }
                  final docs = snap.data?.docs ?? const [];
                  if (docs.isEmpty) {
                    return const Center(
                      child: Text(
                        'Aucun message. Dis bonjour 👋',
                        style: TextStyle(color: Colors.white70),
                      ),
                    );
                  }
                  return ListView(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [for (final d in docs) _bubble(d.data())],
                  );
                },
              ),
            ),
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final e in widget.emojis)
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => widget.onSend(e),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(e, style: const TextStyle(fontSize: 26)),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: ctrl,
                      maxLength: 200,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submit(),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: 'Écris un message...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.12),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _submit,
                    icon: const Icon(Icons.send, color: Color(0xFFFFC21A)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Emojis envoyés à un joueur : ils s'affichent devant lui
// ----------------------------------------------------------------------

/// Emojis proposés quand on touche un joueur.
const List<String> kTagEmojis = [
  '🤣', '🎲', '🙏', '🤬', '🥺', '😏', '👀', '🤫', '🏃💨',
  '😀', '😍', '😎', '😭', '🤔', '😱', '👍', '👏', '🔥',
  '🎉', '💪', '🤝', '😴', '🤑', '💀',
];

/// Écoute les emojis envoyés aux joueurs d'une partie et garde, pour chaque
/// joueur (par uid), le dernier emoji reçu pendant ~3,5 secondes.
/// Les emojis sont enregistrés dans  {collection}/{gameId}/messages  avec
/// les champs  text  (l'emoji) et  to  (uid du joueur visé).
class EmojiReactions extends ChangeNotifier {
  EmojiReactions({
    required this.collection,
    required this.gameId,
    required this.myName,
  }) {
    _sub = _col
        .orderBy('createdAt', descending: true)
        .limit(8)
        .snapshots()
        .listen(_onSnap, onError: (Object _) {});
  }

  final String collection;
  final String gameId;
  final String myName;

  final Map<String, String> _shown = {};
  final Map<String, int> _stamp = {};
  final Map<String, Timer> _timers = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  int _counter = 0;
  bool _disposed = false;
  DateTime _lastSend = DateTime.fromMillisecondsSinceEpoch(0);

  CollectionReference<Map<String, dynamic>> get _col => FirebaseFirestore
      .instance
      .collection(collection)
      .doc(gameId)
      .collection('messages');

  /// Emoji actuellement affiché devant ce joueur (null = aucun).
  String? emojiOf(String uid) => _shown[uid];

  /// Change à chaque nouvel emoji (pour relancer l'animation).
  int stampOf(String uid) => _stamp[uid] ?? 0;

  void _onSnap(QuerySnapshot<Map<String, dynamic>> snap) {
    for (final c in snap.docChanges) {
      if (c.type != DocumentChangeType.added) continue;
      final d = c.doc.data();
      if (d == null) continue;
      final to = d['to'];
      final e = d['text'];
      if (to is! String || to.isEmpty || e is! String || e.isEmpty) continue;
      // Les vieux emojis (déjà passés avant mon arrivée) ne sont pas rejoués.
      final t = d['createdAt'];
      if (t is Timestamp &&
          DateTime.now().difference(t.toDate()) > const Duration(seconds: 20)) {
        continue;
      }
      _show(to, e);
    }
  }

  void _show(String uid, String emoji) {
    if (_disposed) return;
    _timers[uid]?.cancel();
    _shown[uid] = emoji;
    _stamp[uid] = ++_counter;
    _timers[uid] = Timer(const Duration(milliseconds: 3500), () {
      _shown.remove(uid);
      _timers.remove(uid);
      if (!_disposed) notifyListeners();
    });
    notifyListeners();
  }

  /// Envoie un emoji au joueur [toUid] (limité à un toutes les 0,8 s).
  void send(String toUid, String emoji) {
    final me = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (me.isEmpty || toUid.isEmpty || emoji.isEmpty) return;
    final now = DateTime.now();
    if (now.difference(_lastSend) < const Duration(milliseconds: 800)) return;
    _lastSend = now;
    final n = myName.trim().isEmpty ? 'Joueur' : myName.trim();
    _col.add({
      'uid': me,
      'name': n.length > 40 ? n.substring(0, 40) : n,
      'text': emoji,
      'to': toUid,
      'createdAt': FieldValue.serverTimestamp(),
    }).then((_) {}, onError: (Object _) {});
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    super.dispose();
  }
}

/// Pastille ronde avec l'emoji reçu par un joueur (rien si aucun emoji).
class EmojiBubble extends StatelessWidget {
  const EmojiBubble({
    super.key,
    required this.reactions,
    required this.uid,
    this.size = 36,
    this.margin = EdgeInsets.zero,
  });

  final EmojiReactions reactions;
  final String uid;
  final double size;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: reactions,
      builder: (context, _) {
        final e = reactions.emojiOf(uid);
        if (e == null) return const SizedBox.shrink();
        return IgnorePointer(
          child: TweenAnimationBuilder<double>(
            key: ValueKey('${uid}_${reactions.stampOf(uid)}'),
            tween: Tween<double>(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 450),
            curve: Curves.elasticOut,
            builder: (context, v, child) => Transform.scale(
              scale: v < 0 ? 0.0 : v,
              child: child,
            ),
            child: Container(
              width: size,
              height: size,
              margin: margin,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0A1B66),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.45),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(e, style: TextStyle(fontSize: size * 0.52)),
            ),
          ),
        );
      },
    );
  }
}

/// Ouvre la grille d'emojis à côté du widget [anchorContext] (le joueur
/// touché). [onPick] reçoit l'emoji choisi.
Future<void> showEmojiPicker(
  BuildContext anchorContext, {
  required String title,
  required void Function(String) onPick,
}) {
  Rect? anchor;
  final box = anchorContext.findRenderObject();
  if (box is RenderBox && box.hasSize) {
    anchor = box.localToGlobal(Offset.zero) & box.size;
  }
  return showGeneralDialog<void>(
    context: anchorContext,
    barrierDismissible: true,
    barrierLabel: 'Emojis',
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 150),
    transitionBuilder: (ctx, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
    pageBuilder: (ctx, _, __) {
      final screen = MediaQuery.of(ctx).size;
      const w = 264.0;
      const h = 196.0;
      final a = anchor ??
          Rect.fromCenter(
            center: Offset(screen.width / 2, screen.height / 2),
            width: 10,
            height: 10,
          );
      final left =
          (a.center.dx - w / 2).clamp(8.0, screen.width - w - 8).toDouble();
      var top = a.bottom + 6;
      if (top + h > screen.height - 8) top = a.top - h - 6;
      top = top.clamp(8.0, screen.height - h - 8).toDouble();
      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: w,
            height: h,
            child: Material(
              color: Colors.white,
              elevation: 10,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: GridView.count(
                      crossAxisCount: 3,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      children: [
                        for (final e in kTagEmojis)
                          InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              Navigator.of(ctx).pop();
                              onPick(e);
                            },
                            child: Center(
                              child: Text(
                                e,
                                style: const TextStyle(fontSize: 28),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

// ----------------------------------------------------------------------
// Salon d'attente : toutes les informations de la partie
// ----------------------------------------------------------------------

const List<Color> _ludoSeatColors = [
  Color(0xFFE5262B),
  Color(0xFF22B14C),
  Color(0xFF1E6BFF),
  Color(0xFFFFC21A),
];
const List<String> _ludoSeatNames = ['Rouge', 'Vert', 'Bleu', 'Jaune'];

const List<Color> _deSeatColors = [
  Color(0xFFE5262B),
  Color(0xFF22B14C),
  Color(0xFF1E6BFF),
  Color(0xFFFFC21A),
  Color(0xFFFF8A1F),
  Color(0xFF8E44AD),
  Color(0xFFEC5FA6),
  Color(0xFF14B8B0),
];
const List<String> _deSeatNames = [
  'Rouge',
  'Vert',
  'Bleu',
  'Jaune',
  'Orange',
  'Violet',
  'Rose',
  'Turquoise',
];

List<int> _ludoColorsFor(int maxPlayers) => maxPlayers == 2
    ? [0, 2]
    : (maxPlayers == 3 ? [0, 1, 2] : [0, 1, 2, 3]);

/// Ouvre la fenêtre « Salon d'attente » d'une partie en ligne :
/// joueurs, places, mise, cagnotte, code, options... en direct.
/// [collection] = 'games' (Ludo) ou 'deuxdes'.
void showRoomInfoSheet(
  BuildContext context, {
  required String collection,
  required String gameId,
  required String myUid,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF14267A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _RoomInfoSheet(
      collection: collection,
      gameId: gameId,
      myUid: myUid,
    ),
  );
}

/// Petit bouton rond « Salon d'attente » (pour les en-têtes).
class RoomInfoButton extends StatelessWidget {
  const RoomInfoButton({
    super.key,
    required this.collection,
    required this.gameId,
  });

  final String collection;
  final String gameId;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showRoomInfoSheet(
        context,
        collection: collection,
        gameId: gameId,
        myUid: FirebaseAuth.instance.currentUser?.uid ?? '',
      ),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.15),
          border: Border.all(color: Colors.white54, width: 1.5),
        ),
        child: const Icon(Icons.groups, color: Colors.white, size: 22),
      ),
    );
  }
}

class _RoomInfoSheet extends StatefulWidget {
  const _RoomInfoSheet({
    required this.collection,
    required this.gameId,
    required this.myUid,
  });

  final String collection;
  final String gameId;
  final String myUid;

  @override
  State<_RoomInfoSheet> createState() => _RoomInfoSheetState();
}

class _RoomInfoSheetState extends State<_RoomInfoSheet> {
  bool _copied = false;

  bool get _ludo => widget.collection == 'games';

  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _stream =
      FirebaseFirestore.instance
          .collection(widget.collection)
          .doc(widget.gameId)
          .snapshots();

  static const TextStyle _keyStyle =
      TextStyle(color: Colors.white70, fontSize: 12);
  static const TextStyle _valStyle = TextStyle(
    color: Colors.white,
    fontSize: 14,
    fontWeight: FontWeight.w700,
  );

  Widget _line(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 118, child: Text(k, style: _keyStyle)),
          Expanded(child: Text(v, style: _valStyle)),
        ],
      ),
    );
  }

  Widget _dot(Color c, bool filled) {
    return Container(
      width: 22,
      height: 22,
      margin: const EdgeInsets.only(right: 6, bottom: 4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? c : Colors.transparent,
        border: Border.all(
          color: filled ? Colors.white : Colors.white38,
          width: 1.5,
        ),
      ),
    );
  }

  Widget _badge(String text, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  String _date(dynamic t) {
    if (t is! Timestamp) return '';
    final d = t.toDate();
    String two(int n) => n < 10 ? '0$n' : '$n';
    return '${two(d.day)}/${two(d.month)}/${d.year} '
        '${two(d.hour)}:${two(d.minute)}';
  }

  Widget _content(Map<String, dynamic> d) {
    final players = ((d['players'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final max = (d['maxPlayers'] as num?)?.toInt() ?? players.length;
    final stake = (d['stake'] as num?)?.toInt() ?? 0;
    final pot = (d['pot'] as num?)?.toInt() ?? 0;
    final capturePay = (d['capturePay'] as num?)?.toInt() ?? 0;
    final paid = ((d['paid'] as List?) ?? const []).map((e) => '$e').toList();
    final status = '${d['status'] ?? ''}';
    final team = d['teamMode'] == true;
    final partnersRaw = d['partners'];
    final partners = (partnersRaw is List)
        ? partnersRaw.map((e) => (e as num).toInt()).toList()
        : <int>[];
    final scoresRaw = d['scores'];
    final scores = (scoresRaw is List)
        ? scoresRaw.map((e) => (e as num).toInt()).toList()
        : <int>[];

    final palette = _ludo ? _ludoSeatColors : _deSeatColors;
    final names = _ludo ? _ludoSeatNames : _deSeatNames;
    final seats = _ludo ? _ludoColorsFor(max) : List<int>.generate(max, (i) => i);
    Color seatColor(int i) => palette[seats[i] % palette.length];
    String seatName(int i) => names[seats[i] % names.length];

    final statusText = status == 'waiting'
        ? tr('En attente des joueurs', 'Waiting for players')
        : (status == 'finished'
            ? tr('Terminée', 'Finished')
            : tr('En cours', 'In progress'));

    final options = <String>[
      if (_ludo && team) tr('équipes 2 contre 2', 'teams 2 vs 2'),
      if (_ludo && d['doorSafe'] != false)
        tr('portes protégées', 'protected doors'),
      if (_ludo && d['starSafe'] != false)
        tr('étoiles protégées', 'protected stars'),
      if (_ludo && d['startOut'] == true) tr('position 54', 'position 54'),
      if (_ludo && d['startDoor'] == true)
        tr('départ case départ', 'start square'),
    ];

    final host = '${d['hostName'] ?? ''}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Carte résumé : même présentation que la liste des parties
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white.withOpacity(0.12),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('Partie de $host', "$host's game") +
                          (d['private'] == true ? ' 🔒' : ''),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (team) _badge('🤝 2v2', const Color(0xFF7E3FD8)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Wrap(
                      children: [
                        for (int i = 0; i < max; i++)
                          _dot(seatColor(i), i < players.length),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 10),
                    child: Text(
                      '${players.length}/$max',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _badge(
                    stake > 0 ? Wallet.format(stake) : tr('Gratuite', 'Free'),
                    const Color(0xFF1B7F4B),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _line(tr('Statut', 'Status'), statusText),
        if (stake > 0) ...[
          _line(
            tr('Mise', 'Stake'),
            tr('${Wallet.format(stake)} par joueur',
                '${Wallet.format(stake)} per player'),
          ),
          _line(tr('Cagnotte', 'Pot'), Wallet.format(stake * max)),
          if (capturePay > 0)
            _line(tr('Capture payante', 'Paid capture'),
                tr('${Wallet.format(capturePay)} par pion', '${Wallet.format(capturePay)} per pawn')),
          _line(
            tr('Gain du gagnant', 'Winner gets'),
            Wallet.format(Wallet.prize(stake * max)),
          ),
        ],
        if (_ludo)
          _line(
            tr('Pions par joueur', 'Pawns per player'),
            '${(d['pawnCount'] as num?)?.toInt() ?? 4}',
          ),
        if (options.isNotEmpty)
          _line(tr('Options', 'Options'), options.join(' • ')),
        if (_date(d['createdAt']).isNotEmpty)
          _line(tr('Créée le', 'Created on'), _date(d['createdAt'])),
        if (d['code'] != null)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Colors.black26,
              border: Border.all(color: const Color(0xFFFFC21A), width: 1.5),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('Code de la salle', 'Room code'),
                        style: _keyStyle,
                      ),
                      Text(
                        '${d['code']}',
                        style: const TextStyle(
                          color: Color(0xFFFFC21A),
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 5,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: tr('Copier le code', 'Copy code'),
                  icon: Icon(
                    _copied ? Icons.check : Icons.copy,
                    color: _copied ? const Color(0xFF69F0AE) : Colors.white,
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: '${d['code']}'));
                    setState(() => _copied = true);
                    Future<void>.delayed(const Duration(seconds: 2), () {
                      if (mounted) setState(() => _copied = false);
                    });
                  },
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        Text(
          tr('Joueurs', 'Players'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < max; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Colors.white.withOpacity(0.10),
              border: Border.all(
                color: seatColor(i).withOpacity(i < players.length ? 0.95 : 0.4),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(radius: 9, backgroundColor: seatColor(i)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    i < players.length
                        ? '${players[i]['name']}'
                            '${players[i]['uid'] == d['hostUid'] ? ' 👑' : ''}'
                            '${paid.contains(players[i]['uid']) ? ' ✅' : ''}'
                            '${players[i]['uid'] == widget.myUid ? tr(' (moi)', ' (me)') : ''}'
                            '${team && i < partners.length && partners[i] >= 0 && partners[i] < players.length ? '  🤝 ${players[partners[i]]['name']}' : ''}'
                        : tr("En attente d'un joueur...", 'Waiting for a player...'),
                    style: TextStyle(
                      color: i < players.length ? Colors.white : Colors.white54,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  (!_ludo &&
                          status != 'waiting' &&
                          i < scores.length &&
                          i < players.length)
                      ? '${scores[i]} pts'
                      : seatName(i),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.85;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 4, 0),
              child: Row(
                children: [
                  const SizedBox(width: 48),
                  Expanded(
                    child: Text(
                      tr("🎲 Salon d'attente", '🎲 Waiting room'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: tr('Fermer', 'Close'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            Flexible(
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _stream,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        tr('Informations indisponibles pour le moment.',
                            'Information unavailable right now.'),
                        style: const TextStyle(color: Colors.white70),
                      ),
                    );
                  }
                  final d = snap.data?.data();
                  if (d == null) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: _content(d),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
