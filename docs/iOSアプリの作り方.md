# マイ英語 iOSアプリの作り方

このリポジトリの `native/` フォルダに、iOSアプリの「箱」が入っています。
中身（画面や機能）は、Web版と同じ `index.html` です。iOSアプリでは、次の3つが良くなります。

| | Web版（Safari） | iOSアプリ |
|---|---|---|
| 聞き流し | 画面を消すと止まる | **画面を消しても、ほかのアプリを使っても流れつづける** |
| Googleログイン | 1時間で切れる | **一度ログインすれば、そのまま**（自動で更新） |
| 読み上げの声 | Safari の声 | iPhone の声（「拡張」「プレミアム」の声も使える） |

---

## 段階1：自分の iPhone で使ってみる

### 1. Mac の準備（はじめの1回だけ）
1. **Xcode** を App Store から入れる（無料・大きいので時間がかかります）。入れたら一度開いて、追加の部品を入れる。
2. **Node.js** を入れる：<https://nodejs.org/> の「LTS」をダウンロードして入れる。
3. **このリポジトリを Mac にコピー**する：ターミナル（アプリ「ターミナル」）で
   ```sh
   git clone https://github.com/shogoa68-cmyk/eigo-nikki.git
   cd eigo-nikki/native
   npm install
   ```

### 2. Xcode で開く
```sh
cd eigo-nikki/native
npm run ios
```
→ Xcode が開きます。

### 3. 署名（だれのアプリか）を設定する
1. Xcode の左の一覧で、いちばん上の **App** を選ぶ → 真ん中の **Signing & Capabilities**。
2. **Team**：「Add an Account…」で自分の Apple ID を入れて、選ぶ。
3. **Bundle Identifier**：世界でひとつの名前にする。例：`com.あなたの名前.myeigo`（英数字と点だけ）。
   ここで決めた名前は、あとで Google の設定にも使うので、メモしておく。

### 4. iPhone に入れる
1. iPhone を USB ケーブルで Mac につなぐ（「このコンピュータを信頼」→ 信頼）。
2. iPhone の **設定 → プライバシーとセキュリティ → デベロッパモード** をオン（再起動します）。
3. Xcode の上の真ん中で、つないだ iPhone を選び、**▶（Run）** を押す。
4. 無料の Apple ID のときは、iPhone の **設定 → 一般 → VPNとデバイス管理** で、自分の名前を「信頼」する。

> 無料の Apple ID だと、**7日ごとに**もう一度 ▶ を押して入れ直す必要があります。
> Apple Developer Program（年 99ドル）に入ると、1年もちます（TestFlight も使えます）。

### 5. Google ドライブにつなぐ（iOS用のクライアントID）
iOSアプリでは、Web版とは別の「iOS」用のクライアントIDがいります。
1. <https://console.cloud.google.com/> → Web版で使ったのと同じプロジェクト → **APIとサービス → 認証情報**。
2. **認証情報を作成 → OAuth クライアント ID** → アプリケーションの種類：**iOS**。
3. **バンドル ID**：手順3で決めた Bundle Identifier を入れる → 作成。
4. できた **クライアント ID**（`〜.apps.googleusercontent.com`）を、アプリの最初の設定（または 設定 → Googleドライブ）に入れる。
5. **大事**：**OAuth 同意画面**（「対象」や「公開ステータス」のページ）で、公開ステータスを **「本番環境」** にする。
   「テスト」のままだと、**7日ごとにログインが切れます**（Google の決まり）。
   本番にすると、ログインのときに「Google はこのアプリを確認していません」と出ますが、
   自分のアプリなので「詳細」→「（安全ではないページ）に移動」で進んで大丈夫です（100人まで使えます）。

### 6. そのほかの設定
- iOSアプリは、Safari とは**別の保存場所**です。Claude の APIキーなども、アプリでもう一度入れてください。
- Web版のデータを移すには：Web版の **設定 → バックアップ** で保存 → iOSアプリの **設定 → 読み込む** でそのファイルを選ぶ。
  （iOSアプリの「バックアップ」は、iPhone の「共有」が開くので、「ファイルに保存」で保存できます）

### 7. アプリを新しくするとき
Web版（`index.html`）を直したら、Mac で：
```sh
cd eigo-nikki
git pull
cd native
npm run ios
```
→ Xcode で ▶。

