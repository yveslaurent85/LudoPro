return Container(
margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
padding: const EdgeInsets.all(12),
decoration: BoxDecoration(
color: Colors.black26,
borderRadius: BorderRadius.circular(16),
border: Border.all(color: Colors.white24),
),
child: Column(
children: [
Text(
gameOver ? 'PARTIE TERMINÉE' : 'Au tour de ${player.display}',
style: TextStyle(
color: shade(player.color, 0.25),
fontWeight: FontWeight.bold,
fontSize: 17,
),
),
const SizedBox(height: 5),
Text(
message,
textAlign: TextAlign.center,
style: const TextStyle(color: Colors.white70),
),
],
),
);
}

Widget buildDice() {
final player = players
