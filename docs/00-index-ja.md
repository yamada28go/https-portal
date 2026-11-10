# ドキュメント一覧

開発・試験・更新に関する文書は、プロジェクトルートの `docs/` に集約する。利用者向けの製品説明は [README](../README.md)・[日本語README](../README-ja.md)、実行スクリプトは `dev/`、試験資材は `spec/` に置く。

## 目的別の入口

| 目的 | 読む文書 |
|---|---|
| 全体方針を把握する | [更新ロードマップ](10-roadmap/10-upgrade-roadmap-ja.md) |
| P1の試験範囲・契約を調べる | [テスト対応表](15-p1-contracts/test-contract-matrix-ja.md) → [詳細計画](15-p1-contracts/https-portal-p1-detailed-test-plan-ja.md) |
| 開発環境を構築・操作する | [操作手順](20-dev-environment/21-guide-ja.md) |
| CI・結合試験を実行する | [CI手順](30-p2-ci/33-ci-test-guide-ja.md)・[結合試験](30-p2-ci/35-integration-contracts-ja.md) |
| セキュリティ検査を準備・実行する | [実行手順](40-p3-security/41-execution-guide-ja.md)・[収集手順](40-p3-security/45-security-collection-guide-ja.md) |
| 確認済み・未確認を調べる | [開発環境](20-dev-environment/22-verification-ja.md)・[P2](30-p2-ci/32-verification-ja.md)・[P3](40-p3-security/42-verification-ja.md)の検証記録、[ARM64タイムアウト](40-p3-security/48-arm64-timeout-investigation-ja.md)・[IP接続](40-p3-security/49-arm64-ip-connect-timeout-ja.md)の調査記録 |
| 作業メモを残す | 各分類の `notes/`。複数分類にまたがるものは [共通メモ](90-common-notes/README.md) |

## 分類別の全文書

番号は分類・表示順。既存の10・20・30・40・90番台を維持し、P1は15番台にまとめる。

### 10：全体方針・ロードマップ

- [HTTPS-PORTAL セキュリティ対策・継続的バージョン更新計画（案）](10-roadmap/10-upgrade-roadmap-ja.md)
- [メモ：作業メモ](10-roadmap/notes/README.md)

### 15：P1 単体テスト・設定契約

- [C-02：空値・異常入力の契約](15-p1-contracts/c02-input-contract-ja.md)
- [C-07／C-08：現行動作を正解とする契約](15-p1-contracts/c07-c08-current-contract-ja.md)
- [HTTPS-PORTAL P1：変更検知テスト拡充 詳細実施計画](15-p1-contracts/https-portal-p1-detailed-test-plan-ja.md)
- [P1で記録する既知挙動と後続課題](15-p1-contracts/known-behavior-gaps-ja.md)
- [P1 Mutation検証](15-p1-contracts/mutation-check-ja.md)
- [P1 単体・設定契約テスト対応表](15-p1-contracts/test-contract-matrix-ja.md)

### 20：開発環境

- [HTTPS-PORTAL：Docker開発環境構築計画](20-dev-environment/20-plan-ja.md)
- [Docker開発環境の使い方](20-dev-environment/21-guide-ja.md)
- [Docker開発環境：検証記録](20-dev-environment/22-verification-ja.md)
- [メモ：作業メモ](20-dev-environment/notes/README.md)

### 30：P2 CI・結合試験

- [HTTPS-PORTAL P2 実施手順](30-p2-ci/30-execution-guide-ja.md)
- [HTTPS-PORTAL P2実施計画：GitHub Actionsへの移管](30-p2-ci/31-implementation-plan-ja.md)
- [P2 検証記録](30-p2-ci/32-verification-ja.md)
- [GitHub Actions：単体テストの実行・確認](30-p2-ci/33-ci-test-guide-ja.md)
- [Docker試験基盤の実行・確認（P2-03）](30-p2-ci/34-integration-guide-ja.md)
- [重要な結合試験（P2-04）](30-p2-ci/35-integration-contracts-ja.md)
- [36 Docker結合試験のGitHub Actions接続](30-p2-ci/36-actions-integration-guide-ja.md)
- [メモ：最小Ruby runnerの準備と接続制約](30-p2-ci/notes/2026-10-24-01-minimal-ruby-runner.md)
- [メモ：Docker試験基盤：分離とライフサイクル](30-p2-ci/notes/2026-10-24-02-integration-isolation.md)
- [メモ：作業メモ](30-p2-ci/notes/README.md)

### 40：P3 セキュリティ・ARM64調査

- [HTTPS-PORTAL P3 作業計画：セキュリティ試験と監視](40-p3-security/40-implementation-plan-ja.md)
- [41 準備済みイメージによる試験実行](40-p3-security/41-execution-guide-ja.md)
- [P3 検証記録](40-p3-security/42-verification-ja.md)
- [43 IP制限の実通信試験](40-p3-security/43-ip-access-guide-ja.md)
- [44 TLS・証明書異常系の実行手順](40-p3-security/44-tls-security-guide-ja.md)
- [45 脆弱性レポート・SBOMの収集](40-p3-security/45-security-collection-guide-ja.md)
- [46 Critical／High件数バッジ](40-p3-security/46-security-count-badges-ja.md)
- [47 amd64／arm64のネイティブActions実行](40-p3-security/47-native-multiarch-actions-ja.md)
- [ARM64 結合試験のタイムアウト調査と修正](40-p3-security/48-arm64-timeout-investigation-ja.md)
- [ARM64 IP制限試験の接続開始タイムアウト](40-p3-security/49-arm64-ip-connect-timeout-ja.md)

### 90：共通メモ・履歴

- [統合前の索引に記載されていた作業履歴](90-common-notes/2026-11-03-01-former-index-history.md)
- [共通作業メモ](90-common-notes/README.md)

## 保存・更新のルール

- 正式な計画・手順・検証結果は各分類の直下、調査途中の仮説・試行錯誤・判断理由は `notes/` に置く。新規文書はこの一覧にも追加する。
- 文書を別の場所へ複製せず、READMEや資材の説明から `docs/` の正式文書へ相対リンクを張る。`dev/README.md` と `spec/ci/README.md` は実行入口の短い案内に使う。
- 計画、実行手順、検証記録の役割を分ける。確認済み・未確認は検証記録に根拠と日付を残し、索引に作業進捗を追記し続けない。過去の記録は当時の事実として保持する。
- メモ名は `YYYY-MM-DD-NN-topic.md`。NNは同日・同じnotes内の2桁連番。冒頭に日付、状態（調査中／解決／保留）、目的、関連文書を記載する。
- メモは事実、仮説、操作、結果、決定、次の作業を分ける。決定事項は正式文書にも反映する。
- 生ログは `dev/test-results/`（Git対象外）へ保存し、メモには要約とプロジェクト相対パスを記録する。
- 個人名を含む絶対パス、アカウント名、認証情報、秘密鍵を文書へ含めない。UTF-8で保存し、文書間の参照は相対リンク、コマンド中のパスはプロジェクトルート基準で記載する。
