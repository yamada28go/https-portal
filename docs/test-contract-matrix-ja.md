# P1 単体・設定契約テスト対応表

## 実装・検証状態

D26例、H4例、T4例、A5例、R7例、C8例、従来54例に加え、C-02の異常入力29例を追加し、合計83例を実装した。製品コードと既存Docker機能テストは変更していない。

実施済み：Ruby公式Prism 2.0.0のJavaScript/WASM版による追加・変更Rubyファイル10本の構文解析、既存26行の入力・期待値とHEADの一致、Compose/PowerShell構文、Composeの54例実行パス確認。Prismは作業用一時領域だけに展開し、Ruby/GemはWindowsへ導入していない。この解析はRuby 2.7.2による実行確認の代わりにはならない。

**従来54例のRSpec・3 seed・各spec単独・M01〜M05は利用者提供の実行結果で成功を確認済み。追加29例と全83例は未実行。** Docker Engineの名前付きパイプに対する接続拒否が継続している。P0成果との照合、fixtureの人によるレビューも未完了。追加分まで検証済み、またはP1全体が完了とは扱わない。

## 実行

プロジェクトルートのPowerShellから：

```powershell
# 83例のUT・設定契約のみ
.\dev\dev.ps1 Test

# 構文、83例の3 seed、各spec単独、M01〜M05と復元の一括検証
.\dev\dev.ps1 P1
```

Ruby環境内での直接実行：

```bash
SKIP_BUILD=1 bundle exec rspec spec/models/domain_spec.rb spec/models/domain_input_spec.rb spec/contracts --format documentation
SKIP_BUILD=1 bundle exec ruby dev/check_p1.rb
```

全RSpecの無条件実行は既存Docker機能テストを含むため、P1では対象ファイルを限定する。

## 独立性とfixture

`spec/support/contract_render_helpers.rb` はp1タグの例だけに適用する。ENVの試験関連キーを除去し、STAGE=local、FORCE_RENEW=false、更新猶予30日に固定する。例終了時はENV全体をensureで復元する。Domainのディレクトリ作成と外部コマンド起動をモックし、実ERBBinding、Domain、NginxのACMEスニペット生成を使う。Nginxのファイル書き込み・起動メソッドは呼ばない。

fixtureは次の2件。自動再生成は行わず、重要ディレクティブの個別expectも併用する。比較は空行・コメント・行頭末の空白のみ除去し、ポート、URL、コード、証明書パス、認証参照、ヘッダーを保持する。

- `spec/fixtures/contracts/http.conf`：標準HTTPの出力全体。
- `spec/fixtures/contracts/proxy-directives.conf`：HTTP proxyの全proxy_*指示文。

fixtureは実テンプレートと目視照合して作成したが、別担当者による期待値承認は未実施。

## D01〜D26：旧入力と新ケースの対応

旧domain_configsの行順と入力・10属性の期待値を維持。従来の1例内ループを26個のitに分割した。各例はaggregate_failuresでname、env_format_name、upstream_proto、upstreams、redirect_target_url、stage、basic_auth_username、basic_auth_password、access_restriction、portを確認する。

| 新ID | 旧配列行 | 入力リテラル |
|---|---:|---|
| D01 | 1 | `'example.com'` |
| D02 | 2 | `'example.com:4443'` |
| D03 | 3 | `'4example.com'` |
| D04 | 4 | `' example.com '` |
| D05 | 5 | `'example.com #staging'` |
| D06 | 6 | `'example.com -> http://target '` |
| D07 | 7 | `"example.com \n-> http://target \n"` |
| D08 | 8 | `"example.com\n-> http://target "` |
| D09 | 9 | `'example.com -> http://target:8000'` |
| D10 | 10 | `'example.com -> target:8000'` |
| D11 | 11 | `'example.com => http://target'` |
| D12 | 12 | `'example.com => https://target'` |
| D13 | 13 | `'example.com => target'` |
| D14 | 14 | `'example.com=>http://target'` |
| D15 | 15 | `'example.com -> http://target #staging'` |
| D16 | 16 | `'example.com => http://target #staging'` |
| D17 | 17 | `'example.com->http://target #staging'` |
| D18 | 18 | `'exam-ple.com->http://tar-get #staging'` |
| D19 | 19 | `'example_.com->http://target #staging'` |
| D20 | 20 | `'example.com->http://tar_get_ #staging'` |
| D21 | 21 | `'username:password@example.com'` |
| D22 | 22 | `'username:password@example.com -> http://target #staging'` |
| D23 | 23 | `'[1.2.3.4/24]username:password@example.com -> http://target #staging'` |
| D24 | 24 | `' [ 1.2.3.4 4.3.2.1/24 ] username:password@example.com -> http://target #staging'` |
| D25 | 25 | `'example.com -> https://target1\|target2:8000'` |
| D26 | 26 | `'example.com -> http://target1:8000\|target2:8001[backup max_conns=100]'` |
## H/T/A/R/C：実装ファイルとケース

