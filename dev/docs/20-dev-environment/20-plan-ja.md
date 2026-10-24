# HTTPS-PORTAL：Docker開発環境構築計画

用途：開発環境の計画・操作・検証。最新結果は検証記録の先頭を参照。  
[文書一覧](../00-index-ja.md) / [操作手順](21-guide-ja.md) / [検証記録](22-verification-ja.md)

作成日：2026-10-24（日本時間）  
ステータス：構築前の計画。コマンドは実施予定であり、検証済みの記録ではない。  
対象：`https-portal`のプロジェクトルート  
関連：`docs/https-portal-p1-detailed-test-plan-ja.md`

## 1. 目的と範囲

WindowsにRuby、Bundler、Gem、Node.js、Codex CLIを追加インストールせず、専用Linuxコンテナ内で編集・テストする。WindowsではDocker Desktop、PowerShell、ブラウザと既存エディタを使用する。Dockerイメージ、キャッシュ、ボリュームはPCのディスクを使用する。

今回の完了範囲は、開発イメージの構築、Codex認証・起動、既存ドメイン解析テストの成功、環境の再作成と手順整備。P1の54例追加、Mutation試験、製品イメージのビルド、既存Docker機能テスト、証明書発行は後続作業とする。

## 2. 確認済みの現状

| 項目 | 現状・対応 |
|---|---|
| ホスト | docker.exeとwsl.exeは存在。Docker Engineの稼働、Linuxコンテナ利用可否は未確認 |
| WSL | このチャットからの状態確認はWsl/E_ACCESSDENIED。未導入や故障とは断定しない |
| WindowsのRuby | 調査時のPATHからは未検出。新規導入しない |
| Ruby | .ruby-versionは2.7.2 |
| Gem | RSpec 3.10系、Bundler 2.2.4。lockのplatformはarm64-darwin-20のみ |
| テスト | ドメイン解析26入力を1例に集約。spec/contractsは未作成 |
| spec_helper | SKIP_BUILD未指定でDockerビルド。対象パス限定とSKIP_BUILD=1を併用する |
| 製品用Dockerfile | Nginx・s6・ACME等を構築する用途。開発環境に流用しない |
| .dockerignore | spec/、Gemfile、Gemfile.lock等を除外。開発用ビルドコンテキストを別に用意する |
| Git状態 | このチャットからのgit statusは権限制約で未確認。構築前に既存変更を確認・保護する |

## 3. 採用構成

```text
Windows / Docker Desktop（Linux containers）
  └ Composeプロジェクト https-portal-dev
      ├ devサービス：非rootユーザーdev
      │   ├ Ruby / Bundler / RSpec / Git / Bash / ripgrep
      │   ├ Node.js / Codex CLI / CA証明書
      │   ├ /workspace ← https-portalだけを読み書き共有
      │   ├ /bundle ← Gem専用named volume
      │   └ /home/dev/.codex ← Codex専用named volume
      └ testサービス：同じ開発イメージ、network_mode: none
          ├ /workspace ← 同じプロジェクト
          └ /bundle ← 同じGemを読み取り専用で共有
```

Dockerは開発環境を提供する箱として利用し、P1のRSpecからDockerコマンドは呼ばない。この意味でP1計画の「Dockerに依存しないテスト」と両立する。

Docker DesktopのLinuxバックエンドを使い、PowerShellからComposeを操作する。WSL2バックエンドを選ぶ場合も、利用者向けUbuntuやWSL内へのRuby導入は必須にしない。

ホストのホーム全体、Documents全体、SSH鍵、クラウド認証、既存の.codexは共有しない。共有プロジェクト内に秘密情報があればコンテナからも読めるため、開始時に確認する。

## 4. バージョン・依存の方針

1. Ruby 2.7.2、Bundler 2.2.4、lock準拠のGemで再現を試みる。古いRuby環境を公開サービスには使わない。
2. 古いRubyイメージの取得、OSパッケージ配布元、CPUアーキテクチャ、CA/TLSを事前検証する。TLS検証無効化で回避しない。
3. Node.jsとCodex CLIは構築時に公式要件を確認し、動く具体的バージョンを固定する。最終設定にlatestを残さず、ベースイメージdigestも記録する。
4. Nodeを別イメージから導入する場合、実行ライブラリとの互換性を確認する。単純なバイナリコピーで動くとは仮定しない。
5. Linuxのplatform追加が必要なら、依存Gemバージョンを維持してGemfile.lockを調整し、差分を確認する。bundle updateやRSpec更新を混ぜない。
6. bundle installはプロジェクトをマウントした構築段階で実施し、Gemは/bundleに保存する。vendor/bundleやホスト側の.bundle/configを作らない設定にする。
7. Ruby基準を維持できなければ阻害要因と代替案を記録する。Ruby更新はP1とは別の判断事項とし、環境構築の都合で変更しない。

