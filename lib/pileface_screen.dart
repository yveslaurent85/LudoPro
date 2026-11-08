import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;

import 'accounts.dart';
import 'lang.dart';

const Color _kGold = Color(0xFFFFC21A);

String _pfFcfa(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return '${b.toString()} FCFA';
}

String _sideName(String s) => s == 'face' ? 'FACE' : 'PILE';

/// Une face de la pièce (dessinée, sans image).
class _CoinFace extends StatelessWidget {
  const _CoinFace({required this.side, required this.size});

  final String side;
  final double size;

  @override
  Widget build(BuildContext context) {
    final face = side == 'face';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.3, -0.4),
          radius: 1.0,
          colors: [Color(0xFFFFE9A0), Color(0xFFFFC21A), Color(0xFFC98A00)],
          stops: [0.0, 0.55, 1.0],
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 14)),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size * 0.86,
            height: size * 0.86,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF9A6700), width: 2.5),
            ),
          ),
          Container(
            width: size * 0.7,
            height: size * 0.7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFFFF3C4), width: 2),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                face ? 'K' : '100',
                style: TextStyle(
                  color: const Color(0xFF7A4E00),
                  fontSize: face ? size * 0.46 : size * 0.34,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
              Text(
                face ? 'FACE' : 'PILE',
                style: TextStyle(
                  color: const Color(0xFF7A4E00),
                  fontSize: size * 0.085,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Pièce qui tourne sur elle-même et s'arrête sur [result] ('pile' | 'face').
class _FlipCoin extends StatefulWidget {
  const _FlipCoin({required this.result, required this.size, this.onDone});

  final String result;
  final double size;
  final VoidCallback? onDone;

  @override
  State<_FlipCoin> createState() => _FlipCoinState();
}

class _FlipCoinState extends State<_FlipCoin> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final double _turns; // demi-tours : pair = face visible au départ (FACE)

  @override
  void initState() {
    super.initState();
    // Départ : FACE visible. Nombre impair de demi-tours : PILE visible à l'arrivée.
    final base = 10; // 5 tours complets
    _turns = (base + (widget.result == 'pile' ? 1 : 0)).toDouble();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onDone?.call();
      })
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_c.value);
        final angle = t * _turns * pi;
        final front = cos(angle) >= 0;
        final lift = sin(_c.value * pi) * widget.size * 0.45;
        return SizedBox(
          width: widget.size,
          height: widget.size * 1.5,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Transform.translate(
              offset: Offset(0, -lift),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..rotateX(angle),
                child: Transform.scale(
                  scaleY: front ? 1 : -1,
                  child: _CoinFace(side: front ? 'face' : 'pile', size: widget.size),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Écran du résultat : la pièce tourne, puis on annonce gagné / perdu.
class _PfResultPage extends StatefulWidget {
  const _PfResultPage({required this.r});

  final Map<String, dynamic> r;

  @override
  State<_PfResultPage> createState() => _PfResultPageState();
}

class _PfResultPageState extends State<_PfResultPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    final won = r['won'] == true;
    final result = '${r['result']}';
    final mySide = '${r['mySide']}';
    final stake = (r['stake'] as num?)?.toInt() ?? 0;
    final gain = (r['gain'] as num?)?.toInt() ?? 0;
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1F5BFF), Color(0xFF0B2FA6), Color(0xFF061A66)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Text(
                  '${tr('Tu joues', 'You play')} ${_sideName(mySide)} • ${_pfFcfa(stake)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Center(
                    child: _FlipCoin(
                      result: result,
                      size: 190,
                      onDone: () {
                        if (mounted) setState(() => _done = true);
                      },
                    ),
                  ),
                ),
                AnimatedOpacity(
                  opacity: _done ? 1 : 0,
                  duration: const Duration(milliseconds: 350),
                  child: Column(
                    children: [
                      Text(
                        '${_sideName(result)} !',
                        style: const TextStyle(color: _kGold, fontSize: 38, fontWeight: FontWeight.w900, letterSpacing: 2),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: won ? const Color(0xFF108A3E) : const Color(0xFF9E1F18),
                        ),
                        child: Column(
                          children: [
                            Text(
                              won
                                  ? tr('Gagné ! +${_pfFcfa(gain)}', 'You won! +${_pfFcfa(gain)}')
                                  : tr('Perdu ! −${_pfFcfa(stake)}', 'You lost! −${_pfFcfa(stake)}'),
                              style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${tr('Adversaire', 'Opponent')} : ${r['opponentName']}',
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _kGold, foregroundColor: const Color(0xFF1A1200)),
                    onPressed: _done ? () => Navigator.of(context).pop() : null,
                    child: Text(tr('Continuer', 'Continue'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
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

/// Pile ou Face : défis à deux, le serveur tire la pièce.
class PileFaceScreen extends StatefulWidget {
  const PileFaceScreen({super.key});

  @override
  State<PileFaceScreen> createState() => _PileFaceScreenState();
}

class _PileFaceScreenState extends State<PileFaceScreen> {
  static const List<int> _stakes = [100, 500, 1000, 2000];

  bool _loading = true;
  bool _busy = false;
  String? _error;
  int _balance = 0;
  List<Map<String, dynamic>> _open = [];
  List<Map<String, dynamic>> _done = [];
  String _side = 'pile';
  int _stake = 500;
  Timer? _timer;
  Set<String>? _seenDone; // tirages déjà vus (pour annoncer ceux de mes défis relevés)

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && !_busy) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final r = await Wallet.pfList();
      final open = (r['open'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final done = (r['done'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      final ids = done.map((d) => '${d['id']}').toSet();
      final fresh = _seenDone == null ? <Map<String, dynamic>>[] : done.where((d) => !_seenDone!.contains('${d['id']}')).toList();
      setState(() {
        _balance = (r['balance'] as num?)?.toInt() ?? 0;
        _open = open;
        _done = done;
        _error = null;
        _loading = false;
      });
      _seenDone = ids;
      // Quelqu'un a relevé l'un de mes défis : on montre le tirage.
      if (fresh.isNotEmpty && !_busy) {
        final d = fresh.first;
        _showResult({
          'result': d['result'],
          'mySide': d['mySide'],
          'won': d['won'],
          'gain': d['gain'],
          'stake': d['stake'],
          'opponentName': d['opponentName'],
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (!silent) setState(() { _error = Wallet.errorText(e); _loading = false; });
    }
  }

  Future<void> _showResult(Map<String, dynamic> r) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _PfResultPage(r: r)));
    if (mounted) _load(silent: true);
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _create() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await Wallet.pfCreate(stake: _stake, side: _side);
      _snack(tr('Défi lancé : il attend un adversaire.', 'Challenge posted: waiting for an opponent.'));
    } catch (e) {
      _snack(Wallet.errorText(e));
    }
    if (mounted) setState(() => _busy = false);
    await _load(silent: true);
  }

  Future<void> _join(Map<String, dynamic> g) async {
    if (_busy) return;
    final stake = (g['stake'] as num).toInt();
    final other = g['hostSide'] == 'pile' ? 'face' : 'pile';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Relever le défi', 'Accept the challenge')),
        content: Text(tr(
          '${_pfFcfa(stake)} seront débités. Tu joues ${_sideName(other)} contre ${g['hostName']}. La pièce est tirée tout de suite.',
          '${_pfFcfa(stake)} will be taken. You play ${_sideName(other)} against ${g['hostName']}. The coin is flipped right away.',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Annuler', 'Cancel'))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Jouer', 'Play'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final r = await Wallet.pfJoin('${g['id']}');
      if (!mounted) return;
      setState(() => _balance = (r['balance'] as num?)?.toInt() ?? _balance);
      _seenDone?.add('${r['gameId']}');
      await _showResult(r);
    } catch (e) {
      _snack(Wallet.errorText(e));
    }
    if (mounted) setState(() => _busy = false);
    await _load(silent: true);
  }

  Future<void> _cancel(Map<String, dynamic> g) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await Wallet.pfCancel('${g['id']}');
      _snack(tr('Défi annulé, mise remboursée.', 'Challenge cancelled, stake refunded.'));
    } catch (e) {
      _snack(Wallet.errorText(e));
    }
    if (mounted) setState(() => _busy = false);
    await _load(silent: true);
  }

  void _rules() {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Pile ou Face', 'Heads or Tails')),
        content: Text(tr(
          '• Tu choisis ton côté (PILE ou FACE) et ta mise, puis tu lances un défi.\n'
          '• Un autre joueur relève le défi avec la même mise : il prend l\'autre côté.\n'
          '• La pièce est tirée au hasard par le serveur, à égalité de chances.\n'
          '• Le gagnant reçoit les 2 mises moins 5 % de commission.\n'
          '• Tant que personne n\'a relevé ton défi, tu peux l\'annuler : ta mise est rendue.',
          '• Pick your side (PILE or FACE) and your stake, then post a challenge.\n'
          '• Another player accepts with the same stake: they take the other side.\n'
          '• The server flips the coin at random, with equal chances.\n'
          '• The winner gets both stakes minus a 5 % commission.\n'
          '• While nobody has accepted your challenge you can cancel it: your stake is refunded.',
        )),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Fermer', 'Close')))],
      ),
    );
  }

  Widget _panel(List<Widget> children) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(s, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700)),
      );

  Widget _sideBtn(String s) {
    final on = _side == s;
    return Expanded(
      child: GestureDetector(
        onTap: _busy ? null : () => setState(() => _side = s),
        child: Container(
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: on ? _kGold : Colors.white.withOpacity(0.1),
            border: Border.all(color: on ? _kGold : Colors.white38, width: 2),
          ),
          child: Text(_sideName(s),
              style: TextStyle(color: on ? const Color(0xFF1A1200) : Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gain = ((_stake * 2) * 95) ~/ 100;
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1F5BFF), Color(0xFF0B2FA6), Color(0xFF061A66)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
                child: Row(
                  children: [
                    IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back, color: Colors.white)),
                    const Expanded(
                      child: Text('Pile ou Face', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                    ),
                    IconButton(onPressed: _rules, icon: const Icon(Icons.info_outline, color: _kGold)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _kGold, width: 1.5),
                      ),
                      child: Text(_pfFcfa(_balance), style: const TextStyle(color: _kGold, fontWeight: FontWeight.w800, fontSize: 13)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: _kGold))
                    : _error != null
                        ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!, style: const TextStyle(color: Colors.white))))
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                            children: [
                              Center(child: _CoinFace(side: _side, size: 150)),
                              const SizedBox(height: 16),
                              _label(tr('Choisis ton côté', 'Pick your side')),
                              Row(children: [_sideBtn('pile'), const SizedBox(width: 12), _sideBtn('face')]),
                              const SizedBox(height: 14),
                              _label(tr('Ta mise', 'Your stake')),
                              Row(
                                children: [
                                  for (final s in _stakes) ...[
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: _busy ? null : () => setState(() => _stake = s),
                                        child: Container(
                                          height: 44,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(14),
                                            color: _stake == s ? Colors.white : Colors.white.withOpacity(0.1),
                                            border: Border.all(color: _stake == s ? Colors.white : Colors.white30, width: 1.5),
                                          ),
                                          child: Text(
                                            s >= 1000 ? '${s ~/ 1000} 000' : '$s',
                                            style: TextStyle(
                                                color: _stake == s ? const Color(0xFF0B2FA6) : Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (s != _stakes.last) const SizedBox(width: 8),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(16)),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        tr('Gain si tu gagnes\n(2 mises − 5 %)', 'Prize if you win\n(2 stakes − 5 %)'),
                                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                                      ),
                                    ),
                                    Text(_pfFcfa(gain), style: const TextStyle(color: Color(0xFF7CFFB0), fontSize: 21, fontWeight: FontWeight.w900)),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 54,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF22B14C),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                  ),
                                  onPressed: _busy ? null : _create,
                                  child: Text(
                                    '${tr('Lancer le défi', 'Post the challenge')} · ${_pfFcfa(_stake)}',
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              _label(tr('Défis ouverts', 'Open challenges')),
                              if (_open.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(tr('Aucun défi pour le moment. Lance le premier !', 'No challenge yet. Post the first one!'),
                                      style: const TextStyle(color: Colors.white70)),
                                ),
                              for (final g in _open)
                                _panel([
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: _kGold,
                                        foregroundColor: const Color(0xFF1A1200),
                                        child: Text(('${g['hostName']}'.isEmpty ? '?' : '${g['hostName']}'[0]).toUpperCase(),
                                            style: const TextStyle(fontWeight: FontWeight.w900)),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('${g['hostName']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                                            Text(
                                              '${_pfFcfa((g['stake'] as num).toInt())} · ${tr('joue', 'plays')} ${_sideName('${g['hostSide']}')}',
                                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (g['hostUid'] == _myUid)
                                        OutlinedButton(
                                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                                          onPressed: _busy ? null : () => _cancel(g),
                                          child: Text(tr('Annuler', 'Cancel')),
                                        )
                                      else
                                        FilledButton(
                                          style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF0B2FA6)),
                                          onPressed: _busy ? null : () => _join(g),
                                          child: Text(tr('Relever', 'Accept'), style: const TextStyle(fontWeight: FontWeight.w800)),
                                        ),
                                    ],
                                  ),
                                ]),
                              const SizedBox(height: 6),
                              _label(tr('Mes derniers tirages', 'My last flips')),
                              if (_done.isEmpty)
                                Text(tr('Aucun tirage pour le moment.', 'No flips yet.'), style: const TextStyle(color: Colors.white70)),
                              for (final d in _done)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 38,
                                        height: 38,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: d['won'] == true ? const Color(0xFF108A3E) : const Color(0xFF9E1F18),
                                        ),
                                        child: Text('${d['result']}' == 'face' ? 'F' : 'P',
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          '${d['won'] == true ? tr('Gagné', 'Won') : tr('Perdu', 'Lost')} · ${_sideName('${d['mySide']}')} · ${d['opponentName']}',
                                          style: const TextStyle(color: Colors.white, fontSize: 13),
                                        ),
                                      ),
                                      Text(
                                        d['won'] == true ? '+${_pfFcfa((d['gain'] as num).toInt())}' : '−${_pfFcfa((d['stake'] as num).toInt())}',
                                        style: TextStyle(
                                            color: d['won'] == true ? const Color(0xFF7CFFB0) : const Color(0xFFFFB4A8),
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';
}
