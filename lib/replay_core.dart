import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Faux document Firestore : permet de rejouer une partie dans les mêmes
/// écrans que la partie réelle (lecture seule).
class ReplayDoc implements DocumentSnapshot<Map<String, dynamic>> {
  ReplayDoc(this._d, this._id);

  final Map<String, dynamic> _d;
  final String _id;

  @override
  Map<String, dynamic>? data() => _d;

  @override
  bool get exists => true;

  @override
  String get id => _id;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Contrôleur d'une revue de partie : une liste d'états (« images »), dont
/// un seul est affiché à la fois.
class ReplayController {
  ReplayController(this.frames);

  final List<Map<String, dynamic>> frames;
  int index = 0;
  final StreamController<Map<String, dynamic>> _c =
      StreamController<Map<String, dynamic>>.broadcast();

  Map<String, dynamic> get current => frames[index];

  /// État affiché maintenant, puis chaque changement.
  Stream<Map<String, dynamic>> get stream async* {
    yield frames[index];
    yield* _c.stream;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> docs(String id) =>
      stream.map<DocumentSnapshot<Map<String, dynamic>>>(
          (m) => ReplayDoc(m, id));

  void seek(int i) {
    final n = i < 0 ? 0 : (i >= frames.length ? frames.length - 1 : i);
    if (n == index) return;
    index = n;
    if (!_c.isClosed) _c.add(frames[index]);
  }

  void dispose() => _c.close();
}