## 5. 作成・変更予定ファイル

| ファイル | 内容 |
|---|---|
| dev/Dockerfile | 開発専用ツールと非rootユーザー。製品用Dockerfileとは独立 |
| dev/.dockerignore | 小さい開発用コンテキストの不要物除外 |
| dev/dev.ps1 | PowerShellから構築・認証・テスト等を操作 |
| dev/entrypoint.sh | 最小初期化と権限確認。起動時の自動更新・Gem導入は行わない |
| dev/compose.dev.yaml | dev/test、マウント、named volume、ネットワーク設定 |
| dev/.gitattributes | 既存設定を確認し、追加シェルスクリプトだけLF改行を指定 |
| dev/docs/20-dev-environment/21-guide-ja.md | 初回構築、日常操作、認証、再構築、障害対応 |
| dev/docs/20-dev-environment/22-verification-ja.md | 実測バージョン、結果、所要時間、残課題 |
| Gemfile.lock（必要時のみ） | Linux platform対応。依存バージョンを維持 |

build contextはComposeファイルと同じdevディレクトリ（context: .）とし、プロジェクト全体や認証情報をイメージへCOPYしない。既存.dockerignoreは変更しない。製品ソース、製品用Dockerfile、本番設定、Makefileは環境構築のために変更しない。

VS Code Dev Containersは後から追加可能。初期構築はComposeとCLIに絞る。

## 6. 隔離・権限・認証

- 日常作業は非root。ツール導入と書き込み先の準備はビルド時に行い、空のnamed volumeでも非rootで書けることを確認する。
- privileged、Dockerソケット、host network、ホストPID名前空間、ポート公開を使わない。P1にDocker CLIは不要。
- Codexは通常のworkspace-writeとon-request承認を第一候補にし、コンテナ内でサンドボックスが動くか実測する。
- 内側のLinuxサンドボックスが動かない場合、無条件に特権を追加しない。必要設定を調査し、コンテナを外側の隔離境界として使う代替案も記録する。その代替ではdanger-full-accessとon-request承認を組み合わせ、共有プロジェクトを含むコンテナ内に広い権限があることを明示する。yoloを標準手順にしない。
- Codex認証・設定・履歴は専用volumeに保存する。認証情報をDockerfile、イメージレイヤー、Compose、Git、ログに埋め込まない。
- devはCodex利用とGem導入に外向き通信が必要。通常のDockerネットワークは送信先制限ではなく、LANにも到達し得る。厳密な送信先制御には別途プロキシ等が必要。
- testはnetwork_mode: noneとし、Codex認証volumeも渡さない。通信遮断だけでなく、P1のモック・レビューでDNS/ACME/Docker呼び出しがないことを確認する。
- bind mount内の変更・削除はWindows側に反映される。開始前にGit差分を確認し、作業ブランチで復元可能にする。

## 7. 構築手順

### E01：ホスト確認

PowerShellで実施する。

```powershell
# https-portalのプロジェクトルートで実行
docker version
docker compose version
docker info --format '{{.OSType}}'
git status --short
```

完了条件：Engineに接続でき、OSTypeがlinux、Compose V2を利用でき、既存変更を保護できる。必要なら利用者のPowerShellでwsl --list --verboseを実行し、Docker Desktopのバックエンド状態と実行権限を切り分ける。

### E02：イメージとComposeの実装・起動

第4〜6節に沿ってファイルを実装する。同じimage名をdev/testで使い、test実行時の意図しないpullを避ける。

```powershell
docker compose -p https-portal-dev -f dev/compose.dev.yaml config --quiet
docker compose -p https-portal-dev -f dev/compose.dev.yaml build dev
docker compose -p https-portal-dev -f dev/compose.dev.yaml up -d dev
docker compose -p https-portal-dev -f dev/compose.dev.yaml exec dev bash
```

以下はコンテナ内Bashで実施する。

```bash
id
pwd
ruby --version
bundle --version
node --version
codex --version
git --version
```

完了条件：非root、作業場所/workspace、予定したバージョン。マウントとvolumeへの書き込みが可能。Dockerソケットやホストのホームがマウントされていない。

### E03：Gem依存の準備

