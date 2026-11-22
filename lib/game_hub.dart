import 'package:flutter/material.dart' hide Text;

import 'lang.dart';
import 'rules.dart' show showGameInfo;

/// Une partie ouverte, telle qu'elle apparaît dans la liste d'un jeu.
class HubGame {
  const HubGame({
    required this.id,
    required this.host,
    this.badges = const [],
    this.stake = 0,
    this.players = '',
  });

  final String id;
  final String host;
  final List<String> badges; // ex. « 2v2 »
  final int stake; // 0 = gratuit
  final String players; // ex. « 1/2 »
}

const Color _hubBg = Color(0xFFF3F6FF);
const Color _hubInk = Color(0xFF12183A);
const Color _hubMuted = Color(0xFF56608A);
const Color _hubLine = Color(0xFFD5DEF5);
const Color _hubBlue = Color(0xFF2F6FE4);
const Color _hubGreen = Color(0xFF17883F);
const Color _hubRed = Color(0xFFDC2626);

/// Page d'un jeu (même modèle pour Ludo, Deux dés, Tiah, Fap-Fap…) :
/// Présentiel · En ligne, puis la liste des parties ouvertes à rejoindre.
class GameHubPage extends StatefulWidget {
  const GameHubPage({
    super.key,
    required this.title,
    required this.icon,
    required this.accent,
    required this.onOnline,
    required this.onJoin,
    required this.source,
    this.onPresentiel,
    this.onTournois,
    this.infoKey,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Color accent;
  final String? infoKey;
  final VoidCallback? onPresentiel; // null : jeu 100 % en ligne
  /// Salon en ligne ; [mode] : « create », « code » (partie privée) ou « live » (en direct).
  final void Function(String mode) onOnline;
  final VoidCallback? onTournois;
  final void Function(HubGame game) onJoin;
  final Stream<List<HubGame>> Function() source;

  @override
  State<GameHubPage> createState() => _GameHubPageState();
}

class _GameHubPageState extends State<GameHubPage> {
  late final Stream<List<HubGame>> _stream = widget.source();
  bool _menu = false; // menu « Créer ou rejoindre » déplié

  Widget _chip(String label, IconData icon, Color bg, Color fg, VoidCallback? f, {bool outline = false}) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Material(
        color: outline ? const Color(0xFFE3EAFF) : bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: outline ? _hubBlue : bg),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: f,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 5),
                Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(color: widget.accent, width: 5),
          top: const BorderSide(color: _hubLine),
          right: const BorderSide(color: _hubLine),
          bottom: const BorderSide(color: _hubLine),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: widget.accent.withOpacity(0.14), shape: BoxShape.circle),
            child: Icon(widget.icon, color: widget.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _hubInk, fontSize: 20, fontWeight: FontWeight.w900)),
                if (widget.subtitle != null)
                  Text(widget.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _hubMuted, fontSize: 11)),
              ],
            ),
          ),
          if (widget.onTournois != null)
            _chip(tr('Tournois', 'Tournaments'), Icons.emoji_events_outlined, _hubRed, Colors.white, widget.onTournois),
          if (widget.infoKey != null)
            _chip(tr('Règles', 'Rules'), Icons.info_outline, _hubBlue, _hubBlue,
                () => showGameInfo(context, widget.infoKey!),
                outline: true),
        ],
      ),
    );
  }

  Widget _bigButton(String label, IconData icon, Color color, VoidCallback f) {
    return SizedBox(
      height: 58,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: f,
        icon: Icon(icon),
        label: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
      ),
    );
  }

  Widget _menuItem(IconData icon, Color color, String label, String mode, bool line) {
    return InkWell(
      onTap: () {
        setState(() => _menu = false);
        widget.onOnline(mode);
      },
      child: Container(
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          border: line ? const Border(bottom: BorderSide(color: _hubLine)) : null,
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 18),
            Expanded(
              child: Text(label,
                  style: const TextStyle(color: _hubInk, fontSize: 17, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String t, Color bg, Color fg) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Text(t, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w800)),
      );

  Widget _row(HubGame g) {
    final free = g.stake <= 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _hubLine))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(g.host,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _hubInk, fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    for (final b in g.badges) _pill(b, const Color(0xFF7C3AED), Colors.white),
                  ],
                ),
                if (g.players.isNotEmpty)
                  Text('${g.players} ${tr('joueurs', 'players')}',
                      style: const TextStyle(color: _hubMuted, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 44,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _hubBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => widget.onJoin(g),
              icon: const Icon(Icons.play_circle_outline, size: 20),
              label: Text(tr('Rejoindre', 'Join'), style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          _pill(free ? tr('GRATUIT', 'FREE') : '${g.stake} FCFA', free ? const Color(0xFFE3EAFF) : _hubGreen,
              free ? _hubBlue : Colors.white),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _hubBg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: tr('Retour', 'Back'),
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back, color: _hubInk),
                  ),
                ],
              ),
            ),
            _header(),
            Expanded(
              child: StreamBuilder<List<HubGame>>(
                stream: _stream,
                builder: (context, snap) {
                  final games = snap.data ?? const <HubGame>[];
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    children: [
                      if (widget.onPresentiel != null) ...[
                        _bigButton(tr('Présentiel', 'Face to face'), Icons.groups, _hubGreen, widget.onPresentiel!),
                        const SizedBox(height: 10),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: _bigButton(tr('Créer ou rejoindre en ligne', 'Create or join online'),
                                _menu ? Icons.keyboard_arrow_up : Icons.add_circle_outline, _hubBlue,
                                () => setState(() => _menu = !_menu)),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            height: 58,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: _hubGreen, width: 2),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('${games.length}',
                                    style: const TextStyle(color: _hubGreen, fontSize: 18, fontWeight: FontWeight.w900)),
                                Text(tr('en attente', 'waiting'),
                                    style: const TextStyle(color: _hubGreen, fontSize: 11)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (_menu) ...[
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _hubLine),
                            boxShadow: const [BoxShadow(color: Color(0x1F12183A), blurRadius: 18, offset: Offset(0, 8))],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              _menuItem(Icons.add_box_outlined, _hubGreen, tr('Créer une nouvelle partie', 'Create a new game'), 'create', true),
                              _menuItem(Icons.vpn_key_outlined, _hubBlue, tr('Rejoindre cette partie privée ?', 'Join a private game?'), 'code', true),
                              _menuItem(Icons.sensors, _hubRed, tr('En direct', 'Live'), 'live', false),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _hubLine),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: snap.hasError
                            ? Padding(
                                padding: const EdgeInsets.all(20),
                                child: Text(tr('Impossible de charger les parties.', 'Could not load the games.'),
                                    style: const TextStyle(color: _hubMuted)),
                              )
                            : !snap.hasData
                                ? const Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Center(child: CircularProgressIndicator()),
                                  )
                                : games.isEmpty
                                    ? Padding(
                                        padding: const EdgeInsets.all(20),
                                        child: Text(
                                            tr('Aucune partie ouverte pour le moment. Crée la tienne !',
                                                'No open game right now. Create yours!'),
                                            style: const TextStyle(color: _hubMuted)),
                                      )
                                    : Column(children: [for (final g in games) _row(g)]),
                      ),
                    ],
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
