# HTTPS-PORTAL P2実施計画：GitHub Actionsへの移管

用途：P2の分析・設計・試験仕様・完了条件。P2-01は検証成功・完了。P2-02のCI移管は未着手。
[文書一覧](../00-index-ja.md) / [実施手順](30-execution-guide-ja.md)

- 作成日：2026-10-24（日本時間）
- 対象：`https-portal` のプロジェクトルート（ローカル絶対パスは省略）
- 基準：[バージョン更新ロードマップ](../10-roadmap/10-upgrade-roadmap-ja.md) のP2
- 調査時HEAD：公開版では省略。実装開始時に作業環境で確認・記録する。
- 調査時ブランチ：P1のテスト追加用ブランチ（個人識別子を含む名称は省略）
- 状態：P2-01の最小環境で実ビルド・全検証に成功。P2-01完了、P2-02未着手。GitHubへのpush・設定変更は未実施。[検証記録](32-verification-ja.md)を参照。

## 1. 結論と対象範囲

**P1の113例を先にCIへ移し、独立したDocker試験を追加する。旧機能テストをそのままActionsで起動する方式は採らない。**

P2の成果は、PRで `lint-and-unit` と `docker-smoke` が自動起動し、公開DNS・公開ACME・前回実行の状態に依存せず、失敗原因を成果物から調査できること。5回連続の成功と再実行性を確認した後、対象ブランチに両チェックを必須設定する。

対象は、Ruby構文、既存113例、順序変更・単独実行・Mutation検証、Composeプラグインへの移行、local起動、HTTPリダイレクト、proxy、Basic認証、証明書検証、永続化・通常更新スキップ、ログ収集・後片付け、運用手順とする。

脆弱性検査、CodeQL、SBOM、IP制限・TLSポリシー等の網羅的なセキュリティ試験、PebbleによるACME試験、Docker socketを使うauto-discovery、multiarch、依存更新、リリースは後続フェーズ。P1で固定した既知挙動は、CI化の都合で製品修正しない。

## 2. 現状分析

以下のパスはプロジェクトルート基準。

| 観点 | 確認した事実 | P2での対応 |
|---|---|---|
| P1 | modelsの55例、contractsの58例、合計113例。`dev/check_p1.rb` は3 seed・9ファイル単独・M01〜M08と復元を検証 | 既存資産を再利用する |
| P1証跡 | `dev/test-results/p1-console.log` と `p1-check.log` に113例、全seed、単独、Mutation、復元後の成功記録あり | 技術的な移管前提の証跡として使用。レビュー承認とは区別 |
| 文書の鮮度 | P1対応表、C-07/C-08契約、開発環境検証記録には追加30例等が未実行との記述が残る | 開始時に最新ログへ状態を合わせる |
| CI | `.github/workflows` と `spec/ci` は実ディレクトリ・Git追跡一覧ともに存在しない | ロードマップの「初期ファイル」という記述を存在確認とせず、新設する |
| Ruby/Gem | Ruby 2.7.2、Bundler 2.2.4、RSpec 3.10系。lockのplatformはarm64-darwin-20とruby | P2で更新せずLinux CIで成立させる |
| 開発環境 | `dev/compose.dev.yaml` は既にservices形式。testはUID1000、Gem volume読み取り専用、network none、SKIP_BUILD=1 | UTの隔離を維持。Node/Codex・認証volumeをCIの依存にしない |
| RSpec入口 | `.rspec` がspec_helperを読込。SKIP_BUILD未指定ならsuite前にDocker build。support全読込、順序はdefined | UTはSKIP_BUILD=1と対象パスを明示。新ITは別のhelper・入口を使う |
| 旧IT | featuresは6ファイル12例。Composeは5構成中3つが旧ルート形式、2つがversion 2 | CI用の独立fixtureを追加する |
| Docker操作 | `portal_helpers.rb` はdocker-compose、固定project portalspec、shell展開で削除。非0を即時例外にしない | 引数配列・固有project・全終了コード確認へ移行 |
| 待機 | read_https_contentはretryのたびにtries=60へ戻る構造で、意図した回数上限にならない。主にECONNREFUSEDのみ捕捉 | 単調時計の締切と通信timeoutを設け、assert失敗をretryしない |
| 公開環境 | TEST_DOMAIN既定はtest.nginx-acme.site。STAGE省略時は原則staging | 全fixtureを.test名・STAGE=localに限定し、公開CAに向かう設定を拒否 |
| 状態依存 | renewalは前グループのコンテナを再利用、portalspec_https-portal_1を直書き。afterはstopのみ | 各試験で必要な状態を生成し、Composeサービス名でexec、試験後down |
| static/proxy | staticはdocker-machineと/data/https-portal。proxyはWordPress/MariaDBの可変タグ | static fixtureと小さなHTTP echoへ置換し、DBを必須経路から外す |
| TLS | 旧helperはVERIFY_NONE。local自己署名生成はSANを付ける | 新クライアントでは検証有効。自己署名起動と独立CA検証を分ける |
| 更新ログ | 旧期待値No need to renew certs forと実装Renewal skipped forが不一致 | 本体を合わせず、現行ログ・fingerprint・通信を試験する |
| 製品イメージ | nginx:1.30.2、s6-overlay v3.2.3.0、docker-gen 0.16.3、acme-tiny 5.0.3。起動で鍵・dummy・DH生成 | バージョン維持。初回生成時間を計測して待機上限を調整 |
| 証明書参照 | Nginxはchained.crt、Commandsはsigned.crtへのsymlinkを作る | 提示leaf・参照先・鍵の公開鍵一致も確認 |