### うまくいかないとき
- **画面が真っ白**：`npm run sync` をしてから ▶。
- **署名のエラー**：Bundle Identifier を、ほかとかぶらない名前に変える。
- **Google で「エラー 400」**：iOS用のクライアントIDの「バンドル ID」と、Xcode の Bundle Identifier が同じか確かめる。
- **GitHub の「iOS build check」**：Mac で組み立てられるかを、GitHub が自動で確かめています（リポジトリの「Actions」タブ）。

---

## しくみ（開発メモ）
- `native/scripts/copy-web.js`：`index.html` などを `native/www` にコピー → `npx cap sync ios` で Xcode のプロジェクトに入る。
- `native/plugins/my-eigo-native`：iPhone 専用の部品（Swift）。
  - `speak`：文のならびを AVSpeechSynthesizer の順番待ちに入れて読む（文の間の「間」も iPhone 側で入れる）→ 画面を消しても止まらない。
  - `authenticate`：ASWebAuthenticationSession で Google のログイン画面を開く（PKCE つきの認可コード方式）。
  - `httpPost`：通行証（アクセストークン）の受け取り・更新。
  - `shareFile`：バックアップの保存（共有シート）。
- `index.html` の `NATIVE` が true のとき（iOSアプリの中）だけ、これらを使います。Web版の動きは変わりません。
- Info.plist：バックグラウンドで音を出す（`UIBackgroundModes: audio`）、縦向きだけ、iPhone 専用。

---

## 段階2：公開して、収益化する（これからの計画）

自分で使ってみて良かったら、次の準備をして App Store に出します。いまのままでは出せない理由と、その対策です。

### 1. Claude の APIキー → 自分のサーバーに置く（いちばん大事）
- いまは、使う人がそれぞれ自分の Claude APIキーを入れるしくみ。ふつうの人には、むずかしすぎます。
- 対策：**小さなサーバー**（例：Cloudflare Workers や Firebase）を用意し、APIキーはサーバーだけが持つ。
  アプリ → サーバー → Claude の順に頼む。使いすぎを防ぐ回数制限も、サーバーでかける。
- お金の流れ：英文1本つくるたびに、Claude の料金（数円ほど）がかかります。その分を、月額のサブスクで回収します。

### 2. 課金 → App Store のアプリ内課金
- アプリの中で売るデジタルなもの（サブスクなど）は、**Apple のアプリ内課金**を使う決まりです。
- 手数料：売上の 15%（年の売上が100万ドル以下の「Small Business Program」に申し込んだとき）。
- 例：無料（1日1本・お試し）＋ 月額プラン（たくさん作れる・聞き流しなど）。

### 3. Google ドライブの読み方を変える
- いま使っている「ドライブを全部読む（drive.readonly）」は、Google が特にきびしく審査する権限です。
  一般公開には、Google の審査と、毎年の**セキュリティ診断（有料）**が必要になります。
- 対策（どれか、または組み合わせ）：
  - **アプリの中で日記を書ける**ようにする（いちばん手軽）。
  - **ファイルを選んでもらう方式**（Google Picker・`drive.file` 権限）にする：審査がずっと軽い。
  - iPhone の**「共有」からアプリに送る**（メモ、Googleドキュメント、ファイルApp など）。

### 4. App Store の審査に必要なもの
- **プライバシーポリシー**のページ（日記の文章を Claude に送ること、保存場所などを書く）。
- App Store の「**プライバシー**」の質問への回答（どんなデータを、だれに送るか）。
- アカウントを作るなら：**アプリの中でアカウントを消せる**こと、Google ログインでアカウントを作るなら **Sign in with Apple** も用意。
- AI が作った文章であることの説明、スクリーンショット（iPhone 6.9インチ など）、アプリの説明文。

### 5. 名前とブランド
- 「マイ英語」は、App Store で同じような名前がないか調べる。かぶるなら変える。

### 6. 公開までの順番（おすすめ）
1. 段階1：自分で毎日使って、直したいところを出す。
2. Apple Developer Program に入る → **TestFlight** で友だちに配る（最大1万人まで、ベータ版として）。
3. サーバー（APIキー・回数制限）とアカウント、日記の入れ方の変更。
4. アプリ内課金。プライバシーポリシー。
5. 審査に出す → 公開。
