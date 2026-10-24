# HTTPS-PORTAL 開発環境

Dockerfile、Compose、操作スクリプト、開発環境ドキュメントをこのディレクトリにまとめています。

プロジェクトルートのPowerShellから実行します。

```powershell
.\dev\dev.ps1 Setup
.\dev\dev.ps1 Login
.\dev\dev.ps1 Codex
```

- [文書一覧・読む順番](docs/00-index-ja.md)
- [操作手順](docs/20-dev-environment/21-guide-ja.md)
- [検証記録](docs/20-dev-environment/22-verification-ja.md)
- [構築計画](docs/20-dev-environment/20-plan-ja.md)

Composeは親ディレクトリのプロジェクト全体を/workspaceに共有します。Ruby依存のGemfileとGemfile.lock、P1テスト計画はプロジェクト本来の場所に置きます。

P1の113例：`.\dev\dev.ps1 Test`。順序変更・単独実行・Mutation検証：`.\dev\dev.ps1 P1`。

P2-01の最小Ruby環境：`.\dev\check_p2_baseline.ps1`。[実行と検証条件](../spec/ci/README.md)を参照。

## Docker試験基盤（P2-03）

プロジェクトルートで `.\dev\check_p2_integration.ps1 -Repeat 2`。[実行・受入手順](docs/30-p2-ci/34-integration-guide-ja.md)を参照。実Dockerの起動確認は利用者側で行う。

P2-04の重要契約を一括実行：`.\dev\check_p2_integration.ps1 -Scenario all`。[試験内容・受入手順](docs/30-p2-ci/35-integration-contracts-ja.md)を参照。実Dockerの実行受入は利用者側で行う。
