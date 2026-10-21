import 'dart:math';
import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _lancer() {
    _controller.forward(from: 0);
    setState(() {
      _de1 = _random.nextInt(6) + 1;
      _de2 = _random.nextInt(6) + 1;
    });
  }

  void _suivant() {
    setState(() {
      _tour++;
      _de1 = 1;
      _de2 = 1;
    });
    _controller.reset();
  }

  Widget _buildDe(int valeur) {
    return RotationTransition(
      turns: _controller,
      child: Container(
        width: 80,
        height: 80,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(width: 2),
        ),
        child: Text(
          '$valeur',
          style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
        ),
      ),
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
                _buildDe(_de1),
                const SizedBox(width: 24),
                _buildDe(_de2),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Total : ${_de1 + _de2}',
              style: const TextStyle(fontSize: 24),
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
