# HTTPS-PORTAL P3 作業計画：セキュリティ試験と監視

[文書一覧](../00-index-ja.md) / [全体ロードマップ](../10-roadmap/10-upgrade-roadmap-ja.md) / [P2検証記録](../30-p2-ci/32-verification-ja.md)

- 作成日：2026-10-24（日本時間）
- 状態：現状調査・計画作成済み。P3の実装・受入は未着手。
- 調査時HEAD：`0dba751`（ci: add Docker integration tests to GitHub Actions）
- 以下のコード・証跡パスはプロジェクトルート基準。ブランチ名・ホスト絶対パス・個人識別情報は省略する。

## 1. 方針と範囲

P2の独立Docker試験を拡張し、重要なセキュリティ退行と新規Critical/Highを自動検知する。Basic認証・独立CAチェーン検証は既存試験を再利用し、IP制限、TLSプロトコル、証明書異常系を補う。製品イメージの脆弱性検査・SBOMとRubyのCodeQLを接続し、検出後の判断方法も定義する。

本書は調査と実装計画であり、P3実装やGitHub設定変更の実施記録ではない。Nginx・Ruby等のバージョン更新はP4、Dependabot/Renovate・リリース公開・署名/provenance・ロールバックはP5またはリリース工程へ引き継ぐ。ACME発行のE2E、Docker socketを使うauto-discovery、multiarch全体の保証も別工程とする。

P2のGitHub受入は未確認である。P3のローカル実装準備は進められるが、P3のCI完了判定と必須化はP2受入を確認してから行う。

## 2. 現状調査

### 2.1 確認した実装・証跡

| 観点 | 確認した事実 | P3での扱い |
|---|---|---|
| UT | P1の113例、seed 1/17/101、単独実行・M01〜M08の受入記録がある | 既存lint-and-unitを維持する |
| CI | `.github/workflows/tests.yml` にpush/PR/手動、lint-and-unit、docker-smokeがある。ubuntu-24.04、最小権限、Action SHA固定、成果物14日保持 | 同じ安全方針でP3ジョブを追加する |
| Docker IT | `dev/check_p2_integration.ps1` と `spec/ci/compose.yaml` にlocal/redirect/proxy/auth/ca/persistence/renewal/staticの8件 | fixture・診断・cleanupを拡張する |
| ローカル受入 | `dev/test-results/p2-integration/20261024t105928z-3865e7dc/result.json` はresult=passed、stage=complete、8件passed。P2記録でも全件診断・cleanup成功 | 保存済みの結果として使用する。今回の再実行成功とはしない |
| Basic認証 | `spec/ci/integration/contracts.rb` のI-04は未認証・誤認証401/challenge、正認証200/upstreamを検証 | 重複作成せず、IP制限との併用を追加する |
| CAチェーン | prepare.rbでroot→intermediate→leafを生成。rootだけを信頼し、提示leaf・中間証明書・誤CA・誤名拒否をI-05で検証 | 中間欠落・期限切れの負の対照を追加する |
| 鍵一致 | CA fixture生成時の公開鍵比較、P2ホスト側のkeyMatches受入記録がある | Nginxへ提示された証明書との対応も維持する |
| IP制限 | `spec/contracts/nginx_access_spec.rb` のA03/A04でallow順序とdeny allを検証。SSLテンプレートに実装あり | 実通信の許可/拒否、偽装ヘッダー、認証併用が不足 |
| TLS | nginx.conf.erbはTLSv1.2/TLSv1.3、UT T01が設定値を固定 | 実ハンドシェイクの許可/拒否が不足 |
| 信頼確立 | client.rb/probe.rbのlocal自己署名bootstrapにVERIFY_NONEがある。その後はVERIFY_PEER。CA経路は独立rootを使用 | local bootstrapを独立CA検証の代替にしない。新規CA試験で検証無効化しない |
| 旧feature | `spec/support/portal_helpers.rb` は引き続きVERIFY_NONE | 旧featureはP3安全性の判定に使用しない |
| 脆弱性・SBOM・CodeQL | 追跡ソース内に専用workflow/設定は見当たらない | 新設する。GitHub側の機能有効状態は別途確認する |
| 製品依存 | nginx:1.30.2、s6-overlay v3.2.3.0、docker-gen 0.16.3、acme-tiny 5.0.3。Rubyはapt導入 | 実ビルド成果物の版を採取し、P4の更新基準にする |
| 供給元検証 | Dockerfileのwget取得物にSHA-256照合がない。ベースdigest固定なし、apt-get upgradeあり | P3で外部取得物のハッシュ照合と実体台帳を整備。バージョンは変更しない |
| テスト用依存 | Ruby 2.7.2-busterはdigest固定、RSpec 3.10系。製品Rubyとは別 | 製品とテスト用イメージを区別して台帳・検出結果を管理する |

