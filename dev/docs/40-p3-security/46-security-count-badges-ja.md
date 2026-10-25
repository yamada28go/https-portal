# 46 Critical／High件数バッジ

[文書一覧](../00-index-ja.md) / [収集手順](45-security-collection-guide-ja.md) / [検証記録](42-verification-ja.md)

## 表示する値

日英READMEにCritical／Highの件数バッジを追加した。値は既定ブランチの最新の成功した製品検査から取得する。同じCVEが複数パッケージで検出された場合は複数レコードとなる。修正待ちチケット数・異なるCVE数・安全性の合否ではない。

Criticalが1件以上なら赤、Highが1件以上なら橙、0件なら緑。0件でも全コンポーネントの網羅や安全を保証しない。既存のSecurity report状態バッジと併せて見る。

クリック先latest.jsonには検査日時、対象commit、Docker/config ID、元のActions run URL、件数を保存する。後続の検査が失敗した場合は最後の成功値を残す。日時とSecurity report状態を確認し、古い値を最新の安全性判定として使わない。

## 自動更新

1. security-reportは従来どおり検査・SBOMを生成する。成功/cleanup、summary/resultのimage IDとCritical/High件数対応を検査する。
2. dev/security/badges.ps1が公開用のcritical.json、high.json、latest.jsonを生成し、通常のevidence artifactにも保存する。公開用のmetadataは許可フィールドだけに限定する。
3. 既定ブランチの成功したpush/手動/日次実行だけ、publish-count-badgesジョブでGitHub REST Git APIを使いsecurity-badgesブランチを作成・更新する。PR・作業ブランチ・tag実行はartifact生成までで公開値を更新しない。
4. 初回は3ファイルだけの独立したroot commitを作る。既存の専用ブランチに無関係なファイルがある場合は停止し、上書きしない。更新は通常のfast-forwardでforce-pushしない。
5. READMEはShields.io endpoint badgeからraw.githubusercontent.comのJSONを参照する。表示はキャッシュにより遅れる場合がある。

GITHUB_TOKENだけを使用し、追加Secrets・Pages設定は不要。トップレベルのcontents:readは維持し、公開ジョブだけcontents:write。公開ジョブのcheckoutは既存の固定SHAとpersist-credentials:falseを使う。PR由来のプログラムやartifactを書込み権限で実行しない。件数をjob outputとして渡し、別ジョブで検証して公開する。

公開処理は専用concurrencyで直列化し、開始時とref更新直前に既定ブランチHEADが検査commitと一致することを確認する。既定HEADが進んだ実行や公開済み/古いrunはskipする。公開失敗はジョブ失敗として扱い、成功扱いにせず、元の検査evidenceは保存する。

公開対象は集計と最小metadataの3ファイルだけ。生レポート、環境変数、DB、image archive、tokenは公開ブランチへ含めない。検査workflowのreport-only・閾値未導入は変更しない。

## 初回の反映・受入

この変更を既定ブランチへ反映し、Security reportを成功させる。作業ブランチへpushしただけではpublish-count-badgesはskipされ、件数バッジは初期化されない。初回公開まではデータ未取得の表示になる場合がある。既定ブランチの初期化を待つための手動branch作成やSecrets登録は不要。

公開ジョブが権限・branch rule等で拒否された場合はそのログを確認する。今回の実装ではrepository設定・保護規則を変更していない。

受入では以下を確認する。

- security-reportとpublish-count-badgesが成功し、security-badgesブランチに3 JSONだけがある。
- latest.jsonのref/commit/image ID/run URLと元のsummary/resultが一致し、Critical／Highが同数である。
- READMEの各バッジがJSONの件数を表示する。クリックで元runと日時を確認できる。
- PR実行では公開ジョブがskipされ、既定ブランチの値が保持される。
- 後続失敗時は前回成功値が残り、Security report状態・latest.json日時で区別できる。

## 検証

ローカルではdev/security/check-badges.ps1を実行する。色/0件、不正件数、失敗・cleanup異常、summary/result不一致、余分な公開metadata、PR非公開、初回作成・通常更新、古い実行のskip、既存branch衝突・API異常を検査する。APIは代役であり実公開の証明とはしない。

今回は22件成功、PowerShell 7/5.1構文とactionlint成功。ローカル実製品summaryのCritical 12 / High 135から同じ件数を生成するsmokeも成功したが、元run metadataはテスト用に置き換えたQA資材であり、CIの件数として公開していない。GitHubへの公開・README実表示の受入は変更反映後の利用者実行待ち。

一次資料：[Shields endpoint](https://shields.io/badges/endpoint-badge)、[GitHub Git commits API](https://docs.github.com/en/rest/git/commits#create-a-commit)、[GitHub Git trees API](https://docs.github.com/en/rest/git/trees#create-a-tree)。
