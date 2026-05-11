importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js");

firebase.initializeApp({
    apiKey: 'AIzaSyBJQ76n5gPZgQRBH2oq4ojmbry-8__iuIA',
    appId: '1:1086613473742:web:7834e3199e2184f8fd039f',
    messagingSenderId: '1086613473742',
    projectId: 'nutritionanalyzer-6485e',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const title = payload.notification?.title ?? '通知';
  const body = payload.notification?.body ?? '';

  self.registration.showNotification(title, {
    body,
    data: payload.data, // ⭐ 關鍵：把 data 帶進來
  });
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const data = event.notification.data;

  let url = '/';
  if (data?.type === 'chat') {
    url = `/chat/${data.targetId}`;
  }

  event.waitUntil(
    clients.openWindow(url)
  );
});

