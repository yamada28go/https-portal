# P2 検証記録

[文書一覧](../00-index-ja.md) / [実施手順](30-execution-guide-ja.md) / [詳細計画](31-implementation-plan-ja.md)

## 最新：P2-01 基準確定完了（2026-10-24）

**利用者実行の保存ログ・host-run.json・baseline.jsonを照合し、最小Ruby環境での再現成功を確認した。P2-01は完了。P2-02のGitHub Actions導入は未着手。**

| 確認項目 | 結果 |
|---|---|
| 実行ID | 20261024T052651Z-033960e1 |
| 実行時間 | 2026-10-24 14:26:51〜14:27:31 JST（ビルドキャッシュ利用の再実行） |
| ホスト操作 | host-run.jsonのresult=passed、stage=complete |
| コンテナ内検証 | baseline.jsonのresult=passed、stage=complete |
| Ruby構文 | 30ファイル成功 |
| 全113例 | seed 1/17/101で各113例・0 failures |
| 単独実行 | 9ファイルすべて成功 |
| Mutation | M01〜M08の変更前成功・意図した失敗・復元後成功 |
| 復元後 | 113例・0 failures |
| 入力不変 | コンテナ側の完了判定で入力fingerprint、HEAD、Git差分状態の実行前後一致を確認 |
| 実行隔離 | ホストGit不要。network noneのコンテナで実行し、ソースは読み取り専用、一時コピーで試験 |
| 証跡 | dev/test-results/p2-baseline/20261024T052651Z-033960e1/のconsole.log、host-run.json、baseline.json、inputs.sha256、p1-check.log |

HEAD・入力fingerprint・イメージIDはローカルJSONに記録済み。個人識別子との照合を避けるため、この公開文書には転記しない。

baseline.jsonには複数のGit差分が記録されている。実行対象は記録された作業ツリーであり、「コミット済みHEADと完全一致したソースで成功した」という意味ではない。ホストとコンテナの改行設定などによる差分の可能性も含め、CIへ移す際はコミット済みの基準で再検証する。

過去の失敗記録は以下に保持する。今回の成功をGitHub Actions上の成功やP2全体の完了とは扱わない。

## 過去：利用者実行でビルド成功・Git所有者チェックで停止（2026-10-24）

実行ID：20261024T051305Z-4d239633。利用者提供ログで、Ruby 2.7.2ベースの取得、Gitの導入、Bundler 2.2.4と固定Gemの導入、イメージ出力まで成功した。ビルド完了条件は確認できたが、113例・Mutationはまだ実行前。

コンテナ内のGit 2.20.1が/checkoutの所有者不一致を検出し、コマンド単位のsafe.directory指定では通過しなかった。このため、コンテナのtmpfsに一時HOMEを作り、そのglobal設定へ/checkoutだけを登録する方式へ修正した。ホストの設定・リポジトリ設定・他ディレクトリの信頼範囲は変更しない。

Windows PowerShellで標準エラーの空行がRemoteException型名として出る問題も、ErrorRecordからメッセージを取得するよう修正した。Dockerの非0終了を失敗として扱う動作は維持する。

BuildKitの「ホストのGitが見つからずcommit情報を取得できない」という警告は、今回のビルドを停止させていない。基準HEADはコンテナ内で別途記録する。修正後は同じコマンドで再実行し、今回の全検証成功を確認するまでP2-01完了とはしない。

## 実行方式の修正（2026-10-24）

利用者の通常PowerShellではGitがPATHにないため、旧スクリプトはGit呼出しで停止した。実行をDocker内部へ集約する方針に変更した。

ホストはDockerのbuild/runとログ出力だけを行う。Git調査・入力fingerprint・構文検査・113例・Mutation・入力不変確認は、network noneのコンテナ内で実行する。ソースを読み取り専用で渡し、一時コピー上で試験する。最小イメージにはGitを含めるがNode/Codexは含めない。

dev.ps1を経由する必要はない。ホストのGit導入・PATH変更も不要。修正後の実ビルド・試験は利用者による実行待ちであり、まだ成功とは扱わない。初回ビルドの依存取得は外部通信を伴う。

```powershell
.\dev\check_p2_baseline.ps1
```

## 前回の確認：P2-01（2026-10-24）

**最小環境と実行スクリプトを実装。Docker Engineの接続拒否により実ビルド・113例・Mutation検証は未完了。P2-02へは進まない。**

| 項目 | 結果 |
|---|---|
| 開始時点 | git statusで変更なしを確認。HEADはローカル証跡へ記録し、公開文書では省略 |
| 依存 | Ruby 2.7.2、Bundler 2.2.4、既存Gemfile.lockを維持 |
| 最小イメージ定義 | spec/ci/Dockerfile.unitを追加。既存開発環境と同じRuby digest、Node/Codexなし |
| ビルド入力 | Dockerfile専用ignoreでspec・製品ファイル・固定Gem情報・検証scriptに限定。Git履歴・開発ログ・認証volumeを含めない |
| 実行 | dev/check_p2_baseline.ps1を実際に呼び出したが、Docker APIのnamed pipe接続がpermission deniedで停止 |
| 失敗処理 | Docker終了コード1を伝播、baseline.jsonのresult=failedとconsole.logを保存。build前に停止 |
| 実行証跡 | dev/test-results/p2-baseline/20261024T050418Z-af63924e/（Git対象外） |
| 製品・既存113例 | 製品コード・specの期待値・依存バージョンは変更していない |
| 未実行 | Docker build、Bundler導入、コンテナのRuby構文検査、113例、3 seed、単独実行、M01〜M08、復元後実行 |

以前の113例成功ログは過去の証跡であり、今回の最小イメージで成功した証拠にはしない。

## 再実行

通常のPowerShellでLinux Docker Engineへの接続を確認してから、プロジェクトルートで実行する。

```powershell
docker version
.\dev\check_p2_baseline.ps1
```

[最小環境の説明](../../../spec/ci/README.md)を参照。実行はHEAD・作業差分・入力fingerprintを保存する。新しい実行IDのbaseline.jsonがpassedとなり、p1-check.logで全項目成功と入力不変が確認できた後にP2-01完了へ更新する。

## P2-01完了条件

- [x] 開始時の変更状態を確認した
- [x] 最小Rubyイメージ・実行入口を実装した
- [x] 今回の失敗を以前の成功ログと区別して記録した
- [x] 最小イメージを実際にビルドした（利用者提供ログで確認）
- [x] 最小環境で113例・3 seed・9ファイル単独が成功した
- [x] M01〜M08の検知・復元と復元後113例が成功した
- [x] 実行前後の入力fingerprintが一致した