### 調査で確認した証跡と限界

- 保存ログの開始は2026-10-24 11:34:22 JST（2026-10-24T02:34:22Z）。Ruby 2.7.2、x86_64-linux。113例のseed 1/17/101、9ファイル単独、M01〜M08の意図した失敗と復元、復元後113例の成功を確認した。
- 保存ログのSHA-256：公開版では省略。必要に応じて管理された作業環境で照合する。
- 今回の `docker compose -f dev/compose.dev.yaml config --quiet` は成功。ホストComposeはv5.6.1。「V2対応」は旧standaloneからプラグイン形式への移行を指し、2.xへの固定を意味しない。
- このチャットからEngineへの接続はnamed pipeでpermission denied。今回RSpec・製品ビルド・ITは再実行していない。保存ログにはHEADがなく、現在HEADとの厳密な同一性はCI初回で証明する。
- git statusは当該ツール環境でwork treeエラー。HEAD・ブランチ・追跡一覧は確認できたが、未コミット差分は未確定。開始前に通常環境で確認する。
- GitHub側のActions有効状態、履歴、ruleset、管理権限は未照会。ローカルファイルの不存在からGitHub設定の不存在を断定しない。

## 3. 実装設計

### 3.1 UT用の最小runner

`spec/ci/Dockerfile.unit` に、開発環境と同じRuby 2.7.2ベース・digestとBundler 2.2.4を使うCI用イメージを追加する。既存Gemfile.lockを維持し、Node/Codexやログインを必要としない構成にする。P2-01ではGit調査もオフラインコンテナ内で行うため、最小イメージにGitを含める。ホストはDocker操作のみとし、ソースは読み取り専用で渡して一時コピー上で検証する。

依存取得は準備工程の `bundle _2.2.4_ install --frozen` に限定し、試験時はnetwork noneで動かす。古いRuby/Busterの取得・TLS・Bundler互換性は最初に実証する。失敗をTLS検証無効化やbundle updateで回避しない。依存更新が不可避なら別変更として扱う。

`dev/check_p1.rb` を再利用する。構文検査は製品Ruby全体と試験コードへ拡張し、ログへHEAD、Ruby/Bundler/RSpec、コマンド、seedを記録する。113例の件数検査・0 pendingを維持する。

