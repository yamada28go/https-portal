# Docker試験基盤の実行・確認（P2-03）

用途：単独・繰り返し実行、起動待ちの期限、診断保存、試験専用リソースの後片付けを確認する。

[文書一覧](../00-index-ja.md) / [検証記録](32-verification-ja.md) / [詳細計画](31-implementation-plan-ja.md)

## 現在の状態

P2-03は完了。利用者の保存ログで、独立2回のHTTPS/echo疎通と診断・cleanup成功、never-readyの10秒期限切れ・非0・診断保存・cleanup成功、全リソース残存なしを確認した。失敗時は設定/証明書の未生成による診断partialも記録済み。詳細は検証記録を参照する。

ホストに必要なのはPowerShellとDocker CLI。Git/Ruby/Gemの追加導入やdev.ps1の起動は不要。GitHubへのpush・CIジョブ追加は今回行わない。

## 実行する順序

Docker DesktopをLinux containersで起動し、プロジェクトルートのPowerShellで実行する。

```powershell
# 1. 設定だけ確認（Engine・build・起動・削除を使わない）
.\dev\check_p2_integration.ps1 -ValidateOnly

# 2. 通常起動から後片付けまで、独立した2回の実行を確認
.\dev\check_p2_integration.ps1 -Repeat 2

# 3. 起動待ち失敗時も期限内に停止し、診断・後片付けされることを確認
# このコマンドは意図的に非0終了する
.\dev\check_p2_integration.ps1 -Scenario never-ready -StartupTimeoutSeconds 10
```

通常はlocalの1回だけを指定なしで実行できる。キャッシュなしのbuildには-NoCacheを追加する。各コマンドは今回専用のイメージtag/projectを生成し、他の実行と共有しない。-Repeatは同じイメージを使うが、network・証明書volume・コンテナは回ごとに新規作成する。

never-readyは通信先を外部へ変えず、期待するwelcome本文だけを意図的に一致しない値にする。期限切れで失敗することを確認するための専用モードであり、失敗を成功へ読み替えない。

## 成功の確認

通常実行でP2-03 integration foundation passedと表示され、result.jsonのresult=passed、各runs要素のresult/diagnostics/cleanup=passedになること。後片付け後のremainingのcontainer/network/volumeはすべて空になること。

never-readyではresult=failedで、probeログにReadiness timed out、cleanup=passedとremainingが空であることを確認する。失敗を検知しながら後片付けできたことが、このモードの受入条件。

## 通信・データの境界

| 対象 | 構成 |
|---|---|
| build | 製品の既存Dockerfileと、固定Rubyのツール用Dockerfileを事前にbuild。イメージ・パッケージ・ツール取得には外部通信が発生 |
| runtime | Composeのinternal network。portal、echo、testerはこのnetworkだけに接続し、実際にInternal=trueも確認 |
| 名前解決 | 内部aliasのportal.testとサービス名echoだけを使用。公開DNS登録やホストのhosts編集なし |
| 証明書 | STAGE=local、DOMAINS=portal.test、FORCE_RENEW=false。公開ACMEへ発行要求を送らない |
| 公開ポート | ホストへのports公開なし |
| ソケット・共有 | Docker socket・ホストbind mount・外部volumeなし。testerには証明書volumeや秘密鍵も渡さない |
| portal | 製品本来のroot/s6起動と書込領域を使用。privilegedは使わない |
| echo/tester | UID1000、read-only rootfs、cap-drop ALL、no-new-privileges、tmpfs |
| 保存領域 | 今回のCompose project専用の証明書・Nginxログvolume。固定グローバルnameなし |
| 後片付け | 今回確保したprojectだけdown --volumes --remove-orphans。ラベルでcontainer/network/volume残存を確認。pruneや他projectの削除なし |

internal networkに既定ルートがなくても製品の初期化が進むよう、dockerhostは試験コンテナ自身の127.0.0.1へ向ける。ホストへの経路を追加する設定ではない。

ユーザーの.envを読み込ませず、今回生成したfixture-SCENARIO.envと明示値を使う。実行開始前に、外部network/volume・ports・bind mount・非local stage等の不適切な設定を拒否する。取得はbuild工程だけで、Compose runtimeのpull_policyはnever。

## 起動判定の範囲

Nginxのプロセスだけではreadyにしない。portal.testのSAN/ホスト名、有効期間、自己署名の一致を確認し、自己署名leafをpinしたHTTPSで200とwelcome本文を確認する。echoにも内部HTTPで到達することを確認する。

local証明書を最初に取得するbootstrap通信だけはVERIFY_NONEを使い、その後のHTTP取得はVERIFY_PEERとホスト名検証を有効にする。これは試験専用networkでの起動判定であり、独立CAでの信頼・誤CA拒否を検証したことにはしない。独立CA・認証・proxyなどのP2-04追加試験は[35 結合試験の内容と実行手順](35-integration-contracts-ja.md)を参照する。

## 時間上限

