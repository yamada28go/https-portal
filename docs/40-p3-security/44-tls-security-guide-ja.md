# 44 TLS・証明書異常系の実行手順

[文書一覧](../00-index-ja.md) / [P3計画](40-implementation-plan-ja.md) / [検証記録](42-verification-ja.md)

状態：手順5の実装済み。実Docker・GitHub Actionsでの受入は未実施。

## 検証する契約

| Scenario | 内容 | 合格条件 |
|---|---|---|
| tls-policy | S-T07：TLSバージョン | TLS1.2/1.3を個別固定して成功。TLS1.0/1.1は各loopback制御サーバーへ接続成功後、portalからprotocol version alertで拒否 |
| tls-policy | S-T08：SNI | 正常SNIで成功。対象外SNIとSNIなしはunrecognized_nameで拒否 |
| tls-chain | S-T02：中間証明書欠落 | 正常チェーンで200→leafのみへ差し替え/reload→検証コード20/21で拒否→正常チェーンへ復元/reload→200 |
| tls-expired | S-T03：期限切れ | 正常証明書で200→同じ鍵/SANの期限切れleaf＋中間証明書へ差し替え/reload→検証コード10で拒否→復元/reload→200 |

接続拒否・クライアント側の旧TLS非対応・別の証明書エラーを、期待するセキュリティ拒否とみなさない。検査不成立は失敗とし、skipで通過させない。

## 仕組みと分離

- 初期証明書はP2と同じ一時root→intermediate→leaf。testerは公開rootだけを信頼し、CA秘密鍵を保存/共有しない。異常証明書も同じleaf鍵を使用する。
- 起動時は残存期間90日の正常証明書を使う。異常系は起動後のfixture差し替えと直接nginx reloadで検証し、製品の自動発行・更新試験とは区別する。
- 差し替え前に製品が使用する/tmp/https-portal.lockを試験用の期限付きプロセスで保持する。定期renew/reconfigによる置き換えを防ぐ。ロック保持確認後だけ差し替え、保持プロセスは使い捨てportalと共に終了する。
- reload後、期待するleaf fingerprintと中間証明書の有無が連続して確認できるまで待つ。この観測だけはVERIFY_NONEを使用するが、拒否判定は毎回rootのみの新しいtrust storeとVERIFY_PEERを使用する。
- 期限切れはnotBefore < notAfter < 現在時刻となるfixture。名前不一致等による失敗とは切り分ける。
- 旧TLS能力の確認はtester自身の127.0.0.1・一時ポートで行う。試験専用SSLContextだけsecurity level 0を使用し、製品のTLS設定や通常クライアントの検証を緩めない。
- internal network、STAGE=local、公開DNS/ACME不要、pull never、実行ごとのproject/volume、診断/cleanupは従来どおり。

## 1. 新しいtoolsイメージの準備

プロジェクトルートで実行する。製品コードは変更していないため既存の製品イメージを再利用できる。toolsは今回のコードを含むものに作り直す。

```powershell
docker build --network none --pull=false -f spec/ci/Dockerfile.integration -t https-portal-prepared-tools:p3-tls .
```

このDockerfileはRubyベース＋試験ソースCOPY。ベースの取得・メタデータ解決が必要なら、試験とは別の通信可能な準備工程で行う。旧toolsを指定すると新規ファイルやメソッドがなく失敗する。

Ruby 2.7での構文確認も可能：

```powershell
docker run --rm --pull never --network none --entrypoint ruby https-portal-prepared-tools:p3-tls -c /opt/it/client.rb
docker run --rm --pull never --network none --entrypoint ruby https-portal-prepared-tools:p3-tls -c /opt/it/prepare.rb
docker run --rm --pull never --network none --entrypoint ruby https-portal-prepared-tools:p3-tls -c /opt/it/tls_contracts.rb
docker run --rm --pull never --network none --entrypoint ruby https-portal-prepared-tools:p3-tls -c /opt/it/switch_tls_fixture.rb
```

## 2. 通常実行

```powershell
.\dev\check_p2_integration.ps1 `
  -UsePreparedImages `
  -PortalImage sha256:50799eef7566b2502e16e154f4829b8ef0997b86f922cf073f8bdf426b9df400 `
  -TestImage https-portal-prepared-tools:p3-tls `
  -Scenario tls `
  -Repeat 2
```

tlsは3件、Repeat 2なら6件の独立実行。単独はtls-policy/tls-chain/tls-expiredで指定できる。全体回帰は同じ指定のScenarioをallに変更する。allは既存10件＋TLS3件の計13件、securityはIP2件＋TLS3件の計5件へ拡張した。過去の件数は当時の証跡として維持する。

## 3. 故意変更の検知

通常実行の成功後、使い捨てportal内だけでTLS1.2を無効にする。ホストの製品ソースやイメージ自体は変更しない。

```powershell
.\dev\check_p2_integration.ps1 `
  -UsePreparedImages `
  -PortalImage sha256:50799eef7566b2502e16e154f4829b8ef0997b86f922cf073f8bdf426b9df400 `
  -TestImage https-portal-prepared-tools:p3-tls `
  -Scenario tls-policy `
  -TLSMutation disable-tls12
```

変更前に通常のtls-policy全項目を実行して起動完了と正常契約を確認し、更新ロックを保持してから設定を書き換える。変更前の結果はtlsBeforeMutation、ログはrun-*-before-mutation-tls-checkとして別保存する。変更前試験の失敗時は設定を書き換えない。

期待は非0終了とresult=failed。TLS1.2の正常接続チェックでprotocol version alertにより失敗したことをrun-*-tls-checkのJSONで確認する。mutationApplied=disable-tls12とcleanup=passedも照合する。設定書換え・nginx -t・reload失敗や、mutation unexpectedly survivedは「検知成功」の証拠にならない。失敗をpassedに書き換えない。

その後、TLSMutationを外した同じtls-policyをもう一度実行し、独立projectで正常復帰を確認する。通常のActions all実行はTLSMutation=noneで動く。

## 4. 証跡と受入

result.jsonの全体passed/complete、期待件数、各result/diagnostics/cleanup=passed、remainingが全て空であることを確認する。TLSの各runにはtls配列を保存し、tls-policyはcheck、証明書異常系はbaseline→mutated→restoredの3段階のcases/checksを記録する。

確認対象：検証コード、OpenSSL版、TLS能力の正の対照、サーバーのalert、提示leaf fingerprint、使用image ID、正常復元。公開証明書だけを共有成果物にし、fixture envと秘密鍵volumeを含めない。

今回の変更をcommit/pushすると既存docker-smokeのScenario allに自動で含まれる。新しいActionsの成功を確認し、artifactのresult.jsonも取得して全13件とcleanupを照合する。ジョブ成功表示だけで成果物の中身を確認済みにしない。

[NGINXのTLS/SNI仕様](https://nginx.org/en/docs/http/configuring_https_servers.html)、[Ruby OpenSSL API](https://ruby-doc.org/stdlib-2.7.2/libdoc/openssl/rdoc/OpenSSL.html)を参照。
## 故意変更の起動待ち修正（2026-10-25）

TLS mutation anchor missingがrun-*-mutation-tls12で発生する場合は故意変更の適用前に停止している。起動完了待ちより前に設定を書き換える順序を修正済み。修正はホストのdev/check_p2_integration.ps1のみで、既存p3-tls tools/製品イメージを再利用できる。上記の故意変更コマンドをそのまま再実行する。