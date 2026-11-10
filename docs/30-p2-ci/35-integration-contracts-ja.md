# 重要な結合試験（P2-04）

用途：リダイレクト・proxy・認証・独立CA・証明書保持・更新スキップ・静的配信の実通信契約を検証する。

[文書一覧](../00-index-ja.md) / [検証記録](32-verification-ja.md) / [基盤の手順](34-integration-guide-ja.md)

## 状態と実行境界

実装・設定解析・静的検証まで完了。新しいシナリオの実build/実通信は利用者の実行待ちで、P2-04完了とはしていない。

**試験中はinternal network内だけで通信する。公開DNS・Let's Encrypt・外部upstreamを使わず、イメージも公開しない。** 初回buildは従来どおりベースイメージ・OS依存等の取得で外部通信を伴う。

ホストはDocker操作とログ保存だけ。Git/Ruby/Gemの導入やdev.ps1の起動は不要。testerへDocker socket・ホストディレクトリ・秘密鍵volumeを渡さない。

## 実行

プロジェクトルートのPowerShellで実行する。

```powershell
# 全シナリオの設定だけ解析。コンテナは起動しない
.\dev\check_p2_integration.ps1 -Scenario all -ValidateOnly

# 全8シナリオを独立したprojectで実行
.\dev\check_p2_integration.ps1 -Scenario all

# 個別に実行する例
.\dev\check_p2_integration.ps1 -Scenario ca
.\dev\check_p2_integration.ps1 -Scenario proxy
```

allはlocal、redirect、proxy、auth、ca、persistence、renewal、staticの順。イメージは一度buildして共有するが、各scenarioのnetwork・証明書・静的配信・公開データのvolumeは共有しない。途中で失敗した場合は診断・cleanup後に停止する。

既定値は従来どおりlocal。-Repeat 2を付けると、選んだシナリオ全体を2回、別projectで実行する。never-readyは意図的失敗用なのでallには含めない。

## 検証内容

| Scenario | 契約ID | 主な合格条件 |
|---|---|---|
| local | I-01 | 既存の自己署名・HTTPS 200/welcome・echo疎通 |
| redirect | I-02 | HTTPが301。Locationのscheme/host/path/queryが完全一致。redirectを追従しない |
| proxy | I-03 | echoへのHTTPS経由応答200、path/query保持、Host、X-Forwarded-Proto=https、X-Real-IP/X-Forwarded-Forがtester IPと一致 |
| auth | I-04 | 未認証・誤認証は401とBasic challenge、正しい架空資格情報では200とecho本文 |
| ca | I-05 | 独立root→intermediate→leafの検証、提示leafの一致、intermediate提示、誤CA・誤名拒否、実際に使用する証明書と鍵の公開部分一致 |
| persistence | I-06 | 初回HTTPS成功後にportalだけforce-recreate。証明書volumeを維持し、同じleaf fingerprintとwelcome応答を確認 |
| renewal | I-07 | 初回証明書を記録。renew_certsを明示実行し、skipログ・終了0・証明書不変・HTTPS正常を確認 |
| static | I-08 | indexと別階層のファイルを、query付きでも正確な本文・200で配信 |

契約のassertは起動待ちから分け、違反を再試行で成功扱いにしない。新クライアントは同じ証明書で3回連続のTLS/HTTP応答を待ってから契約を判定する。未対応API等のプログラムエラーは再試行しない。

## 独立CAとホスト名検証

prepareコンテナがRSA鍵と一時CAを生成する。root/intermediateの秘密鍵はメモリ内だけに保持し、volumeやログへ書かない。portalの証明書volumeにはleaf秘密鍵とleaf+intermediateの証明書を保存する。

testerのpublic volumeへ渡すのはroot公開証明書、誤CAの公開証明書、期待する公開fingerprintだけ。testerは正しいrootだけを信頼してTLSを検証する。CAシナリオではVERIFY_NONEによる信頼のbootstrapは行わない。

誤ホスト名は、正しいSNIと接続先でTLSを成立させたうえでwrong.testとの名前照合を要求する。単にNginxの不明SNI拒否を見て、クライアントのホスト名検証が成功したことにはしない。

証明書・鍵の一致はportal内のopensslで双方の公開部分だけを出力して比較する。秘密鍵の内容はログへ出さない。独立CA試験は既存証明書のロード・提示の契約であり、ACME発行試験ではない。

## 証明書保持と更新スキップ

persistence/renewalだけは同じscenario内でpublic volumeにbefore.jsonを保持し、初回のleaf fingerprintを次のtesterコンテナで比較する。別scenario・別繰り返しでは新規volumeを作る。

renewalはcronの実行時刻を待たず、製品のwith-contenv/s6-envdir経由でrenew_certsを呼ぶ。FORCE_RENEW=false、残有効期間十分な証明書のskipだけを試す。強制更新・公開CAでの更新・失敗時の原子性を保証したことにはしない。

