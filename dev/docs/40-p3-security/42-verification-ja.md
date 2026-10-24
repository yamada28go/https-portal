# P3 検証記録

[文書一覧](../00-index-ja.md) / [P3作業計画](40-implementation-plan-ja.md)

## P3-00 開始状態の調査（2026-10-24 日本時間）

状態：開始状態は利用者の目視確認により受入OK（2026-10-24）。手順1は完了。P3実装はまだ開始していない。以下の未確認記載は、エージェントによる調査時点の制約・履歴を示す。

### 現在の基準

| 項目 | 結果 |
|---|---|
| HEAD | `0dba7511925a43bc3f9891ee52a0d688a94e89b7` |
| 最新コミット | ci: add Docker integration tests to GitHub Actions |
| 直前の変更 | `33c9339` Docker結合試験、`4f465a5` Docker試験基盤 |
| 未コミット差分 | 未確定。通常statusと明示git-dir/work-treeのstatusがwork treeエラー。空出力をcleanとは判定しない |
| 作業中の文書 | P3計画・文書一覧をこのチャットの前段で作成/編集済み。今回この検証記録・一覧を更新。Gitの変更一覧とは区別する |
| Docker接続 | Docker Desktop Linux Engineのnamed pipeへのpermission denied。build/UT/ITは今回は未実行 |
| 現在入力 | 追跡対象ファイルの現物SHA-256を証跡へ保存。raw bytesの記録であり、Git index/HEADとの一致やcleanの証明ではない |

Gitの設定、index、製品コード、既存試験、workflow、依存版は変更していない。commit/push・Actions起動・ブランチ保護変更も実施していない。

### 既存試験の保存結果

| 種別 | 確認した証跡 | 結果・留保 |
|---|---|---|
| UT基準 | `dev/test-results/p2-baseline/20261024T052651Z-033960e1/` のhost-run.json・baseline.json・p1-check.log | JSONはpassed/complete。ログ末尾に113 examples, 0 failuresとAll P1 automated checks passedを確認 |
| UTの入力 | baseline.jsonのHEADは `d92f9e187586b95c03e5349be54b1168a8b6e458` | 現HEADと異なり、当時のgitStatusにも変更あり。現在のHEADそのものの成功証跡にはできない |
| UT詳細 | P2検証記録に3 seed・9ファイル単独・M01〜M08・復元後成功の記録 | 既存の受入記録として引き継ぐ。今回の再実行ではない |
| Docker全体 | `dev/test-results/p2-integration/20261024t105928z-3865e7dc/result.json` | result=passed、stage=complete、8件成功 |
| Docker各件 | local/redirect/proxy/auth/ca/persistence/renewal/static | 全件result/diagnostics/cleanup=passed、残存container/network/volume合計0、caのkeyMatches=true |
| Dockerの入力 | JSONにimage情報はあるがGitHub event/SHA等の実行記録なし | 現HEADとの厳密な同一性は未証明。現在の入力で再検証が必要 |

過去の失敗ログは履歴として維持する。成功・失敗を実行IDごとに区別する。保存結果を現在入力の成功と読み替えない。

### P2のGitHub受入

`.github/workflows/tests.yml`にlint-and-unitとdocker-smoke、およびpush/pull_request/workflow_dispatch、成果物uploadの実装があることを確認した。

GitHub接続ツールとgh CLIは利用できず、公開Web経由のActions画面/API取得も失敗した。取得失敗から非公開・不存在・未実行を推測しない。remote-tracking refだけでもGitHub受入を証明しない。

| 受入項目 | 状態 |
|---|---|
| workflowのローカル実装 | 確認済み |
| push時の両ジョブ成功 | 過去の一覧にUT側push成功の記述あり。ただし今回の両ジョブのrun URL/SHAは未確認 |
| PR自動実行・手動実行 | 未確認 |
| 同じ基準で5回連続成功 | 未確認 |
| artifactの内容・cleanup | ローカル結果は成功。GitHub実行の成果物は未確認 |
| 故意変更によるCI失敗・復元成功 | 未確認 |
| 必須チェック設定・マージ阻止 | 未確認 |

