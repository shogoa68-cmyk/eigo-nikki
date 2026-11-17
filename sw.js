// オフラインでも開けるように、アプリ本体をスマホに保存しておく仕組み
const CACHE = 'eigo-v3';
const FILES = ['./', './index.html', './manifest.webmanifest', './icon.svg'];
self.addEventListener('install', e => e.waitUntil(caches.open(CACHE).then(c => c.addAll(FILES))));
self.addEventListener('activate', e => e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k))))));
// 先にネットから最新を取り、だめなら保存してあるものを使う
self.addEventListener('fetch', e => {
  // Googleなど外のサイトとのやりとり（ログインやドライブ）には口を出さない
  if (e.request.method !== 'GET' || new URL(e.request.url).origin !== self.location.origin) return;
  e.respondWith(fetch(e.request).then(r => { const copy = r.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)); return r; }).catch(() => caches.match(e.request)));
});