ComposeでBUNDLE_PATH=/bundle等を設定し、コンテナ内でbundle installとbundle checkを実行する。必要なら実際のLinux platformをlockへ追加し、Gemバージョン不変を差分で確認する。

完了条件：既存Gemのバージョンを維持して解決でき、Gemがホストのプロジェクト配下に展開されていない。

### E04：Codex認証・編集確認

```bash
codex login --device-auth
codex --sandbox workspace-write --ask-for-approval on-request
```

表示URLをWindowsのブラウザで開き、利用者本人がログインする。device code方式はアカウントやワークスペース設定で有効にできる必要がある。利用できない場合は公式の代替認証方法を選び、必要な公開範囲を個別に設定する。ホストの認証フォルダ全体の共有には切り替えない。

Codexに一時確認ファイルを作成・削除させ、Windowsへの反映とコマンド実行を確認する。サンドボックスに問題があれば第6節の分岐に従う。

完了条件：認証・編集・コマンド実行が成功し、認証情報がプロジェクトやログに出ない。

### E05：既存テストのスモーク確認

PowerShellで実施する。testサービスにSKIP_BUILD=1、BUNDLE_PATH=/bundle、network_mode: noneを設定しておく。

```powershell
docker compose -p https-portal-dev -f dev/compose.dev.yaml run --rm test bundle exec rspec spec/models/domain_spec.rb --format documentation
```

現状は26入力が1例に集約されているため、構築時に54例の成功を期待しない。ネットワーク・Dockerソケットなしで既存解析テストが成功し、意図しない生成物がないことを確認する。失敗時は環境と既存不具合を切り分け、環境構築のために製品動作を変更しない。

P1実装後のコマンドは以下。spec/contractsが存在しない現時点では実行しない。

```powershell
docker compose -p https-portal-dev -f dev/compose.dev.yaml run --rm test bundle exec rspec spec/models/domain_spec.rb spec/contracts --format documentation
```

### E06：再作成と記録

```powershell
docker compose -p https-portal-dev -f dev/compose.dev.yaml down
docker compose -p https-portal-dev -f dev/compose.dev.yaml up -d dev
```

Gemの再ダウンロード不要、Codex設定・認証の保持、テスト再成功を確認する。イメージ再ビルド手順も検証する。通常停止でdown -vを使わない。volume削除は認証・履歴・Gemを消す初期化操作として別途説明する。

## 8. 完了条件

- [ ] WindowsにRuby、Bundler、Gem、Node.js、Codex CLIを追加導入していない。
- [ ] 専用Compose設定でビルド・起動・終了できる。
- [ ] 各ツールの実測バージョンとベースイメージdigestを記録した。
- [ ] 非root、マウント範囲、ポート、Codexサンドボックス方式を確認した。
- [ ] 既存変更を保護し、製品用Dockerfile・製品動作を変更していない。
- [ ] Codex認証、編集、コマンド実行を確認した。
- [ ] 認証情報がGit・イメージ・ログに入っていない。
- [ ] ネットワークなしで既存ドメイン解析テストに成功した。
- [ ] 再作成後もGemとCodex設定・認証を保持し、テストが再成功した。
- [ ] 構築手順・実測・残課題をdev/docsに記録した。

## 9. 工数と後続

ホスト確認0.5〜1時間、イメージ・Compose実装2〜4時間、依存・認証・テスト確認1〜3時間、再作成・手順整備1〜2時間。合計約1〜2営業日を目安とする。古いRubyの配布環境やサンドボックス互換性の問題は追加調査となる。

環境構築完了後にP1のW01〜W09へ進む。P0成果と参照コミットの照合はP1開始条件として別途実施する。P2以降のDocker機能テストは、今回のコンテナにソケットを追加する前提にせず、ホストからの操作や専用実行環境を別途設計する。

## 10. 参照資料

公式資料確認日：2026-10-24。実装時にはCLIオプションと利用要件を再確認する。

- [P1詳細実施計画](../../../docs/https-portal-p1-detailed-test-plan-ja.md)
- [Codex CLI：OpenAI公式](https://learn.chatgpt.com/docs/codex/cli)
- [認証・device code・認証情報保存：OpenAI公式](https://learn.chatgpt.com/docs/auth)
- [Codex権限とDev Containers：OpenAI公式](https://learn.chatgpt.com/docs/agent-approvals-security#run-codex-in-dev-containers)
- [Docker Desktop WSL2バックエンド](https://docs.docker.com/desktop/features/wsl/)
- [Docker bind mounts](https://docs.docker.com/engine/storage/bind-mounts/)
