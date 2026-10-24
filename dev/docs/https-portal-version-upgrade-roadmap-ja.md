# HTTPS-PORTAL セキュリティ対策・継続的バージョン更新計画（案）

- 対象：アップロードされた `https-portal-master.zip`（アーカイブに記載されたコミット `0e72267b57d54dec723de1228dc370cb43f30e74`）
- 起案日：2026-10-22
- 目標：**機能退行を自動検知しながら、依存コンポーネントのセキュリティ更新を小さな PR で継続適用できる状態にする。**
- 注：本書はコード静的調査に基づく計画。GitHub Actions／Docker を実際に実行した結果ではない。工期は概算（主担当１名＋レビュー担当、環境構築済みを想定）。

## 1. 意思決定（結論）

1. **先に変更検知テスト（characterization / contract / regression tests）を整備する。** ただし現状の危険な動作まで永続的な正解にしない。現状維持テストと、安全要件テストを分離する。
2. 単体試験・設定ファイル生成試験は **PR ごとの必須ゲート** にする。Docker 結合試験はローカル・自己署名環境に作り替えてから必須化する。
3. 現状の試験が失敗している可能性を先に切り分け、テストの期待値を無条件に書き換えず、実装意図と合否を確定する。
4. テスト基盤確立後、Nginx（＋OS）、Ruby、s6-overlay、docker-gen、acme-tiny を **１コンポーネントずつ** 更新する。
5. Dependabot／必要に応じた Renovate、コンテナ脆弱性検査、SBOM、保護ルール、リリース・ロールバック手順を最後に接続し、常時更新を可能にする。

## 2. コードから確認できた現状

| 観点 | 確認結果 | 影響 |
|---|---|---|
| 既存テスト | 7 件の `*_spec.rb` に 13 個の RSpec `it`（ドメイン解析 1、Docker 機能テスト 12） | UT はドメイン解析に偏っている |
| ドメイン解析 | 1 件の `it` で 26 パターンを一括検証 | 不具合時の検知粒度が粗い |
| 旧 Docker 環境 | `docker-compose`、`docker-machine`、一部 Compose v1 形式 | GitHub-hosted runner にそのまま移植できない |
| 試験間依存 | `spec/features/renewal_spec.rb` は前のテストのコンテナ状態を再利用 | 並列化・単独実行・再現性に問題 |
| 外部依存 | 既定 `TEST_DOMAIN` が公開ドメイン、`STAGE` 未指定時は staging | CI で外部 DNS / ACME に依存し得る |
| TLS | `PortalHelpers#read_https_content` は `VERIFY_NONE` | HTTPS 取得だけでは証明書の妥当性を検証できない |
| 証明書更新 | 期待ログ `No need to renew certs for` に対し実装は `Renewal skipped for` | テストと実装に不一致（実行結果は未確認） |
| Dockerfile | `ARG DIST=nginx:1.30.2`、Ruby は apt、s6-overlay `v3.2.3.0`、docker-gen `0.16.3`、acme-tiny `5.0.3` | 更新起点が分散、外部ダウンロードの整合性検証がない |
| Ruby 開発環境 | `.ruby-version` は `2.7.2`、RSpec lock は `3.10.x`、`Gemfile.lock` は `arm64-darwin-20` | Linux runner と Ruby 更新時に再検証が必要 |
| イメージ取得 | Dockerfile で `apt-get upgrade` と `wget` を実行 | ビルド時点により成果物が変わり得る |
| CI | 元の ZIP には `.github/workflows` がない | 現時点の GitHub Actions 実行成功は確認できない |

セキュリティ観点で合わせて精査すべきもの：`docker.sock` のマウント権限、外部値のシェルコマンド埋め込み、生成 Nginx 設定の想定外差分。これらは静的なリスク候補であり、未検証の脆弱性と断定しない。

## 3. 段階的な計画と完了条件

| フェーズ | 概算 | 作業 | 完了ゲート（次へ進む条件） |
|---|---:|---|---|
| P0：現状固定と棚卸し | 2–3 営業日 | コミット・ビルド成果物の記録、機能契約、依存関係一覧、既存 13 ケースの実行確認・既知失敗の分類 | ベースライン結果・既知不具合・変更禁止事項が記録されている |
| P1：**変更検知テストの拡充** | 5–8 営業日 | 26 入力の個別化、設定生成差分、TLS/HTTP/認証/ルーティング/証明書更新判断の契約試験を追加 | 重要な振る舞いの変更をテストが検出でき、故意の変更でも失敗を確認した |
| P2：GitHub Actions に移管 | 4–6 営業日 | Compose V2、外部 DNS・ACME 非依存の IT、独立した fixture、ログ収集、PR 必須ジョブ | 連続 5 回程度の CI 成功、再実行可能、PR 時に自動起動 |
| P3：セキュリティ試験と監視 | 3–5 営業日 | 証明書チェーン検証、Basic 認証/IP 制限、脆弱性検査、CodeQL（適用可能範囲）、SBOM | 新規重大脆弱性・重要セキュリティ退行の検知ルールがある |
| P4：段階的なバージョン更新 | 5–10 営業日 | ベースイメージ・Ruby・外部ツールを一つずつ更新、差分確認、機能・セキュリティ試験 | 各更新 PR の全必須チェック合格、互換性影響がレビューされている |
| P5：継続更新・リリース管理 | 3–5 営業日 | Dependabot／Renovate 設定、保護ルール、リリース CI、ロールバック演習、運用文書 | 新バージョン検出→PR→試験→レビュー→リリースが手順通り進む |

