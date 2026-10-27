import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Chat d'une partie en ligne : les joueurs s'envoient des messages et des
/// emojis sans quitter la partie (la fenêtre s'ouvre par-dessus le jeu).
///
/// Les messages sont dans  {collection}/{gameId}/messages
///   { uid, name, text, createdAt }
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
            const SizedBox(height: 10),
            const Text(
              '💬 Discussion de la partie',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
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