### 2.2 今回の調査の限界

- コード、既存文書、保存済みresult.jsonを読んだ。今回Docker Engine接続はnamed pipeのpermission deniedとなり、build・UT・IT・スキャンは実行していない。
- Git HEAD・履歴は取得できたが、git statusはwork treeエラー、明示work-treeでもpermission denied。未コミット変更の有無は確定していない。Git設定を変更して回避していない。
- GitHub Actionsの実行履歴、リポジトリ公開範囲、Code Security利用可否、ruleset、通知設定は未照会。P2文書ではpush/PR/手動受入、故意失敗、5回連続成功、必須チェックが残課題。
- 現時点でCVE件数や実際の到達可能性は未確認。古い依存・シェル文字列埋め込み等の静的リスク候補を、検証済み脆弱性とは扱わない。

## 3. 実装順と成果物

| ID | 作業 | 主な変更先（予定） | 完了条件 |
|---|---|---|---|
| P3-00 | 基準確定・P2受入確認 | P2検証記録、本書、`42-verification-ja.md` | HEAD/差分、P2の未確認項目、GitHub機能・権限、試験環境を記録 |
| P3-01 | セキュリティIT追加 | `spec/ci/integration/{prepare,client,contracts}.rb`、compose.yaml、`dev/check_p2_integration.ps1`、新規security用fixture | 下記S-T01〜S-T08の正/負の対照、独立実行・cleanup成功 |
| P3-02 | 製品イメージのスキャン・SBOM・判定 | `dev/check_p3_security.ps1`、`dev/security/`、`dev/test-results/p3-security/`（Git対象外） | 同一image IDにスキャンとSBOMが紐付き、ポリシーの負の試験が成功 |
| P3-03 | 外部取得物の整合性 | Dockerfile、`dev/security/download-checksums.*`、依存台帳 | 対応アーキの取得物を照合。不一致で展開前にbuild失敗 |
| P3-04 | CodeQL適用 | `.github/workflows/codeql.yml`、必要な解析設定 | Ruby製品コードの抽出・解析・結果保存、重大検出のゲートを確認 |
| P3-05 | CI・監視・運用接続 | `.github/workflows/security.yml`、`41-execution-guide-ja.md`、`42-verification-ja.md`、文書一覧 | PR/push/手動/日次、通知経路、故意失敗、復元成功、必須化を受入 |

基本は上から順に進め、小さなPRに分割する。初期見積もり3〜5営業日はP2受入・権限・スキャナー導入が成立する場合の目安。既存重大検出の調査、全アーキchecksum確保、CodeQL利用不可時の代替は別途再見積もりする。

## 4. セキュリティ試験仕様

既存I-04/I-05とP1のA/T契約を維持し、以下を追加する。

