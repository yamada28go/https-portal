# 45 脆弱性レポート・SBOMの収集

[文書一覧](../00-index-ja.md) / [P3計画](40-implementation-plan-ja.md) / [検証記録](42-verification-ja.md)

状態：手順6初期のローカル製品収集は20261025t071211z-49f60b78で成功。security-reportのpush実行もrun 40174288486 / commit a1301d7で成功し、artifact生成を確認。CI成果物の内部照合とCritical/Highの一次分類が次工程。

## 今回の範囲

製品イメージの既知脆弱性JSONとCycloneDX SBOMを生成し、同じ保存イメージへ紐付けて保存する。Dockerが選択したIDと、archiveから検証したconfig digest（Trivy ImageID）を両方記録する。初回はreport-onlyとし、Critical/Highがあっても重大度だけでは失敗させない。例外リスト・重大度ゲート・ruleset/必須チェックはまだ導入しない。

一方、イメージ不足、古い/変更されたDB、検査エラー、不正/空のJSON・SBOM、image ID不一致、作業資材cleanup失敗は処理失敗とする。成功のresultはcollectedであり「脆弱性なし」「セキュリティ合格」を意味しない。

製品のバージョン・Dockerfile・通常動作・既存Tests workflowは変更しない。CodeQL、秘密情報検査、開発用Gemfile.lock単独の監査、外部ダウンロード物の正当性/ハッシュ照合、脆弱性の修正は今回の収集とは別工程。

## 固定したツール

- Trivy 0.76.1。dev/security/trivy-settings.jsonに公式イメージのmanifest digestを固定。
- 公式Docker Hubのmanifest応答とSHA-256を照合した。CLI版も公式releaseのchecksumを照合して検証に使用した。
- スキャナーの更新は設定レビューと再準備が必要。検査時に最新版へ自動追従しない。

## 1. 準備（外部通信あり）

プロジェクトルートで実行する。PowerShellとLinux Docker Engineが必要。

```powershell
$prepared = .\dev\prepare_p3_security.ps1
```

固定したTrivyイメージをpullし、新しい専用volumeへ脆弱性DBとJava DBを取得する。既存DB volumeを更新しない。準備後にscanner image ID、platform、両DBのmetadataと各2ファイルのSHA-256をprepared.jsonへ記録する。Java DBのない古いreceiptは再準備が必要。

成功時だけ、PreparationFile/ScannerImageId/DatabaseVolumeを持つオブジェクトを返す。ログはWrite-Hostへ出し、このオブジェクトと混ぜない。失敗時に次の検査へ進まない。

保存先：dev/test-results/p3-security-preparation/<実行ID>/。失敗した準備のreceiptはfailedとなり、検査へ使用できない。失敗した準備volumeは診断用に残る場合がある。

脆弱性DB本体は今回の検証時点で約1.6GB。これにJava DBの容量が加わる。検査用コピー・image archiveも作るため、それらを含めたDocker/ホストの空き容量が必要。DBの一時展開は小さなtmpfsへ入れず、専用volume上のTMPDIRを使う。

## 2. 検査（build・pull・外部通信なし）

手順3〜5で使用した製品イメージを検査する例：

```powershell
.\dev\check_p3_security.ps1 -PortalImage sha256:50799eef7566b2502e16e154f4829b8ef0997b86f922cf073f8bdf426b9df400 -PreparationFile $prepared.PreparationFile
```

PowerShellを開き直した場合は、PreparationFileに保存済みprepared.jsonの実パスを明示する。検査では新しい準備を自動実行しない。

- ローカルの製品・固定scannerをinspectし、解決したimage IDを使用する。
- DBはpurpose label、receiptのハッシュ、schema、UpdatedAtの鮮度を確認する。脆弱性DBはschema 2・既定最大48時間（MaxDatabaseAgeHours）、Java DBはschema 1・既定最大168時間（MaxJavaDatabaseAgeHours）。各1〜720時間で明示変更可能だが、古いDBには新規CVEや新しいJava成果物が反映されていない。
- 製品を一度だけdocker image saveし、archiveのSHA-256を記録する。固定scannerのnetwork noneコンテナでmanifest.jsonを読み、指定configの実バイトSHA-256とパス中のdigestを照合する。従来の64桁.jsonとblobs/sha256/64桁に対応し、manifest複数・不正パス・hash不一致は拒否する。config本文をログへ出さない。
- scannerコンテナはnetwork none、read-only、cap-drop ALL、no-new-privileges、pull never。Docker socket、ソース、ホスト認証ディレクトリをマウントしない。
- 両DBを含むvolumeは読み取り専用で渡し、dbとjava-dbを実行固有の作業volumeへコピーして使用する。DB/Java DB/checkの自動更新、依存API問い合わせ、version check、telemetryも無効にする。
- 検査対象はarchive。レジストリから取得し直さず、環境にある別タグへ切り替えない。
- 一度のTrivy JSONからImageConfig（環境変数・履歴等）を除去して保存し、その同じ結果からSBOMへ変換する。Trivy JSONのImageIDとSBOMのImageIDはarchive config digestと一致することを要求し、Docker側IDとの単純比較はしない。DBが途中で変更されていないことも再照合する。
- Java DBも準備・照合対象とする。これだけで対象外言語や手動導入部品を網羅したとみなさない。

## 成果物と判定

保存先：dev/test-results/p3-security/<実行ID>/。

