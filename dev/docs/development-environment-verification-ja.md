# Docker開発環境：検証記録

実施日：2026-10-24（日本時間）

## 結果

**設定ファイルと手順は作成済み。実ビルド・コンテナ起動・RSpec・Codex認証は未確認。** このチャットの実行環境はDocker Desktopの名前付きパイプへの接続が拒否される。ファイルシステム権限とネットワーク権限を取得しても同じ結果だった。パイプを追加権限として指定する試みも、権限ツールがパスを表現できず失敗した。利用者の通常PowerShellでの動作とは区別する。

## 実施済み

| 確認 | 結果 |
|---|---|
| 元のGit状態 | docs/が未追跡。既存のソース変更なし。既存docsは保持 |
| Docker CLI | 29.9.2、windows/amd64、context desktop-linux |
| Compose CLI | v5.6.1 |
| Compose構文 | docker compose -f dev/compose.dev.yaml config --quiet 成功 |
| PowerShell構文 | System.Management.Automation.Language.Parserでdev.ps1を確認、エラーなし |
| Codex配布メタデータ | npm registryの@openai/codexは0.164.0、Node要件>=16。採用は固定したNode 22.14.0 |
| ベースイメージ | Docker RegistryにRuby/Nodeタグの存在を確認しmanifest digestを取得・固定 |
| Gemfile.lock差分 | PLATFORMSにrubyを1行追加。Gemバージョンは変更なし |
| Compose隔離設定 | 展開した設定でtestのnetwork none、UID1000、Gem読み取り専用、Codex認証非共有、ソケット・公開ポート・特権なしを確認 |
| ファイル確認 | シェルスクリプトはUTF-8 BOMなし・LF。git diff --check成功 |
| ホストへの依存導入 | Ruby、Bundler、Gem、Node、Codexをホストに追加インストールしていない |

Ruby digest: sha256:1dd0106849233fcd913b7c4608078fa1a53a5e3ce1af2a55e4d726b0d8868e2f

Node digest: sha256:73a9dfbb6c761aebdf4666cce2627635a30d1d4c20f67ff642d01b8f09e709a3

取得時のregistry tokenはファイルやログに保存していない。

## 未確認の項目

- [ ] イメージのビルドとRuby/Node/Codexの実起動、共有ライブラリ互換性。
- [ ] named volumeの初回所有権、非rootによる書き込み。
- [ ] lock固定でのGem導入、ネットワークなしの既存RSpec成功。
- [ ] Codexのdevice code認証、編集、Linuxサンドボックスの互換性。
- [ ] コンテナ再作成後のGem・認証・設定保持。

## 次に実行する操作

利用者のPowerShellでプロジェクトへ移動し、以下を実行する。

```powershell
.\dev\dev.ps1 Setup
.\dev\dev.ps1 Login
.\dev\dev.ps1 Codex
```

Setupが成功したら、日付・バージョン出力・テストの件数と結果をこの記録に追記する。Loginは利用者本人によるブラウザ操作が必要。

その後、VerifyとRecreateで権限・テスト・再作成を確認する。P1の54件追加はこの環境検証完了後に実施する。

## dev配下への集約（2026-10-24）

Compose、PowerShell、開発環境計画・手順・検証記録、改行設定をdev配下に集約。Composeのbuild contextはdev自身、bind mount元は親のプロジェクトルートに修正した。

移動後のCompose構文、PowerShell構文、展開されたbuild contextと両サービスのbind mount元、GitのLF指定、git diff --checkを確認し成功した。実ビルドは引き続き未確認。