| ID | 入力・操作 | 合格条件 |
|---|---|---|
| S-T01 | rootのみを信頼した正常チェーン、誤CA、誤名（既存I-05） | 正常200。誤CA/誤名は原因を区別してTLS検証失敗 |
| S-T02 | 同一root/leafで中間証明書だけ提示しないfixture | 完全チェーンの正常対照は成功、欠落時はissuer/chain検証で失敗 |
| S-T03 | 正しいSAN・署名だが期限切れのleaf | 独立クライアントが期限を理由に拒否。製品がlocal再署名していないこともfingerprintで確認 |
| S-T04 | 許可送信元と非許可送信元から同じIP制限ドメインへアクセス | 許可元200、非許可元403。接続不能やTLS失敗を403の代替にしない |
| S-T05 | 非許可元から許可IPのX-Forwarded-For/X-Real-IPを送信 | 引き続き403。ヘッダー値でアクセス制御を迂回できない |
| S-T06 | IP制限＋Basic認証を同一ドメインへ設定 | 許可IP＋正認証200、許可IP＋無/誤認証401、非許可IP＋正認証403。両条件が必要 |
| S-T07 | TLS1.2/1.3を各固定して接続、TLS1.0/1.1も各固定して接続 | 1.2/1.3成功、1.0/1.1はサーバーのprotocol拒否。クライアント側非対応で送信できない場合は試験不成立 |
| S-T08 | 対象外SNIとSNIなしでdefault SSL serverへ接続 | handshake拒否。正常SNIの成功対照も併記する |

実装上の注意：

- internal network・実行固有project/volume・公開DNS/ACME不要を維持する。公開ポートやDocker socketをtesterへ渡さない。
- IP試験は同じ隔離ネットワークに異なる送信元のtesterを用意する。送信元IPを取得して許可リストを構築し、必要なら専用Compose overrideのIPAMを使う。固定サブネット衝突・同時実行も検証する。
- ready!は現在200/401だけを許容するため、拒否元403を起動待ちとして扱わない。許可元または正常fixtureで準備完了を確認してから、一度だけ拒否を検証する。
- prepare.rbの証明書期限指定を拡張する。期限切れ証明書は製品が更新し得るため、起動後の隔離fixtureへ異常証明書を配置しnginx -t/reload後に確認する等、更新処理と分離して設計する。試験fixtureの操作と製品発行の成功を混同しない。
- 旧TLS試験ではクライアントのOpenSSL版・対応プロトコル・security levelも記録する。試験限定の調整が必要なら専用クライアント内に限定し、通常CA検証の設定は維持する。
- timeout、通信の失敗原因、expected/actual、診断とcleanupを記録する。断言失敗の自動retryやskipで合格にしない。
- IP deny削除、旧TLS有効化、CA検証無効化を一時コピーで意図的に行い、対応試験が失敗することを確認する。本体へ残さない。

## 5. 脆弱性・SBOM・整合性の設計

### 5.1 スキャン対象と保存情報

Trivyを第一候補とし、導入時に公式配布元・安定版・checksumと対応runnerを確認し、ツール版/Action SHAまたはコンテナdigestを固定する。製品を一度buildし、そのローカルimage IDまたはsaveした同一archiveをスキャンとCycloneDX JSON生成に共用する。スキャン後に再buildして同一成果物と称さない。

必須対象は製品イメージのOS・言語依存、リポジトリのGemfile.lockと秘密情報。UT/testerイメージは別レポートにし、製品の検出件数と混ぜない。秘密情報検査から実際の鍵volume・認証volume・生成ログを除外し、意図的な架空資格情報はパス/ルールを限定した例外にする。

保存項目：commit/入力fingerprint、実行ID、platform、image ID、取得可能なベースdigest、実際の主要依存版、ツール版、DB更新日時、全重大度のJSON、判定要約、SBOM、依存台帳。レジストリへpushしない場合はRepoDigestがないことを明記し、image IDを記録する。

s6-overlayや単体Pythonスクリプト等は自動列挙・CVE照合が不足し得る。SBOMのcomponentsと実体を突き合わせ、Nginx/OS/Ruby/s6-overlay/docker-gen/acme-tinyを取得元・版・ハッシュ付き台帳へ記録する。検出できない部品は未検出と明記し、SBOMがあるだけで網羅済みにしない。

