# HTTPS-PORTAL P1：変更検知テスト拡充 詳細実施計画

**版**：1.0（2026-10-22）  
**対象ベースライン**：ユーザー提供 `https-portal-master.zip`／アーカイブ記載コミット `0e72267b57d54dec723de1228dc370cb43f30e74`  
**期間**：5〜8営業日（標準計画は7〜8営業日、主担当1名＋レビュー担当1名）  
**前提**：P0で現行ソース・既知不具合・開発環境の基準化が完了。P1では原則として製品のバージョン・本番動作を変更しない。  
**ステータス**：実施計画（テストの追加・実行は本書作成時点では未着手）。

## 1. 目的と対象境界

**目的**：Nginx、Ruby、依存ツールの将来のバージョン更新に先立ち、重要な既存動作が変わったことを、Dockerや公開ACMEサービスに依存しない高速なテストで検知できるようにする。テスト自体が意図的な変更に反応することまで証明する。

- **P1で実装するもの**：RSpecによる26入力の個別テスト、ERBから生成したNginx設定の契約試験（HTTP／TLS関連設定／Basic認証／IP制限／ルーティング）、証明書の更新要否判定UT、期待値差分レビュー、故意の変更（mutation）による検知能力の確認。
- **P1で実装しないもの**：実通信のTLS証明書チェーン／ホスト名検証、HTTP 301の実レスポンス、実際の認証401/200、実upstreamへのルーティング、ACMEの発行・更新、GitHub Actions上のDocker IT。これらはP2〜P3の試験項目（P1では設定生成までを検査）。
- **契約の2分類**：`C（characterization）` は現在の振る舞いを検知する基準、`S（security／desired）` はあるべき安全性を検証する基準。現行コードに危険な振る舞いがあれば、Cとして現状と差分を記録し、Sは別課題・後続フェーズで是正する。危険な設定を永続的な正解として承認しない。

## 2. 現行コードの事実と試験設計上の注意

| 確認事項 | 現行の実装 | P1での取り扱い |
|---|---|---|
| 26種類のドメイン解析 | `spec/models/domain_spec.rb` の単一の `it` に26パターン×10属性を集約 | 各パターンを独立した`it`にし、10属性の期待値は保持 |
| テスト開始時のDockerビルド | `spec/spec_helper.rb` の `before :suite` がデフォルトでDockerビルド | P1実行は必ず `SKIP_BUILD=1`。P2でヘルパー分離／CI改修 |
| HTTPリダイレクト | `default.conf.erb` が `301 https://$server_name$request_uri` を生成 | **HTTP→HTTPSの301**を文字列・構造で検証。ただし非443ポートのURLは別途仕様判断 |
| 転送先リダイレクト | `default.ssl.conf.erb` が `REDIRECT_CODE` 未指定なら **307** | `=>` モードの**HTTPS上の307**を別ケースで検証。301と混同しない |
| TLSプロトコル | `nginx.conf.erb` に `ssl_protocols TLSv1.2 TLSv1.3;` | Nginx生成設定の試験であり、実際のネゴシエーション成功／拒否の保証ではない |
| HTTPS用認証・IP制限 | `default.ssl.conf.erb` で `auth_basic`／`auth_basic_user_file`／`allow`／`deny all` | 有無と設定値を検証。401／403の実レスポンスはP2・P3 |
| 証明書更新判断 | `OpenSSL.need_to_sign_or_renew?` は強制更新、鍵・証明書存在、dummy判定、有効期限 `> renew_margin_days` | 31／30／29日の境界、鍵・証明書欠落、dummy、強制更新を検証 |
| HTTPS確認ヘルパー | `spec/support/portal_helpers.rb` に `VERIFY_NONE` | P1では触らない。P2／P3で信頼CAを使う実通信試験に置換・追加 |
| 更新試験の期待ログ差分 | `renewal_spec.rb` は `No need to renew...`、実装は `Renewal skipped...` | 既知差分として記録。P1の更新判定UTにログ比較は混在させない |