参照：[P2検証記録](../30-p2-ci/32-verification-ja.md)、[Actions受入手順](../30-p2-ci/36-actions-integration-guide-ja.md)。文書上の未確認状態を維持し、実際の未実行とは断定しない。

### 確定に必要な次の確認

1. 通常のPowerShellでプロジェクトルートを開き、以下のGitコマンドでHEAD・差分を取得する。結果はこの記録へ反映する。差分を消す操作は不要。
2. Dockerへ接続できる環境で現在入力のUT/IT結果を採取する。ただし既存入口はbuildを含み外部通信が起き得るため、通信禁止の実行には次工程の準備/実行分離を先に適用する。
3. GitHubで対象SHAのpush/PR/手動run URL、両ジョブ結果、artifact、必須チェックを確認する。5回成功・故意失敗の残項目をP2受入として追跡する。

```powershell
git rev-parse HEAD
git status --short --untracked-files=all
git diff --stat
git diff --cached --stat
docker version
```

調査時点ではエージェントが確定できたものはHEADと保存済み試験の結果。下記の利用者による目視確認をもって開始状態を受け入れ、次工程へ進める。
### 今回の調査証跡

保存先：dev/test-results/p3-start/20261024T113812Z/。start-state.jsonに調査結果・元証跡ハッシュ、tracked-inputs.sha256に追跡対象132ファイルの現物ハッシュを記録。Git対象外のローカル証跡として扱う。


## 利用者の目視確認による受入（2026-10-24）

利用者から「開始時の状態を確定する（HEAD・未コミット差分、既存試験の結果、P2のGitHub受入状況を記録）」を目視確認し、OKとする旨の指示を受領した。これをもって手順1を完了とする。

- 確認方法：利用者による目視確認。
- 判定：開始状態の受入OK。次は手順2の準備済みイメージで実行できる入口の追加。
- エージェントによるGit差分取得・試験再実行・GitHub受入の自動検証は追加していない。具体的なrun URLや5回連続成功等の証跡が新規取得されたことを意味しない。
- この受入の反映では製品コード・試験・workflow・GitHub設定を変更していない。
## 手順2：準備済みイメージの実行入口（2026-10-24）

実装済み。dev/check_p2_baseline.ps1にUsePreparedImages/UnitImage、dev/check_p2_integration.ps1にUsePreparedImages/PortalImage/TestImageを追加した。

- 準備済みモードはbuild/pullを呼ばず、指定されたローカルLinuxイメージを確認する。存在しない・ID不正・非Linuxなら起動前に失敗する。
- 使用ID/platformとモード・指定参照を記録し、実行はイメージIDへ固定する。docker/Compose run・upはpull neverを明示する。inspectの記録対象はID/OS/architectureに限定し、image環境変数等を記録しない。
- NoCache併用・必要引数不足・モードなしの参照指定・env展開につながる不正入力を拒否する。
- UTのnetwork none、ITのinternal network、診断/cleanupと失敗伝播を維持する。

検証：PowerShell 7およびWindows PowerShell 5.1の構文確認、実Composeのall/ValidateOnly（8構成）成功。Docker代役プロセスによる18項目（両入口の正常・不足・不正ID・非Linux・試験非0、引数異常）と、従来build経路2項目が成功した。代役による結果は実UT/IT成功とは扱わず、p3-entrypoint-checksへ隔離した。

実Dockerの通信遮断下での受入は手順3で別途確認する。製品・toolsイメージと現在ソースの完全一致は今回の機能の保証対象外であり、準備時の入力記録と照合する。

[実行手順](41-execution-guide-ja.md)を参照。

