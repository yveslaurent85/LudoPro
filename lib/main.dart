Excellent ! 🎉👏 Maintenant, nous allons donner à LudoPro une interface beaucoup plus colorée et professionnelle.
🎲 Étape 3 : Copier le nouveau code
Attention : copie tout le code ci-dessous, du début jusqu'à la dernière ligne, puis colle-le dans ton fichier lib/main.dart.
import 'dart:math';
import 'package:flutter/material.dart';

void main() {
  runApp(const LudoProApp());
}

const Color navy = Color(0xFF10172A);
const Color redLudo = Color(0xFFFF4757);
const Color greenLudo = Color(0xFF2ED573);
const Color yellowLudo = Color(0xFFFFD32A);
const Color blueLudo = Color(0xFF3742FA);

class LudoProApp extends StatelessWidget {
  const LudoProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LudoPro',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: navy,
        colorScheme: ColorScheme.fromSeed(
          seedColor: blueLudo,
          brightness: Brightness.dark,
        ),
        fontFamily: 'Roboto',
      ),
      home: const LudoHomePage(),
    );
  }
}

class LudoHomePage extends StatefulWidget {
  const LudoHomePage({super.key});

  @override
  State<LudoHomePage> createState() => _LudoHomePageState();
}

class _LudoHomePageState extends State<LudoHomePage> {
  int dice = 1;
  int position = 0;
  int player = 0;

  final Random random = Random();

  final List<Color> colors = [
    redLudo,
    greenLudo,
    yellowLudo,
    blueLudo,
  ];

  final List<String> players = [
    'ROUGE',
    'VERT',
    'JAUNE',
    'BLEU',
  ];

  void rollDice() {
    setState(() {
      dice = random.nextInt(6) + 1;
      position += dice;
      player = (player + 1) % 4;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              const SizedBox(height: 12),

              Row(
                children: [
                  Container(
                    height: 55,
                    width: 55,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [blueLudo, Color(0xFF8B5CF6)],
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.casino_rounded,
                      size: 32,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LudoPro',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'JOUE • DÉFIE • GAGNE',
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 2,
                            color: Color(0xFFB8C4E0),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.account_circle_rounded,
                    color: Colors.white,
                    size: 38,
                  ),
                ],
              ),

              const SizedBox(height: 28),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF293A80),
                      Color(0xFF552B88),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PRÊT À JOUER ? 🎲',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'La bataille commence !',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Retrouve tes amis et deviens le champion.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'TON PLATEAU',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF202B43),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '4 JOUEURS',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF222D42),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 36,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 6,
                      crossAxisSpacing: 3,
                      mainAxisSpacing: 3,
                    ),
                    itemBuilder: (context, index) {
                      Color cellColor = const Color(0xFFF4F6FB);
                      IconData? icon;

                      if (index < 12) {
                        cellColor = const Color(0xFFFFE1E4);
                      }

                      if (index >= 12 && index < 18) {
                        cellColor = const Color(0xFFD9FBE5);
                      }

                      if (index >= 18 && index < 24) {
                        cellColor = const Color(0xFFFFF3C4);
                      }

                      if (index >= 24) {
                        cellColor = const Color(0xFFDDE3FF);
                      }

                      if ([0, 5, 30, 35].contains(index)) {
                        icon = Icons.circle;
                      }

                      if ([14, 15, 20, 21].contains(index)) {
                        cellColor = Colors.white;
                        icon = Icons.star_rounded;
                      }

                      if (index == 2 || index == 33) {
                        icon = Icons.home_rounded;
                      }

                      Color iconColor = blueLudo;

                      if (index < 12) {
                        iconColor = redLudo;
                      } else if (index < 18) {
                        iconColor = greenLudo;
                      } else if (index < 24) {
                        iconColor = yellowLudo;
                      }

                      if (index >= 24) {
                        iconColor = blueLudo;
                      }

                      return Container(
                        decoration: BoxDecoration(
                          color: cellColor,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Center(
                          child: icon == null
                              ? null
                              : Icon(
                                  icon,
                                  color: iconColor,
                                  size: index == 14 ||
                                          index == 15 ||
                                          index == 20 ||
                                          index == 21
                                      ? 24
                                      : 18,
                                ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 22),

              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF19243A),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: colors[player],
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Center(
                        child: Text(
                          '$dice',
                          style: const TextStyle(
                            fontSize: 38,
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'AU TOUR DE',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            players[player],
                            style: TextStyle(
                              color: colors[player],
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'Position : $position',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.casino_rounded,
                      color: colors[player],
                      size: 38,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: rollDice,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7158F5),
                    foregroundColor: Colors.white,
                    elevation: 5,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.casino_rounded, size: 27),
                      SizedBox(width: 10),
                      Text(
                        'LANCER LE DÉ',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              Row(
                children: [
                  Expanded(
                    child: _menuButton(
                      icon: Icons.play_arrow_rounded,
                      label: 'JOUER',
                      color: greenLudo,
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Le mode de jeu complet sera ajouté ensuite !',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _menuButton(
                      icon: Icons.people_alt_rounded,
                      label: 'AVEC DES AMIS',
                      color: blueLudo,
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Le mode amis sera développé ensuite !',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              _menuButton(
                icon: Icons.emoji_events_rounded,
                label: 'CLASSEMENT',
                color: yellowLudo,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Le classement sera ajouté prochainement !',
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 25),

              const Text(
                'LudoPro • Joue avec passion ❤️',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                ),
              ),

              const SizedBox(height: 15),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 55,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: navy,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
📱 Étape 4 : Enregistrer le nouveau code
Après avoir collé le code :
Vérifie que le début du fichier commence par import 'dart:math';.
Descends jusqu'à la fin pour vérifier que le code est complet.
Appuie sur Commit changes.
Confirme avec Commit changes si GitHub te le demande.
GitHub lancera ensuite la compilation de l'application.
Important : cette version améliore l'interface et le bouton du dé. Le véritable jeu de Ludo et le mode multijoueur ne sont pas encore implémentés.
Dis-moi quand tu as collé le code.
Réponds simplement : « Code collé ». Je te guiderai ensuite pour l'enregistrer et télécharger la nouvelle version de LudoPro. 🎲🌈