### 5.2 マージ判定ポリシー案

- 新規Critical/High、重要セキュリティIT退行、実秘密情報混入は失敗。修正版未提供も一覧と判定から一律除外しない。
- 「既存」は初回の基準コミット・image ID・DBで記録した組だけ。既存分にも個別の期限付き承認例外が必要。自動baseline再生成で新規検出を既存へ取り込まない。
- 例外キーは検出ID＋対象パッケージ/PURL＋インストール版＋対象（製品/試験環境）とし、理由・根拠・担当役割・承認者・登録日・期限・追跡課題を持つ。ワイルドカードやCVEだけの全面除外は禁止する。
- 例外はUTC日付で期限を判定し、期限切れ・不正形式・対象の版変更で失敗する。PR側で例外を追加する場合もレビュー対象とし、保護ルール/CODEOWNERS等で承認を要求する。
- 新規検出は依存変更だけでなくDB更新による発見も含む。日次にdefault branchを新DBで再検査する。
- DB取得失敗、解析失敗、空/破損JSON、SBOMの必須部品欠落は検査失敗として区別する。古いキャッシュやcontinue-on-errorで成功扱いにしない。
- Medium/Low/Unknownも保存して一次分類する。High/Criticalの初期大量検出はP4の修正候補へ整理し、初回観測中と必須ゲート成立後を明確に分ける。

判定器の意味のある試験として、新規High、既存有効例外、期限切れ例外、対象版変更、不正JSON、DB取得エラーを用意する。秘密情報検査は架空の検出用トークンで失敗と復元を確認し、実秘密情報は使わない。

### 5.3 外部取得物の照合

Dockerfileのs6-overlay noarch/各arch、docker-gen各arch、acme_tiny.pyのSHA-256を取得元と共に版別管理し、展開・配置前に検証する。upstreamの署名済みchecksum等がある場合は優先する。独立した正当性の確認ができない値を、同じダウンロードから計算しただけで信頼済みとしない。

未登録アーキ・改ざんchecksum・取得失敗ではbuildを停止する。amd64の実buildとchecksum不一致の故意失敗を受入対象にし、他archは取得物/ハッシュの対応を確認、実起動はmultiarch工程へ引き継ぐ。ベースdigestやaptの再現性改善はP4側で扱い、P3では実際の取得結果を記録する。

## 6. CodeQLとCI監視

