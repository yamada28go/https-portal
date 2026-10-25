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

## Actionsのpush成功確認：既存10件構成（2026-10-24）

利用者提供の[run 40095349214](https://github.com/yamada28go/https-portal/actions/runs/40095349214)をブラウザーで確認した。対象commitは106e1f8e26e9466062df1dd0d8cb88a5832f5e38、push起動、全体Success。lint-and-unitは1m5s、docker-smokeは3m57s。unit/integrationのartifact計2件が生成されている。

ログ閲覧・artifact取得にはサインインが必要であり、中身の全10件・cleanup照合は未実施。この記録は公開の成功表示の確認であり、後述TLS3件の受入ではない。

## 手順5：TLS・証明書異常系の実装（2026-10-24）

状態：実装済み・実Docker受入待ち。

追加：tls-policy/tls-chain/tls-expiredとtls選択、TLSプロトコル固定・SNI省略・検証コード取得、異常証明書fixture、差し替え/reload/正常復元。更新ロックで定期renewとの競合を防ぐ。任意のTLSMutation disable-tls12は使い捨てコンテナ内のみ設定を変更し、TLS1.2正常契約の故意失敗を検証できる。通常all/securityはmutationなし。

- PowerShell 7の構文成功。最初の13構成は実ComposeのValidateOnlyでvalidated/completeを確認。
- 変更Ruby4ファイル（client/prepare/tls_contracts/switch_tls_fixture）はRuby公式Prism 2.0.0で構文エラー0。検証用parserはnpm配布のintegrityを照合し、workへ配置。製品・Gem依存は変更していない。
- 代役DockerでTLS6実行、全13件回帰のホスト制御、baseline/mutated/restoredの各失敗、差し替え/reload失敗、空casesの拒否とcleanupを検証。これらはHTTP/TLSや証明書検証の実証ではない。
- ホストからDocker Engineは引き続きpermission denied。Ruby 2.7/OpenSSLでの実動作、通信遮断下での完走、実際の故意変更検知・復元、今回変更のActions受入は利用者実行待ち。

証跡をdev/test-results/p3-tls-harness/以下へ保存し、代役のpassed JSONを実ITの結果と混同しないよう隔離する。[44 TLS試験の実行手順](44-tls-security-guide-ja.md)にコマンドと判定を記載した。

最終追加確認：更新ロック失敗・正常3件・TLSMutation故意失敗の代役制御3項目も成功。最終版はPowerShell 7/5.1、埋め込みRuby3片も構文成功。証跡：dev/test-results/p3-tls-harness/20261024T130953Z/。構文・代役検証の成功を実TLSの受入とは区別する。


## 最新：手順5のTLS試験が実Dockerで成功（2026-10-24）

利用者実行ID 20261024t131715z-427b2388のresult.jsonを照合した。Scenario=tls、Repeat=2、mode=prepared-images、tlsMutation=none、全体passed/complete。実行時刻は22:17:15〜22:21:50 JST。

| 確認 | 結果 |
|---|---|
| 実行件数 | TLS3件×2回、全6件result/diagnostics/cleanup=passed |
| S-T07 | 両回TLS1.2/1.3成功。TLS1.0/1.1はloopback能力対照で成功し、portalはprotocol version alertで拒否 |
| S-T08 | 両回対象外SNI/SNIなしをunrecognized_nameで拒否 |
| S-T02 | 両回正常200→中間欠落を検証コード20で拒否→復元200。正常時fingerprintが復元後と一致 |
| S-T03 | 両回正常200→期限切れを検証コード10で拒否→復元200。異常leafは別fingerprint、正常復元は元と一致 |
| 残存 | container/network/volumeの合計0 |

証跡：dev/test-results/p2-integration/20261024t131715z-427b2388/。

判定：手順5の通常TLS実通信受入は成功。TLSMutation disable-tls12による故意失敗・mutationなしでの復帰、全13件回帰、今回変更のGitHub Actions成功/成果物照合は未確認。実行JSONのtlsMutation=noneのため、この成功を故意変更検知の証拠とはしない。ホストのインターネット遮断もログ単独では未証明。

## 次の受入作業：故意変更試験を試行（2026-10-25 日本時間）

依頼に基づき、準備済み製品/toolsを指定し、Scenario tls-policy / TLSMutation disable-tls12を実際に呼び出した。

- 実行ID：20261025t022637z-dfcef44a。
- 結果：failed、stage=engine。Docker API named pipeへのpermission deniedによりdocker-versionで停止。
- 証跡：dev/test-results/p2-integration/20261025t022637z-dfcef44a/のresult.json、docker-version.stderr.log、Compose設定ログ。
- mutation設定を受け取ったことは記録されているが、mutationAppliedに至っていない。コンテナ起動・設定変更・TLS検証は未実施であり、故意変更検知の成功ではない。
- build/pullを行う経路へ切り替えていない。正常復帰・全13件回帰は、故意変更検知の受入後に実施する。

利用者の通常PowerShellで[44 TLS手順](44-tls-security-guide-ja.md)の故意変更コマンドを実行し、result.jsonとrun-*-tls-checkの失敗理由を照合する。期待はTLS1.2の正常接続検証でprotocol version alertを受けること。設定書換え・reload・Engineの失敗を検知成功と混同しない。

## 故意変更の起動待ち不足を修正（2026-10-25）

利用者実行ID 20261025t022726z-882f35c6はrun-1-mutation-tls12でexit 1。stderrはTLS mutation anchor missing。製品ログはcont-initの20-setup途中、HTTP設定の診断も未生成で失敗していた。故意変更が起動完了より先に生成設定を読んでいたため、期待するTLS1.2検証失敗には到達していない。cleanup=passed、残存なし、diagnostics=partial。この失敗は検知成功としない。

修正：TLSMutationを適用する前に通常tls-policyの全項目を成功させ、その結果をtlsBeforeMutation・別prefixのログへ保存する。続けて製品の更新ロックを保持し、設定書換え→nginx -t→reload→変更後のTLS契約へ進む。変更前試験が失敗すれば書換えない。

変更先はホストのdev/check_p2_integration.ps1。製品コード・tools内Rubyは変更せず、イメージ再build不要。同じ故意変更コマンドで再実行する。実Docker受入は再実行待ち。

修正検証：PowerShell 7/5.1構文成功。代役プロセスで『変更前の成功→書換え→変更後の失敗』と『変更前失敗なら書換えない』の2件を確認し、cleanup成功・変更前ログの別保存も照合。証跡：dev/test-results/p3-tls-harness/startup-fix-20261025T024341Z/。これは制御順序の検証であり、実TLS検知成功は未確認。


## 最新：TLS故意変更の検知成功（2026-10-25）

利用者実行ID 20261025t024506z-8f12e242のresult.json・run-1-tls-check.stdout.logを照合した。

- 変更前：tlsBeforeMutation.result=passed、S-T07/S-T08成功。
- 適用：mutationApplied=disable-tls12。nginx設定の変更とreload後に検証へ到達。
- 期待失敗：verified HTTPS 200の後、TLS1.2固定接続でIntegrationClient::TLSFailure / tlsv1 alert protocol version。run-1-tls-checkがexit 1。
- 後片付け：diagnostics/cleanup=passed、container/network/volume残存なし。

判定：TLS1.2無効化による退行を試験が検知した。実行自体のresult=failedは正しい負の証跡として維持する。過去のEngine拒否・anchor missing・引数貼り付け誤りとは区別する。

残作業：TLSMutationなしの正常復帰を確認し、全13シナリオの回帰試験、今回変更のActions成功とartifact内容を照合する。

## 最新：全13件回帰とTLS正常復帰の受入成功（2026-10-25）

利用者実行ID 20261025t024745z-c4d9ac62のresult.jsonを照合した。

- 実行時刻：11:47:45〜12:04:10 JST。
- 全体：passed/complete、Scenario all、Repeat 2、mode=prepared-images、tlsMutation=none。
- auth/ca/ip/ip-auth/local/persistence/proxy/redirect/renewal/static/tls-chain/tls-expired/tls-policyの13件が各2回、計26件成功。
- 全件result/diagnostics/cleanup=passed。不成功・診断partialは0件。残存container/network/volume合計0。
- tls-policyは両回S-T07/S-T08成功。直前の故意変更検知後、mutationなしの新規projectで通常契約へ正常復帰したことを確認。

判定：手順5のローカル通常試験・故意変更検知・正常復帰・全体回帰の受入は成功。証跡はdev/test-results/p2-integration/20261025t024745z-c4d9ac62/。今回のTLS変更を含むGitHub Actions成功とartifactの全13件/cleanup照合は引き続き未確認。

## 最新：TLS変更のGitHub Actions push実行成功（2026-10-25）

利用者提供の[run 40163898918](https://github.com/yamada28go/https-portal/actions/runs/40163898918)をブラウザーで照合した。

- commit：2fe7819953fa05c9a727a85ffa95aa9b387ef115（test: add TLS and certificate regression checks）。
- 起動：push、2026-10-25 13:59 JST、Tests #4。全体Status Success、所要4m55s。
- lint-and-unit：成功、1m2s。
- docker-smoke：成功、4m53s。
- artifact：integration-test-evidence-40163898918-1（176KB）、unit-test-evidence-40163898918-1（16.6KB）の2件が生成されている。

判定：今回のTLS変更を含むpush実行の両ジョブ成功を確認した。artifactのダウンロードとログ詳細はサインインが必要であり、内部の全13件・cleanupは未照合。公開の成功表示、ローカル26件成功、artifact内容確認を区別する。PR/手動実行、連続5回、必須チェック・マージ阻止は別途追跡を継続する。

## 手順6初期：脆弱性レポート・SBOM収集基盤（2026-10-25）

状態：report-onlyの実装済み・製品イメージの初回受入待ち。重大度によるブロック、期限付き例外、必須チェック設定はまだ導入していない。

追加：dev/prepare_p3_security.ps1、dev/check_p3_security.ps1、dev/securityの固定設定・共通関数・契約試験/fixture、独立の.github/workflows/security.yml。Trivy 0.76.1と公式manifest SHA-256を固定した。準備はpull/DB取得、検査は準備済み資材とnetwork noneでarchiveを検査し、同じJSONからSBOMへ変換する。

| 確認 | 結果 |
|---|---|
| 固定版 | 公式release、Docker Hub manifestのcontent SHA-256、実CLI archiveの公式checksumを照合。Trivy依存DBのschema 2も固定版ソースで確認 |
| 構文・workflow | PowerShell 7/5.1の構文成功、actionlint 1.7.12成功。Windows PowerShell 5.1での実行検証はこのホストのexecution policy制約で未実施 |
| データ契約 | PS7で17件成功。Critical/Highはreport-only、空/不正・ID違い・古い/変更DBを拒否し、ImageConfigを除去 |
| Docker代役 | 正常、image不足、古いDB、scan失敗、image ID違い、壊れたJSON/SBOM、DB途中変更、cleanup失敗、DB download失敗の10件成功。実検査とは区別 |
| 実CLI smoke | 合成Docker archive（製品ではない）を実Trivy＋実DBで検査。package 2件、Critical 1/High 9/Medium 14/Low 25を収集し、非公開設定文字列を除去、SBOM変換とImageID対応を確認。重大検出でも収集が成功する仕様を実証 |
| 製品実行 | Docker Engineのnamed pipeがpermission deniedで準備のengine段階に停止。20261025t053446z-9e6f05ee。scanner pull/製品検査には未到達 |
| 未受入 | 製品イメージの実レポート/SBOM、今回のsecurity-report Actions、artifact内容・部品網羅性。P3全体の完了とはしない |

実CLI smokeはネットワーク遮断を施したホストでの検査ではない。ソフトウェアのoffline flagsを指定した互換性検証であり、Docker network noneの実証は利用者の製品検査で確認する。製品・既存試験・Tests workflowは変更していない。

[45 収集の準備・実行手順](45-security-collection-guide-ja.md)を参照。補助台帳は外部部品のENV宣言版だけであり、取得物hash・CVE網羅性を未確立として残す。秘密情報/開発Gemの検査、CodeQL、供給元検証、依存修正は別工程。

手順6初期の最終証跡：dev/test-results/p3-security-harness/20261025T053931Z/。合成イメージの実CLI検証と代役結果を製品結果から隔離し、入力hashを記録。最終PowerShell 7/5.1構文・actionlintも成功。DB本体やimage archiveはQA成果物へ複製していない。


## Java DB準備漏れの修正（2026-10-25）

利用者実行20261025t054616z-737c68daはvulnerability-scanで失敗。Java解析がJava DBを要求した一方、準備処理は脆弱性DBだけを取得していた。--skip-java-db-updateは初回DB取得の代わりにならない。result.jsonでcleanup=passedを確認した。

修正：準備段階で--download-java-db-onlyも実行し、java-db/trivy-java.dbとmetadata.jsonのhash/metadataをreceiptへ保存。Java DBはschema 1・UpdatedAtの既定最大168時間で検証する。オフライン検査では両DBを専用work volumeへコピーし、検査前後に両DBのhashを照合する。Java DBのない旧receiptはimage export前に再準備を要求する。network none・更新禁止・report-onlyを維持。製品再buildは不要。

検証：PowerShell 7/5.1構文成功、PS7データ契約23件、Docker代役15件成功（Java DB不足/古さ/途中変更、旧receipt、Java DB取得失敗を追加）。実Trivy 0.76.1で実Java DBを取得し、Java JARを加えた合成イメージをoffline flagsで検査。commons-lang3を検出し、秘匿設定除去・SBOM生成・ImageID対応を確認した。Java DB本体は約1.2GBで、脆弱性DBと合わせた検査用コピー容量も必要。native smokeは物理通信遮断や製品検査の受入ではない。

製品の再受入は修正後のprepare→checkの利用者実行待ち。GitHub Actionsも同じprepare/checkを使用するため修正が適用される。
証跡：dev/test-results/p3-security-harness/java-db-fix-20261025T060051Z/。

## Docker側IDとTrivy config IDの照合修正（2026-10-25）

利用者実行20261025t061444z-dc00d81c：両DBの事前検証、image export、Trivyスキャンは成功。Debian 13.7の235 OS packageとGo binaryの解析後、レポートのschema/type/IDをまとめて判定する箇所で失敗した。cleanup=passed。生レポートは規定どおり削除されており、過去のreport ImageID自体は確認できないため、失敗理由を完全確定したとは扱わない。

調査：Docker側IdがRepoDigestと同じ値であり、固定scannerでもmanifest digestと同じ値だった。Docker側がmanifest/index digestを返す環境で、Trivyのconfig digestを直接比較している実装上の問題を確認した（今回の直接原因としては推定）。schema/type/IDの失敗メッセージも分離した。

修正：指定IDのdocker image save直後、固定scannerのnetwork noneコンテナでarchive manifest.jsonとconfig内容のSHA-256を検証する。manifestは1件、configは64桁.jsonまたはblobs/sha256/64桁に限定し、内容hashとパス中digestの一致を要求する。config本文をログへ保存しない。JSONとSBOMはこの独立計算済みconfig digestへ照合し、結果が供給したIDを無条件採用しない。result/summaryにはDocker imageIdとscanImageId、archiveIdentityを併記し、形式が正しいreportImageIdも診断として記録する。検査・cleanup・report-onlyの仕様は維持。

検証：データ契約31件、Docker代役17件成功。Docker IDとconfig IDが異なる正常系を受け入れ、wrong report ID、archive hash不一致、複数manifest、不正パス等は拒否する。実ファイルをnative tarで読み、従来形式/OCI config path形式の両archiveで独立計算したconfig digestと、前段の実Trivy合成イメージレポート/SBOMのID一致を確認した。このnative adapter検証をDocker隔離や製品の実受入とは扱わない。

再受入：成功済み準備20261025t060213z-c6489bf3のreceiptを再利用し、checkだけ再実行する。製品のbuild・scanner/DBの再取得は不要（鮮度・hash検査は引き続き実施）。今回の製品受入は利用者再実行待ち。

一次資料：Trivy v0.76.1のimage artifact実装 https://github.com/aquasecurity/trivy/blob/v0.76.1/pkg/fanal/artifact/image/image.go およびDocker containerd image store https://docs.docker.com/engine/storage/containerd/ 。
証跡：dev/test-results/p3-security-harness/image-identity-fix-20261025T064228Z/。

## 準備receiptの相対パス解決修正（2026-10-25）

利用者実行20261025t070804z-55ec01f1はpreflightでCannot read JSON: prepared.json。対象の成功済みreceiptは存在し、PowerShellのGet-Content/ConvertFrom-Jsonで正常に解析できた。.NETのCurrentDirectoryとPowerShellの現在位置を異ならせることで、従来のReadAllTextに相対パスを直接渡す実装の失敗を再現した。

Read-SecurityJsonはSessionState.Path.GetUnresolvedProviderPathFromPSPathでPowerShellの現在位置から絶対パスへ解決してからReadAllTextするよう修正。JSON解析エラーを秘匿する既存仕様は維持。データ契約32件が成功し、現在位置とprocess directoryが異なる場合の相対/絶対パスの同値性、および実prepared.jsonの相対パス読み込み成功（prepared、両DBあり）を確認した。Docker検査は今回開始前の失敗であり、再build/DB再取得は不要。製品スキャンの再受入は引き続き利用者実行待ち。

## 製品イメージの初回収集受入成功（2026-10-25）

利用者実行20261025t071211z-49f60b78の成果物を照合した。実行時刻16:12:11〜16:17:34 JST、result=collected、stage=complete、mode=offline-report-only、cleanup=passed、thresholdEnabled=false。手順6初期のローカル収集は成功。脆弱性の解消・重大度ゲート・P3全体の完了を意味しない。

- 選択したDocker ID：sha256:50799eef7566b2502e16e154f4829b8ef0997b86f922cf073f8bdf426b9df400。
- archive SHA-256：306cec9eec2a8e5ed8858818874d30888176f5953867f291b336fd67a53ba7b2。
- archive config digest / scanImageId / reportImageId：sha256:b4161ae46c5e75dee0fa5e373fa6dff4510b4984330aaca3a93d39337e6c3bc4。SBOMのImageIDも一致。Docker側とconfig側のIDが異なる実ケースを受入できた。
- Trivy 0.76.1。準備20261025t060213z-c6489bf3の脆弱性DB/Java DBとreceiptのhash一致を確認。検査前後のmetadata/hashログも正常。検査は既存コードのnetwork none実行で成功した。ホスト全体の通信遮断を示すものではない。
- OS：Debian 13.7。package entry 272（OS 241 / Go 31）、CycloneDX component 274。TrivyログのOS pkg_num=235と、収集JSONのpackage entry数は集計段階が異なるため同数とみなさない。
- vulnerabilities.json / sbom.cdx.json / summary.json / external-components.jsonのSHA-256がartifacts.sha256と全件一致。ImageConfigは除去済み。archive/raw reportは削除済み、work-cleanupログは正常。

| 重大度 | 検出件数 |
|---|---:|
| Critical | 12 |
| High | 135 |
| Medium | 198 |
| Low | 237 |
| Unknown | 18 |
| 合計 | 600 |

検出件数はパッケージ等ごとのレコード数であり、CVEの重複を含む。VulnerabilityIDの異なり数は315。OS側532件（Critical 11 / High 99）、Go側68件（Critical 1 / High 36）。これは収集データの集計であり、到達可能性や修正要否の判定はまだしていない。

Criticalの初期内訳：Ruby関連が10レコード（libruby3.3/ruby3.3の各5、IDは重複）、libxml2が1、Go stdlibが1。Ruby/libxml2はこのレポートのFixedVersion欄が空であり「将来も修正不可」とは解釈しない。Go stdlib v1.25.5はレポートに修正版の記載あり。次工程で一次資料、導入経路、実際の利用箇所・到達可能性、修正方法を確認し、依存更新と期限付き例外を個別判断する。

補助台帳：s6-overlay v3.2.3.0、docker-gen 0.16.3、acme-tiny 5.0.3のENV宣言版を取得。実物hashや自動SBOM/CVE網羅性は引き続き未確立であり、初回収集成功だけで台帳完備としない。

証跡：dev/test-results/p3-security/20261025t071211z-49f60b78/。
次は今回変更のcommit/push後にsecurity-report Actionsの成功とartifact内容を照合する。並行してCritical/Highの一次分類を行う。重大度ゲートや広範な例外除外を先に有効化しない。
