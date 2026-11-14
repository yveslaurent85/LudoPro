import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:http/http.dart' as http;

import 'lang.dart';

/// Adresse de ton Worker Cloudflare (sans « / » à la fin).
/// À remplacer après la publication du Worker.
const String kWorkerUrl = 'https://katika-api.ychachouang.workers.dev';

/// Erreur renvoyée par le serveur (message lisible pour le joueur).
class WalletException implements Exception {
  final String message;
  WalletException(this.message);
  @override
  String toString() => message;
}

/// Un joueur connecté à son propre compte (avec son compte d'argent).
class PlayerAccount {
  final String uid;
  final String name;
  final String email;
  final int balance;

  /// Jeton de connexion, utilisé par le serveur pour débiter la mise d'un
  /// joueur connecté sur le même téléphone (mode présentiel).
  final String? idToken;

  const PlayerAccount({
    required this.uid,
    required this.name,
    required this.email,
    required this.balance,
    this.idToken,
  });
}

/// Compte de jetons de chaque joueur : document Firestore `users/{uid}`.
/// Le solde ne se modifie PAS depuis l'appli (voir les règles Firestore) :
/// crédit de départ, mises, gains et recharges passent par le serveur
/// (Cloud Functions).
class Wallet {
  static const String currency = 'FCFA';

  /// Jetons offerts à chaque compte.
  static const int welcomeBonus = 0;

  /// Mise minimale, et mises proposées.
  static const int minStake = 100;
  /// 0 = partie gratuite.
  static const List<int> stakes = [0, 100, 200, 500, 1000, 2000, 5000];

  static String stakeLabel(int v) => v == 0 ? 'Gratuit' : '$v';

  /// Commission de l'application sur la cagnotte en ligne (doit être la même
  /// que COMMISSION_PERCENT dans worker.js).
  static const int commissionPercent = 5;

  /// Commission en présentiel, sur tous les jeux (Ludo, Deux dés, Songô). Doit
  /// être la même que COMMISSION_LOCAL_PERCENT dans worker.js.
  static const int commissionLocalPercent = 5;

  /// Gain du gagnant pour une cagnotte donnée (après commission).
  /// [local] = true : partie en présentiel (commission de 5 %).
  static int prize(int pot, {bool local = false}) {
    // La commission peut avoir une décimale (ex. 7,5 %) : calcul en dixièmes.
    final tenths =
        ((local ? commissionLocalPercent : commissionPercent) * 10).round();
    return pot * (1000 - tenths) ~/ 1000;
  }

  static String format(int amount) => '$amount $currency';

  static DocumentReference<Map<String, dynamic>> _ref(
    FirebaseFirestore db,
    String uid,
  ) =>
      db.collection('users').doc(uid);

