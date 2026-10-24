# P2 検証記録

[文書一覧](../00-index-ja.md) / [実施手順](30-execution-guide-ja.md) / [詳細計画](31-implementation-plan-ja.md)

## 最新：P2-03 Docker試験基盤の受入完了（2026-10-24）

通常ケースの独立2回成功と、never-readyの期限切れ失敗・診断保存・cleanupを保存ログとJSONで照合した。**P2-03は完了。** P2-04の重要契約追加とP2-05のDocker CI接続はまだ実施していない。P2-02の残る受入項目も別途追跡する。

| 項目 | 結果 |
|---|---|
| 通常実行ID | 20261024t083419z-abe23cda |
| 通常時刻 | 2026-10-24 17:34:19〜17:36:30 JST |
| 通常実行 | result=passed、stage=complete、2つの独立projectで各result/diagnostics/cleanup=passed |
| 疎通 | 各probeがHTTPS 200・期待本文・echo到達を含めpassed。証明書fingerprintも2回で異なる |
| 通常後の残存 | 各回ともcontainer/network/volumeが空 |
| 失敗実行ID | 20261024t084200z-a6a76267 |
| 失敗時刻 | 2026-10-24 17:42:00〜17:42:41 JST |
| 意図的失敗 | never-ready、probeのtimeout_seconds=10、10試行後に期限切れ・exit 1 |
| 失敗時診断 | ps・サービスログと診断エラーを保存。設定/証明書未生成のためdiagnostics=partial |
| 失敗時cleanup | cleanup=passed、container/network/volumeが空 |

失敗時のlast_errorはECONNREFUSEDで、10秒時点ではportalがまだ待受を始めていなかった。従って今回証明したのは「起動前でも期限切れを検出して非0となり、診断とcleanupが完了すること」。意図した本文不一致まで到達したとは扱わない。

診断のpartialは隠さず記録する。HTTP/HTTPS設定ファイルとsigned.crtが存在しない旨のstderrが保存され、psとサービスログから起動途中を追跡できる。正常時は両回とも診断が全取得できた。

表示のtimeout=FalseはDocker CLI自体が強制終了されなかった意味。probe内部の10秒期限切れとは別であり、今回の失敗受入は想定どおり。result=failedを成功へ書き換えず、負の試験として受入成功を記録する。

証跡：dev/test-results/p2-integration/の上記2実行ディレクトリ。個人名を含むComposeラベルやホスト絶対パスは公開文書へ転記しない。

## 過去：P2-03起動成功・probeのRuby互換性を修正（2026-10-24）

利用者実行ID 20261024t064801z-32c98ee8では、製品・toolsのbuildとlocal証明書の生成が進み、portalはhealthy、echoはrunningだった。probeはRuby 2.7.2のNet::HTTPにないverify_hostname=を呼び、NoMethodErrorを繰り返して180秒で失敗した。

| 確認項目 | 結果 |
|---|---|
| 製品起動 | s6初期化・自己署名・Nginx起動成功、診断時healthy |
| 証明書 | portal.testの自己署名証明書を生成 |
| probe | 未対応APIのNoMethodErrorで失敗。HTTPS本文・echo応答の完了は未確認 |
| 診断 | diagnostics=passed |
| 後片付け | cleanup=passed |
| 残存 | container/network/volumeすべて空 |
| Repeat | 1回目失敗で停止。2回連続成功は未確認 |

verify_hostname=を除去した。VERIFY_PEERとleaf pinは維持し、Ruby 2.7.2のNet::HTTPが接続後に行うホスト名照合を使用する。起動中の接続エラー等だけを再試行し、NoMethodError等のプログラムエラーはprobe_error・exit 2で即時失敗に変更した。静的Ruby構文は成功。修正後の実通信は利用者の再実行待ち。