### 3.2 Docker試験の独立化

Linux CIホストが `spec/ci/run-integration.sh` でDockerを操作し、`spec/ci/compose.yaml` のportal、HTTP echo、testerを実行する。testerへDocker socketを渡さない。WindowsでもDocker CLI経由で同じ入口を呼び出せるようにする。

- 製品はルートDockerfileから一度ビルドし、全fixtureで同じローカルタグを使う。レジストリ公開は不要。
- echoはpath/query、Host、X-Real-IP、X-Forwarded-For、X-Forwarded-Protoを判定可能な形式で返す。環境変数を全量返す実装は避ける。
- .test名をportalのnetwork aliasに割り当て、URLにも同じ名前を使う。Hostヘッダー書換えだけではTLS SNI・名前検証を代替しない。
- runtimeはinternal networkとし、pull・Gem取得・buildを事前に完了させる。公開DNS・公開ACMEなしで完走することを確認する。
- ホスト80/443の公開、container_name、links、外部volume、実データbind mountは使わない。upstreamにはサービスDNSで到達する。
- projectはrun ID・attempt・scenario等から一意にし、ローカルも衝突しない識別子を使う。volumeへ固定のグローバルnameを設定しない。
- 各試験は新規project/volumeから開始する。永続化試験の内部だけ同じvolumeを再使用する。
- readyはhealthcheckと対象HTTPS・証明書で判定する。dummy証明書の段階で合格にしない。
- 新ITはspec/ci配下の専用helperを使い、旧feature hook・P1タグを適用しない。通信クライアントへ製品のOpenSSLモジュールを読み込まない。
- internal networkでのdefault route取得と `/etc/hosts` 初期化も実測する。失敗時は原因を切り分け、外部通信を無条件に許可して回避しない。

### 3.3 TLS検証を2経路に分ける

**A：localの新規自己署名。** 空volumeから製品自身に署名させる。起動後のsigned.crtの公開証明書だけを専用trustへ取得し、verify peer・ホスト名検証を有効にしてHTTPSアクセスする。SAN、有効期限、提示fingerprint、証明書と鍵の公開鍵一致を確認する。この経路だけで独立CAのチェーンを検証したとはしない。

**B：独立CA fixture。** 実行時に一時root CAとSAN付きleafを生成する。leaf証明書・鍵を `/var/lib/https-portal/<domain>/local/` のsigned.crt/domain.keyへ投入し、非dummy・更新猶予30日を十分超える有効期間・FORCE_RENEW=falseで起動する。testerにはroot公開証明書だけを渡し、チェーンとホスト名を検証する。異なるCA・異なるホスト名では必ず失敗させる。

CA秘密鍵、account.key、証明書volume全体をtesterや成果物へ渡さない。公開leafのメタデータだけ保存する。Bは既存証明書のロード・提示の検証であり、ACME発行試験は後続工程。

### 3.4 更新試験の注意点

CertsManager#renewは署名前の作業中鍵を生成せず、ACME.signの戻り値を検査せずにRenewed certsを出す。local初回署名後はdomain.ongoing.keyが正式鍵へ移動するため、単純な強制更新が正しく成立するかは要実測。ログだけの成功判定を踏襲しない。

renewの実行はcron時刻を待たず、Compose execと製品の `/command/with-contenv /command/s6-envdir -I /var/lib/https-portal/dynamic-env /bin/renew_certs` を使う方針とする。実装時に起動環境の伝播を確認する。

P2の必須範囲は、通常起動・再作成での証明書保持と、残日数十分・FORCE_RENEW=falseでの更新スキップ。強制更新は独立調査として記録し、fixtureで作業中鍵を補って製品の正常更新と称さない。製品修正が必要なら、契約の変更と合わせた別PRにする。

## 4. 試験仕様