  /// Appelle une fonction du Worker avec le jeton de connexion du joueur.
  static Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> body, {
    User? user,
  }) async {
    final u = user ?? FirebaseAuth.instance.currentUser;
    if (u == null) throw WalletException('Connexion requise.');
    final token = await u.getIdToken();
    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('$kWorkerUrl/$name'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw WalletException('Pas de connexion. Réessaie.');
    }
    Map<String, dynamic> j = {};
    try {
      j = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
    } catch (_) {}
    if (res.statusCode != 200) {
      throw WalletException(
        (j['error'] as String?) ??
            tr('Erreur du serveur (${res.statusCode}).',
                'Server error (${res.statusCode}).'),
      );
    }
    final d = j['data'];
    return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
  }

  /// Message lisible à partir d'une erreur serveur.
  static String errorText(Object e) {
    if (e is WalletException) return e.message;
    return 'Pas de connexion. Réessaie.';
  }

  /// Crée le compte de jetons s'il n'existe pas (0 jeton offert) et renvoie
  /// le solde. Les comptes déjà existants reçoivent le crédit une seule fois.
  static Future<int> ensure(
    FirebaseFirestore db,
    User user, {
    String? pseudo,
    FirebaseApp? app,
  }) async {
    try {
      final res = await _call(
        'ensureWallet',
        <String, dynamic>{'pseudo': pseudo ?? user.displayName ?? ''},
        user: user,
      );
      final b = res['balance'];
      return b is num ? b.toInt() : 0;
    } catch (_) {
      // Serveur injoignable : on lit simplement le solde existant.
      try {
        final snap = await _ref(db, user.uid).get();
        final b = snap.data()?['balance'];
        return b is num ? b.toInt() : 0;
      } catch (_) {
        return 0;
      }
    }
  }

  /// Solde en direct (pour l'afficher et le voir changer).
  static Stream<int> watch(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((s) {
      final b = s.data()?['balance'];
      return b is num ? b.toInt() : 0;
    });
  }

  // --- Mises (toutes les opérations d'argent se font côté serveur) --------

  /// Partie en ligne : le joueur paie sa mise (idempotent).
  static Future<void> payStake(String gameId) async {
    await _call('payStake', <String, dynamic>{'gameId': gameId});
  }

  /// Le créateur lance la partie (dès 2 joueurs, salle pleine ou non).
  static Future<void> startGame(String gameId) async {
    await _call('startGame', <String, dynamic>{'gameId': gameId});
  }

  /// Partie en ligne pas encore commencée : quitter (ou annuler si on est
  /// le créateur) et récupérer sa mise.
  static Future<void> leaveGame(String gameId) async {
    await _call('leaveGame', <String, dynamic>{'gameId': gameId});
  }

  /// Fin d'une partie en ligne : le serveur verse la cagnotte au gagnant.
  static Future<void> settleOnline(String gameId) async {
    await _call('settleGame', <String, dynamic>{'gameId': gameId});
  }

  /// Présentiel : débite la mise de tous les joueurs connectés.
  /// [game] = 'ludo' ou 'deuxdes' (sert au tableau de bord administrateur).
  /// Renvoie l'identifiant de la partie côté serveur.
  static Future<String> startLocalGame({
    required int stake,
    required List<String> tokens,
    List<String> names = const [],
    String game = 'unknown',
    int capturePay = 0,
  }) async {
    final res = await _call(
      'startLocalGame',
      <String, dynamic>{
        'stake': stake,
        'tokens': tokens,
        'names': names,
        'game': game,
        'capturePay': capturePay,
      },
    );
    return res['id'] as String;
  }

  /// Présentiel : verse la cagnotte aux gagnants. Renvoie le jackpot gagné
  /// (0 si le jackpot n'est pas tombé).
  static Future<int> settleLocal(String id, List<String> winnerUids) async {
    final res = await _call(
      'settleLocalGame',
      <String, dynamic>{'id': id, 'winnerUids': winnerUids},
    );
    final j = res['jackpot'];
    return j is num ? j.toInt() : 0;
  }

  /// Présentiel : fin de partie avec les scores (règle aussi les paris).
  /// Renvoie { jackpot, bets }.
  static Future<Map<String, dynamic>> settleLocalFull(
    String id,
    List<String> winnerUids,
    List<int> scores, {
    List<int>? fscores,
  }) {
    return _call(
      'settleLocalGame',
      <String, dynamic>{
        'id': id,
        'winnerUids': winnerUids,
        'scores': scores,
        if (fscores != null) 'fscores': fscores,
      },
    );
  }

  /// Tableau de bord administrateur : le serveur refuse tout compte qui
  /// n'est pas dans ADMIN_UIDS.
  static Future<Map<String, dynamic>> adminStats({int limit = 150}) {
    return _call('adminStats', <String, dynamic>{'limit': limit});
  }

  /// Administrateur : transfère les commissions de Katika vers son solde
  /// principal (possible à partir de 2500 FCFA). Renvoie { amount, balance }.
  static Future<Map<String, dynamic>> adminHouseWithdraw() {
    return _call('adminHouseWithdraw', <String, dynamic>{});
  }

  /// Administrateur : tous les joueurs inscrits avec leurs statistiques.
  /// Renvoie { players: [ { uid, pseudo, balance, createdAt, played, won,
  /// lost, staked, wonAmt, lostAmt, winRate } ], total }.
  static Future<Map<String, dynamic>> adminPlayers({int limit = 1000}) {
    return _call('adminPlayers', <String, dynamic>{'limit': limit});
  }

  /// Administrateur : donne ou retire le statut de partenaire (code promo).
  static Future<Map<String, dynamic>> adminSetPartner(String code, bool on) {
    return _call('adminSetPartner', <String, dynamic>{'code': code, 'on': on});
  }

  /// Administrateur : liste des partenaires et de leurs gains.
  static Future<Map<String, dynamic>> adminPartners() {
    return _call('adminPartners', <String, dynamic>{});
  }

  /// Transfère [amount] vers un autre joueur (pseudo ou code promo).
  /// Renvoie { amount, toName, balance }.
  static Future<Map<String, dynamic>> transfer(String to, int amount) {
    return _call('transfer', <String, dynamic>{'to': to, 'amount': amount});
  }

  /// Administrateur : compte dans les statistiques les parties en ligne
  /// terminées avant [before] (ISO UTC). Renvoie { counted, processed,
  /// remaining } : à relancer tant que remaining > 0.
  static Future<Map<String, dynamic>> adminBackfillStats(String before) {
    return _call('adminBackfillStats', <String, dynamic>{'before': before});
  }

  /// Historique des transactions (recharges, retraits, transferts).
  /// [uid] : réservé à l'administrateur pour consulter un joueur.
  static Future<Map<String, dynamic>> txHistory({String? uid}) =>
      _call('txHistory', <String, dynamic>{if (uid != null) 'uid': uid});

  /// Les parties en ligne d'un joueur (le mien, ou celui d'un joueur pour l'administrateur).
  static Future<Map<String, dynamic>> playerGames({String? uid}) =>
      _call('playerGames', <String, dynamic>{if (uid != null) 'uid': uid});

  /// Tiah / Boubayah : déroulé complet d'une manche terminée.
  static Future<Map<String, dynamic>> cardsReplay(String gameId) =>
      _call('cardsReplay', <String, dynamic>{'gameId': gameId});

  /// Administrateur : annule une partie ouverte ou en cours (mises remboursées).
  static Future<Map<String, dynamic>> adminCancelGame(String gameId) =>
      _call('adminCancelGame', <String, dynamic>{'gameId': gameId});

  /// Deux dés « serveur » : act = roll | next.
  static Future<Map<String, dynamic>> deuxDesAct(
          String gameId, String act, int seat) =>
      _call('deuxDesAct',
          <String, dynamic>{'gameId': gameId, 'act': act, 'seat': seat});

  /// Ludo « serveur » : act = roll | move | pass | forfeit.
  static Future<Map<String, dynamic>> ludoAct(String gameId, String act,
          {int? pawn, int? seat, bool proxy = false}) =>
      _call('ludoAct', <String, dynamic>{
        'gameId': gameId,
        'act': act,
        if (pawn != null) 'pawn': pawn,
        if (seat != null) 'seat': seat,
        if (proxy) 'proxy': true,
      });

  /// Administrateur : marque un joueur comme vérifié (on) ou le remet sous surveillance (off).
  static Future<Map<String, dynamic>> adminRiskClear(String uid, bool on) =>
      _call('adminRiskClear', <String, dynamic>{'uid': uid, 'on': on});

  /// Prévient par notification push le joueur que je viens d'inviter comme binôme.
  static Future<Map<String, dynamic>> notifyInvite(String gameId) =>
      _call('notifyInvite', <String, dynamic>{'gameId': gameId});

  /// Administrateur : tranche une partie « à vérifier » (action : approve | refund).
  static Future<Map<String, dynamic>> adminResolveGame(String gameId, String action) =>
      _call('adminResolveGame', <String, dynamic>{'gameId': gameId, 'action': action});

  /// Mes limites : conditions acceptées, limite de recharge, auto-exclusion.
  static Future<Map<String, dynamic>> myLimits() => _call('myLimits', <String, dynamic>{});

  /// J'ai 18 ans ou plus et j'accepte les conditions.
  static Future<Map<String, dynamic>> acceptTerms() =>
      _call('acceptTerms', <String, dynamic>{'age18': true, 'terms': true});

  /// Limite de recharge par 24 h (0 = aucune) et/ou auto-exclusion (en jours).
  static Future<Map<String, dynamic>> setLimits({int? depositLimitDay, int? excludeDays}) =>
      _call('setLimits', <String, dynamic>{
        if (depositLimitDay != null) 'depositLimitDay': depositLimitDay,
        if (excludeDays != null) 'excludeDays': excludeDays,
      });

  /// Administrateur : journal des validations des caissières.
  static Future<Map<String, dynamic>> adminCashierLog({String? uid}) =>
      _call('adminCashierLog', <String, dynamic>{if (uid != null) 'uid': uid});

  /// Mon rôle : { admin, cashier }.
  static Future<Map<String, dynamic>> myRole() => _call('myRole', <String, dynamic>{});

  /// Administrateur : active ou retire un compte caissière (par code promo).
  static Future<Map<String, dynamic>> adminSetCashier(String code, bool on) =>
      _call('adminSetCashier', <String, dynamic>{'code': code, 'on': on});

  /// Administrateur : liste des caissières.
  static Future<Map<String, dynamic>> adminCashiers() =>
      _call('adminCashiers', <String, dynamic>{});

  /// Administrateur : donne ou retire le statut d'hôtesse (par code promo).
  static Future<Map<String, dynamic>> adminSetHostess(String code, bool on) {
    return _call('adminSetHostess', <String, dynamic>{'code': code, 'on': on});
  }

  /// Administrateur : les hôtesses et leurs inscrits sur la période
  /// ([from] inclus, [to] exclu, en ISO UTC ; null = sans limite).
  static Future<Map<String, dynamic>> adminHostesses({
    String? from,
    String? to,
  }) {
    return _call('adminHostesses', <String, dynamic>{
      if (from != null) 'from': from,
      if (to != null) 'to': to,
    });
  }

  /// Hôtesse : mes inscrits sur la période (l'administrateur peut donner le
  /// [code] d'une hôtesse pour la consulter).
  static Future<Map<String, dynamic>> hostessStats({
    String? from,
    String? to,
    String? code,
  }) {
    return _call('hostessStats', <String, dynamic>{
      if (from != null) 'from': from,
      if (to != null) 'to': to,
      if (code != null) 'code': code,
    });
  }

  /// Partenaire : mes gains, mes filleuls et mon historique.
  static Future<Map<String, dynamic>> partnerStats() {
    return _call('partnerStats', <String, dynamic>{});
  }

  /// Partenaire : transfère mes gains vers mon solde principal.
  static Future<Map<String, dynamic>> partnerWithdraw() {
    return _call('partnerWithdraw', <String, dynamic>{});
  }

  /// Code promo : mon code (= pseudo), mon parrain, mes filleuls et mes gains.
  static Future<Map<String, dynamic>> referralInfo({String? pseudo}) {
    return _call('referralInfo', <String, dynamic>{
      'pseudo':
          pseudo ?? FirebaseAuth.instance.currentUser?.displayName ?? '',
    });
  }

  /// Saisit le code promo (pseudo) de mon parrain. Possible une seule fois.
  static Future<Map<String, dynamic>> applyPromo(String code) {
    return _call('applyPromo', <String, dynamic>{'code': code});
  }

  /// Code promo : transfère les gains de parrainage vers le solde principal
  /// (possible à partir de 100 FCFA). Renvoie { amount, balance }.
  /// Le solde affiché se met à jour tout seul (voir [watch]).
  static Future<Map<String, dynamic>> referralWithdraw() {
    return _call('referralWithdraw', <String, dynamic>{});
  }

  /// Captures payantes : montant minimum par capture et montants proposés.
  static const int minCapture = 100;
  static const List<int> captureAmounts = [100, 200, 500, 1000, 2000];

  /// Capture payante (partie en ligne) : le serveur prend le montant de la
  /// capture sur le solde du joueur capturé et le verse au joueur qui capture.
  /// [eventId] évite de payer deux fois la même capture. Renvoie { amount }.
  static Future<Map<String, dynamic>> captureFee({
    required String gameId,
    required String capturerUid,
    required String victimUid,
    required String eventId,
  }) {
    return _call('captureFee', <String, dynamic>{
      'gameId': gameId,
      'capturerUid': capturerUid,
      'victimUid': victimUid,
      'eventId': eventId,
    });
  }

  /// Dépôt Mobile Money (Campay) : le joueur reçoit une demande de paiement
  /// sur son téléphone. [phone] = numéro MTN ou Orange (ex : 670000000).
  /// Renvoie { depositId, reference }.
  static Future<Map<String, dynamic>> campayDeposit({
    required int amount,
    required String phone,
  }) {
    return _call('campayDeposit', <String, dynamic>{
      'amount': amount,
      'phone': phone,
    });
  }

  /// Paiement AUTOMATIQUE SebPay (Orange Money / MTN MoMo).
  /// Renvoie { enabled, operators: [{id,label}], depositMin, depositMax, withdrawMin, withdrawMax }.
  static Future<Map<String, dynamic>> sebpayInfo() {
    return _call('sebpayInfo', <String, dynamic>{});
  }

  /// Recharge automatique : le joueur valide sur son téléphone.
  /// [operator] = 'orange' ou 'mtn'. Renvoie { id, status, providerLink }.
  static Future<Map<String, dynamic>> sebpayDeposit({
    required int amount,
    required String phone,
    required String operator,
  }) {
    return _call('sebpayDeposit', <String, dynamic>{
      'amount': amount,
      'phone': phone,
      'operator': operator,
    });
  }

  /// État d'une recharge automatique (crédite le solde si SebPay a confirmé).
  static Future<Map<String, dynamic>> sebpayDepositStatus(String id) {
    return _call('sebpayDepositStatus', <String, dynamic>{'id': id});
  }

  /// Retrait automatique : le solde est débité, SebPay envoie l'argent.
  static Future<Map<String, dynamic>> sebpayWithdraw({
    required int amount,
    required String phone,
    required String operator,
  }) {
    return _call('sebpayWithdrawRequest', <String, dynamic>{
      'amount': amount,
      'phone': phone,
      'operator': operator,
    });
  }

  /// Mes recharges et retraits automatiques : { deposits, withdrawals, balance }.
  static Future<Map<String, dynamic>> sebpayMine() {
    return _call('sebpayMine', <String, dynamic>{});
  }

  // ---------------------------------------------------------------- Tournois
  static Future<Map<String, dynamic>> tournamentList() =>
      _call('tournamentList', <String, dynamic>{});

  static Future<Map<String, dynamic>> tournamentRegister(String tid) =>
      _call('tournamentRegister', <String, dynamic>{'tid': tid});

  static Future<Map<String, dynamic>> tournamentTeamCreate(String tid, String teamName) =>
      _call('tournamentTeamCreate', <String, dynamic>{'tid': tid, 'teamName': teamName});

  static Future<Map<String, dynamic>> tournamentTeamJoin(String code) =>
      _call('tournamentTeamJoin', <String, dynamic>{'code': code});

  static Future<Map<String, dynamic>> tournamentLeave(String tid) =>
      _call('tournamentLeave', <String, dynamic>{'tid': tid});

  static Future<Map<String, dynamic>> adminTournamentCreate({
    required String type,
    required int startAt,
    required int regDeadline,
    bool test = false,
  }) =>
      _call('adminTournamentCreate', <String, dynamic>{
        'test': test,
        'type': type,
        'startAt': startAt,
        'regDeadline': regDeadline,
      });

  // ---- Paris par derrière : Sports (P2P)
  static Future<Map<String, dynamic>> sportsList() => _call('sportsList', <String, dynamic>{});

  static Future<Map<String, dynamic>> sportBetCreate({
    required String eventId,
    required String side,
    required int amount,
  }) =>
      _call('sportBetCreate', <String, dynamic>{'eventId': eventId, 'side': side, 'amount': amount});

  static Future<Map<String, dynamic>> sportBetAccept(String betId) =>
      _call('sportBetAccept', <String, dynamic>{'betId': betId});

  static Future<Map<String, dynamic>> sportBetCancel(String betId) =>
      _call('sportBetCancel', <String, dynamic>{'betId': betId});

  static Future<Map<String, dynamic>> adminSportEventSave({
    required String category,
    required String subcategory,
    required String teamA,
    required String teamB,
    required int startsAt,
  }) =>
      _call('adminSportEventSave', <String, dynamic>{
        'category': category,
        'subcategory': subcategory,
        'teamA': teamA,
        'teamB': teamB,
        'startsAt': startsAt,
      });

  static Future<Map<String, dynamic>> adminSportEventCancel(String id) =>
      _call('adminSportEventCancel', <String, dynamic>{'id': id});

  static Future<Map<String, dynamic>> adminSportEventResult(String id, String result) =>
      _call('adminSportEventResult', <String, dynamic>{'id': id, 'result': result});

  // ---- Paris par derrière : Courses (pari mutuel)
  static Future<Map<String, dynamic>> racesList() => _call('racesList', <String, dynamic>{});

  static Future<Map<String, dynamic>> raceBetCreate({
    required String raceId,
    required String formula,
    required List<int> picks,
    required int coef,
  }) =>
      _call('raceBetCreate', <String, dynamic>{'raceId': raceId, 'formula': formula, 'picks': picks, 'coef': coef});

  static Future<Map<String, dynamic>> adminRaceSave({
    required String name,
    required int runners,
    required int startsAt,
  }) =>
      _call('adminRaceSave', <String, dynamic>{'name': name, 'runners': runners, 'startsAt': startsAt});

  static Future<Map<String, dynamic>> adminRaceCancel(String id) =>
      _call('adminRaceCancel', <String, dynamic>{'id': id});

  static Future<Map<String, dynamic>> adminRaceResult(String id, List<int> arrival) =>
      _call('adminRaceResult', <String, dynamic>{'id': id, 'arrival': arrival});

  static Future<Map<String, dynamic>> adminTournamentCancel(String tid) =>
      _call('adminTournamentCancel', <String, dynamic>{'tid': tid});

  static Future<Map<String, dynamic>> adminTournamentEntries(String tid) =>
      _call('adminTournamentEntries', <String, dynamic>{'tid': tid});

  // -------------------------------------------------- Damier « Deux buts sort »
  static Future<Map<String, dynamic>> dbList([String? rid]) =>
      _call('dbList', <String, dynamic>{if (rid != null) 'rid': rid});

  static Future<Map<String, dynamic>> dbCreate({required int stake, required int timeMin}) =>
      _call('dbCreate', <String, dynamic>{'stake': stake, 'timeMin': timeMin});

  static Future<Map<String, dynamic>> dbJoin(String rid) =>
      _call('dbJoin', <String, dynamic>{'rid': rid});

  static Future<Map<String, dynamic>> dbLeave(String rid) =>
      _call('dbLeave', <String, dynamic>{'rid': rid});

  static Future<Map<String, dynamic>> dbClose(String rid) =>
      _call('dbClose', <String, dynamic>{'rid': rid});

  // ------------------------------------------------------------ Pile ou Face
  static Future<Map<String, dynamic>> pfList() =>
      _call('pfList', <String, dynamic>{});

  static Future<Map<String, dynamic>> pfCreate({required int stake, required String side}) =>
      _call('pfCreate', <String, dynamic>{'stake': stake, 'side': side});

  static Future<Map<String, dynamic>> pfJoin(String gameId) =>
      _call('pfJoin', <String, dynamic>{'gameId': gameId});

  static Future<Map<String, dynamic>> pfCancel(String gameId) =>
      _call('pfCancel', <String, dynamic>{'gameId': gameId});

  // ------------------------------------------------------------ Cartes en ligne
  static Future<Map<String, dynamic>> cardsList(String game) =>
      _call('cardsList', <String, dynamic>{'game': game});

  static Future<Map<String, dynamic>> cardsCreate({
    required String game,
    required int stake,
    required int maxPlayers,
    required bool isPublic,
  }) =>
      _call('cardsCreate', <String, dynamic>{
        'game': game,
        'stake': stake,
        'maxPlayers': maxPlayers,
        'isPublic': isPublic,
      });

  static Future<Map<String, dynamic>> cardsJoin({String? gameId, String? code}) =>
      _call('cardsJoin', <String, dynamic>{
        if (gameId != null) 'gameId': gameId,
        if (code != null) 'code': code,
      });

  static Future<Map<String, dynamic>> cardsGet(String gameId) =>
      _call('cardsGet', <String, dynamic>{'gameId': gameId});

  static Future<Map<String, dynamic>> cardsStart(String gameId) =>
      _call('cardsStart', <String, dynamic>{'gameId': gameId});

  static Future<Map<String, dynamic>> cardsOpen(String gameId) =>
      _call('cardsOpen', <String, dynamic>{'gameId': gameId});

  /// Paris aux cartes : 'duel' (TIAH, BOUBAYAH) ou 'fetiche' (BOUBAYAH, plus ou moins que 13).
  static Future<Map<String, dynamic>> cardsBetPropose({
    required String gameId,
    required String type,
    required int amount,
    String? targetUid,
    bool over = true,
  }) =>
      _call('cardsBetPropose', <String, dynamic>{
        'gameId': gameId,
        'type': type,
        'amount': amount,
        if (targetUid != null) 'targetUid': targetUid,
        'side': over ? 'over' : 'under',
      });

  static Future<Map<String, dynamic>> cardsBetAccept(String gameId, String betId) =>
      _call('cardsBetAccept', <String, dynamic>{'gameId': gameId, 'betId': betId});

  static Future<Map<String, dynamic>> cardsBetCancel(String gameId, String betId) =>
      _call('cardsBetCancel', <String, dynamic>{'gameId': gameId, 'betId': betId});

  static Future<Map<String, dynamic>> cardsLeave(String gameId) =>
      _call('cardsLeave', <String, dynamic>{'gameId': gameId});

  static Future<Map<String, dynamic>> cardsRematch(String gameId) =>
      _call('cardsRematch', <String, dynamic>{'gameId': gameId});

  /// Recharge / retrait manuels par code marchand Orange Money.
  /// Renvoie { code, ussd, depositMin, depositMax, withdrawMin, withdrawMax }.
  static Future<Map<String, dynamic>> manualInfo() {
    return _call('manualInfo', <String, dynamic>{});
  }

  /// Le joueur a payé au code marchand : demande de recharge en attente de
  /// confirmation. [txRef] = identifiant de transaction reçu par SMS.
  static Future<void> manualDeposit({
    required int amount,
    required String phone,
    required String txRef,
    String operator = 'orange',
  }) async {
    await _call('manualDepositRequest', <String, dynamic>{
      'amount': amount,
      'phone': phone,
      'txRef': txRef,
      'operator': operator,
    });
  }

  /// Demande de retrait : le montant est retiré du solde, l'administrateur
  /// envoie l'argent puis confirme.
  static Future<void> manualWithdraw({
    required int amount,
    required String phone,
  }) async {
    await _call('manualWithdrawRequest', <String, dynamic>{
      'amount': amount,
      'phone': phone,
    });
  }

  /// Mes demandes : { deposits: [...], withdrawals: [...] }.
  static Future<Map<String, dynamic>> manualMine() {
    return _call('manualMine', <String, dynamic>{});
  }

  /// Administrateur : demandes en attente et dernières traitées.
  static Future<Map<String, dynamic>> adminManualList() {
    return _call('adminManualList', <String, dynamic>{});
  }

  /// Administrateur : confirme ou refuse une demande.
  /// [kind] = 'deposit' ou 'withdrawal', [approve] = confirmer ou refuser.
  /// Administrateur : remet tous les soldes à zéro (irréversible).
  static Future<int> adminResetBalances() async {
    final r = await _call('adminResetBalances', <String, dynamic>{
      'confirm': 'ZERO',
    });
    return (r['reset'] as num?)?.toInt() ?? 0;
  }

  static Future<void> adminManualDecide({
    required String kind,
    required String id,
    required bool approve,
  }) async {
    await _call('adminManualDecide', <String, dynamic>{
      'kind': kind,
      'id': id,
      'action': approve ? 'approve' : 'reject',
    });
  }

  /// Où en est un dépôt : 'pending', 'credited', 'failed' ou 'mismatch'.
  /// Renvoie { status, balance }.
  static Future<Map<String, dynamic>> campayDepositStatus(String depositId) {
    return _call('campayDepositStatus', <String, dynamic>{
      'depositId': depositId,
    });
  }

  /// Présentiel : crée un pari entre deux joueurs (les deux mises sont
  /// débitées tout de suite). Les jetons prouvent les deux comptes.
  static Future<void> localBet({
    required String id,
    required String type,
    required int amount,
    required String proposerToken,
    required String opponentToken,
    bool over7 = true,
  }) async {
    await _call('localBetCreate', <String, dynamic>{
      'id': id,
      'type': type,
      'amount': amount,
      'side': over7 ? 'over' : 'under',
      'proposerToken': proposerToken,
      'opponentToken': opponentToken,
    });
  }

  /// Montant actuel du jackpot (le seuil de déclenchement reste secret).
  static Stream<int> watchJackpot() {
    return FirebaseFirestore.instance
        .collection('app')
        .doc('jackpot')
        .snapshots()
        .map((s) {
      final p = s.data()?['pool'];
      return p is num ? p.toInt() : 0;
    });
  }

  /// Connexion d'un joueur "invité" sur le même téléphone, SANS déconnecter
  /// le joueur principal : on utilise une 2e instance Firebase.
  static Future<PlayerAccount> signInGuest(String email, String password) async {
    FirebaseApp app;
    try {
      app = Firebase.app('joueur');
    } catch (_) {
      app = await Firebase.initializeApp(
        name: 'joueur',
        options: Firebase.app().options,
      );
    }
    final auth = FirebaseAuth.instanceFor(app: app);
    final cred = await auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = cred.user!;
    int balance = 0;
    try {
      balance = await ensure(
        FirebaseFirestore.instanceFor(app: app),
        user,
        app: app,
      );
    } catch (_) {
      // Solde illisible : on laisse quand même jouer, solde affiché à 0.
    }
    String? token;
    try {
      token = await user.getIdToken();
    } catch (_) {}
    final name = (user.displayName != null && user.displayName!.isNotEmpty)
        ? user.displayName!
        : (user.email ?? 'Joueur');
    final account = PlayerAccount(
      uid: user.uid,
      name: name,
      email: user.email ?? '',
      balance: balance,
      idToken: token,
    );
    await auth.signOut(); // la session invité n'est pas gardée
    return account;
  }
}