**主要参照コード**：`spec/models/domain_spec.rb`、`spec/spec_helper.rb`、`fs_overlay/opt/certs_manager/models/domain.rb`、`fs_overlay/opt/certs_manager/lib/open_ssl.rb`、`fs_overlay/opt/certs_manager/lib/erb_binding.rb`、`fs_overlay/opt/certs_manager/lib/nginx.rb`、`fs_overlay/var/lib/nginx-conf/{default.conf.erb,default.ssl.conf.erb,nginx.conf.erb}`。

## 3. WBS：実装タスク／工数／完了条件

| WBS | 優先度 | 作業（担当：開発／レビュー） | 目安 | 成果物・受入条件 |
|---|---|---|---:|---|
| W01 | 必須 | P0結果の再確認、既存26入力と10属性の棚卸し、既知不具合の区別 | 0.5日 | 参照コミット、26件の台帳、期待値の承認 |
| W02 | 必須 | DockerなしのRSpec実行導線、fixture／ERB描画ヘルパー、ENV退避復元 | 0.75日 | `SKIP_BUILD=1`で単独実行でき、外部DNS／ACME／Dockerコマンドを起動しない |
| W03 | 必須 | 既存26件を個別`it`に展開し、IDを付与 | 0.75日 | `D01`〜`D26`が独立表示され、各10属性を確認 |
| W04 | 必須 | Nginx ERBの実描画、重要ディレクティブ比較、fixture／期待差分のレビュー | 1.25日 | HTTP・TLS・認証・ルーティングの契約検証が実テンプレートを利用 |
| W05 | 必須 | HTTPとTLS関連の設定契約 | 1.0日 | H01〜H04、T01〜T04が合格 |
| W06 | 必須 | 認証／IP制限／ルーティングの設定契約 | 1.0日 | A01〜A05、R01〜R07が合格 |
| W07 | 必須 | 証明書更新要否の判断テスト、境界値と独立性 | 1.0日 | C01〜C08が合格、時間／ファイル／環境への依存を制御 |
| W08 | 必須 | 故意の変更による検知テスト（検知能力実証） | 0.75日 | 重要な4種類以上の変更で対応テストが赤、復元後に緑 |
| W09 | 必須 | 一括・個別実行、レビュー、テスト仕様一覧、既知問題・P2引継ぎ | 0.75日 | 完了判定表と再現コマンド、レビュー記録、対象テストがすべて緑 |
| | | **標準合計** | **7.75日** | 5日達成は既存環境が安定し、テンプレートfixtureのレビューを並行できる場合に限定 |

## 4. 試験項目台帳（54件）

### 4.1 ドメイン解析：D01〜D26（26件、各10項目を検証）

**判定項目**：`name`／`env_format_name`／`upstream_proto`／`upstreams`／`redirect_target_url`／`stage`／`basic_auth_username`／`basic_auth_password`／`access_restriction`／`port`。すべて既存テストの値を保持し、データの位置・順番によらずケースごとに失敗を特定できるようにする。

| ID | 入力・観点 | 重点確認 |
|---|---|---|
| D01 | `example.com` | 基本値、既定ポート443 |
| D02 | `example.com:4443` | カスタムHTTPSポート |
| D03 | `4example.com` | 数字で始まる名称の現行解釈 |
| D04 | ` example.com ` | 前後空白除去 |
| D05 | `example.com #staging` | ステージ指定 |
| D06 | `example.com -> http://target` | HTTP upstream |
| D07 | 入力・矢印の前後に改行 | 複数行を許容する現行動作 |
| D08 | ドメイン直後で改行し `->` | 改行の別パターン |
| D09 | `-> http://target:8000` | upstream側のポート |
| D10 | `-> target:8000` | upstreamプロトコル省略時のHTTP |
| D11 | `=> http://target` | 明示HTTPへのリダイレクト |
| D12 | `=> https://target` | 明示HTTPSへのリダイレクト |
| D13 | `=> target` | `=>` の既定プロトコルHTTPS |
| D14 | `example.com=>http://target` | スペースなし構文 |
| D15 | `-> http://target #staging` | upstream＋ステージ |
| D16 | `=> http://target #staging` | リダイレクト＋ステージ |
| D17 | `example.com->http://target #staging` | スペースなし＋ステージ |
| D18 | ハイフンを含むドメイン／upstream | `_` に置換した環境変数名 |
| D19 | アンダースコアを含むドメイン | 現行の名称処理 |
| D20 | アンダースコアを含むupstream | upstream解釈 |
| D21 | `username:password@example.com` | Basic認証資格情報の解析 |
| D22 | Basic認証＋upstream＋staging | 組合せ |
| D23 | `[1.2.3.4/24]`＋Basic認証 | CIDR制限を1件抽出 |
| D24 | `[ 1.2.3.4 4.3.2.1/24 ]` | 複数IP制限を抽出 |
| D25 | `https://target1\|target2:8000` | 複数upstream、HTTPS |
| D26 | `http://target1:8000\|target2:8001[backup max_conns=100]` | 複数upstream、パラメータ付き |

