# C-07／C-08：現行動作を正解とする契約

## 方針

利用者の指示に基づき、現在の実装を正解として固定する。C-07に12例、C-08に18例を追加し、全P1対象を113例にした。製品コード・Ruby/Gemバージョンは変更していない。

例外の無視、途中まで更新されたファイル、失敗時の空ファイルも現在の期待値に含む。ロールバックや入力検証等の新機能は追加しない。将来これらを変更する際は、仕様変更に合わせて期待値も更新する。

## C-07：ACME署名（12例）

実装：`spec/contracts/acme_signing_spec.rb`

| ID | 条件 | 現行の期待値 |
|---|---|---|
| C-07-01 | staging署名コマンド成功 | 120秒枠でコマンドを呼び、証明書→鍵の順で正式ファイルへ移動。戻り値はtruthy |
| C-07-02 | コマンドがfalse | falseを返す。移動せず既存ファイル・作業中ファイルを保持 |
| C-07-03 | コマンドがnil | falseを返す。正式ファイルを置き換えない |
| C-07-04 | コマンド中のTimeout::Error | falseを返す。正式ファイルを置き換えない |
| C-07-05 | 作業中証明書が欠落 | 例外を外へ出さず、既存証明書を残して新しい鍵だけを移動 |
| C-07-06 | 作業中鍵が欠落 | 例外を外へ出さず、新しい証明書と古い鍵が残る |
| C-07-07 | 証明書renameがEACCES | 例外を外へ出さず、古い証明書と新しい鍵が残る |
| C-07-08 | 鍵renameがEACCES | 例外を外へ出さず、新しい証明書と古い鍵が残る。証明書を戻さない |
| C-07-09 | local自己署名がtrue | 自己署名へ委譲しtrue。ACMEコマンドやtimeout枠は呼ばない |
| C-07-10 | local自己署名がfalse | falseを返す |
| C-07-11 | local自己署名がTimeout::Error | falseを返す |
| C-07-12 | 署名コマンドがその他の例外 | 元の例外を伝播し、既存ファイルを保持 |

`force: true`でのFileUtils.mvはSystemCallErrorを無視するため、欠落・権限エラーは例外伝播としない。低水準のFile.renameをスタブし、FileUtils.mvの実装を通して確認する。

## C-08：Nginx設定生成・reload（18例）

実装：`spec/contracts/nginx_failure_spec.rb`

| ID | 条件 | 現行の期待値 |
|---|---|---|
| C-08-01 | 通常reloadがfalse | falseを返しkillしない |
| C-08-02 | reloadがtrue | trueを返しkillしない |
| C-08-03 | 通常reloadがnil | nilを返しkillしない |
| C-08-04 | kill指定でreloadがfalse | reload後にpkill、戻り値はreloadのfalse |
| C-08-05 | kill指定でreloadがtrue | killせずtrue |
| C-08-06 | kill指定でreloadがnil、killがfalse | killを呼び、戻り値はreloadのnil |
| C-08-07 | reloadコマンドが例外 | 元の例外を伝播。killしない |
| C-08-08 | グローバル設定生成成功 | 描画結果で対象ファイルを置換。reloadしない |
| C-08-09 | HTTP設定生成成功 | ドメインの.confにHTTP設定を書き込む |
| C-08-10 | SSL443設定生成成功 | 従来の.ssl.conf名へ書き込む |
| C-08-11 | SSL4443設定生成成功 | _4443.ssl.conf名へ書き込む |
| C-08-12 | グローバル設定の描画失敗 | 例外を伝播。既存ファイルは開かず保持 |
| C-08-13 | HTTP設定の描画失敗 | 例外を伝播。先に開いたHTTPファイルは空のまま |
| C-08-14 | SSL設定の描画失敗 | 例外を伝播。先に開いたSSLファイルは空のまま |
| C-08-15 | HTTPファイルのopen失敗 | 描画せず例外を伝播。既存ファイルを保持 |
| C-08-16 | HTTPファイルのwrite失敗 | 例外を伝播。開いたファイルは空のまま |
| C-08-17 | HTTP更新後にSSL描画失敗 | HTTPは新しい設定、SSLは空のまま。戻さない |
| C-08-18 | HTTP描画が先に失敗 | HTTPは空、SSLは旧設定。SSL設定処理は呼ばない |

## 外部通信・本番副作用の隔離

- acme_tiny、openssl、nginx、pkillを実行しない。systemを限定した引数でスタブし、それ以外のコマンドは既存のp1ガードで失敗させる。
- Timeout.timeout(120)は即座にブロックを実行するスタブを使い、タイムアウト例では例外を即時発生させる。120秒待たない。
- 証明書は一時ディレクトリのダミーファイルを本当に移動して、最終内容を比較する。
- Nginxの本体描画・書き込み順序を通す。テンプレート入力だけをリポジトリ内へ、/etc/nginxへの書き込みだけを一時ディレクトリへ差し替える。未定義のNginx出力先は書き込む前に失敗する。
- testサービスのnetwork_mode: noneを維持し、DNS・ACME・upstreamへの通信を行わない。
- 一時ディレクトリは各例のensure経路で削除し、モックはRSpecが例ごとに復元する。

## 自動検証

```powershell
# 全113例
.\dev\dev.ps1 Test

# 構文、3 seed、各spec単独、M01〜M08、復元後113例
.\dev\dev.ps1 P1
```

新しいMutationは次の3件。

| ID | 一時変更 | 検知対象 |
|---|---|---|
| M06 | 署名のtimeout指定を120から121へ | C-07-01 |
| M07 | reload失敗時にkill指定を無視して常にkill | C-08-01 |
| M08 | 証明書移動のforceをtrueからfalseへ | C-07-05 |

Mutationは一時コピーだけを変更する。元の製品ソースは書き換えない。

## 検証状況

従来83例の3 seed・各spec単独・M01〜M05と復元は利用者実行ログで成功確認済み。今回追加30例とM06〜M08は、Prismによる構文とケース数・実行設定を確認する。実RSpecはこのチャットのDocker Engine接続拒否により未確認。実行後に113例とM01〜M08の結果を記録する。

## 参照

- [P1対応表](test-contract-matrix-ja.md)
- [Mutation検証](mutation-check-ja.md)
- [Ruby 2.7 FileUtils.mvの仕様と実装](https://docs.ruby-lang.org/en/2.7.0/FileUtils.html#method-c-mv)
