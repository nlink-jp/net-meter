# net-meter

1 つのネットワークインターフェースの現在の上り/下り速度を、数値とグラフで macOS の
メニューバーに表示します。

同じことができる既存のアプリは、統合システムモニタの一機能として提供されています。
net-meter はこれだけを行います。

[English](README.md)

## 動作環境

- macOS 26 以降、Apple Silicon。
- 権限は不要です。プライバシーの許可、管理者権限、entitlement のいずれも必要とせず、
  アプリ自身はネットワーク通信を行いません。

> macOS 向けリリースは **Developer ID で署名し、Apple の公証（notarize）を受けて**
> います（staple 済み）。Gatekeeper の警告なしに起動でき、オフラインでも動作します。

## ソースからのビルド

```bash
make build-app
```

`dist/NetMeter.app` が生成されます。署名にはキーチェーン内の Developer ID Application
を使います。無い場合もビルドは成功し、アプリは ad-hoc 署名のままになります。
ビルドした Mac で動かすにはそれで足ります。

```bash
make test
```

```bash
make run
```

`make run` はデバッグビルドを端末から起動します。先に、実行中の net-meter を終了して
ください。単一インスタンスガードが効くのは組み立て済みの `.app` だけです。デバッグ
バイナリには識別に使う bundle identifier が無いため、そのまま起動してメニューバーの
項目が 2 つになります。

## ドキュメント

- [RFP](docs/ja/net-meter-rfp.ja.md) — スコープ、挙動、その背景にある設計判断
- [スパイク](spikes/README.md) — 設計の根拠になった実測

## ライセンス

MIT