Rubyを対象にCodeQL advanced setupを第一候補とする。Rubyは対応言語でbuild-mode noneを使用できる。製品`fs_overlay/opt/certs_manager`等が抽出されることを確認し、独自Rubyからsystem等へのデータフローをレビューする。CodeQLだけでERB生成設定・シェル・ダウンロード完全性まで保証しない。[対応言語](https://codeql.github.com/docs/codeql-overview/supported-languages-and-frameworks/)・[Action設定](https://github.com/github/codeql-action/blob/main/README.md)

公開範囲・契約によって利用可否が変わるため、着手時に確認する。利用不可なら理由と代替SASTの対象・不足を記録し、Rubyのシェル実行箇所レビューと検証可能なルールを設ける。無条件skipで完了にしない。[非公開リポジトリの利用条件](https://docs.github.com/en/code-security/reference/code-scanning/troubleshoot-analysis-errors/private-repository-enablement)

| チェック/実行 | 設計 |
|---|---|
| lint-and-unit | 既存P1契約とMutationを維持 |
| docker-smoke | 既存8件を維持。P3 security ITは独立ジョブまたは明示scenarioとして追加し、必ず起動する |
| security-check | PR/push/手動/日次。build→scan→SBOM→例外判定。導入時の収集期間後、負の受入が済んだ段階で必須化 |
| codeql-ruby | PR/push/手動/日次。解析成功だけでなく重大アラートのマージ阻止をruleset等で確認 |
| 成果物 | 成否にかかわらず許可ファイルだけupload。通常14日。基準SBOM・例外判断は次の基準確定まで別途保管する |
| 権限 | 原則contents:read。SARIF uploadに必要なsecurity-events:writeはCodeQLジョブだけ。fork PRは権限条件を確認し、高権限イベントでPRコードを実行しない |
| ネットワーク | IT本体は従来どおり隔離。scannerのDB取得・CodeQL取得等はCI準備/解析ジョブで必要な通信として区別する |

SARIF送信権限がないfork PRの扱いを実確認する。送信不可と解析失敗を区別し、必要なら解析成果物と独立の判定でPR検査を維持する。CodeQLのworkflow成功だけでは「検出なし」を保証しないため、重大アラートを実際にブロックできるか受入する。

日次監視はGitHub Actionsのscheduleを使用する案とし、この計画作成でCodex自動化は作成しない。担当者がGitHubの失敗通知を受け取れることを確認し、Criticalは原則1営業日以内、Highは原則3営業日以内に一次判断する。ツール障害・新規重大検出・期限切れ例外を区別して確認する。P3受入時に担当役割・通知先・欠落実行の確認手順を確定する。

## 7. 受入手順とDone

1. 通常環境でHEAD/差分を確認し、P2のpush/PR/手動・5回連続成功・必須チェック・失敗時マージ阻止の証跡を補う。
2. security ITを単独・全体・独立2回で実行する。各成功と負の対照、timeout、診断マスク、container/network/volume残存なしを確認する。
3. 製品イメージで初回スキャンとSBOMを生成し、同じimage ID・実部品台帳との対応を確認する。既存検出は個別判断し、期限付き例外とP4の修正課題を分ける。
4. 新規High・期限切れ例外・壊れたchecksum等を検証用の一時コピー/ブランチで投入し、ローカルとCIで非0/赤判定を確認する。復元後の成功も保存する。
5. CodeQLの抽出対象、解析、アラート表示とマージ阻止、fork PRの権限を確認する。代替時は理由と同等の判定証跡を残す。
6. 日次/手動で検査が起動し、失敗通知・成果物を担当が確認できることを受入する。必須チェックを設定し、実行URL/commit/成果物を42-verification-ja.mdへ記録する。

- [ ] P2の未確認事項を解消し、P3の開始基準を記録した
- [ ] I-04/I-05を維持し、S-T01〜S-T08と対応Mutationで重要退行を検知した
- [ ] 製品イメージの初回脆弱性結果・SBOM・実体台帳が同一成果物へ紐付いている
- [ ] 新規Critical/Highと期限切れ例外がブロックされ、スキャン障害も失敗する
- [ ] 全外部取得物のハッシュ対応を管理し、不一致を展開前に検知した
- [ ] CodeQLの適用可否と解析対象を記録し、重大検出のブロックを確認した（代替時は根拠と不足を明記）
- [ ] PR・日次・手動、失敗通知、成果物保管、必須チェック、担当役割が受入済み
- [ ] 未解決事項をP4/P5へID・根拠・期限付きで引き継いだ

## 8. 参照・後続文書

- P2：[詳細計画](../30-p2-ci/31-implementation-plan-ja.md)、[結合試験](../30-p2-ci/35-integration-contracts-ja.md)、[Actions受入](../30-p2-ci/36-actions-integration-guide-ja.md)
- P1：`docs/test-contract-matrix-ja.md`、`spec/contracts/nginx_access_spec.rb`、`spec/contracts/nginx_tls_spec.rb`
- Trivy：[脆弱性検査](https://trivy.dev/docs/dev/guide/scanner/vulnerability/)、[SBOM](https://trivy.dev/docs/dev/guide/supply-chain/sbom/)。本書では導入方針を確認。CLI/API・固定版は実装時に再確認する。
- 今後追加：41-execution-guide-ja.md（操作と障害対応）、42-verification-ja.md（実行証跡）。本書から未作成文書へのリンクは置かない。