| ID | ファイル（spec/contracts/配下） | 観点 |
|---|---|---|
| H01 | nginx_http_spec.rb | HTTP 80、名前、301、標準fixture |
| H02 | nginx_http_spec.rb | ACME例外location、allow、alias、try_files |
| H03 | nginx_http_spec.rb | IPv6 ONで両listen生成 |
| H04 | nginx_http_spec.rb | 非443ポートを省略する現行挙動（C） |
| T01 | nginx_tls_spec.rb | TLSv1.2/TLSv1.3の正確なプロトコル集合 |
| T02 | nginx_tls_spec.rb | SSLポート、名前、証明書・鍵・DHパス |
| T03 | nginx_tls_spec.rb | HSTS未設定/設定/復元後とmax-age |
| T04 | nginx_tls_spec.rb | デフォルトSSL server内でhandshake拒否 |
| A01 | nginx_access_spec.rb | Basic認証指示文とパスワードファイル参照 |
| A02 | nginx_access_spec.rb | 未指定時に認証・IP制限指示文なし |
| A03 | nginx_access_spec.rb | 単一CIDRのallowとdeny allの順序 |
| A04 | nginx_access_spec.rb | 複数allowの指定順、末尾deny all |
| A05 | nginx_access_spec.rb | ダミー資格情報の平文を出力しない |
| R01 | nginx_routing_spec.rb | 静的root/index、proxyなし |
| R02 | nginx_routing_spec.rb | HTTP proxy、4ヘッダー、標準fixture |
| R03 | nginx_routing_spec.rb | HTTPS複数upstream、順序、パラメータ、backend |
| R04 | nginx_routing_spec.rb | HTTPS転送の既定307とURI |
| R05 | nginx_routing_spec.rb | 指定した308とURI |
| R06 | nginx_routing_spec.rb | WebSocketヘッダー、HTTP1.1、グローバルmap |
| R07 | nginx_routing_spec.rb | 動的upstreamとbackend変数 |
| C01 | certificate_renewal_spec.rb | 鍵欠落で更新必要 |
| C02 | certificate_renewal_spec.rb | 証明書欠落で更新必要 |
| C03 | certificate_renewal_spec.rb | dummyなら更新必要 |
| C04 | certificate_renewal_spec.rb | 残31日なら更新不要 |
| C05 | certificate_renewal_spec.rb | 残30日なら更新必要 |
| C06 | certificate_renewal_spec.rb | 残29日なら更新必要 |
| C07 | certificate_renewal_spec.rb | 強制更新で残31日でも更新必要 |
| C08 | certificate_renewal_spec.rb | 固定日付と満了日の差分、閏日をまたぐ30日 |

C01〜C07は判定関数そのものをモックせず、指定パスの存在、dummy、残日数、NAConfigのみ制御する。C08はexpires_in_daysの本実装へ戻し、Date.todayとexpires_atを固定する。opensslコマンドは実行しない。

HTTP/TLS/認証/ルーティングの試験は生成設定の検証。実通信のセキュリティやステータスを保証しない。現状固定のC契約と、安全性に関する要求を混同しない。

## 後続・証跡

- [既知挙動・後続課題](known-behavior-gaps-ja.md)
- [Mutation手順と未実行の記録](mutation-check-ja.md)
- [詳細計画](https-portal-p1-detailed-test-plan-ja.md)

G01〜G07の実行証跡とG08のレビュー承認は、自動検証と人によるレビュー完了後に記録する。

## C-02の追加29例

`spec/models/domain_input_spec.rb`に空値・ポート・制御文字・不正構文と現行の未検証入力の扱いを追加。[ケース一覧・実行手順・既知の差](c02-input-contract-ja.md)を参照。製品の入力検証は変更していない。
