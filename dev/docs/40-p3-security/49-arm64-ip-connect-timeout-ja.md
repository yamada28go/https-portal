# ARM64 IP制限試験の接続開始タイムアウト

## 対象と確認結果

Tests #14 / run 40196588599 / attempt 1 / commit 7d262b7d37168455b15957b421487e1837fae08d。
成果物 integration-test-evidence-arm64-40196588599-1 / 20261025t131309z-5a107840。

- 製品・試験イメージとも linux/arm64。local から static まで最初の8シナリオは成功。以前失敗した proxy も成功している。
- IP許可側は 172.18.0.2 から200を得て成功。
- IP拒否側は 172.18.0.5 からの通常アクセス、X-Forwarded-For単独偽装、X-Real-IP単独偽装がいずれも403。
- 最後の両ヘッダー同時偽装では Net::OpenTimeout: execution expired。HTTP応答の assertion に達していない。該当リクエストの nginx access log もない。
- portal は healthy、echo は running。診断・cleanup は成功し、残留リソースはない。

run-9-probe.stdout.log は failed、cases=[S-T04-denied]、checks=[denied:403, spoof-1:403, spoof-2:403] を記録する。S-T05全体は未受入。

## 判断と限界

確認できた直接の失敗は接続開始段階の時間切れ。IP制限が予期しない200を返したという結果ではない。ただし、TCP接続、TLSハンドシェイク、実行環境の負荷等のどれが起点かを既存ログだけで確定することはできない。ARM64固有のRuby/OpenSSL不具合とも断定しない。

今回の変更は接続時間切れへの限定的な耐性と証拠追加であり、未確定の根本原因を解消したとするものではない。再試行が記録された場合は、最終成功でも一時的な接続失敗があった事実を残す。

## 変更

spec/ci/integration/client.rb の GET リクエストで Net::OpenTimeout のみ最大3試行（再試行2回、間隔0.25秒）。試行ごとに新しい Net::HTTP を作る。各操作の時間制限、起動期限の残り時間、Dockerプロセスの外側の時間制限は維持する。

各失敗を stderr へ HTTP connection timeout: host=... attempt=N/3 error=... と記録する。認証情報と送信ヘッダーは出力しない。Net::HTTP 自身の max_retries は0を維持し、再試行回数を二重管理しない。

読み取りタイムアウト・証明書エラーは再試行しない。HTTP応答が返ったら従来どおり各シナリオの assertion で検証し、拒否試験の200応答は直ちに失敗する。全3試行で接続できなければ Net::OpenTimeout のまま失敗する。製品ファイルは変更しない。

## 検証

check_client.rb に次の5件を追加し、既存7件と合わせて12件が Windows x64 / RubyInstaller 3.4.12 で成功（exit 0）。

1. 接続開始タイムアウト後に再試行でき、警告が記録される。
2. 接続開始タイムアウトが3回続けば失敗する。
3. 読み取りタイムアウトは再試行しない。
4. 証明書エラーは再試行しない。
5. 403を期待する試験で200が返れば、再試行せず契約違反となる。

Prismによる変更Rubyの構文検査も成功。Ruby 2.7.2/LinuxおよびARM64での新変更の実行確認は未実施。

## 再受入

新たな変更を commit/push し、新コミットの Tests を確認する。古いコミットの Re-run では変更が反映されない。

- build-tools に Integration client: ...: passed が12件ある。
- docker-smoke (amd64)/(arm64) が全13シナリオで成功する。
- IP試験は許可側200、拒否側の通常アクセスと全3偽装パターンが403。
- 接続開始タイムアウトが発生した場合は probe stderr の試行記録を確認する。再発する場合は負荷・TLS接続段階等を追加調査する。
- 各CPUの result.json の result、imagePlatforms、cleanup と残留リソースを確認する。
