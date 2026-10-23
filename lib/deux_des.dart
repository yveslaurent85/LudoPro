import 'dart:math';

import 'package:flutter/material.dart';

import 'dice3d.dart';

class DeuxDesPage extends StatefulWidget {
  const DeuxDesPage({super.key});

  @override
  State<DeuxDesPage> createState() => _DeuxDesPageState();
}

class _DeuxDesPageState extends State<DeuxDesPage>
    with SingleTickerProviderStateMixin {
  final _random = Random();
  late final AnimationController _controller;

  int _de1 = 1;
  int _de2 = 1;
  int _tour = 1;
  List<int> _spin1 = [2, 3, 1];
  List<int> _spin2 = [3, 2, 2];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
      value: 1.0, // au repos
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<int> _randomSpin() => [
        (_random.nextBool() ? 1 : -1) * (1 + _random.nextInt(2)),
        (_random.nextBool() ? 1 : -1) * (2 + _random.nextInt(2)),
        (_random.nextBool() ? 1 : -1) * (1 + _random.nextInt(2)),
      ];

  void _lancer() {
    if (_controller.isAnimating) return;
    setState(() {
      _de1 = _random.nextInt(6) + 1;
      _de2 = _random.nextInt(6) + 1;
      _spin1 = _randomSpin();
      _spin2 = _randomSpin();
    });
    _controller.forward(from: 0);
  }

  void _suivant() {
    setState(() {
      _tour++;
      _de1 = 1;
      _de2 = 1;
    });
    _controller.value = 1.0;
  }

  Widget _buildDe(int valeur, List<int> spin) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final bounce = sin(t * pi * 4).abs() * (1 - t) * 30;
        return Transform.translate(
          offset: Offset(0, -bounce),
          child: SizedBox(
            width: 110,
            height: 110,
            child: Die3D(
              value: valeur,
              t: t,
              spin: spin,
              glow: _controller.isAnimating,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Tour $_tour')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildDe(_de1, _spin1),
                const SizedBox(width: 24),
                _buildDe(_de2, _spin2),
              ],
            ),
            const SizedBox(height: 16),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Text(
                _controller.isAnimating
                    ? '...'
                    : 'Total : ${_de1 + _de2}',
                style: const TextStyle(fontSize: 24),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(onPressed: _lancer, child: const Text('Lancer')),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _suivant, child: const Text('Suivant')),
          ],
        ),
      ),
    );
  }
}