| ID | 内容 | 合格条件 | 実行先 |
|---|---|---|---|
| P2-U01 | Ruby構文・P1 | 製品/試験の構文成功、113例がseed 1/17/101で0 failure/0 pending | lint-and-unit |
| P2-U02 | 独立性・Mutation | 9ファイル単独成功、M01〜M08各1件の意図した失敗、復元後113例成功 | lint-and-unit |
| P2-I01 | local新規起動 | 空volumeからSAN付き自己署名、対象HTTPS 200とwelcome本文 | docker-smoke |
| P2-I02 | HTTP→HTTPS | /path?q=valueが301、Locationはhttps://portal.test/path?q=value。追従せず判定 | docker-smoke |
| P2-I03 | proxy | echoの200、path/queryとHost保持、転送ヘッダーとProto=httpsが正しい | docker-smoke |
| P2-I04 | Basic認証 | 未認証/誤認証は401とchallenge、正認証は200と対象本文 | docker-smoke |
| P2-I05 | 証明書 | 独立CAで成功、誤CA/誤名で失敗、提示leaf一致、証明書と鍵の公開鍵一致 | docker-smoke |
| P2-I06 | 永続化 | 初回成功後にFORCE_RENEW=falseでコンテナ再作成。同じfingerprintとHTTPS 200 | docker-smoke |
| P2-I07 | 更新スキップ | 独立初期化後にrenewコマンドを明示実行。終了コード、現行skipログ、fingerprint不変、HTTPS正常 | docker-smoke |
| P2-I08 | static | fixtureのindexと別パスが正確な本文で200。固定ホストパス・Docker Machine不要 | docker-smoke |
| P2-H01 | harness失敗検知 | 停止portal/不正upstream等で非0、期限内停止、診断保存、対象project後片付け | 実装時/CI受入 |
| P2-H02 | 再実行性 | 個別指定・順序変更・全体再実行で成功し、以前のvolumeを必要としない | CI受入 |

I02は標準443。非443のLocationからポートが欠けるGAP01は現行契約として維持し、仕様修正は別変更とする。WebSocket、IP制限、TLSバージョン拒否、reload障害の網羅は後続工程。

## 5. GitHub Actions設計

`.github/workflows/tests.yml` を新設する。

| 項目 | 採用案 |
|---|---|
| トリガー | pull_request、push、workflow_dispatch。必須workflowをpath filterで省略しない |
| runner | ubuntu-24.04、GitHub-hosted Linux/amd64。multiarchは別工程 |
| チェック | lint-and-unitとdocker-smoke。表示名も固定し、workflow間の同名チェックを避ける |
| 権限 | contents: read、checkoutのpersist-credentials: false。秘密情報・公開トークンなし |
| PR | pull_request_targetでPRコードを高権限実行しない。fork PRにも秘密情報不要 |
| Action参照 | 実装時に公式配布を確認して完全commit SHA固定。最新版番号を推測で埋めない |
| 並行制御 | PR/branch単位のconcurrencyで旧runをcancel。projectはrun/attempt単位に分離 |
| ジョブ | UTとDockerは独立。Docker内はbuild→初期化→IT→診断→cleanup |
| 時間上限 | 暫定UT20分、Docker30分、起動180秒、1通信10秒。DH生成等を計測して根拠付き調整 |
| retry | readinessのみ締切付き。assert失敗の自動再試行はしない。非0・0件・pendingを失敗にする |
| 証跡 | HEAD/event/run/attempt、バージョン、イメージID/ベース参照、件数、seed、所要時間 |
| 成果物 | RSpec/実行ログ、sanitized compose、ps/health、サービスログ、必要なNginx設定、公開証明書メタデータ。14日保持案 |

診断収集・upload・cleanupは成功/失敗後も動く条件で配置し、shell側もtrapで回収する。元の試験終了コードを保存し、収集やcleanupで失敗を成功へ上書きしない。強制cancel・runner喪失では回収できない場合がある。

