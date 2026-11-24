// Webアプリのファイル（リポジトリのいちばん上にあるもの）を、iOSアプリ用の www フォルダにコピーする
const fs = require('fs'), path = require('path');
const root = path.join(__dirname, '..', '..'), out = path.join(__dirname, '..', 'www');
fs.rmSync(out, { recursive: true, force: true }); fs.mkdirSync(out, { recursive: true });
for (const f of ['index.html', 'manifest.webmanifest', 'icon.svg']) fs.copyFileSync(path.join(root, f), path.join(out, f));
console.log('copied web files to', out);
