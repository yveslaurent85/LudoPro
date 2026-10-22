// functions/stakes.js
// Solde de départ, mises et gains (jetons virtuels).
// Toute opération sur le solde passe par ici : l'appli ne modifie jamais
// le champ « balance » elle-même.

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

const REGION = 'europe-west1';
const WELCOME = 10000; // jetons offerts à chaque compte
const MIN_STAKE = 100; // mise minimale
const COMMISSION_PERCENT = 5; // part gardée par Katika sur la cagnotte (0-100)
const JACKPOT_PERCENT = 10; // part de la commission versée au jackpot
const JACKPOT_MIN = 550; // le jackpot se déclenche entre ces deux montants
const JACKPOT_MAX = 650;
const opts = { region: REGION };

function needAuth(request) {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Connexion requise.');
  }
  return request.auth.uid;
}

function balanceOf(snap) {
  const d = snap.exists ? snap.data() : null;
  return d && typeof d.balance === 'number' ? d.balance : 0;
}

// --- Jackpot ----------------------------------------------------------
// app/jackpot       : { pool }   (lisible par les joueurs, pour l'afficher)
// app/jackpotTarget : { target } (secret : tirage au sort entre 550 et 650)
// Quand la cagnotte du jackpot a atteint le seuil tiré au sort, le gagnant de
// la partie suivante remporte tout le jackpot, puis un nouveau seuil est tiré.
