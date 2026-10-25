# 開発・更新ドキュメント一覧

番号は分類・表示順。名前順で並べると、全体方針→開発環境→P2→P3の順になる。

## 目的別の入口

| 目的 | 読む文書 |
|---|---|
| 全体方針を把握する | [10 更新ロードマップ](10-roadmap/10-upgrade-roadmap-ja.md) |
| 開発環境を構築・操作する | [21 操作手順](20-dev-environment/21-guide-ja.md) |
| 開発環境の設計を確認する | [20 構築計画](20-dev-environment/20-plan-ja.md) |
| 確認済み・未確認を調べる | [22 検証記録](20-dev-environment/22-verification-ja.md) |
| P2を開始する | [30 実施手順](30-p2-ci/30-execution-guide-ja.md) → [31 詳細計画](30-p2-ci/31-implementation-plan-ja.md) |
| 作業メモを残す | 各分類のnotes。複数分類にまたがるものは[共通メモ](90-common-notes/README.md) |

## 分類と保存先

| 番号帯 | 保存先 | 内容 |
|---|---|---|
| 00 | この文書 | 全体の入口 |
| 10番台 | 10-roadmap/ | 全フェーズのロードマップ |
| 20番台 | 20-dev-environment/ | 開発環境の計画・操作・検証 |
| 30番台 | 30-p2-ci/ | P2の手順・詳細設計・実施後の検証 |
| 40番台 | 40-p3-security/ | P3の現状調査・セキュリティ試験と監視の計画 |
| 90番台 | 90-common-notes/ | 複数分類にまたがるメモ |

P2-01は完了。最小Ruby環境で113例・3 seed・単独実行・M01〜M08・復元後検証に成功。P2-02はworkflow実装済み・GitHub受入待ち。[32 P2検証記録](30-p2-ci/32-verification-ja.md)を参照。[33 CI実行・受入手順](30-p2-ci/33-ci-test-guide-ja.md)を追加済み。

P1の詳細契約・テスト計画はプロジェクト直下の[docs](../../docs/)に置いたまま。[P1対応表](../../docs/test-contract-matrix-ja.md)を参照する。

## メモの運用

- 正式な計画・手順・検証結果は各分類の直下、調査途中の仮説・試行錯誤・判断理由はnotesへ置く。
- メモ名は `YYYY-MM-DD-NN-topic.md`。NNは同日・同じnotes内の2桁連番。個人名を含めない。
- 冒頭に日付、状態（調査中／解決／保留）、目的、関連文書を記載する。
- 事実、仮説、操作、結果、決定、次の作業を分ける。決定事項は正式文書にも反映する。
- 生ログは `dev/test-results/`（Git対象外）へ保存し、メモには要約とプロジェクト相対パスを記録する。
- 個人名を含む絶対パス、アカウント名、認証情報、秘密鍵をメモへ含めない。
- 既存番号は維持し、同じ分類へ文書を追加する。分類を超えるほど増えた時点で分類を見直す。

## 完了済み：P2-03

P2-03のDocker試験基盤は受入完了。独立2回成功と、期限切れ失敗時の診断・cleanup・残存なしを確認済み。[34 Docker試験の実行・受入手順](30-p2-ci/34-integration-guide-ja.md)を参照。P2-04の実装と受入状況は次節を参照。P2-02のpush成功は確認済みだが、残りの受入項目も[32 検証記録](30-p2-ci/32-verification-ja.md)で追跡する。

## 完了済み：P2-04

重要な結合試験は全8件の実Docker受入完了。[35 結合試験の内容と実行手順](30-p2-ci/35-integration-contracts-ja.md)を参照。試験中の外部通信遮断は維持する。

## 現在の作業：P2-05

Testsにdocker-smokeを追加済み・GitHub受入待ち。[36 Actions接続・受入手順](30-p2-ci/36-actions-integration-guide-ja.md)を参照。commit/push後に両ジョブと成果物を確認する。必須チェック設定と5回連続成功は未確認。

## P3の準備：現状調査・作業計画

[40 P3作業計画](40-p3-security/40-implementation-plan-ja.md)を追加。既存の認証・CA試験を再利用し、IP制限/TLS異常系、脆弱性検査、SBOM、外部取得物の照合、CodeQL、監視の順に整備する。P3実装は未着手。P2のGitHub受入・必須チェックの未確認事項は開始基準として追跡する。

[P3開始状態の検証記録](40-p3-security/42-verification-ja.md)を追加。手順1の開始状態は利用者の目視確認により受入OK（2026-10-24）。エージェント調査時の制約は検証記録へ保持。次は準備済みイメージで実行できる入口の追加。

