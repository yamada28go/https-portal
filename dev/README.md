# HTTPS-PORTAL 開発環境

Dockerfile、Compose、操作スクリプト、開発環境ドキュメントをこのディレクトリにまとめています。

プロジェクトルートのPowerShellから実行します。

```powershell
.\dev\dev.ps1 Setup
.\dev\dev.ps1 Login
.\dev\dev.ps1 Codex
```

- [操作手順](docs/development-environment-ja.md)
- [検証記録](docs/development-environment-verification-ja.md)
- [構築計画](docs/https-portal-dev-environment-plan-ja.md)

Composeは親ディレクトリのプロジェクト全体を/workspaceに共有します。Ruby依存のGemfileとGemfile.lock、P1テスト計画はプロジェクト本来の場所に置きます。
