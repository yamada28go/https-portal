# Docker開発環境の使い方

作成日：2026-10-24。実装状況は [検証記録](development-environment-verification-ja.md) を参照。

WindowsにRuby・Gem・Node.jsを導入せず、専用コンテナでCodex CLIとRSpecを使う。製品用Dockerfileとは独立した開発環境。

## 初回構築

Docker Desktopを起動し、Linux containersを使用する。PowerShellで次を実行する。

```powershell
# https-portalのプロジェクトルートで実行
git status --short
.\dev\dev.ps1 Setup
```

SetupはCompose設定検証、Engine接続・Linux確認、ビルド、起動、バージョン表示、lock固定でのGem導入、P1の54例を順に行う。失敗時はその場で停止する。Codexログインは別工程。既存の変更をコミット・破棄する処理は行わない。

PowerShellの実行ポリシーでps1が拒否された場合、組織のポリシーに従う。スクリプトを使わない場合は以下の直接コマンドでも実施できる。

```powershell
docker compose -p https-portal-dev -f dev/compose.dev.yaml config --quiet
docker compose -p https-portal-dev -f dev/compose.dev.yaml build dev
docker compose -p https-portal-dev -f dev/compose.dev.yaml up -d dev
docker compose -p https-portal-dev -f dev/compose.dev.yaml exec -T dev dev-versions
docker compose -p https-portal-dev -f dev/compose.dev.yaml exec -T dev bundle _2.2.4_ install --frozen
docker compose -p https-portal-dev -f dev/compose.dev.yaml run --rm test
```

## Codexログインと起動

```powershell
.\dev\dev.ps1 Login
.\dev\dev.ps1 Codex
```

Loginで表示されるURLをWindowsのブラウザで開き、利用者本人が認証する。device codeログインはアカウントやワークスペースで許可されている必要がある。認証コードやトークンはチャットやGitへ貼らない。

Codexはworkspace-write、on-request承認で起動する。Docker内でLinuxサンドボックスが動かない場合、エラーを確認し、特権モードやDockerソケット追加で回避しない。

コンテナを唯一の隔離境界とする代替操作は次のとおり。自動的には切り替えない。この操作では共有プロジェクトを含むコンテナ内と、利用可能な認証情報へのアクセスが広がる。

```powershell
docker compose -p https-portal-dev -f dev/compose.dev.yaml exec dev codex --sandbox danger-full-access --ask-for-approval on-request
```

認証情報・履歴・設定は専用named volumeの/home/dev/.codexに保存する。ホストの既存Codex認証ディレクトリは共有しない。ボリュームやDockerデータの削除時には消失する。サインアウトはコンテナ内のcodex logoutで行う。

## 日常操作

```powershell
# コンテナ内Bash
.\dev\dev.ps1 Shell

# P1の54例（ドメイン解析26、Nginx設定20、更新判定8）
.\dev\dev.ps1 Test

# バージョン、共有領域の書込権限、ソケット非共有、P1テストを確認
.\dev\dev.ps1 Verify

# コンテナ再作成とGem保持・テストの確認
.\dev\dev.ps1 Recreate

# 停止・コンテナ削除。named volumeは保持
.\dev\dev.ps1 Stop
```

Stop後の起動は次を使う。イメージ変更後はSetupを再実行する。

```powershell
docker compose -p https-portal-dev -f dev/compose.dev.yaml up -d dev
```

P1のUTは次の直接コマンドでも実行できる。54例の対応は[テスト対応表](../../docs/test-contract-matrix-ja.md)を参照。

```powershell
docker compose -p https-portal-dev -f dev/compose.dev.yaml run --rm test bundle exec rspec spec/models/domain_spec.rb spec/contracts --format documentation
```

テスト対象を指定せず全スイートを実行すると、既存のDocker機能テストも含まれる。P1は必ず対象パスを指定する。SKIP_BUILD=1は両サービスに設定済み。

## 保存場所と境界

| 対象 | 保存先 |
|---|---|
| ソース・編集結果 | ホストのプロジェクトと/workspaceをbind mount |
| Gem | https-portal-dev_gemsボリューム → /bundle |
| Codex認証・設定・履歴 | https-portal-dev_codexボリューム → /home/dev/.codex |
| 一時Bundler設定 | コンテナの/tmp。ホストに.bundle/configは作らない |
| 開発イメージ | https-portal-dev:ruby2.7.2-codex0.164.0 |

testにはCodex volumeを渡さず、Gem volumeを読み取り専用、ネットワークをnoneにする。作業ユーザーはUID/GID 1000。privileged、host network、Dockerソケット、公開ポートは使用しない。devはCodex等のため外向き通信が可能で、送信先のallowlistは設定していない。

プロジェクト内の編集・削除はホストにも反映される。Git差分を確認して作業する。プロジェクト配下の秘密ファイルはコンテナからも読める。コンテナは完全な隔離を保証するものではない。

## 固定バージョンと制約

- Ruby 2.7.2、Bundler 2.2.4、既存RSpec 3.10系を維持。
- Node.js 22.14.0、Codex CLI 0.164.0を固定。
- Ruby・NodeベースはDockerfileにmanifest digestを固定。
- Gemfile.lockには純Ruby GemをLinuxでも使うためruby platformを追加。Gemバージョンは変更していない。
- RubyベースのDebian Busterは古いため、署名付きDebian archiveからパッケージを取得する。署名/TLS検証は無効化しない。有効期限確認のみarchiveのためupdateコマンド単位で無効化。
- Nodeのバイナリ互換性、Codexの実起動はビルド中にバージョン表示で検査する。ビルド未実施の状態では互換性確認済みとはしない。
- 公開サービス用途には使用しない。依存更新はP1と別の作業として管理する。

## トラブル対応

| 症状 | 対応 |
|---|---|
| Engineへのpermission denied | 利用者のPowerShellでdocker versionを確認。Desktopの起動状態、Linux containers、利用者・組織のアクセス権を確認。Dockerfileを変更する問題ではない |
| イメージ取得・archive失敗 | ネットワーク、プロキシ、証明書、公式配布元を確認。TLS/署名検証を無効化しない |
| /bundleや.codexへ書けない | ボリュームの所有者を確認。標準は空のボリュームへイメージのUID1000のディレクトリをコピーする。既存データを削除する前に保持内容を確認 |
| npm、node、codexのビルド時失敗 | Ruby/Nodeベースのライブラリ互換性や配布物を調査。RubyやRSpecをまとめて更新しない |
| bundle install --frozen失敗 | Gemfile/lock差分とplatformを確認。bundle updateで回避しない |
| device code認証が不可 | アカウント・管理設定とOpenAI公式の認証代替手段を確認。既存ホストのホーム全体はマウントしない |

通常停止にdown -vを使わない。GemとCodexのボリューム削除は認証・履歴・依存を消す明示的な初期化作業として扱う。

## 公式資料

- [Codex CLI](https://learn.chatgpt.com/docs/codex/cli)
- [Codex認証](https://learn.chatgpt.com/docs/auth)
- [権限とDev Containers](https://learn.chatgpt.com/docs/agent-approvals-security#run-codex-in-dev-containers)
- [Docker bind mounts](https://docs.docker.com/engine/storage/bind-mounts/)

## P1の順序変更・Mutation検証

```powershell
.\dev\dev.ps1 P1
```

構文、54例の3 seed、各spec単独、M01〜M05の検知と復元を検査する。証跡はdev/test-results/p1-check.log（Git対象外）。Mutationは一時コピー上で行い、元の製品コードは変更しない。詳細は[Mutation手順](../../docs/mutation-check-ja.md)を参照。
