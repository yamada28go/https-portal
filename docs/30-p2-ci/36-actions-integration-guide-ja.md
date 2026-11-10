# 36 Docker結合試験のGitHub Actions接続

[文書一覧](../00-index-ja.md) / [検証記録](32-verification-ja.md) / [結合試験](35-integration-contracts-ja.md)

## 追加した内容

.github/workflows/tests.ymlのTests workflowにdocker-smokeジョブを追加した。既存lint-and-unitとは独立に実行する。push・pull_request・workflow_dispatchで、ローカルと同じ入口を使用する。

```powershell
./dev/check_p2_integration.ps1 -Scenario all
```

ubuntu-24.04上で製品Dockerfile由来のimageをbuildし、local・redirect・proxy・auth・ca・persistence・renewal・staticの8件を順に検証する。ジョブ上限45分、試験step上限40分、upload上限3分。従来計画のDocker30分は、各buildの上限20分＋10分に加えて試験と診断・cleanupの時間を確保するため調整した。通常のローカル受入は約4分40秒。CI実測後に見直す。

contents: read、checkoutのpersist-credentials: false、既存と同じ完全SHA固定のAction参照を使用する。新たなSecrets設定やregistry loginは不要。

## 通信と後片付け

試験コンテナはinternal networkだけに接続し、公開DNS・公開ACME・外部upstreamへ依存しない。自己署名・試験用CAを使用し、imageの外部公開を行わない。

Actions全体ではソースcheckout・Action取得・build依存物取得・artifact uploadに外部通信がある。試験実行中のコンテナ通信の隔離と、CI全工程の外部通信は区別する。

試験成功・失敗時に共通scriptのfinallyで診断、対象projectだけのdown --volumes、残存検査を実施する。cleanup失敗は全体失敗を維持する。強制cancel・step/job期限切れ・runner喪失ではfinallyやuploadが完了しないことがあり、GitHub-hosted runnerの破棄に委ねられる場合がある。self-hosted runnerをこの構成の受入済み対象にはしない。

## 成果物

integration-test-evidence-<run ID>-<attempt>を成功・失敗後ともuploadし、14日間保存する。

| 対象 | 内容 |
|---|---|
| result.json | 全体・scenarioごとの成否、診断、cleanup、残存、image ID、GitHub event/run/attempt/expectedSha |
| *.stdout.log / *.stderr.log | build、マスク済みCompose設定、probe、サービス診断、公開証明書情報、cleanup |

fixture-*.env、証明書volume、CA秘密鍵、証明書秘密鍵は対象に含めない。表示・保存時に固定の架空Basic資格情報をマスクする既存処理を維持する。PRのexpectedShaは通常PRのmerge commitを指すため、branch先端とは異なる場合がある。

## push後の受入手順

1. 差分を確認し、workflow・共通script・文書をcommitしてpushする。GitHub上の実行確認はpush後に行う。
2. Testsにlint-and-unitとdocker-smokeが表示され、両方成功することを確認する。
3. integration-test-evidenceを取得し、result.jsonがpassed/complete、runsが8件、各result/diagnostics/cleanupがpassed、remainingが全て空、caのkeyMatches=trueであることを確認する。
4. PR自動実行と手動実行も確認する。手動実行はworkflowがデフォルトbranchに存在する状態で行う。
5. 実行識別子、event、対象SHA、attempt、時間、artifact、cleanup結果を検証記録へ残す。公開文書には個人名や所有者名を含めない。

P2-04のローカル8件成功をGitHub上の成功とみなさない。P2-05は接続実装済み・GitHub受入待ち。故意の失敗検知、同じ基準で5回連続成功（キャッシュなし・再実行を含む）、実際の必須チェック設定とマージ阻止は引き続き未確認。workflow追加だけではブランチ保護は設定されない。

## 実装時の検証

- actionlintでworkflowを検査。
- PowerShell 7／Windows PowerShell 5.1で共通scriptの構文を検査。
- ローカル受入ログの成果物対象を確認し、env・秘密鍵を含めず、架空資格情報がマスクされていることを確認。
- この接続作業ではコンテナ起動・build・push・GitHub workflow起動を実施していない。

公式資料：[Workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)、[Workflow artifacts](https://docs.github.com/en/actions/tutorials/store-and-share-data)。
