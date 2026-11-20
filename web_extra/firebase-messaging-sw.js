// Réception des notifications de Katika quand l'appli est fermée ou en arrière-plan.
// Ce fichier doit être servi à la racine du site (/firebase-messaging-sw.js) et dans /jouer/.
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyD1G5bR4xxr7vf7UTQcQWB5ChfUzLkkP44',
  authDomain: 'ludopro-cameroun-2026.firebaseapp.com',
  projectId: 'ludopro-cameroun-2026',
  storageBucket: 'ludopro-cameroun-2026.firebasestorage.app',
  messagingSenderId: '29829821712',
  appId: '1:29829821712:web:893f1d241896d094a4a195',
});

// Les messages contenant « notification » sont affichés automatiquement par le navigateur.
firebase.messaging();

self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (list) {
      for (const c of list) {
        if ('focus' in c) return c.focus();
      }
      return clients.openWindow('/jouer/');
    })
  );
});
