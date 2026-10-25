# ARM64 結合試験のタイムアウト調査と修正

対象: Tests run 40186960466 / attempt 1 / commit e2f34d5e33ed93cde680d95321a88f6d41b592ba。
成果物: integration-test-evidence-arm64-40186960466-1 / 20261025t105913z-a68ee2aa。

## 確認できた事実

- result.json は製品・試験用イメージの双方を linux/arm64 と記録している。
- local、redirect は成功。proxy の run-3-probe は exit 1、Docker の外側の時間制限には達していない。
- run-3-probe.stdout.log は空。stderr は contracts.rb:91 の失敗 JSON の puts/write における Timeout::Error のみ。元の失敗内容は出力できていない。
- nginx は起動済みで、準備確認の GET / に2回 200 を返している。実際の転送内容を検証する /forward/path の記録はない。
- 診断と cleanup は成功し、残留 container/network/volume はない。

## 判断

client.rb は ready! の最大10秒の Timeout.timeout の中で、tls の10秒タイマーや request の10秒タイマーを起動していた。Ruby の既知問題では、入れ子のタイマーが同時に発火すると rescue 後の puts にも例外が届く。今回のログはこの競合と整合するため、試験側の構造を修正する。ARM64 固有の製品不具合とは断定しない。また、最初の通信待ちが発生した理由は記録が失われており未確定。

一次資料: https://bugs.ruby-lang.org/issues/20314
Ruby 2.7.2 の実装: https://github.com/ruby/ruby/blob/v2_7_2/lib/timeout.rb

## 修正

- ready! の外側の非同期タイマーを除去。起動期限の残り時間を TLS と HTTP の各操作へ渡す。
- TLS は単独のタイマーで制限する。証明書差替え待ちも外側の重複タイマーを除去する。
- HTTP は Net::HTTP の open/read/write timeout を使い、自動再試行を無効化。試験の外側のプロセス時間制限も維持する。
- 同じ証明書で3回連続の成功、証明書・ホスト名の検証、実際の転送条件の assertion は維持する。契約違反は再試行しない。
- check_client.rb に7つの確認を追加し、試験イメージの build 中に実行する。両CPUの build でタイマーの非重複、安定回数、過渡エラー、証明書切替、契約違反、期限、HTTP設定を確認する。

HTTPの制限は各接続・読み取り・書き込みの制限であり、リクエスト全体の厳密な締切ではない。全体の停止は既存の Docker プロセス制限でも保証する。

## 検証と再受入

ローカルでは変更 Ruby の Prism 構文検査と Tests workflow の actionlint が成功。このホストでは Docker Engine にアクセスできず、Ruby 2.7.2 による7チェックと実通信試験は未実行。Actions で実行する。

変更を commit/push し、新しいコミットで Tests を実行する。古い run の Re-run では修正コードを使わない。

1. build-tools の Integration client: ...: passed が7件ある。
2. docker-smoke (amd64)/(arm64) が全13シナリオ成功する。
3. 各CPUの result.json が result=passed、imagePlatforms が期待CPU、cleanup=passed となる。
4. 失敗が続く場合は新しい成果物の probe stdout/stderr と該当シナリオの診断ログを再確認する。

## 追記: Tests #13 の試験イメージ build 失敗

ユーザー提供ログでは docker-smoke (amd64) が build-tools で失敗している。これは元の proxy 通信試験の再発とは区別する。check_client.rb の最初の4チェックは成功し、5件目の「expired startup deadline fails and clears budget」の assertion で停止した。

原因は追加した試験の不備。fixture が @readiness_deadline だけを過去へ変更しており、ready! のローカル変数 deadline は5秒後のままだった。sleep を省略した試験ループが実時間で5秒間再試行を続け、「1回で終了」という期待に反した。

修正は check_client.rb のみ。Process.clock_gettime の単調時計を試験中だけ制御し、開始100秒→通信操作中106秒と進めることで、5秒の期限を両方の処理に同時に超過させる。時計は ensure で必ず復元する。assertion の削除や期待回数の緩和は行わない。

実行検証:

- 公式 RubyInstaller 3.4.12 (Windows x64) で修正前のチェックを実行し、同じ5件目の失敗を再現（exit 1）。
- 同じ実行環境で修正後の7チェックがすべて成功（exit 0）。
- Prism による構文検査も成功。
- RubyInstaller 2.7.2 はこのホストで DLL 再配置エラーとなり起動できなかった。Ruby 2.7.2/Linux と ARM64 による確認は Actions で未受入。
- 製品コードと client.rb の動作はこの追記の修正では変更していない。

ローカル実行ログはチャット作業ディレクトリの work/multiarch/client-before-fix.log と client-after-fix.log に保存。修正を新たに commit/push した run で、build-tools の7チェックと全13シナリオを両CPUとも確認する。