### 4.2 Nginx生成契約：H／T／A／R（20件）

**試験の方法**：本体のERBテンプレートを直接描画し、生成されたNginx設定の重要なディレクティブを比較する。`Nginx.config_domain` のような `/etc/nginx` への書き込み処理は直接呼び出さない。描画は `ERBBinding` と `Domain` の実装を使用し、読み込み元のみチェックアウト配下の実ファイルへ差し替える。期待値の固定化と、意味上必須の個別 `expect` の両方を用いる。

| ID | 契約・入力 | 期待する生成物・検出対象 |
|---|---|---|
| H01 | 標準HTTPサイト | `listen 80`、`server_name`、`return 301 https://$server_name$request_uri` |
| H02 | ACME HTTP-01ルート | `/.well-known/acme-challenge/` の例外locationが存在 |
| H03 | `LISTEN_IPV6=true` | IPv6用の `listen [::]:80` が追加される |
| H04 | `:4443` のドメイン | **現行仕様**の `301 https://$server_name$request_uri` を記録。ポートが含まれない点は仕様確認票へ |
| T01 | グローバルTLS | `ssl_protocols TLSv1.2 TLSv1.3;` が含まれる |
| T02 | HTTPS server | SSL listen／domain名／証明書パス／鍵パスが一致 |
| T03 | `HSTS_MAX_AGE` 未設定／設定 | HSTS指示文の有無、max-age値が一致 |
| T04 | デフォルトサーバー | `ssl_reject_handshake on;` の指示文を生成 |
| A01 | Basic認証指定 | `auth_basic` と `auth_basic_user_file` が存在 |
| A02 | Basic認証未指定 | `auth_basic` 指示文を生成しない |
| A03 | IP制限1件 | `allow <CIDR>;`、`deny all;` が存在 |
| A04 | IP制限複数件 | 指定順に全 `allow` を生成し、最後に `deny all;` |
| A05 | 認証設定の出力 | 資格情報の平文をNginx設定に埋め込まず、参照ファイルパスのみ含む |
| R01 | 静的サイト | `root`／`index` が期待通り、`proxy_pass` は生成しない |
| R02 | HTTP upstream | 正しい `proxy_pass http://...` と Host／Real-IP／Forwarded系ヘッダーを生成 |
| R03 | 複数upstream | `upstream` のserver列挙、backup等のパラメータ、backend参照 |
| R04 | `=>` 転送先指定 | HTTPS側の既定 `return 307 <target>$request_uri` |
| R05 | `REDIRECT_CODE=308` | HTTPS側の `return 308` を生成 |
| R06 | `WEBSOCKET=true` | Upgrade／Connection／HTTP 1.1の設定を生成 |
| R07 | `DYNAMIC_UPSTREAM=true` | `$backend` 経由の `proxy_pass` を生成 |

**重要**：H01はHTTP→HTTPSリダイレクト、R04・R05はHTTPS上での別URLへの転送である。HTTP 301の検証をもって、HTTPS転送307／308が検証済みとはしない。またH04は現状固定の確認であり、非443ポートへのリダイレクトが正しいと承認した意味ではない。

### 4.3 証明書更新判断：C01〜C08（8件）

| ID | 判定条件（ほかの条件は正常・非dummy・更新不要に固定） | 期待 |
|---|---|---|
| C01 | 秘密鍵なし | `need_to_sign_or_renew? == true` |
| C02 | 署名証明書なし | `true` |
| C03 | dummy証明書である | `true` |
| C04 | 更新猶予30日／残り31日 | `false` |
| C05 | 更新猶予30日／残り30日 | `true` |
| C06 | 更新猶予30日／残り29日 | `true` |
| C07 | `FORCE_RENEW=true`／残り31日 | `true` |
| C08 | 固定した日付に対する `expires_in_days` | 証明書有効期限との差分日数が一致 |

