# 43 IP制限の実通信試験

[文書一覧](../00-index-ja.md) / [P3計画](40-implementation-plan-ja.md) / [検証記録](42-verification-ja.md)

状態：手順4の実装と静的・代役検証を完了。実Dockerでの受入は利用者実行待ち。

## 追加した試験

| Scenario | 検証 |
|---|---|
| ip | S-T04：許可送信元200/echo本文、別の非許可送信元403 |
| ip / ip-auth | S-T05：非許可元がX-Forwarded-For、X-Real-IP、両方へ許可IPを設定しても各403 |
| ip-auth | S-T06：許可元＋正認証200、許可元＋未認証/誤認証401とBasic challenge、非許可元＋正認証403 |

- 許可元tester-allowedを先に起動し、そのIPv4を取得して単一IPのallowを設定する。固定サブネットやホストIPに依存しない。
- 拒否元には独立したtesterコンテナを使い、TLS接続で得た実際の送信元IPが許可元と異なることを検証する。
- 許可元で通常の起動完了と200を確認してから拒否元を実行する。拒否元は公開leafだけを信頼し、VERIFY_PEERとホスト名検証を使用する。接続失敗・TLS失敗・401を403の代わりに合格させない。
- 許可元はpublic volumeだけを共有する。秘密鍵volume・Docker socketは渡さない。内部ネットワーク、local stage、pull neverを維持する。
- ローカル独立projectごとにprepare→起動→許可元→拒否元→診断→cleanupを実施する。異常時にも対象projectの後片付けと残存確認を行う。

## 1. toolsイメージを準備

今回のRuby試験を含めるため、toolsイメージを必ず更新する。旧toolsイメージは新シナリオに対応していない。以下はプロジェクトルートで実行する。

```powershell
cd <プロジェクトルート>

docker build --network none --pull=false -f spec/ci/Dockerfile.integration -t https-portal-prepared-tools:p3-ip .
```

DockerfileはRubyベースに試験ソースをCOPYする構成で、新規Gem/apt取得はない。RUNのネットワークはnone、pull更新はfalseを指定するが、ベースが未準備の場合の取得・メタデータ解決は別問題である。資材準備の工程として扱い、必要なベースを事前に用意する。試験本体ではbuildしない。

任意の構文確認（準備済み新toolsを使用、外部通信なし）：

```powershell
docker run --rm --pull never --network none --entrypoint ruby https-portal-prepared-tools:p3-ip -c /opt/it/client.rb
docker run --rm --pull never --network none --entrypoint ruby https-portal-prepared-tools:p3-ip -c /opt/it/ip_contracts.rb
```

## 2. IP制限試験を独立2回実行

製品コードは変更していないため、手順3で成功した製品イメージIDを再利用する。toolsは新しいタグを指定する。実行開始時にIDへ固定し、以後build/pullしない。

```powershell
.\dev\check_p2_integration.ps1 `
  -UsePreparedImages `
  -PortalImage sha256:50799eef7566b2502e16e154f4829b8ef0997b86f922cf073f8bdf426b9df400 `
  -TestImage https-portal-prepared-tools:p3-ip `
  -Scenario security `
  -Repeat 2
```

securityは現在ip/ip-authの2件。Repeat 2では計4件の独立実行となる。単独確認はScenario ipまたはip-authで実行できる。

成功後に既存試験を含む全体を確認する場合は、同じ指定のScenarioをallへ変更する。allは従来8件＋ip/ip-authの計10件になり、Repeat 2では計20件。既存P2文書の8件は当時の受入記録である。

## 3. 結果確認

最後のEvidenceに表示されるdev/test-results/p2-integration/<実行ID>/を確認する。

- 全体result=passed、stage=complete。
- security/Repeat 2はrunsが4件。各result/diagnostics/cleanup=passed、remainingのcontainer/network/volumeが全て空。
- 各runのallowedIp、allowed.source_ipが一致し、denied.source_ipは異なる。
- allowed/deniedのchecksに実際のHTTP statusが記録されている。ipの許可200/拒否403、ip-authの200/401/403、spoof-1/2/3の403を確認する。
- 公開証明書fingerprint、使用image IDを記録する。生成fixture envは資格情報を含むため共有成果物へ含めない。

試験を壊せることの受入も必要。使い捨ての試験用イメージでdeny allを削除した際に非許可元試験が失敗すること、Basic認証を外した際に許可元の401期待が失敗することを確認する。通常の製品イメージを直接書き換えたり、失敗を合格へ変更しない。

ホストのインターネット通信ゼロを確認する場合は資材準備後に遮断・観測する。内部Docker通信は試験に必要であり維持する。