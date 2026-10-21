import 'dart:math';
import 'package:flutter/material.dart';

enum _Phase { reglage, mise, lancers, resultat }

class _Joueur {
  String nom;
  int jetons;
  int d1 = 1, d2 = 1;
  bool aLance = false;
  _Joueur(this.nom, this.jetons);
  int get total => d1 + d2;
}

class DeuxDesPage extends StatefulWidget {
  const DeuxDesPage({super.key});

  @override
  State<DeuxDesPage> createState() => _DeuxDesPageState();
}

class _DeuxDesPageState extends State<DeuxDesPage>
    with SingleTickerProviderStateMixin {
  static const _depart = 1000;
  static const _mises = [10, 50, 100, 500];

  final _rnd = Random();
  late final AnimationController _win = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400));
  late final Animation<double> _scale =
      CurvedAnimation(parent: _win, curve: Curves.elasticOut);

  _Phase _phase = _Phase.reglage;
  int _nb = 2;
  int _mise = 50;
  int _pot = 0;
  int _courant = 0;
  int _gen = 0;
  int _gain = 0;
  bool _anime = false;
  bool _egalite = false;
  List<_Joueur> _joueurs = [];
  List<_Joueur> _participants = [];
  List<_Joueur> _actifs = [];
  _Joueur? _gagnant;

  @override
  void dispose() {
    _win.dispose();
    super.dispose();
  }

  void _commencer() {
    setState(() {
      _joueurs = List.generate(_nb, (i) => _Joueur('Joueur ${i + 1}', _depart));
      _phase = _Phase.mise;
    });
  }

  void _recommencer() {
    setState(() {
      _gen++;
      _anime = false;
      _phase = _Phase.reglage;
    });
  }

  void _demarrerManche() {
    final p = _joueurs.where((j) => j.jetons >= _mise).toList();
    if (p.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pas assez de joueurs avec assez de jetons. Baisse la mise.')));
      return;
    }
    setState(() {
      for (final j in _joueurs) {
        j.d1 = 1;
        j.d2 = 1;
        j.aLance = false;
      }
      _participants = p;
      _actifs = List.of(p);
      _pot = 0;
      for (final j in p) {
        j.jetons -= _mise;
        _pot += _mise;
      }
      _egalite = false;
      _gagnant = null;
      _courant = 0;
      _anime = false;
      _phase = _Phase.lancers;
    });
  }

  Future<void> _lancer() async {
    if (_anime) return;
    final g = _gen;
    final j = _actifs[_courant];
    setState(() => _anime = true);
    for (var i = 0; i < 12; i++) {
      await Future.delayed(const Duration(milliseconds: 70));
      if (!mounted || g != _gen) return;
      setState(() {
        j.d1 = _rnd.nextInt(6) + 1;
        j.d2 = _rnd.nextInt(6) + 1;
      });
    }
    setState(() => j.aLance = true);
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted || g != _gen) return;
    _suivant();
  }

  void _suiva