**制御すべき依存**：`File.exist?` の指定された鍵・証明書パス、`OpenSSL.dummy?`、`OpenSSL.expires_in_days`、`NAConfig.force_renew?`、`NAConfig.renew_margin_days`。C08だけは `Date.today` を固定し、`OpenSSL.expires_at` にテスト用の満了日を与えた日付差分計算とする（実コマンド実行はしない）。C01〜C07は `expires_in_days` をスタブして比較する。プロジェクトの `OpenSSL` モジュールに追加されたメソッドを呼び出すことを確認する。

## 5. 実装方式と推奨ファイル構成

```text
spec/
├── models/
│   └── domain_spec.rb                 # 既存26データを独立したRSpecケースに変更
├── contracts/
│   ├── nginx_http_spec.rb            # H01-H04
│   ├── nginx_tls_spec.rb             # T01-T04
│   ├── nginx_access_spec.rb          # A01-A05
│   ├── nginx_routing_spec.rb         # R01-R07
│   └── certificate_renewal_spec.rb   # C01-C08
├── support/
│   └── contract_render_helpers.rb    # ERB描画、ENV退避復元、固定fixture
└── fixtures/
    └── contracts/                    # レビュー済みの比較対象（必要最小限）
docs/
├── test-contract-matrix-ja.md         # この試験一覧と要件対応
├── known-behavior-gaps-ja.md          # 現状挙動と望ましい仕様の差
└── mutation-check-ja.md              # 故意の変更検知の実施記録
```

**描画fixtureの固定条件**：ドメイン名は例示用 `example.test` などの外部に出ない値、テスト用資格情報はダミー、`STAGE=local`、必要な `ENV` のみ一時設定。`domain`／`acme_challenge_location`／`dhparam_path` を明示してERBを描画する。`ENV` は `ensure` 等で必ず復元し、テスト同士を独立させる。`Domain#initialize` のディレクトリ作成は一時領域／モックで隔離する。

**比較ルール**：タイムスタンプ、絶対パスの一時ディレクトリ、不要な空白だけ正規化する。HTTPコード、`server_name`、listenポート、TLSバージョン、証明書パス、`proxy_pass`、Proxyヘッダー、認証・アクセス制限、ACMEルートは正規化で消してはいけない。スナップショットの一括再生成だけでレビュー承認としない。

### 実装時のRSpec形（参考・擬似コード）

**26ケースの個別化**は、既存 `domain_configs` の内容と属性期待値を変更せず、`each_with_index` の中で **`it` を定義**する。`it` の実行ブロック内で26行をループさせる方式では、失敗が1例に集約されるため不可。

```ruby
cases.each_with_index do |config, index|
  it format('D%02d: %s', index + 1, config.fetch(:descriptor).inspect) do
    domain = Domain.new(config.fetch(:descriptor))
    fields.each do |field|
      expect(domain.public_send(field)).to eq(config.fetch(field))
    end
  end
end
```

**Nginx契約試験**は `ERBBinding` に本物のテンプレートとテスト用の `domain` 等を渡して描画する。描画後に `return 301`、`proxy_set_header` など重要ディレクティブを直接検証する。`Nginx.config_domain` のような絶対パスへ書き込む本体メソッドをテスト中に呼ぶ構成にしない。

**更新境界試験**では `OpenSSL.need_to_sign_or_renew?(domain)` を実際に呼び、`File.exist?` の対象パス、`dummy?`、`expires_in_days`、`NAConfig.force_renew?`、`NAConfig.renew_margin_days` のみを制御する。比較演算子 `>` を実際に通す試験とし、判定関数そのものをモックしない。

**既存テストとの関係**：12件の既存Docker機能テストはP1で変更しない。`spec/spec_helper.rb` が全スイート実行前にビルドするため、P1ローカル実行は `SKIP_BUILD=1` を付けて **新規UT／契約テストのパスだけ** 指定する。P2でRSpecヘルパーのDocker依存分離、Compose V2、テスト間依存排除を扱う。

## 6. 8営業日の作業順（5〜6営業日への短縮条件つき）

