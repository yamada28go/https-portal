# P2-01 Docker内での基準検証

ホストに必要なのはPowerShellとDocker CLIのみ。ホストのGit・Ruby・Bundlerは使用しない。dev.ps1の起動や開発コンテナの常駐も不要。

## 実行

Docker DesktopをLinux containersで起動し、プロジェクトルートのPowerShellから実行する。

```powershell
.\dev\check_p2_baseline.ps1

# キャッシュなしでイメージを作り直す場合
.\dev\check_p2_baseline.ps1 -NoCache
```

## 通信と書き込みの境界

- 初回ビルド：固定Rubyベース、署名検証付きDebian archiveのGit/CA、Bundler 2.2.4、固定Gemを取得するため外部通信が必要。Node/Codexは導入しない。
- 実行：network none、read-only rootfs、UID/GID 1000、cap-drop ALL、no-new-privileges。Docker socketは渡さない。
- ソース：ホストのプロジェクトを/checkoutへ読み取り専用で渡す。GitのHEAD・差分調査もコンテナ内で行う。
- 試験：必要なソースだけを/tmpの一時コピーへ複製し、その中で実行する。元のソース・Git管理情報を変更しない。
- 結果：今回専用の/resultsだけホストへ書き出す。公開DNS変更、公開ACME発行、イメージpushは行わない。

閉じた実行環境はネットワークを隔離する意味。読み取り専用でもプロジェクト内のファイルはコンテナから参照できるため、ソースを完全に不可視にする構成ではない。

## 実行内容・成功条件

1. コンテナ内でGitのHEAD・作業差分と、入力ファイルのSHA-256を記録。
2. 一時コピーと読み取り専用ソースの一致、イメージ内とソースのGemfile/lock一致を確認。
3. 製品Ruby・spec全体・dev/check_p1.rbの構文検査。
4. 113例をseed 1/17/101で実行し、0 failures/0 pendingを確認。
5. 9ファイル単独、M01〜M08の変更前成功・対象1例の意図した失敗・復元後成功を確認。
6. 復元後113例の成功と、元ソースのfingerprint・HEAD・差分状態が実行前後で同じことを確認。

成功時は `P2-01 baseline passed` と表示する。dev/test-results/p2-baseline/<実行ID>/にconsole.log、host-run.json、コンテナ実行時はbaseline.json・inputs.sha256・p1-check.logを保存する。過去のP1ログは上書きしない。

host-run.jsonはDocker起動側、baseline.jsonはコンテナ内検証の記録。Engine接続やbuildの段階で失敗した場合、baseline.jsonは作成されない。失敗を成功扱いにせず、以前の成功ログも今回の成功証跡として流用しない。

コンテナは終了時に削除する。ローカルのビルドイメージ・cacheと結果ログは残る。個人名・アカウント名・絶対パスを公開メモへ転記しない。

[検証記録](../../dev/docs/30-p2-ci/32-verification-ja.md)

## GitHub Actions

Tests / lint-and-unitも同じスクリプトを使用する。[CI実行・受入手順](../../dev/docs/30-p2-ci/33-ci-test-guide-ja.md)を参照。Linuxでは実行専用の結果ディレクトリだけ書き込みを許可する。GitHubでの成功は実行後に確認する。

## Docker試験基盤（P2-03）

プロジェクトルートで `.\dev\check_p2_integration.ps1 -Repeat 2`。[実行・受入手順](../../dev/docs/30-p2-ci/34-integration-guide-ja.md)を参照。実Dockerの起動確認は利用者側で行う。

P2-04の重要契約を一括実行：`.\dev\check_p2_integration.ps1 -Scenario all`。[試験内容・受入手順](../../dev/docs/30-p2-ci/35-integration-contracts-ja.md)を参照。実Dockerの実行受入は利用者側で行う。

## 準備済みイメージによる実行（P3 手順2）

build・pullを行わない入口を追加した。UTは `-UsePreparedImages -UnitImage <ローカル参照>`、結合試験は `-UsePreparedImages -PortalImage <ローカル参照> -TestImage <ローカル参照>` を指定する。指定なしは従来どおりbuildを含む。

[実行手順・資材準備・制約](../../dev/docs/40-p3-security/41-execution-guide-ja.md)を参照。通信遮断下での実試験受入は別途必要。

P3手順4：IP制限は -Scenario security（ip/ip-auth）で実行する。allは既存8件＋IP制限2件の計10件。[準備・実行手順](../../dev/docs/40-p3-security/43-ip-access-guide-ja.md)に従いtoolsイメージを更新する。