手順2の制御フロー検証証跡：dev/test-results/p3-entrypoint-checks/20261024T115639Z/。代役実行ディレクトリ16件を移動し、実試験の保存結果と分離した。


## 手順3：既存試験のオフライン実行を試行（2026-10-24）

状態：実行を試みたが、Docker Engine接続拒否で停止。受入未完了。実UT/ITの成功として扱わない。

過去の実成功ログのimage IDを指定し、両入口をUsePreparedImagesで起動した。UTは1回、ITはScenario all/Repeat 2を要求した。イメージIDはローカルにまだ存在することや現在ソースとの一致が未確認のため、接続回復後のpreflight・準備時入力との照合が必要。

| 対象 | 実行ID | 結果 |
|---|---|---|
| UT | 20261024T115650Z-b837cf76 | host-run.jsonはmode=prepared-images、result=failed、stage=engine |
| Docker IT | 20261024t115650z-6e6df94a | result.jsonはmode=prepared-images、result=failed、stage=engine。全8件のCompose設定確認後、docker-versionで停止 |

原因：Docker Desktop Linux Engineのnamed pipeに対するpermission denied。Docker CLIは利用可能だがEngineへ接続できない。認証情報やGit/Docker設定は変更していない。

イメージinspect、build、pull、コンテナ起動、UT、IT、試験による資源作成へは未到達。新規コンテナのcleanup検証や外部通信遮断下での完走も未検証。試験起動前の失敗のため、過去の成功を今回の結果へ流用しない。

証跡：dev/test-results/p2-baseline/20261024T115650Z-b837cf76/のhost-run.json・console.log、およびdev/test-results/p2-integration/20261024t115650z-6e6df94a/のresult.json・docker-version.stderr.log・Compose設定ログ。

### 接続可能な環境での再実行

Docker DesktopのLinux Engineへ接続できる通常のPowerShellで実行する。過去の成功記録から得たIDを使用するため、資材の存在・対象ソースとの対応を確認する。不足時にこの実行が自動build/pullすることはない。

```powershell
.\dev\check_p2_baseline.ps1 -UsePreparedImages -UnitImage sha256:e3de411070f5dff3a1a2d3f339c960c2346e3d2bd699fad6023d7dfe4b62fbc0
.\dev\check_p2_integration.ps1 -UsePreparedImages -PortalImage sha256:50799eef7566b2502e16e154f4829b8ef0997b86f922cf073f8bdf426b9df400 -TestImage sha256:e43fe080bb90d826b3cfba7ec693c104504ba5b8c221d1f9f67e5bd544f6d131 -Scenario all -Repeat 2
```

実行時には外部通信を遮断・観測できる環境を用い、UT成功、IT16実行（8件×2回）、全件診断/cleanup、残存なし、build/pullなしを確認する。Docker APIやDocker内部の通信を一律遮断して試験自体を壊さないよう、インターネット宛て通信と内部通信を区別する。イメージが不足・不一致の場合は、試験側の遮断を緩めず別の準備工程で資材を整える。

## 最新：手順3の利用者実行で実試験成功（2026-10-24）

利用者の実行報告を受け、保存済みJSONとログを確認した。準備済みイメージを使用した既存UT/ITの実行受入は成功。前節のEngine接続失敗は過去の履歴として保持する。

| 項目 | 確認結果 |
|---|---|
| UT実行ID | 20261024T120349Z-f38f72ad |
| UT時刻 | 21:03:49〜21:04:26 JST |
| UT | host-run.jsonとbaseline.jsonがpassed/complete、mode=prepared-images。HEADは0dba7511925a43bc3f9891ee52a0d688a94e89b7 |
| UT証跡 | p1-check.log末尾の113 examples, 0 failures、All P1 automated checks passed、Mutationの検知・復元を確認 |
| IT実行ID | 20261024t121106z-b38f5730 |
| IT時刻 | 21:11:06〜21:19:51 JST |
| IT全体 | passed/complete、mode=prepared-images、Repeat=2。8件×2回の全16件passed |
| 診断・後片付け | 全16件diagnostics/cleanup=passed、残存container/network/volume合計0 |
| CA | 両回keyMatches=true |
| 隔離 | internal network確認ログがtrue。STAGE=local・固定内部ドメインを検査する入口で成功 |
| build/pull | 準備済み分岐を使用。ITのbuildログ0件。実装上build分岐を通らず、run/upのpull neverを指定 |
| インターネット遮断 | 実際に接続を切ったこと、ホスト全体の外向き通信ゼロはログだけでは確認できないため未確認 |

