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

  void _suivant() {
    if (_courant + 1 < _actifs.length) {
      setState(() {
        _courant++;
        _anime = false;
      });
      return;
    }
    final best = _actifs.map((j) => j.total).reduce(max);
    final top = _actifs.where((j) => j.total == best).toList();
    if (top.length > 1) {
      // Égalité : seuls les ex æquo relancent
      setState(() {
        _egalite = true;
        _actifs = top;
        _courant = 0;
        _anime = false;
        for (final j in top) {
          j.aLance = false;
        }
      });
      return;
    }
    final w = top.first;
    setState(() {
      _gagnant = w;
      _gain = _pot;
      w.jetons += _pot;
      _pot = 0;
      _anime = false;
      _phase = _Phase.resultat;
    });
    _win.forward(from: 0);
  }

  String _message() {
    switch (_phase) {
      case _Phase.mise:
        return 'Choisis la mise : chaque joueur paie la même mise';
      case _Phase.lancers:
        return _egalite
            ? 'Égalité ! Les ex æquo relancent'
            : 'Le plus grand total gagne';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1E3F),
      appBar: AppBar(
        title: const Text('2 Dés'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_phase != _Phase.reglage)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Recommencer',
              onPressed: _recommencer,
            ),
        ],
      ),
      body: SafeArea(
          child: _phase == _Phase.reglage ? _reglage() : _jeu()),
    );
  }

  Widget _reglage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎲🎲', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            const Text('Nombre de joueurs',
                style: TextStyle(color: Colors.white, fontSize: 18)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (var n = 2; n <= 6; n++)
                  ChoiceChip(
                    label: Text('$n'),
                    selected: _nb == n,
                    onSelected: (_) => setState(() => _nb = n),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton(
                onPressed: _commencer, child: const Text('Commencer')),
            const SizedBox(height: 12),
            Text('Chacun démarre avec $_depart jetons',
                style: const TextStyle(color: Colors.white54)),
          ],
        ),
      ),
    );
  }

  Widget _jeu() {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Text('Pot : $_pot jetons',
                  style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(_message(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              Expanded(child: ListView(children: _joueurs.map(_carte).toList())),
              const SizedBox(height: 8),
              _actions(),
            ],
          ),
        ),
        if (_phase == _Phase.resultat && _gagnant != null) _overlay(),
      ],
    );
  }

  Widget _carte(_Joueur j) {
    final enJeu = _phase == _Phase.mise ? true : _participants.contains(j);
    final actif =
        _phase == _Phase.lancers && _actifs.isNotEmpty && _actifs[_courant] == j;
    return Opacity(
      opacity: enJeu ? 1 : 0.4,
      child: Card(
        color: actif ? const Color(0xFF1F4E9C) : const Color(0xFF14305E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
              color: actif ? Colors.amber : Colors.transparent, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(j.nom,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    Text('${j.jetons} jetons',
                        style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
              _De(j.d1),
              const SizedBox(width: 8),
              _De(j.d2),
              const SizedBox(width: 12),
              SizedBox(
                width: 28,
                child: Text(j.aLance ? '${j.total}' : '–',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.amber,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions() {
    switch (_phase) {
      case _Phase.mise:
        return Column(
          children: [
            Wrap(
              spacing: 8,
              children: _mises
                  .map((m) => ChoiceChip(
                        label: Text('$m'),
                        selected: _mise == m,
                        onSelected: (_) => setState(() => _mise = m),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _demarrerManche,
                child: Text('Lancer la manche (mise $_mise)'),
              ),
            ),
          ],
        );
      case _Phase.lancers:
        {
          final nom = _actifs[_courant].nom;
          return SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _anime ? null : _lancer,
              child: Text('$nom : lancer les 2 dés'),
            ),
          );
        }
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _overlay() {
    final w = _gagnant!;
    return Positioned.fill(
      child: Container(
        color: Colors.black87,
        child: Center(
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('💰🏆💰', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 8),
                const Text('KATIKA !',
                    style: TextStyle(
                        color: Color(0xFFFFC107),
                        fontSize: 56,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text('${w.nom} décharge les caisses',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 20)),
                const SizedBox(height: 4),
                Text('avec un ${w.total} • +$_gain jetons',
                    style: const TextStyle(color: Colors.amber, fontSize: 18)),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => setState(() => _phase = _Phase.mise),
                  child: const Text('Manche suivante'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _De extends StatelessWidget {
  final int v;
  const _De(this.v);

  static const _pts = {
    1: [4],
    2: [0, 8],
    3: [0, 4, 8],
    4: [0, 2, 6, 8],
    5: [0, 2, 4, 6, 8],
    6: [0, 2, 3, 5, 6, 8],
  };

  @override
  Widget build(BuildContext context) {
    final pts = _pts[v]!;
    return Container(
      width: 44,
      height: 44,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: GridView.count(
        crossAxisCount: 3,
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        children: List.generate(
          9,
          (i) => pts.contains(i)
              ? Container(
                  margin: const EdgeInsets.all(1.5),
                  decoration: const BoxDecoration(
                      color: Colors.black87, shape: BoxShape.circle),
                )
              : const SizedBox(),
        ),
      ),
    );
  }
}
