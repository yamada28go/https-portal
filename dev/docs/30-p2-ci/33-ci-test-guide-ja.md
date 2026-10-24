# GitHub Actions：単体テストの実行・確認

用途：P2-02で追加したCIの操作と受入手順。

[文書一覧](../00-index-ja.md) / [検証記録](32-verification-ja.md) / [P2実施手順](30-execution-guide-ja.md)

## 実装状態

workflowとLinux対応を実装し、actionlintとPowerShell構文検査に成功した。Run ID 40068897258でpush自動起動・lint-and-unit成功・artifact保存を確認済み。PR・手動起動・故意変更での失敗と復元は未確認のため、P2-02の全受入完了とはしていない。詳細は検証記録を参照する。

## 実行される内容

| 項目 | 内容 |
|---|---|
| ファイル | .github/workflows/tests.yml |
| workflow / job | Tests / lint-and-unit |
| 起動 | 全branchのpush、pull_request、workflow_dispatch。path filterなし |
| runner | ubuntu-24.04、ジョブ上限20分 |
| 共通入口 | dev/check_p2_baseline.ps1。ローカルと同じ最小Ruby環境を使用 |
| 検証 | Ruby構文、113例の3 seed、9ファイル単独、M01〜M08検知・復元、復元後113例、入力不変 |
| 隔離 | Git調査・試験はDocker内。network none、UID1000、read-only rootfs、ソースは読み取り専用、試験は一時コピー |
| ビルド | Rubyイメージ・OSパッケージ・固定Gemの取得で外部通信が発生する |
| 権限 | contents: read、checkoutの資格情報保存なし、PRコードへ秘密情報を渡さない |
| 並行制御 | 同じevent・PR/branchの旧実行をcancelする |
| 公開 | イメージpush・公開DNS変更・公開ACME発行を行わない |

UbuntuのホストUIDとコンテナUIDが異なるため、各実行専用の結果ディレクトリだけchmod 0777にする。ソースの権限は変更しない。Windows側ではこの処理を行わない。

checkout v7.0.1とupload-artifact v7.0.2は、公式releaseとcommitを照合して完全SHAで固定した。採用時点は2026-10-24。[checkoutの公式release](https://github.com/actions/checkout/releases/tag/v7.0.1)、[upload-artifactの公式release](https://github.com/actions/upload-artifact/releases/tag/v7.0.2)を参照。

## 最初の実行

1. 差分をレビューし、workflow・共通スクリプト・関連文書をcommitして作業branchへpushする。pushだけでTestsが起動する。
2. GitHubのActionsからTestsを開き、対象commit・eventとlint-and-unitの状態を確認する。
3. PRを作成または更新し、PR上でもlint-and-unitが自動起動して成功することを確認する。
4. 手動実行はworkflowがデフォルトbranchに存在する状態で、ActionsのRun workflowから対象branchを選ぶ。詳細は[GitHubのworkflow_dispatch仕様](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#onworkflow_dispatch)を参照。
5. 実行URL、event、対象commit、run/attempt、成否、artifact名を検証記録へ追記する。個人名・所有者名を含むURLを公開文書に転記する場合は匿名化する。

PRではcheckoutの既定動作によりPRのmerge commitを検証する。ローカルのbranch先端と同じSHAとは限らない。host-run.jsonのexpectedShaとbaseline.jsonのheadで実対象を確認する。

## 結果とログ

成功時はP2-01 baseline passedと表示し、host-run.json・baseline.jsonのresultはpassedになる。Mutationのdetectedで「1 failure」が出るのは期待した検知であり、全体成功時は異常ではない。

Actionsの実行画面から、unit-test-evidence-<run ID>-<attempt>というartifactを取得する。保存期間は14日。

| ファイル | 用途 |
|---|---|
| console.log | Docker buildと検証の出力 |
| host-run.json | Docker起動側のstage・成否、GitHub event/run/attempt/expectedSha、image ID |
| baseline.json | コンテナ内のHEAD・差分・入力fingerprint・stage・成否 |
| inputs.sha256 | 実行入力のハッシュ一覧 |
| p1-check.log | seed・単独実行・Mutation・復元後の詳細 |

uploadは試験の成否にかかわらず試行する。build前の失敗ではbaseline.jsonやp1-check.logがない場合がある。強制cancel・runner喪失では全ログが残らない場合がある。診断工程で元のテスト失敗を成功扱いにしない。

artifactの対象は上記5種類のみ。Git管理情報・ソース全体・秘密鍵・認証volumeはアップロードしない。プロジェクト内の秘密ファイルをログへ出力する変更は加えない。

## 故意変更で失敗を確認する

1. 受入検証専用のbranchで、fs_overlay/var/lib/nginx-conf/default.conf.erbのHTTP 301を302へ一時変更する。テスト期待値は変更しない。
2. pushし、lint-and-unitが失敗すること、artifactにH01等の失敗理由があることを確認する。
3. 301へ戻してpushし、成功へ戻ることを確認する。検証用の変更は本線へmergeしない。
4. 失敗・復元成功の両runを記録する。CI内のM01検知と、workflow全体が赤になる確認は区別する。

## P2-02の完了条件

- [x] Tests / lint-and-unitを実装
- [x] 完全SHA固定、最小権限、timeout、ログ保存を設定
- [x] actionlint・PowerShell構文・差分チェックを実施
- [x] pushで自動起動と成功を確認（Run ID 40068897258）
- [ ] PRで自動起動と成功を確認
- [ ] 手動起動を確認
- [ ] 故意変更でジョブ失敗・診断artifactを確認
- [ ] 復元後に成功することを確認し、runを記録

マージ必須チェック設定と5回連続成功はP2-05。P2-02ではdocker-smoke・脆弱性検査・依存更新を追加しない。
