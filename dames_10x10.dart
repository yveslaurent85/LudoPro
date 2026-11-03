import 'package:flutter/material.dart';

class Dames10x10Screen extends StatefulWidget {
  @override
  _Dames10x10ScreenState createState() => _Dames10x10ScreenState();
}

class _Dames10x10ScreenState extends State<Dames10x10Screen> {
  // Plateau 10x10 représenté par une liste de 100 cases
  // 0 = vide, 1 = pion blanc, 2 = dame blanche, 3 = pion noir, 4 = dame noire
  late List<int> board;
  int? selectedIndex;
  String turn = 'Blanc'; // 'Blanc' ou 'Noir'

  @override
  void initState() {
    super.initState();
    _initializeBoard();
  }

  void _initializeBoard() {
    board = List.filled(100, 0);
    // Placement initial des pions pour les dames internationales (10x10)
    // Les pions se jouent uniquement sur les cases sombres.
    for (int i = 0; i < 100; i++) {
      int row = i ~/ 10;
      int col = i % 10;
      if ((row + col) % 2 == 1) {
        if (row < 4) {
          board[i] = 3; // Pions noirs (lignes 0 à 3)
        } else if (row > 5) {
          board[i] = 1; // Pions blancs (lignes 6 à 9)
        }
      }
    }
  }

  bool _isDarkSquare(int index) {
    int row = index ~/ 10;
    int col = index % 10;
    return (row + col) % 2 == 1;
  }

  void _onSquareTap(int index) {
    if (!_isDarkSquare(index)) return;

    setState(() {
      if (selectedIndex == null) {
        // Sélectionner une pièce du joueur actif
        if (turn == 'Blanc' && (board[index] == 1 || board[index] == 2)) {
          selectedIndex = index;
        } else if (turn == 'Noir' && (board[index] == 3 || board[index] == 4)) {
          selectedIndex = index;
        }
      } else {
        // Déplacer la pièce vers une case vide
        if (board[index] == 0) {
          board[index] = board[selectedIndex!];
          board[selectedIndex!] = 0;
          turn = (turn == 'Blanc') ? 'Noir' : 'Blanc';
        }
        selectedIndex = null; // Désélectionner
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Damier International 10x10'),
        backgroundColor: Colors.brown[800],
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Tour : $turn',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 20),
          Center(
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(border: Border.all(color: Colors.brown, width: 4)),
              child: GridView.builder(
                physics: NeverScrollableScrollPhysics(),
                itemCount: 100,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 10,
                ),
                itemBuilder: (context, index) {
                  bool isDark = _isDarkSquare(index);
                  int piece = board[index];
                  bool isSelected = selectedIndex == index;

                  return GestureDetector(
                    onTap: () => _onSquareTap(index),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? Colors.brown[700] : Colors.brown[250],
                        border: isSelected ? Border.all(color: Colors.yellow, width: 3) : null,
                      ),
                      child: Center(
                        child: piece != 0
                            ? Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: (piece == 1 || piece == 2) ? Colors.white : Colors.black,
                                  border: Border.all(color: Colors.grey, width: 2),
                                ),
                                child: Center(
                                  child: (piece == 2 || piece == 4)
                                      ? Text('👑', style: TextStyle(fontSize: 12))
                                      : null,
                                ),
                              )
                            : null,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