| 営業日 | 当日実施すること | 当日完了の証拠 |
|---|---|---|
| 1日目 | P0成果を確認、既存26件と期待値を台帳化、RSpec実行導線／ERB描画ヘルパーを作成 | Dockerを起動せずに単独UTを実行できる |
| 2日目 | D01〜D26へ分割、テスト名の安定化・相互独立・出力形式を確認 | `--format documentation` で26件が独立表示 |
| 3日目 | H01〜H04／T01〜T04、グローバル・HTTP・SSLテンプレートの契約を作成 | 生成された重要指示文が期待どおり |
| 4日目 | A01〜A05／R01〜R07、環境変数ON/OFFのfixtureを拡充 | 設定条件の分岐を個別検出 |
| 5日目 | C01〜C08、強制更新・dummy・有効期限境界を検証 | 30/31日の境界試験と時刻固定試験が緑 |
| 6日目 | 全54件を通し、重複・不安定要因を修正、Mutation試験を実施 | 意図した変更でテストが赤に変わる証拠 |
| 7日目 | テスト期待値・既知挙動のレビュー、契約台帳と証跡の整備 | レビュアーが妥当な契約かを承認 |
| 8日目（予備） | OS差・Ruby依存差などの修正、再実行・PR仕上げ | 受入基準チェックが全項目完了 |

**5営業日に短縮可能な条件**：P0成果が確定、Ruby/RSpec環境が既に稼働、レビュー担当が3〜5日目に並行対応、テンプレート描画ヘルパーが1日目で安定。条件が満たされない場合は7〜8日を採用する。期間を守るために重要な検証を削除しない。

## 7. 故意の変更による検知実証（必須）

| Mutation ID | 検証用ブランチで一時的に変更する箇所 | 落ちるべきケース |
|---|---|---|
| M01 | HTTP `return 301` を `302` に変える | H01（HTTP契約） |
| M02 | SSL設定から `proxy_set_header X-Forwarded-Proto` を消す | R02（proxy契約） |
| M03 | SSL設定から `auth_basic_user_file` を消す | A01（認証契約） |
| M04 | 証明書判断の `expires_in_days > renew_margin_days` を `>=` に変える | C05（残り30日境界） |
| M05（推奨） | HTTPS転送の既定 `307` を `302` に変える | R04（転送契約） |

**実施手順**：通常コードで合格（緑）→ 1つだけ変更 → 対応テストだけを実行し非ゼロ終了（赤）を確認 → 元に戻す → 再実行して緑を確認。M01〜M04は必須、M05は推奨。コード差分、試験名、失敗メッセージ、実施日時、復元確認を `docs/mutation-check-ja.md` に記録し、故意の変更はPRに残さない。

## 8. 実行コマンド（計画する操作）

```bash
# P1は単体・テンプレート契約のみ。外部DNS/ACME、Dockerを使用しない。
SKIP_BUILD=1 bundle exec rspec spec/models/domain_spec.rb spec/contracts --format documentation

# ケース単位の再実行例
SKIP_BUILD=1 bundle exec rspec spec/contracts/certificate_renewal_spec.rb --format documentation

# Rubyファイルの構文確認例（実装後）
find spec/models spec/contracts spec/support -name '*.rb' -print0 | xargs -0 -n1 ruby -c
```

注：`Gemfile.lock` は提供ZIPでは `arm64-darwin-20` のみが記載されており、Linux上のBundle実行には事前の依存環境調整が必要となる可能性がある。P1開始時に記録し、Ruby/RSpecのメジャーバージョン更新はP4まで同時実施しない。上記コマンドは**提案する検証手順**であり、本計画作成時点で実行成功を保証するものではない。

## 9. 完了条件（Definition of Done）