根拠：[Ruby 2.7.2のNet::HTTP実装](https://github.com/ruby/ruby/blob/v2_7_2/lib/net/http.rb#L971-L974)。公開文書には実行ログの個人名を含むパスやComposeラベルを転記しない。

## P2-03初回buildのCRLF問題を修正（2026-10-24）

利用者実行ID 20261024t062936z-e1c38209は、build-portalで停止した。先行するapt・s6-overlay-noarch取得は成功しており、保存ログでは/usr/bin/archnameにCR起因の「not found」「expecting in」がある。アーキテクチャ名が取得できず、後続wgetがexit 8となった。公開配布物のバージョン不整合とは判断しない。

Gitの確認で、archname・s6起動ファイルはindexがLF、Windows作業ツリーがCRLFだった。rootの.gitattributesにfs_overlay/** text=auto eol=lfを追加し、作業ツリーのテキストをLFへ正規化した。33ファイルを検査し、CRLFだった31ファイルを変換した。正規化後のfs_overlayはgit diffで内容差分なし。製品ロジック・依存バージョンは変更していない。

失敗はbuild段階で、result.jsonのrunsは空。今回のscenario用コンテナ・network・volumeを起動する前に停止している。修正後の再build・実起動は利用者の実行待ち。

```powershell
.\dev\check_p2_integration.ps1 -Repeat 2
```

-NoCacheは不要。Dockerは変更されたCOPY以降を再buildする。P2-03は引き続き実行検証待ち。

## P2-03 Docker試験基盤を実装・利用者実行待ち（2026-10-24）

P2-02のpush成功後、利用者の指示でP2-03へ進めた。P2-02のPR・手動・故意変更受入は別途未完了として保持する。

Composeでportal・echo・testerをinternal networkに分離し、STAGE=local、portal.test、専用証明書/log volumeを設定した。ホスト公開ポート・ソケット・bind mountなし。ホストの入口はdev/check_p2_integration.ps1。Git/Ruby不要で、実通信はtesterコンテナ内に閉じる。

| 確認 | 状態 |
|---|---|
| 開始時の既存差分 | 前回のGitHub成功反映に伴う32/33文書の差分を保持 |
| Compose展開 | -ValidateOnlyでtester profileを含めたconfig解析に成功。Engine・コンテナは起動していない |
| Ruby静的構文 | Prismでprobe.rb/echo.rbに成功。Ruby 2.7.2による実実行は未確認 |
| PowerShell | PowerShell 7とWindows PowerShell 5.1の構文検査 |
| 期限・失敗伝播 | Dockerを起動しない代役プロセスで、引数の空白/引用符/末尾backslash/空文字、Windows引数方式、非0、期限切れ停止を検証 |
| 構成ガード | internal解除、production stage、公開port、bind mount、共有volume名を拒否する補助検証 |
| 実装 | 専用project、繰り返し、期限、診断、down、ラベルによる残存確認。既存projectの再使用・削除を拒否 |
| 製品context | .dockerignoreから.git/dev/.githubを除外。専用Dockerfileのignoreは独立して維持 |
| 未実行 | 製品build・実起動・実通信・2回連続・never-ready・Dockerリソース削除の実確認 |

[実行・受入手順](34-integration-guide-ja.md)に従い利用者が実行する。P2-03は実装済み・実行検証待ち。P2-04の独立CA/認証/proxy契約、P2-05のdocker-smokeジョブはまだ追加しない。

## P2-02 GitHub Actionsのpush実行に成功（2026-10-24）

GitHub公式APIで実行・ジョブ・artifactのメタデータを照合し、pushによる自動起動と成功を確認した。

| 確認項目 | 結果 |
|---|---|
| Run ID / attempt | 40068897258 / 1 |
| event | push |
| workflow | completed / success |
| job | lint-and-unit / success |
| ジョブ実行時間 | 2026-10-24 15:06:43〜15:07:44 JST（約61秒） |
| ソース取得 | Check out sourceがsuccess |
| Docker内検証 | Run the offline Ruby baselineがsuccess |
| 診断保存 | Upload unit test evidenceがsuccess |
| artifact | unit-test-evidence-40068897258-1、16,444 bytes、確認時点で未失効 |
| artifact期限 | 2026-11-07 15:07:42 JST |

GitHub所有者名を公開文書へ含めないため、実行URL・HEADの値は省略する。対象runの画面またはAPIで照合できる。今回確認したのは実行状態・step結果・artifactの存在であり、artifact内のログ本文は未取得。

P2-02のpush成功は確認済み。PR起動・手動起動・故意変更でのジョブ失敗と復元成功は別の受入項目として残る。P2全体やP2-02の全受入完了とはしない。

## 実装時点：P2-02 workflow実装・GitHub受入待ち（2026-10-24）

Tests / lint-and-unitを.github/workflows/tests.ymlへ追加。PR・push・手動起動、ubuntu-24.04、20分上限、contents: read、checkout資格情報非保存、完全SHA固定を設定した。

実行はP2-01と同じdev/check_p2_baseline.ps1を使用。Linuxの結果ディレクトリだけコンテナUID1000が書き込めるようにし、GitHub event/run/attempt/expectedShaをhost-run.jsonへ記録する。試験中のnetwork none、読み取り専用ソース、一時コピーでの検証は維持する。

| 確認 | 結果 |
|---|---|
| 開始時状態 | P2-01がコミット済み。作業ツリーに差分なしを確認 |
| Action参照 | 公式APIでcheckout v7.0.1・upload-artifact v7.0.2の完全commitを確認 |
| workflow | actionlint 1.7.12で成功。検証ツールは公式releaseのchecksumを照合 |
| 共通スクリプト | PowerShell 7とWindows PowerShell 5.1の構文検査成功 |
| 失敗伝播 | continue-on-errorなし。Dockerの非0で共通スクリプトがthrowし、ジョブを失敗にする設計。実際のGitHub上の赤判定は未確認 |
| ログ | 成否にかかわらず限定5種類をartifact化し14日保存する設定 |
| 未実行 | GitHubへのpush、push/PR/手動実行、Ubuntuでの実Docker検証、故意変更でのジョブ失敗・復元成功 |

[CI実行・受入手順](33-ci-test-guide-ja.md)に従って利用者が実行する。P2-01のローカル成功でGitHub上の成功を代替しない。P2-02は実装済み・受入未完了。

## P2-01 基準確定完了（2026-10-24）

**利用者実行の保存ログ・host-run.json・baseline.jsonを照合し、最小Ruby環境での再現成功を確認した。P2-01は完了。P2-02はworkflow実装済み・GitHub受入待ち。**

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
