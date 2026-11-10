# Docker試験基盤：分離とライフサイクル

- 日付：2026-10-24
- 状態：解決（P2-03受入完了）
- 目的：P2-03の単独・繰り返し・期限・診断・後片付けを成立させる
- 関連：[実行手順](../34-integration-guide-ja.md)、[検証記録](../32-verification-ja.md)

## 決定

- ホストではDocker操作とログ保存のみ。共通入口は既存のP2-01と同じPowerShellとし、Linuxでもpwshで再利用できる。計画にあったrun-integration.shは重複するため追加しない。
- 実通信はinternal networkのtester内。portal.testのaliasとechoのサービスDNSを使い、ports・Docker socket・ホストbind mountなし。
- 製品のensure_dockerhost_in_hostsはdefault routeへ依存するため、extra_hostsでdockerhostをコンテナ自身の127.0.0.1へ固定して経路取得を避ける。
- local証明書の取得後にleafをpinしてHTTPSを検証する。独立CAの信頼検証はP2-04へ残す。testerへ秘密鍵volumeを渡さない。
- 各実行・繰り返しに固有projectを割り当て、事前に同名リソースがないことを確認してからcleanup対象として確保する。既存リソースを見つけた場合は削除しない。
- 通信だけでなくDocker CLIにも時間上限を付ける。stdout/stderrのpipe回収にも有限の猶予を設ける。
- 診断・cleanup・残存確認を行い、不完全な診断や削除失敗を全体成功にしない。強制終了時の回収不能に備えてprojectとfixture.envを保存する。

## 実装時の確認

Composeはprofileを指定しないとtesterをconfigから除外するため、test profileを明示して全サービスを検査するようにした。Compose展開、Ruby静的構文、PowerShell構文、代役プロセスによる引数・失敗・期限、危険な構成の拒否を確認した。

製品・toolsの実build、起動時のDH生成時間、実通信、Dockerリソースの削除は利用者実行待ち。成功を確認するまでP2-03完了とはしない。

## 初回buildのCRLF対応

実行ID 20261024t062936z-e1c38209のログで、archnameのCRLF構文エラーからアーキテクチャ名のないURLを生成し、wget exit8になることを確認。fs_overlayの改行をLFへ正規化し、root .gitattributesで再発を防ぐ。Git上の製品内容・依存バージョンは変更しない。修正後の実buildは利用者実行待ち。

## probeのRuby 2.7互換性

実行ID 20261024t064801z-32c98ee8で製品起動と失敗時cleanupを確認。verify_hostname=がRuby 2.7.2にないためprobeが待機し続けた。setterを除去し標準のVERIFY_PEER時の名前照合を利用する。プログラムエラーは再試行せず即時失敗にした。修正後の通常疎通は再実行待ち。

## 受入完了

通常実行20261024t083419z-abe23cdaで独立2回の疎通・診断・cleanup成功。失敗実行20261024t084200z-a6a76267で10秒期限切れ・非0・診断保存・cleanup成功。いずれもリソース残存なし。失敗時は設定/証明書未生成のため診断partialを記録し、本文不一致まで到達したとは扱わない。P2-03は完了。