## fixtureとログ

| サービス/volume | 役割 |
|---|---|
| prepare | rootで試験volumeを準備する一時コンテナ。cap-drop ALL、read-only rootfs、tmpfs、内部network |
| portal | 製品イメージ。local設定・シナリオごとの固定.test domain |
| echo | proxy先の試験用HTTPサービス。Authorizationや環境変数は応答・ログに出さない |
| tester | UID1000。public volumeだけを共有し、証明書の秘密鍵・静的ファイル用volumeは受け取らない |
| certificates | portalの鍵・証明書。prepareとportalだけが利用 |
| site | 静的fixture。prepareとportalだけが利用 |
| public | CA公開証明書・fingerprint・before.json。秘密鍵なし |
| nginx-logs | portalのログ領域 |

従来と同じdev/test-results/p2-integration/<実行ID>/へ保存する。result.jsonのrunsにはscenario、project、fixtureEnv、成否、診断・cleanup・残存状態が入る。

- compose-config-SCENARIOのログは全profile込みの有効設定。架空資格情報はREDACTEDへ置換する。
- run-N-probe.stdout.logは契約結果のJSONとcases。persistence/renewalの初回はrun-N-probe-beforeにも保存する。
- caの公開鍵比較はrun-N-cert-public-key、run-N-key-public-part。秘密鍵は保存しない。
- renewalのskip確認はrun-N-renew-skip、persistenceの再作成はrun-N-recreate。
- ps診断はservice/state/health/exitだけを保存し、ホストパスを含むComposeラベルは出力しない。
- 認証の固定ユーザー名・パスワード・Basic tokenは、標準出力/標準エラーの保存・表示時にマスクする。configの検査にはメモリ内の生データを使う。

fixture-SCENARIO.envは実行用なので固定の架空資格情報が入る場合がある。これは実ユーザーの秘密ではないが、手作業でマスクすると再実行・cleanup用設定が壊れるため、編集しない。将来のCI artifact対象へは追加しない。

## 成功と後片付け

allが成功するとIntegration checks passed (8 isolated run(s), cleanup verified).と表示する。result.jsonのresult=passed、runsが8件、各result/diagnostics/cleanup=passed、remainingがすべて空であることを確認する。caではkeyMatches=trueも確認する。

強制終了時はresult.json内のprojectとfixtureEnvを確認し、該当projectだけを片付ける。RUN_ID/SCENARIO/PROJECTは記録の値に置き換える。

```powershell
docker compose --profile test --env-file dev/test-results/p2-integration/RUN_ID/fixture-SCENARIO.env -p PROJECT -f spec/ci/compose.yaml down --volumes --remove-orphans --timeout 10
```

## 受入項目

- [x] 7種類の契約scenarioと既存localを実装
- [x] 一時CA・中間証明書・公開データだけのtester共有を実装
- [x] 契約assertとreadinessを分離し、全scenarioの設定・Ruby静的構文・PowerShell構文を検査
- [x] ログマスク・testerへの秘密鍵volume拒否と既存のプロセス制御を補助検証
- [x] allの8 scenarioが実Dockerで成功
- [x] 証明書と鍵の公開部分一致、誤CA・誤ホスト名拒否を実確認
- [x] 再作成後の同一証明書・renew skipと不変性を実確認
- [x] 全projectの診断・cleanup・リソース残存なしを確認

全8件の実Docker受入を完了し、P2-05でdocker-smokeを追加済み。GitHub上の受入は[36 Actions接続・受入手順](36-actions-integration-guide-ja.md)で確認する。

## 起動時間の安定化

prepareは全scenarioの専用certificate volumeに、RFC 3526 section 3の公開2048-bit DHパラメータ（MODP group 14、generator=2）を配置する。毎回の安全素数生成で起動待ち180秒を超えるばらつきを避ける。値はソース内に保持し、実行時の取得・外部通信は不要。証明書・CA秘密鍵を固定する変更ではない。製品側のDH生成処理自体は、この結合試験では検証しない。

出典：[RFC 3526 section 3](https://www.rfc-editor.org/rfc/rfc3526.html#section-3)。修正後はca単独、続いてallを実行して受入する。

CA fixtureはdomain.keyとleaf＋intermediateを格納したsigned.crtに加え、Nginxが読むchained.crt → signed.crtの相対リンクもprepareで配置する。既存証明書を使う起動経路では製品によるリンク生成を通らないため、事前に準備する。


更新試験のCompose execでは、s6補助コマンドを解決できるようPATHに/commandを指定してwith-contenvを呼ぶ。with-contenv・dynamic-env経由で製品のrenew_certsを実行し、skipログと前後の証明書不変性を確認する。