全体の目安：**約 4–7 週間**。相互に並行化できる作業あり。初週に P0/P1 の主要部分を優先し、更新作業を先行させない。

## 4. 変更検知テストの設計（P1 の最重要成果物）

「現行動作の契約（変更したら気づく）」と「安全性の契約（満たさなければならない）」を区別する。

| ID | 種別 | 優先 | 試験項目／入力例 | 期待結果と検出対象 | 自動実行 |
|---|---|---|---|---|---|
| C-01 | UT | P0 | `DOMAINS` の標準・複数・ポート指定・リダイレクト・認証・IP 指定（既存 26 ケース分割） | パースしたドメイン・upstream・フラグが契約と一致 | PR 必須 |
| C-02 | UT | P0 | 空値、異常ポート、制御文字、不正な設定構文 | 安全な失敗または明示した扱い（現実装動作をまず調査） | PR 必須 |
| C-03 | UT | P0 | Nginx 80 番設定生成 | HTTP リクエストが正しい HTTPS URL へ `301` | PR 必須 |
| C-04 | UT | P0 | Nginx 443 番設定生成 | server_name、証明書パス、upstream、proxy headers を検証 | PR 必須 |
| C-05 | UT | P0 | Basic 認証・IP 制限・WebSocket・HSTS 設定生成 | オン／オフで指示文が適切に変わる | PR 必須 |
| C-06 | UT | P0 | 証明書の更新要否（時刻・有効期限を固定） | 有効期限・FORCE_RENEW で更新判定が一致 | PR 必須 |
| C-07 | UT | P1 | ACME 署名成功・失敗・タイムアウト（外部 HTTP をスタブ） | 失敗が検出され、既存証明書を壊さない | PR 必須 |
| C-08 | UT | P1 | Nginx 設定 reload／生成失敗 | 不正な設定で旧状態へ戻す／停止など合意した仕様に一致 | PR 必須 |
| I-01 | IT | P0 | `STAGE=local` でコンテナ起動 | ヘルスチェック／HTTPS コンテンツ 200 | PR 必須 |
| I-02 | IT | P0 | HTTP からリクエスト | 301 と Location（パス・クエリ維持） | PR 必須 |
| I-03 | IT | P0 | upstream へのリバースプロキシ | アプリ応答、Host／Forwarded ヘッダー | PR 必須 |
| I-04 | IT | P0 | Basic 認証あり／なし | 401、正しい資格情報では 200 | PR 必須 |
| I-05 | IT | P0 | 証明書提示とホスト名 | 証明書・鍵一致、ホスト名、TLS ポリシーを検証（独立の信頼 CA を使用） | PR 必須 |
| I-06 | IT | P1 | 証明書をボリュームへ保存して再起動 | 起動後に同一証明書が使用される／必要に応じ更新される | PR 必須化の後段 |
| I-07 | IT | P1 | 静的コンテンツ、複数ドメイン、複数 upstream | 意図した内容が指定ドメイン・パスで配信 | PR 必須化の後段 |
| I-08 | IT | P1 | Nginx 設定変更と reload | 正常更新・異常更新の挙動を検証 | PR 必須化の後段 |
| I-09 | IT | P1 | アクセス制限、upstream 障害 | 403／適切な 5xx、復旧で正常化 | PR 必須化の後段 |
| E-01 | ACME-IT | P1 | ローカル ACME テスト CA を利用した新規発行 | ACME HTTP-01→発行→提示まで検証 | 夜間／手動 |
| E-02 | ACME-IT | P1 | 証明書更新・期限切れ・CA 失敗 | 更新検知、失敗時の既存証明書維持 | 夜間／手動 |
| S-01 | セキュリティ | P0 | コンテナ依存の既知脆弱性 | 新規 Critical/High についてポリシーに従って失敗（既存分は期限付き例外） | PR 必須／夜間 |
| S-02 | セキュリティ | P1 | Ruby 静的検査・外部取得物のハッシュ照合 | 既知の重大欠陥、供給元変更・改ざんを検出 | PR 必須 |

### 「本当に変更を検知できる」ことの確認