DEBUGはfalse文字列等を入れず、変数自体を未設定にする（現実装はENVの値の存在で判定）。DOMAINS内のBasic資格情報、Authorization、htpasswd、秘密鍵、account.key、CA秘密鍵を収集しない。docker inspect全量やnginx -Tの無加工保存を避け、故意の失敗でもマスク漏れがないことを確認する。

## 6. 実施順序・変更単位

| 順序 | 内容 | 主な差分 | 完了条件 | 概算 |
|---|---|---|---|---|
| P2-01 | 基準確定・最小Ruby runner | spec/ci/Dockerfile.unit、P1記録 | 既存差分確認、HEAD付き113例/Mutation成功、最小イメージでlock固定実行 | 0.5〜1日 |
| P2-02 | UTのActions移管 | workflow、run-unit.sh | PR/push/手動で成功、故意の失敗で赤、成果物に件数あり | 0.5日 |
| P2-03 | 独立IT基盤 | compose、run-integration.sh、helper、echo | local起動、期限・project分離、外部ACMEなし、失敗時収集とcleanup | 1〜1.5日 |
| P2-04 | 重要契約・CA fixture | IT spec、CA生成script、static fixture | I01〜I08、誤CA/誤名の負の対照、旧テストの代替範囲が明確 | 1〜1.5日 |
| P2-05 | Dockerジョブ・運用 | workflow、dev.ps1入口、手順・検証記録 | 同じ入口でローカル/CI成功、5回連続成功、必須チェック受入 | 1〜1.5日 |

合計4〜6.5人日。Ruby旧版の取得、初回製品ビルド、管理権限調整が増加要因。CI5回とレビューの待ち時間は別途。各変更はレビュー可能なPRに分ける。

### 予定する配置

```text
.github/workflows/tests.yml
spec/ci/
  Dockerfile.unit
  compose.yaml
  run-unit.sh
  run-integration.sh
  generate-cert-fixtures.sh
  integration_spec.rb
  support/                 # lifecycle、HTTP/TLS、診断
  fixtures/                # echo、static。秘密鍵なし
dev/dev.ps1               # CiUnit/CiIntegration等の薄い入口
dev/docs/
  00-index-ja.md
  30-p2-ci/
    30-execution-guide-ja.md
    31-implementation-plan-ja.md
    32-verification-ja.md       # 実施後に追加
    33-ci-test-guide-ja.md      # CI導入時に追加
    notes/
```

ファイル分割は実装で整理可能。dev/check_p1.rbは複製せず再利用する。生成物・鍵・一時ログをGit対象外にし、CI成果物へは選択的に保存する。必要に応じ.dockerignoreでdev成果物/CI fixtureを除外し、製品contextへの混入を防ぐ。fs_overlayのコピーと実行権限を維持する。

## 7. 旧12例の扱い

| 旧グループ | P2の代替と残る範囲 |
|---|---|
| local_stage | I01/I06。新規と既存volumeを試験内で明示構築 |
| minimal_setup | local起動で基本配信。公開staging発行は拡張試験へ |
| linked_containers | I03のecho proxy。links自体の互換性保証とはしない |
| static_site | I08。Docker Machine・固定ホストパスを除く |
| renewal | I07の通常skip。強制更新は3.4を調査しACME更新保証と分離 |
| auto_discovery | socketを使う隔離拡張試験へ。PR必須経路に混ぜない |

12例を新12例に機械的に置き換えず、代替する契約を記録する。旧スイートを残す場合はlegacyの入口に分離する。新しい標準コマンドは常に対象を明示し、無指定のbundle exec rspecで旧試験が混入する状態を避ける。

## 8. 受入・安定化・必須チェック化

