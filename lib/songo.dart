import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import 'accounts.dart';
import 'game_chat.dart';
import 'lang.dart';
import 'main.dart';
import 'online_screen.dart';
import 'stake_field.dart';

// ----------------------------------------------------------------------
// Songô : jeu de semis (mancala) camerounais pour 2 joueurs.
//  • 14 cases (2 rangées de 7), 5 graines par case au départ (70 graines).
//  • Semis dans le sens des aiguilles d'une montre ; la case de départ est
//    toujours sautée (grenier).
//  • Capture : la dernière graine tombe chez l'adversaire et la case compte
//    2, 3 ou 4 graines -> on les prend, puis on remonte en arrière (rafle).
//    La première case du camp adverse (case d'entrée) n'est jamais prise.
//  • Interdit d'affamer : une rafle qui viendrait à vider tout le camp
//    adverse est annulée ; si l'adversaire n'a plus de graines, il faut lui
//    en envoyer.
//  • Victoire : 36 graines capturées ou plus.
// En ligne : collection Firestore « songo » (règles à ajouter).
// ----------------------------------------------------------------------

const int kSongoWin = 36;
const int kSongoMoveCap = 400;
const int kSongoTurnSecs = 45;

const BoxDecoration _bg = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1F5BFF), Color(0xFF0B2FA6), Color(0xFF061A66)],
  ),
);

const List<Color> _seatColor = [Color(0xFFFFC21A), Color(0xFF22B14C)];
const Color _gold = Color(0xFFFFC21A);
const Color _goldSoft = Color(0xFFFFE082);

// ======================================================================
// Règles du jeu
// ======================================================================

class SongoSow {
  SongoSow(this.board, this.captured, this.last, this.cancelled);
  final List<int> board;
  final int captured;
  final int last;
  final bool cancelled;
}

class SongoEngine {
  /// Premier index du camp du joueur [p] (0 : cases 0-6, 1 : cases 7-13).
  static int base(int p) => p * 7;
  static bool owns(int p, int i) => i >= base(p) && i < base(p) + 7;

  static int sideSum(List<int> b, int p) {
    var s = 0;
    for (int i = base(p); i < base(p) + 7; i++) {
      s += b[i];
    }
    return s;
  }

  static int total(List<int> b) => b.fold(0, (a, x) => a + x);

  static List<int> start() => List<int>.filled(14, 5);

  /// Joue la case [pit] du joueur [p] (sans vérifier la légalité).
  static SongoSow sow(List<int> board, int p, int pit) {
    final b = List<int>.from(board);
    var seeds = b[pit];
    b[pit] = 0;
    var i = pit;
    while (seeds > 0) {
      i = (i + 1) % 14;
      if (i == pit) continue; // la case de départ est sautée
      b[i]++;
      seeds--;
    }
    final opp = 1 - p;
    var captured = 0;
    var cancelled = false;
    if (owns(opp, i)) {
      final entry = base(opp); // case d'entrée : jamais capturée
      final taken = <int>[];
      var k = i;
      while (k > entry && b[k] >= 2 && b[k] <= 4) {
        taken.add(k);
        k--;
      }
      if (taken.isNotEmpty) {
        var take = 0;
        for (final x in taken) {
          take += b[x];
        }
        if (sideSum(b, opp) - take == 0) {
          cancelled = true; // interdit d'affamer l'adversaire
        } else {
          for (final x in taken) {
            b[x] = 0;
          }
          captured = take;
        }
      }
    }
    return SongoSow(b, captured, i, cancelled);
  }

  /// Cases jouables par [p]. Si l'adversaire n'a plus de graines, seuls les
  /// coups qui lui en envoient sont permis.
  static List<int> legalMoves(List<int> board, int