| 操作 | 上限 |
|---|---|
| Compose設定 | 30秒 |
| Engine等の通常コマンド | 原則60秒 |
| 製品build / tools build | 1200秒 / 600秒 |
| Compose up | 90秒 |
| ready待ち | 既定180秒、1回の試行は最大10秒、単調時計で締切管理 |
| probe用CLI | ready待ち上限＋30秒 |
| 各診断収集 | 20秒 |
| down | 60秒（サービス停止猶予10秒） |
| 残存確認 | リソース種類ごと20秒 |

CLI停止・出力pipe回収には追加で数秒の猶予を設け、ここも有限にする。長い操作では約30秒ごとに待機表示を出す。初回DH生成などでready期限に達したら診断を確認し、根拠なく再試行だけで成功扱いにしない。

## 保存する証跡

保存先：dev/test-results/p2-integration/<実行ID>/（Git対象外）。

- result.json：全体と各projectの成否、cleanup、残存リソース、診断収集の状態、イメージID。
- fixture-SCENARIO.env：今回の固定image tag、timeoutと試験設定。authでは固定の架空資格情報も含むため、CI artifactには含めない。手動cleanupでも使用する。
- compose-config-SCENARIO.stdout.log：tester profileも含めた有効設定。
- build-portal/toolsのstdout/stderr、Docker/Composeのバージョン。
- run-N-probeのstdout/stderr：起動判定のJSON、失敗時の期限と最終エラー。
- run-N-diagnostic-*：ps、固定構成のサービスログ末尾300行、対象ドメインのHTTP/HTTPS設定、公開証明書のメタデータ。
- run-N-cleanupとrun-N-after-*：削除結果・残存確認。

秘密鍵・account.key・htpasswd・volume全体・docker inspect全量は収集しない。現在は認証情報を持たない固定fixtureのみ。将来認証scenarioを追加するときはログのマスクも設計する。

## 中断・残存時の対応

通常の試験失敗はfinallyで診断→down→残存確認を行う。既存リソースが見つかったprojectは再使用せず、削除もしない。cleanup失敗は全体失敗にする。

PowerShellの強制終了・端末終了・Docker停止などではfinallyが完了しないことがある。result.jsonに保存された今回のprojectとfixture-SCENARIO.envを確認して、該当projectだけ片付ける。次のPROJECT・RUN_IDは実際の記録に置き換える。

```powershell
docker compose --profile test --env-file dev/test-results/p2-integration/RUN_ID/fixture-SCENARIO.env -p PROJECT -f spec/ci/compose.yaml down --volumes --remove-orphans --timeout 10
```

ビルドしたイメージとbuild cache、ホストの結果ログは残す。全体pruneや開発環境のvolume削除は行わない。

## P2-03の完了条件

- [x] 分離したCompose構成、固定local domain、衝突しないproject名を実装
- [x] ホストGit/Ruby不要の共通PowerShell入口を実装
- [x] 起動期限・プロセス期限・失敗伝播・診断・限定cleanup・残存確認を実装
- [x] Compose展開、PowerShell構文、Ruby静的構文、プロセス制御と安全設定の補助検証に成功
- [x] 製品・toolsを実際にbuildし、portalの起動・自己署名を確認
- [x] 修正後のprobeでHTTPS本文・echoを含む起動判定が成功
- [x] -Repeat 2で別project・新規volumeの連続成功
- [x] never-readyで期限切れ・非0・診断保存・cleanup成功を確認（未生成ファイルによる診断partialは記録）
- [x] 通常・失敗の両方でcontainer/network/volume残存なしを確認

## 根拠

- [Compose networkのinternal](https://docs.docker.com/reference/compose-file/networks/#internal)
- [Compose services](https://docs.docker.com/reference/compose-file/services/)
- [Compose downの削除対象とvolumes](https://docs.docker.com/reference/cli/docker/compose/down/)

## Windowsの改行

fs_overlayのLinux用ファイルはroot .gitattributesでLFを指定する。archnameやs6起動ファイルがCRLFだとLinuxの構文エラーになる。今回の作業ツリーはLFへ正規化済み。wget exit8の前にnot found・expecting in等があれば、配布先の変更を推測する前に改行を確認する。

## probeの互換性

Ruby 2.7.2ではNet::HTTPのverify_hostname=を使わず、VERIFY_PEER時の標準ホスト名照合を利用する。接続・起動中の一時エラーだけ再試行し、未対応API等のプログラムエラーはprobe_error・exit 2で即時失敗にする。

## P2-04による拡張

現在はprepareが試験用CA・静的ファイルをproject専用volumeへ準備する。testerに共有するのは公開証明書・試験前後の比較データ用public volumeだけで、証明書秘密鍵のvolumeは共有しない。result.jsonのfixtureEnvは各scenarioの設定ファイル名を記録する。追加契約と受入状況は[35 結合試験の内容と実行手順](35-integration-contracts-ja.md)を参照。