- 例1：HTTP 301 を 302 に故意に変えて `C-03`／`I-02` が失敗する。
- 例2：`proxy_set_header X-Forwarded-Proto` を外して `C-04`／`I-03` が失敗する。
- 例3：証明書の期限判定を意図的に反転して `C-06` が失敗する。
- この故意の変更は **検証用ブランチだけ** で実施し、本線にマージしない。重要な契約ごとにテストが「壊せる」ことを確認する。
- スナップショットは Nginx 設定全体のバイト一致ではなく、正規化した重要指示文・動作を主判定とする。意図的な安全性改善は仕様更新 PR と同時に期待値を変更する。

## 5. GitHub Actions の最終形

| ジョブ | タイミング | 入力と実行 | マージブロック |
|---|---|---|---|
| `lint-and-unit` | PR / push | Ruby 構文・UT・設定生成の契約試験 | 必須 |
| `docker-smoke` | PR / push | 自己署名 local モード・HTTP/HTTPS・プロキシ・認証 | 安定後に必須 |
| `security-check` | PR / push | 依存差分・コンテナイメージの脆弱性・秘密情報の誤混入検査 | 重大度ポリシーを満たした段階で必須 |
| `extended-integration` | 夜間 / 手動 | Pebble によるローカル ACME、再起動、永続化、失敗復旧、構成変更 | 夜間通知／リリース前必須 |
| `multiarch-build` | リリース候補 / 手動 | amd64、arm64、arm/v7、386 のビルドと代表アーキの起動 | リリース前必須 |
| `release` | タグ／承認後 | 検証した Docker イメージをレジストリへ公開し SBOM/provenance を生成 | 承認制 |

CI の注意：`pull_request_target` で外部 PR のコードを高権限実行しない。ジョブ権限は最小化し、PR 試験では公開 CA や秘密鍵、レジストリ公開資格情報を使わない。ホストの Docker socket を必要とする auto-discovery テストは隔離・別ジョブ化を検討する。Docker ログには環境変数・Basic 認証文字列が出ないようマスキングする。

初期の `spec/ci/compose.yaml` と `.github/workflows/tests.yml` は導入の足場であり、**現時点の手動スモークだけでは目標のマージゲートを満たさない**。IT ジョブの自動化と検証項目の追加が必要。

## 6. 依存関係の更新方式

### 更新対象台帳（単一の基準表で管理）

| 部品 | 現状の取得方法 | 主な更新手段 | 更新時の重点試験 |
|---|---|---|---|
| Nginx + OS | `ARG DIST=nginx:1.30.2` + `apt-get upgrade` | Docker イメージのバージョンと digest を追跡、脆弱性スキャン | HTTPS、TLS、リダイレクト、Nginx 設定互換 |
| Ruby（実行環境） | コンテナ OS の `apt install ruby` | パッケージ版・ディストリビューション更新の見直し | 証明書処理、設定生成、シェル呼出し |
| Ruby（テスト環境） | `.ruby-version=2.7.2` + `Gemfile.lock` | Bundler のロックファイル更新 | 全 UT／CI 実行互換 |
| RSpec | `Gemfile.lock` 上の RSpec 3.10 系 | Dependabot（Bundler） | 全 UT／IT |
| s6-overlay | Dockerfile `ENV S6_OVERLAY_VERSION` | Renovate regex/custom manager 等（通常の Dependabot 単独では検知不足） | 起動・停止、サービス監視 |
| docker-gen | Dockerfile `ENV DOCKER_GEN_VERSION` | 同上 | Docker ソケット監視、auto-discovery |
| acme-tiny | Dockerfile `ENV ACME_TINY_VERSION` | 同上 | 発行・更新・エラー復旧 |
| GitHub Actions | `.github/workflows/*.yml` | Dependabot（GitHub Actions） | CI の成立、権限設定 |

**重要な仕様上の注意：** GitHub 公式ドキュメントでは、Dockerfile の `ARG` から指定したイメージ参照を Dependabot が更新しない制限が説明されている。現在の `ARG DIST` は、このままでは「更新 PR が来るはず」という運用にできない。対応策は、(A) Nginx ベースイメージを Dependabot が追える直接 `FROM` に整理する、または (B) Renovate の customManagers/regex 管理等で `ARG DIST` や各 `ENV` を監視する、のどちらかを選ぶ。

推奨：まず Dependabot を Bundler／GitHub Actions に使い、Dockerfile の追跡漏れを解消する方針を P0 で決める。更新箇所を一括して扱いたいなら Renovate に寄せる。**両方を同じ依存対象へ重複設定しない。**

リリースアーカイブの `wget` は取得元バージョン固定だけでなく SHA-256 の検証を加える。イメージ digest・ロックファイル・SBOM をリリース記録に含める。

### 自動更新の運用ルール（提案）