[41 準備済みイメージによる実行](40-p3-security/41-execution-guide-ja.md)を追加。手順2の実装と検証状況は[P3検証記録](40-p3-security/42-verification-ja.md)を参照。

手順2の入口実装・制御フロー検証は完了。手順3は実行したがDocker Engine接続拒否で停止し、実試験の受入は未完了。[P3検証記録](40-p3-security/42-verification-ja.md)に証跡と再実行コマンドを記載。

手順3の最新結果：利用者実行でUTとDocker全16件（8件×2回）が成功し、診断/cleanup・残存なしを確認。準備済みイメージによる実行受入は成功。インターネット接続を切ったかはログから未確認。次は手順4のIP制限試験追加。

手順4のIP制限試験を実装済み・実Docker受入待ち。[43 IP制限の実行手順](40-p3-security/43-ip-access-guide-ja.md)を参照。新toolsイメージでsecurity（ip/ip-auth）を実行する。allは10件へ拡張。

手順4の最新結果：利用者実行ID 20261024t123747z-c292cf3eでIP制限2件×2回の全4件が実Dockerで成功。診断/cleanup・残存なしも確認。全体回帰・故意変更検知・Actions受入は別途追跡。

手順5のTLS/証明書異常系は実装済み・実Docker受入待ち。[44 TLS試験の実行手順](40-p3-security/44-tls-security-guide-ja.md)を参照。tlsは3件、securityは5件、allは13件。

手順5の最新受入：20261024t131715z-427b2388でTLS3件×2回の全6件が実Dockerで成功。正常復元・診断/cleanup・残存なしを確認。故意変更検知と全13件回帰・今回変更のActions受入は別途追跡。

TLS故意変更検知：20261025t024506z-8f12e242で変更前成功→TLS1.2無効化→protocol version alertによる期待失敗を確認。診断/cleanup成功・残存なし。次はmutationなしの正常復帰と全13件回帰。

手順5のローカル受入完了：故意変更検知に続き、20261025t024745z-c4d9ac62で全13件×2回（26件）成功。TLS正常復帰・全件診断/cleanup成功・残存なし。次はTLS変更のcommit/push後、Actionsとartifactの全13件/cleanupを確認。

TLS変更のActions確認：run 40163898918 / commit 2fe7819でlint-and-unit・docker-smokeとも成功し、artifact2件生成を確認。成果物内の全13件/cleanupはサインインが必要なため未照合。

手順6初期：脆弱性レポートとSBOMの収集基盤を実装済み・製品初回受入待ち。[45 収集の準備・実行手順](40-p3-security/45-security-collection-guide-ja.md)を参照。準備だけ外部通信を許可し、検査はnetwork none。初期はreport-onlyで重大度ゲート未導入。

手順6初期のローカル収集受入成功：20261025t071211z-49f60b78で製品レポート/SBOMを生成し、両DB・ID対応・成果物hash・cleanupを照合。Critical 12 / High 135を含むreport-only収集。次はsecurity-report Actionsとartifactの受入、重大検出の一次分類。P3全体完了・脆弱性解消とはしない。

手順6初期のActions成功：run 40174288486 / commit a1301d7でsecurity-reportのpush実行成功（2m58s）、security-evidence artifact 1件（518 KB）生成を確認。ログ・artifact内部は要サインインのため未照合。次は成果物内容確認と重大検出の一次分類。

[46 Critical／High件数バッジ](40-p3-security/46-security-count-badges-ja.md)を追加。既定ブランチの成功検査だけ専用security-badgesブランチへ集計値を公開する実装を追加。PR/作業ブランチはartifactのみで公開しない。実公開の受入は変更反映後のActions待ち。

件数バッジ公開条件を修正：ブランチ名の明示設定は不要。成功したbranch実行のGITHUB_REF_NAMEを自動取得し、マージ後も継続更新する。PR/tag/生成データbranchは公開しない。READMEはリポジトリの最後に公開した成功検査を表示し、対象branchはクリック先で確認する。26件検証・構文/actionlint成功、remote表示は修正push後に受入待ち。

[47 amd64／arm64のネイティブActions実行](40-p3-security/47-native-multiarch-actions-ja.md)を追加。UT・全13件IT・脆弱性/SBOMを各CPUで実行し、成果物名を分離。公開件数バッジはamd64基準と明記。CPU判定・構文等の実装検証は成功、両CPUの実Actions受入はpush後。
