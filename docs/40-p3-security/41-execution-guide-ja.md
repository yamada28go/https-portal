# 41 準備済みイメージによる試験実行

[文書一覧](../00-index-ja.md) / [P3計画](40-implementation-plan-ja.md) / [検証記録](42-verification-ja.md)

## 対象

手順2で既存のUT・Docker結合試験の入口へUsePreparedImagesを追加した。このモードではbuildとpullを行わず、ローカルにある明示指定イメージだけを使う。指定なしの従来実行はbuildを含む。

この変更は「資材準備後の実行入口」の整備。通信遮断下での実UT・ITの受入は手順3で行う。

## 事前準備（外部通信が発生し得る）

通信可能な準備環境で、対象ソースを確認して次のイメージを作成する。タグは例。準備工程は試験工程と分け、ソースのHEAD・差分・入力ハッシュとイメージIDを記録する。

```powershell
docker build -f spec/ci/Dockerfile.unit -t https-portal-prepared-unit:p3 .
docker build -t https-portal-prepared:p3 .
docker build -f spec/ci/Dockerfile.integration -t https-portal-prepared-tools:p3 .
docker image inspect --format '{{.Id}}' https-portal-prepared-unit:p3 https-portal-prepared:p3 https-portal-prepared-tools:p3
```

別端末へ搬入する場合はdocker save/load等で必要なイメージを移送する。転送ファイルのハッシュ・ソース対応も管理する。製品とtester内の試験コードはイメージへ埋め込まれているため、対象変更後は準備環境で作り直す。

## 試験実行（build・pullなし）

```powershell
.\dev\check_p2_baseline.ps1 -UsePreparedImages -UnitImage https-portal-prepared-unit:p3
.\dev\check_p2_integration.ps1 -UsePreparedImages -PortalImage https-portal-prepared:p3 -TestImage https-portal-prepared-tools:p3 -Scenario all
```

タグの代わりにローカルのsha256イメージIDも指定できる。結合試験の単独指定・Repeat・StartupTimeoutSecondsは従来どおり使用可能。

動作：

- UTはUnitImage、結合試験はPortalImageとTestImageの両方を必須とする。UsePreparedImagesなしでこれらを渡すこと、NoCacheとの併用、不正な参照文字列は失敗する。
- Docker EngineがLinuxであること、指定イメージがローカルに存在してLinuxイメージであること、取得したIDの形式を確認する。不足や不正時にbuild/pullへ切り替えない。
- 起動には解決したイメージIDを使用し、タグ変更の影響を抑える。UTのdocker run、Compose run/upには明示的にpull neverを付ける。
- UTはnetwork none、結合試験はinternal network・STAGE=localを維持する。公開DNS・公開ACMEは使用しない。
- UTは読み取り専用の現在ソースを一時コピーで試験する。既存のコンテナ内検証によりGemfile/Gemfile.lockとイメージ内の一致を確認し、不一致なら失敗する。
- 結合試験は指定した製品・toolsイメージ内のコードを実行する。指定イメージと現在ソースの全ファイル一致を自動保証する機能は今回追加していない。準備時のソース対応を確認する。

## 設定だけの確認

```powershell
.\dev\check_p2_integration.ps1 -UsePreparedImages -PortalImage https-portal-prepared:p3 -TestImage https-portal-prepared-tools:p3 -Scenario all -ValidateOnly
```

ValidateOnlyはCompose展開と隔離ガードのみ検証する。イメージ存在・Engine・実通信は検証しない。result=validatedをpassedと読み替えない。

## 証跡と失敗時

従来と同じdev/test-results/p2-baseline/またはp2-integration/の実行別ディレクトリに保存する。

| 記録 | 追加内容 |
|---|---|
| UT host-run.json | mode、指定imageTag、解決imageId、imagePlatform |
| IT result.json | mode、requestedImages、IT_PORTAL_IMAGE/IT_TEST_IMAGE（解決ID）、imagePlatforms |
| IT fixture env | 起動時には解決IDを設定。資格情報を含むため共有成果物へ入れない |

イメージ確認エラーはimage-preflight段階で失敗する。試験失敗は非0終了を維持し、結合試験の診断・対象projectのcleanup・残存確認も維持する。引数エラーはDocker呼び出し前に拒否するため、実行結果ディレクトリが作られない場合がある。

オフライン実行モードはホスト全体の通信遮断機能ではない。Docker CLI/Compose等の準備、Docker Desktop、ホストの他プロセスまで含めた外部通信ゼロの確認は、手順3で通信遮断・観測と合わせて行う。資材不足なら準備工程へ戻り、試験側で自動取得しない。