- セキュリティアラート：毎日確認。Critical の修正候補は原則 1 営業日以内に一次判断、High は原則 3 営業日以内（担当・利用状況に応じ調整）。
- 通常更新：週次 PR。バージョンをまとめすぎず、**1 PR = 1 主要コンポーネント変更**を基本とする。
- 自動マージ：最初は使わない。テストと影響差分をレビューしてマージ。運用実績ができたらパッチ版等を条件付きで検討。
- 既存の既知脆弱性は初回で一覧化し、重大度・到達可能性・期限付きの例外を承認して管理。既存問題を隠すために全スキャンを無効化しない。
- リリース：テストされたコミット・イメージ digest を記録し、直前の検証済み digest へ戻せるようにする。証明書ボリュームのデータ移行／バックアップの復旧も対象。

## 7. 実装 PR の推奨順序

| PR | 内容 | 大まかな差分 | 検証／レビュー要件 |
|---|---|---|---|
| PR-01 | 基準とテスト仕様を確定 | `docs/test-plan-ja.md`、現行 13 ケースの実行結果、失敗一覧 | 現状と将来要件を区分して合意 |
| PR-02 | UT 独立化・契約試験 | `spec/models`、`spec/config`、`spec/certs`、Docker 起動を必要としない helper | PR で短時間に安定実行 |
| PR-03 | CI 最小版をマージ必須に | `.github/workflows/tests.yml`、Ruby / Bundler 調整 | UT の成功でのみマージ可 |
| PR-04 | Docker IT のモダン化 | Compose V2、`docker-machine` 排除、内部テスト用ドメイン、isolated volume、timeout | 再実行で安定・外部 ACME 不要 |
| PR-05 | Docker 重要契約とセキュリティ試験 | リダイレクト、HTTPS、Basic 認証、proxy、証明書検証 | 必要な IT を PR 必須化 |
| PR-06 | 脆弱性・依存更新の導入 | scanner、Dependabot/Renovate、依存台帳 | 依存変更 PR が自動作成される |
| PR-07 | Nginx + OS 更新 | Dockerfile 等 | CI、脆弱性差分、互換性確認 |
| PR-08 | Ruby / RSpec 更新 | Dockerfile、`.ruby-version`、`Gemfile.lock` | UT・IT、Ruby 互換性 |
| PR-09 | s6-overlay 更新 | Dockerfile、起動試験 | 起動・停止・リロード・ログの検証 |
| PR-10 | docker-gen 更新 | Dockerfile、auto-discovery の隔離 IT | Docker socket 使用形態のレビュー |
| PR-11 | acme-tiny 更新 | Dockerfile、ACME fake CA 試験 | 発行・更新・失敗時の復旧確認 |
| PR-12 | リリース安全化 | multi-arch build、SBOM/provenance、承認・ロールバック Runbook | release dry-run 成功 |

安全性改善に伴う「従来仕様からの意図的変更」は、独立 PR として変更理由・互換性影響・移行手順・テスト期待値の更新をレビューする。

## 8. 最終的な Done の定義

- [ ] 変更検知テストの代表 3 箇所で意図的な変更を検出した証跡がある
- [ ] UT／構成生成試験が PR 時に自動実行・必須チェックになっている
- [ ] 最重要 Docker IT（HTTPS、HTTP リダイレクト、proxy、認証、証明書）が PR 時に必須実行される
- [ ] テストは公開 ACME 本番環境に依存せず、再試行・タイムアウト・独立性が設計されている
- [ ] 重要な依存関係すべてが「何で更新を検出できるか」台帳に記載されている
- [ ] 自動依存更新の実 PR を 1 件通し、テストとレビューを経てマージした
- [ ] リリース候補イメージの脆弱性結果と SBOM が保存されている
- [ ] 直前の検証済みバージョンへ戻す手順が演習済み
- [ ] 変更・レビュー・マージ・リリース時の責任分界が文書化されている

## 9. 一次情報・参考

- ソース：提供された `https-portal-master.zip` 中の `Dockerfile`、`Gemfile.lock`、`spec/`、`fs_overlay`、`Makefile`
- GitHub Dependabot の構成：https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/secure-your-dependencies/configure-version-updates
- Dockerfile の ARG 等に関する Dependabot の制約：https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/manage-your-dependency-security/configure-private-registries
- GitHub Actions 安全な利用：https://docs.github.com/ja/actions/reference/security/secure-use
- GitHub ブランチ保護・必須チェック：https://docs.github.com/ja/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches
- GitHub CodeQL（Ruby 対応）：https://docs.github.com/ja/code-security/concepts/code-scanning/codeql/codeql-code-scanning
- Docker の SBOM・provenance：https://docs.docker.com/build/metadata/attestations/
- ACME テスト CA（Pebble）：https://github.com/letsencrypt/pebble