| ID | 必須判定基準 | 証跡 |
|---|---|---|
| G01 | D01〜D26が独立した26例として実行され、10属性の従来期待値を保持 | RSpec `documentation` 出力、差分レビュー |
| G02 | H01〜H04、T01〜T04、A01〜A05、R01〜R07が実ERBテンプレートから生成した設定を検証 | 生成設定のレビュー済みfixture、RSpec結果 |
| G03 | C01〜C08で鍵／証明書有無・dummy・強制更新・29/30/31日を検証 | RSpec結果（環境・日付固定） |
| G04 | **合計54例**が単独／一括で緑、実行順や実際の時刻に依存しない | 連続3回の実行結果 |
| G05 | M01〜M04が意図通り対応テストを失敗させ、元に戻すと成功 | Mutation実施ログ、実行コマンドと終了コード |
| G06 | Docker／公開ACME／外部DNS／本番秘密情報へのアクセスがない | テスト設定・モック範囲のレビュー |
| G07 | 現行の怪しい動作（例：非443ポート／renewalログ差分）を既知問題として登録 | `known-behavior-gaps-ja.md` |
| G08 | 設計・期待値・PRのレビュー済み、製品バージョン更新・本番挙動修正を混ぜない | PRレビュー承認 |

**性能目標**：ローカル単体＋設定契約の合計で1分以内を目標とする（厳密な完了阻害条件ではなく、実測をP1終了時に記録）。スキップやpendingで緑を作らない。既知の未解決仕様は試験未実装のまま曖昧にせず、対象外として番号をつけP2／P3へ引き継ぐ。

## 10. PR構成とレビュー

| PR | 範囲 | レビューの焦点 |
|---|---|---|
| P1-PR01 | 実行ヘルパー、D01〜D26への分割 | 現行期待値を一切落としていないか、Docker非依存か |
| P1-PR02 | ERB生成契約 H／T／A／R、fixture | 実テンプレートを検査しているか、重要指示文が抜けないか |
| P1-PR03 | 証明書更新 C01〜C08、Mutation証跡、試験台帳 | 境界値と強制更新を検出できるか、既知欠陥を承認していないか |

依存ライブラリやNginxの更新は、**P1のテスト追加PRと混ぜない**。更新時の不合格は「製品コード変更による差分」として特定できるようにする。各PRのレビューは最低1名を想定する。

## 11. リスク／仕様判断／後続への引継ぎ

| 論点 | リスク・判断 | 対応 |
|---|---|---|
| `:4443`のHTTPリダイレクト | HTTPテンプレートはURLに非443ポートを明示していない | P1で現在の出力を記録、期待仕様は別Issueで決定、機能修正はP2以降 |
| 既定HTTPS転送コード | `=>`は307、HTTP→HTTPSは301 | 2種類を混同しない独立ケースとする |
| 認証資格情報 | Fixtureやログへの平文流出の恐れ | 架空のテスト値のみ、生成物への混入なしを確認 |
| OS/Ruby差分 | ロックファイルはmacOSプラットフォーム、実行環境では再解決の可能性 | P1初日に検証、更新対象と切り離す |
| Golden fileの過剰拘束 | Nginxの整形だけで不要な失敗が増える | 意味を持つディレクティブ中心の比較、正規化ルールをレビュー |
| 既存12件のDocker機能テスト | 旧Compose、Docker Machine、状態依存が残る | P1に混入させず、P2で別タスク化 |
| 実通信のセキュリティ | TLSチェーン・実ステータスの安全性は生成設定だけでは判定不可 | P2のlocalスモーク、P3の信頼CA・認証・IP制限試験へ引継ぎ |
| 証明書更新の副作用 | `renew`やACMEをそのまま呼ぶとネットワーク／外部ファイルを扱う | P1は判定関数だけ試験。実更新の成否はP2〜P3 |

### P2への引継ぎ条件

P1成果の54契約試験をGitHub Actionsの短時間UTジョブで実行し、Dockerを必要とする次の実動作を追加する：`HTTP 301 + Location`、`HTTPS 200`、`HTTPSリダイレクト307/308`、`Basic認証401/200`、`proxy先でHost/Forwardedヘッダー確認`、`独立CAを利用した証明書検証`、`再起動・永続化`。実通信の合否をP1契約試験の成功と混同しない。

---

### 提出時に添付する証跡チェック

- 追加／変更したRSpecファイルの一覧と54件の実行結果
- 既存26入力・10属性の旧→新対応表（脱落なし）
- 実ERBから生成したHTTP／SSL／グローバル設定の代表出力と期待値レビュー
- M01〜M04の意図的な変更による失敗・復元後成功のログ
- 実測の所要時間、既知動作差分、P2／P3の未着手課題一覧