/// Bandeau « Jackpot » affiché dans le salon et avant la partie.
/// Jackpot désactivé : les bandeaux ne s'affichent plus.
const bool kJackpotEnabled = false;

class JackpotBanner extends StatelessWidget {
  const JackpotBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kJackpotEnabled) return const SizedBox.shrink();
    return StreamBuilder<int>(
      stream: Wallet.watchJackpot(),
      builder: (context, snap) {
        if (snap.hasError) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.black26,
            border: Border.all(color: const Color(0xFFFFC21A), width: 1.5),
          ),
          child: Text(
            tr(
              '🎰 JACKPOT : ${Wallet.format(snap.data ?? 0)}\n'
              'Il peut tomber sur n\'importe quelle victoire !',
              '🎰 JACKPOT: ${Wallet.format(snap.data ?? 0)}\n'
              'It can drop on any win!',
            ),
            style: const TextStyle(
              color: Color(0xFFFFE082),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
      },
    );
  }
}

/// Bandeau « Jackpot » compact, affiché pendant la partie.
/// Le montant est mis à jour en direct et défile quand il change.
class JackpotStrip extends StatefulWidget {
  const JackpotStrip({super.key, this.stake = 1});

  /// Mise de la partie (0 = partie gratuite : pas de jackpot à gagner).
  final int stake;