| ファイル | 内容 |
|---|---|
| result.json | collected/failed、stage、Docker ID/platform、scanImageId/configPath、reportImageId、scanner、DB、実行識別子、cleanup |
| summary.json | 全重大度の件数、package数、SBOM component数、Docker IDとscanImageId、DB日時/ハッシュ、report-onlyの明示 |
| vulnerabilities.json | Trivy形式の検査結果。ImageConfigを除去済み |
| sbom.cdx.json | 同一結果から生成したCycloneDX。metadataのImageIDが検証済みarchive config digestと一致することを検査 |
| external-components.json | s6-overlay/docker-gen/acme-tinyのimage ENV宣言版。実体hash検証・CVE網羅性は未確立と明記 |
| artifacts.sha256 | 上記の主要4成果物のSHA-256 |
| *.stdout.log / *.stderr.log | 検査・変換・DB照合・cleanupの診断。共有はworkflowの許可リストを使用 |

正常終了ではcollected/complete、cleanup=passed。package一覧・SBOMが空でも成功させない。Critical/Highがあれば次の一次分類に利用する。ゼロ件でも未検出の部品やDB範囲外があるため、安全の証明とはしない。

製品のS6_OVERLAY_VERSION等は宣言文字列であり、実バイナリの版・取得物の正当性を証明しない。補助台帳の不足を後続で埋め、SBOMと実体を突き合わせる。ローカルでは「指定image ID」の検査であり、現在のソースHEADとの一致を自動保証しない。

## 後片付け

通常終了/検査エラー後は専用作業volume、image archive、未加工raw reportを削除する。製品・scannerイメージ、準備DB volumeは次のオフライン検査のため残す。不要になった古いDBはprepared.jsonのDatabaseVolumeとpurpose labelを確認して個別削除する。共有volumeのpruneは行わない。

強制終了・runner喪失時はfinallyやdocker runの自動削除が完了しない場合がある。GitHub-hosted runnerは破棄に委ねられる。ローカルに残った資材は当該runのログと名前を照合して回収する。

## GitHub Actions

新設の.github/workflows/security.ymlは既存Testsと独立したsecurity-reportジョブ。push/PR/手動/日次で、製品build→scanner/DB準備→隔離検査→artifact保存を実施する。日次は06:17 JST指定で、schedule/手動の利用にはdefault branchへの反映等の条件がある。

- contents:read、checkoutの資格情報保存なし。SARIF送信・レジストリ公開・新Secretsは不要。
- 重大度ゲートは未設定。検査処理自体の異常は赤になる。
- summaryに重大度別の件数を表示し、許可したJSON/SBOM/hash/診断だけを14日間保存する。DB・archive・raw reportはuploadしない。
- 初期設定ではscanner/DB準備の外部通信がある。試験中のコンテナ隔離とActions全工程の通信は区別する。
- ブランチ保護は変更していない。まず実際の検出結果・部品の不足をレビューし、その後に例外ポリシー・マージ判定を導入する。

## 検証・次の受入

dev/security/check-contracts.ps1で、重大検出を収集できること、空/不正JSON・SBOM、image ID不一致、古い/変更されたDBの拒否とImageConfig除去を検証する。Actionsでもbuild前に実行する。

今回の開発検証はPowerShell構文、actionlint、17項目のデータ契約、Docker代役の10異常系/正常系、および実Trivyで合成image archive→検査→秘匿設定除去→SBOM変換を確認した。これを製品の初回検査成功とは扱わない。

利用者は準備と製品の検査を実行し、Evidenceを共有する。result=collected、image ID/DB対応、SBOM内容、外部部品の不足を照合した後、今回変更のActionsを受け入れる。次段階で初回検出を分類し、期限付き例外と重大度ゲートの仕様を確定する。

一次資料：[Trivy air gap](https://trivy.dev/docs/latest/guide/advanced/air-gap/)、[DB設定](https://trivy.dev/docs/dev/configuration/db/)、[公式release](https://github.com/aquasecurity/trivy/releases/tag/v0.76.1)。固定版のhelpとソースでも互換を確認した。
Java DB準備漏れの修正後は準備を再実行する。実Java DBとJava入り合成イメージで検査・SBOM変換、データ契約23件、Docker代役15件を確認した。製品実検査は引き続き再実行待ち。詳細は検証記録を参照。

ID照合修正後は、Java DBを含む成功済みprepared.jsonをそのまま再利用してcheckだけ再実行できる。Docker側のIDはmanifest/index digestとなる場合があり、Trivyのconfig digestと直接比較しない。既存の生レポートはcleanupで削除済みのため、過去の失敗で実際に報告されたIDは未確定。再実行では検証済みdigestをresult.jsonへ記録する。

準備receiptの相対パスはPowerShellの現在位置から解決する。process directoryが異なる場合の回帰確認を含め、データ契約32件が成功。

最新受入：製品でcollected/complete、cleanup=passed。主要4成果物hashとJSON/SBOMのconfig ID一致を確認。package entry 272、SBOM component 274。Critical 12 / High 135 / Medium 198 / Low 237 / Unknown 18を収集した。検出の解消は未実施。詳細は検証記録の『製品イメージの初回収集受入成功』を参照。

Linuxのbind権限：検査前に今回runのarchiveを0640、inputを0750、result directoryを02770、ホスト側で事前作成したraw JSON/SBOMを0660へ設定し、実GIDをscannerへ--group-addで渡す。cap-drop ALLを維持し、入力読取りと出力書込みを許可する。Windowsのbind動作は変更しない。初回Actionsのarchive Permission deniedへの修正であり、修正後の新commitでActions再受入が必要。