証跡：dev/test-results/p2-baseline/20261024T120349Z-f38f72ad/とdev/test-results/p2-integration/20261024t121106z-b38f5730/。

判定：準備済みイメージによる実試験・独立2回・診断/cleanupは受入成功。次の手順4（IP制限試験追加）へ進める。ホストのインターネット遮断下での実施確認は別途残す。GitHub受入や製品/toolsイメージと現在ソースの完全一致を、この結果から新たに保証するものではない。

## 手順4：IP制限の実通信試験を実装（2026-10-24）

状態：実装済み・実Docker受入待ち。製品コード・依存版は変更していない。

追加：ip/ip-auth、security選択、tester-allowedサービス、ip_contracts.rb。許可元を先に起動して動的IPv4を取得し、DOMAINSの単一IP許可へ反映する。拒否元を別コンテナにし、送信元の差・許可200/拒否403・転送ヘッダー3パターンの偽装拒否・Basic併用の200/401/403を検証する。client.rbは対象ホストと任意ヘッダー送信を拡張した。

| 確認 | 結果 |
|---|---|
| PowerShell | 7/Windows PowerShell 5.1の構文成功 |
| Compose | 実CLIでallの10構成をValidateOnly成功。Engine起動なし |
| 隔離ガード | tester-allowedへの秘密鍵volume追加を拒否することを確認 |
| ホスト制御フロー | 代役Dockerでsecurity/Repeat 2の4件、同一送信元の拒否、不正IP拒否、許可元/拒否元の非0伝播、cleanupを確認 |
| 代役の限界 | HTTP/TLS・Nginxの挙動を代役では検証していない。Ruby実行環境はこのホストにないためruby -c/実行検証も未実施。Rubyの追加箇所は静的レビューのみ |
| 実受入 | 利用者による新tools準備・security/Repeat 2・全体再実行と故意変更検知が必要 |

証跡はdev/test-results/p3-ip-harness/以下へ保存。代役生成結果はMOCK-ENTRYPOINT-ONLY.txtを付け、実Docker試験の成功記録と分離した。

[43 IP制限の実行手順](43-ip-access-guide-ja.md)に準備・構文確認・実行・判定を記載。allは計10件に拡張したため、既存P2の8件受入記録と区別する。

## 最新：手順4のIP制限試験が実Dockerで成功（2026-10-24）

利用者の実行報告を受け、dev/test-results/p2-integration/20261024t123747z-c292cf3e/result.jsonを照合した。

- 全体：passed/complete、mode=prepared-images、Scenario security、Repeat 2。22:37:47〜22:40:14 JST。
- ip/ip-authの2件×2回、全4件result/diagnostics/cleanup=passed、container/network/volume残存合計0。
- 許可元172.18.0.2と拒否元172.18.0.5の区別を実証。両回とも許可200、拒否403、spoof-1/2/3は403。
- Basic併用も両回とも正認証200、未認証/誤認証401、非許可元＋正認証403。
- IP制限シナリオの通常実通信受入は成功。全10シナリオの回帰実行、deny/authを故意に壊した検知、GitHub Actions上の今回変更の成功は別途未確認。JSONにGitHub run情報はないため、この結果をActions成功とは扱わない。

次は全体の回帰確認・故意変更の検知証跡を補い、手順5のTLS/証明書異常系へ進める。