  @override
  State<JackpotStrip> createState() => _JackpotStripState();
}

class _JackpotStripState extends State<JackpotStrip> {
  // Le flux n'est créé qu'une fois : sinon il serait relancé (et le montant
  // retomberait à 0) à chaque coup joué.
  late final Stream<int> _stream = Wallet.watchJackpot();
  int _last = 0;

  @override
  Widget build(BuildContext context) {
    if (!kJackpotEnabled) return const SizedBox.shrink();
    return StreamBuilder<int>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) return const SizedBox.shrink();
        final value = snap.data ?? _last;
        _last = value;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.black26,
            border: Border.all(color: const Color(0xFFFFC21A), width: 1.5),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: TweenAnimationBuilder<int>(
              tween: IntTween(begin: value, end: value),
              duration: const Duration(milliseconds: 900),
              builder: (context, shown, _) => Text(
                widget.stake > 0
                    ? tr(
                        '🎰 JACKPOT : ${Wallet.format(shown)}',
                        '🎰 JACKPOT: ${Wallet.format(shown)}',
                      )
                    : tr(
                        '🎰 JACKPOT : ${Wallet.format(shown)} (parties avec mise)',
                        '🎰 JACKPOT: ${Wallet.format(shown)} (stake games)',
                      ),
                style: const TextStyle(
                  color: Color(0xFFFFE082),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

String _authError(String code) {
  switch (code) {
    case 'invalid-email':
      return 'E-mail invalide.';
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return 'E-mail ou mot de passe incorrect.';
    case 'too-many-requests':
      return "Trop d'essais. Réessaie dans quelques minutes.";
    case 'network-request-failed':
      return 'Pas de connexion internet.';
    default:
      return tr('Erreur : $code', 'Error: $code');
  }
}

/// Fenêtre de connexion d'un joueur. Renvoie son compte, ou null si annulé.
Future<PlayerAccount?> showPlayerLogin(
  BuildContext context, {
  required String colorName,
  required Color color,
}) {
  return showDialog<PlayerAccount>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _LoginDialog(colorName: colorName, color: color),
  );
}

class _LoginDialog extends StatefulWidget {
  const _LoginDialog({required this.colorName, required this.color});

  final String colorName;
  final Color color;

  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  bool hide = true;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    emailCtrl.dispose();
    passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = emailCtrl.text.trim();
    final pass = passCtrl.text;
    if (!email.contains('@') || pass.length < 6) {
      setState(() => error = 'E-mail ou mot de passe invalide.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final acc = await Wallet.signInGuest(email, pass);
      if (!mounted) return;
      Navigator.pop(context, acc);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = _authError(e.code);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = 'Une erreur est survenue. Réessaie.';
      });
    }
  }

  InputDecoration _dec(String label, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      labelText: tr(label),
      labelStyle: const TextStyle(color: Colors.white70),
      prefixIcon: Icon(icon, color: Colors.white70),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white.withOpacity(0.12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.white30),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: widget.color, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF14267A),
      title: Text(
        tr('Connexion · Joueur ${widget.colorName}',
            'Sign in · Player ${widget.colorName}'),
        style: const TextStyle(color: Colors.white, fontSize: 18),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailCtrl,
              enabled: !busy,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Colors.white),
              decoration: _dec('E-mail', Icons.email),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              enabled: !busy,
              obscureText: hide,
              style: const TextStyle(color: Colors.white),
              decoration: _dec(
                'Mot de passe',
                Icons.lock,
                suffix: IconButton(
                  onPressed: () => setState(() => hide = !hide),
                  icon: Icon(
                    hide ? Icons.visibility : Icons.visibility_off,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(
                error!,
                style: const TextStyle(
                  color: Color(0xFFFF8A80),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: busy ? null : _submit,
          child: Text(
            busy ? 'Patiente...' : 'Se connecter',
            style: const TextStyle(color: Color(0xFFFFC21A)),
          ),
        ),
      ],
    );
  }
}