1. ローカルで共通入口のUT/ITを実行し、HEADと差分を記録。ITの個別指定、順序変更、全体2回実行を確認する。
2. 実際のGitHub PRで両ジョブが自動起動することを確認する。push/手動も確認し、対象SHAとイベントを記録する。
3. 検証用ブランチまたは一時コピーで301→302、転送ヘッダー欠落、起動不能を注入し、assert失敗・非0・診断・後片付けを確認する。誤CA/誤名は恒常的な負の対照とする。
4. 復元後、同じ基準コミットで通常CIを5回連続成功させる。少なくとも1回はキャッシュなし、1回はworkflow再実行。失敗を再実行で隠さず、対策後に5回を数え直す。
5. 32-verification-ja.mdにrun URL、SHA、attempt、件数、時間、キャッシュ有無、artifact、後片付けを記録する。GitHubの実行をローカルログで代替しない。
6. 実際に発行されたチェック名を確認し、対象ブランチのruleset/保護へlint-and-unitとdocker-smokeを登録する。GitHub Actions提供元も確認。merge queue利用時はmerge_groupへ対応する。
7. 失敗PRでマージを阻止し、復元・成功後にマージ可能になることを確認する。管理者bypassやプラン/権限制約は別記録。必須化できない段階ではP2完了としない。

### Done

- [ ] P1の113例・3 seed・単独・M01〜M08をCIで再検証
- [ ] 製品Dockerfile由来のイメージでI01〜I08に成功
- [ ] 誤CA・誤名・故意のHTTP差分・起動失敗を検出
- [ ] Compose pluginのみ、公開DNS/ACME/Docker Machine非依存
- [ ] fixture独立、単独実行可、volume共有は永続化試験内のみ
- [ ] 全待機に時間上限、非0を保持、試験0件/pendingを失敗扱い
- [ ] 診断成果物を確認し、秘密鍵・資格情報の混入なし
- [ ] 正常/試験失敗後に対象projectのcontainer/network/volumeを片付けた
- [ ] 5回連続成功のrun URLと再実行を記録
- [ ] PR自動起動と必須チェックによるマージ阻止を確認
- [ ] 共通実行手順、旧12例の移行範囲、残課題を文書化

## 9. 開始時に解消する事項

| 項目 | 確認/対応 |
|---|---|
| 作業状態 | 通常PowerShellでgit status/diffを確認し、既存差分を保持した基準を記録 |
| GitHub | originの所有者・URLは作業環境で確認する。移管先、Actions有効状態、保護対象ブランチ、設定担当・権限を確認 |
| 必須化 | workflow追加だけでブランチ保護が完成したことにしない。実設定と受入を別作業で追跡 |
| Docker | Engine接続できる通常環境/CIで実試験。チャットの接続制約を製品不良と扱わない |
| 旧Ruby | 最初の変更でイメージの実ビルドを証明。Ruby/Gem更新を混在させない |
| 強制更新 | ログ以外の状態・通信で評価し、問題があれば別の製品修正PRへ |

## 10. 参照

### ローカルの根拠

- [P1対応表](../../../docs/test-contract-matrix-ja.md)
- [既知挙動](../../../docs/known-behavior-gaps-ja.md)
- [C-07/C-08現行契約](../../../docs/c07-c08-current-contract-ja.md)
- [P1自動検証script](../../check_p1.rb)
- [開発環境手順](../20-dev-environment/21-guide-ja.md)
- 保存実行ログ：dev/test-results/p1-console.log、dev/test-results/p1-check.log（Git対象外）

### 公式資料（2026-10-24確認）

- [Compose networking](https://docs.docker.com/compose/how-tos/networking/)：サービスDNS、projectごとのnetworkを使う設計。
- [GitHub Actions jobs](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-jobs)：ジョブ依存・失敗後の実行条件。
- [Required status checks](https://docs.github.com/en/enterprise-cloud%40latest/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks)：workflowのpath filterによるPendingと必須チェック。
- [Workflow artifacts](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts)：診断成果物の取得・保持。14日は本計画の提案。
- [GitHub Actionsとパッケージ](https://docs.github.com/en/packages/managing-github-packages-using-github-actions-workflows/publishing-and-installing-a-package-with-github-actions)：Action参照のcommit SHA固定の推奨を確認。公開工程はP2対象外。
