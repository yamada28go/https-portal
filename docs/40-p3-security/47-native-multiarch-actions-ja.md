# 47 amd64／arm64のネイティブActions実行

[文書一覧](../00-index-ja.md) / [P3検証記録](42-verification-ja.md) / [件数バッジ](46-security-count-badges-ja.md)

## 対象

従来はubuntu-24.04のamd64だけだった。TestsとSecurity reportを次のmatrixへ変更した。

| CPU | Docker platform | GitHub runner |
|---|---|---|
| amd64（x86-64） | linux/amd64 | ubuntu-24.04 |
| arm64（64bit ARM） | linux/arm64 | ubuntu-24.04-arm |

UT（lint-and-unit）、全13シナリオの結合試験（docker-smoke）、製品build・脆弱性検査・SBOM収集（security-report）を、各CPUで独立に実行する。fail-fast:falseにより片側失敗でも他方の検証を打ち切らない。arm/v7等の32bit ARMは今回対象外。QEMUを設定していない。

本体Dockerfile・fs_overlayや製品バージョンは変更しない。テスト用Ruby 2.7.2、Trivy 0.76.1、既存のdigestも維持する。Docker Hubの公式manifest応答のSHA-256を照合し、固定Ruby/Trivyと現在のNginx 1.30.2がlinux/amd64とlinux/arm64を含むことを確認した。

## CPUの確認

各ジョブの開始時にdev/check_ci_platform_contracts.ps1とdev/check_ci_platform.ps1を実行する。OS CPU、PowerShellプロセスCPU、RUNNER_ARCH、Docker EngineのCPUとLinux OSをmatrixのCI_EXPECTED_ARCHへ照合する。別CPUを指定するDOCKER_DEFAULT_PLATFORMは拒否する。

UT/結合試験/セキュリティの各image inspectでもCI_EXPECTED_ARCHを照合する。製品だけでなくunit/tools/scannerが誤ったCPUなら停止する。CI_EXPECTED_ARCHのない通常ローカル実行では既存のprepared-image等の動作を維持する。

## 成果物とサマリー

成果物名へamd64またはarm64を含め、同名uploadによる衝突を避ける。

- unit-test-evidence-<arch>-<run id>-<attempt>
- integration-test-evidence-<arch>-<run id>-<attempt>
- security-evidence-<arch>-<run id>-<attempt>

サマリーの脆弱性件数・イメージID・SBOMはCPU別に確認する。同じソースでもOSパッケージや実バイナリ、検出結果が同じとは限らない。結合試験ではresult.jsonのimagePlatforms、UTではhost-run.jsonのimagePlatform、securityではresult.jsonのimagePlatformも確認する。

## 件数バッジ

既存のREADME件数バッジはamd64を基準として維持し、Critical (amd64)/High (amd64)と表示する。arm64のJSONもCPU情報付きで成果物へ保存する。両CPUの件数を合算したり、後に終了したmatrixの値で上書きしたりしない。

matrix jobの共通outputに件数を載せる方式は廃止。publish-count-badgesは両CPUのsecurity-report成功を待ち、固定SHAの公式actions/download-artifact v8で同じrun/attemptのamd64成果物だけを取得し、最新metadataが1個であることを要求する。生成データにはarchitectureを含め、arm64データからamd64公開バッジへの更新は拒否する。既存の公開済みmetadata（architectureなし）は履歴として読める。

公開ジョブだけcontents:writeとactions:read。PR/tag/生成データbranchの公開禁止、実行元branch自動取得、HEAD照合・古いrun拒否は維持する。ダウンロードした成果物はJSONとして検証するだけで、その中のプログラムを実行しない。

## 受入手順

変更をcommit/push後、次を確認する。

1. Testsのlint-and-unit (amd64)/(arm64)、docker-smoke (amd64)/(arm64)が全件成功。
2. security-report (amd64)/(arm64)が成功し、scan/SBOM/image ID/DB/cleanupが各CPUで対応する。
3. unit/integration/securityのCPU別成果物が計6件生成されている。
4. pushではpublish-count-badgesが成功し、latest.jsonがarchitecture=amd64で当該runを指す。READMEにamd64件数が表示される。
5. PRでは両CPUの検査は実行し、公開ジョブはskipされる。

必須チェックを設定する場合は、CPU付きの4個のUT/ITチェック名とセキュリティ側のチェック名を選択する。今回repositoryの保護規則は変更していない。

## 実装検証の範囲

ローカルでCPU判定10件、件数バッジ29件、既存セキュリティ契約35件が成功。PowerShell 7/5.1構文と両workflowのactionlintも成功。公式manifestによるCPU対応確認はimageの実build/起動成功とは区別する。今回のホストではネイティブARM runnerを起動しておらず、Actions上の実行受入はpush後に確認する。

一次資料：[GitHub runner一覧](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)、[Ubuntu ARM64の搭載ソフトウェア](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Arm64-Readme.md)、[upload-artifactのmatrix名要件](https://github.com/actions/upload-artifact)、[download-artifact固定版](https://github.com/actions/download-artifact/tree/9000827ccba6bdab643e8b6fd33ac0654aef8333)。
