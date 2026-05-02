# workers-benchmark

Hono と Elysia を **Bun ネイティブ** と **Cloudflare Workers (workerd)** の両環境で計測し、ランタイム差・フレームワーク差を比較するためのベンチプロジェクト。

主な動機: 「Elysia は Bun に最適化されて速い」と公称されているが、Workers (workerd ≠ Bun) に乗せるとどうなるか、Hono とどれくらい差が出るかを実測する。

---

## 構成

```
workers-benchmark/
├── bench.sh                  # ベンチドライバ（local | remote）
├── summarize.sh              # 結果 JSON を集計表示
├── targets.local.json        # ローカル URL（自動）
├── targets.remote.json       # デプロイ後の URL（手動・gitignore）
├── targets.remote.example.json
├── results/<timestamp>-<mode>/  # 各実行の oha JSON 出力
└── apps/
    ├── workerd-hono/         # `bun create cloudflare` ＋ hono — wrangler dev / deploy
    ├── workerd-elysia/       # 同上 ＋ elysia + CloudflareAdapter
    ├── bun-hono/             # Bun.serve ＋ hono
    └── bun-elysia/           # Elysia .listen() ＋ Bun
```

各アプリは同一の 4 エンドポイントを公開:

| Method | Path           | Body / Response                |
| ------ | -------------- | ------------------------------ |
| GET    | `/`            | `Hello` (text)                 |
| GET    | `/json`        | `{ hello: "world" }`           |
| GET    | `/params/:id`  | `:id` をエコー (text)          |
| POST   | `/echo`        | リクエスト body をそのまま返す |

すべてのハンドラは **関数形式** に統一（後述の Elysia/Workers 制約のため）。

---

## 計測条件

### バージョン (2026-05-02 時点)

| ツール / ライブラリ | バージョン |
| ------------------- | ---------- |
| Bun                 | 1.3.8      |
| Wrangler            | 4.87.0     |
| Hono                | 4.12.16    |
| Elysia              | **1.4.28** （Elysia 2α は npm 未公開のため stable 最新） |
| oha                 | 1.14.0     |
| OS                  | macOS (Darwin 25.0.0, arm64) |

### oha パラメータ

- ウォームアップ: **5s × 50 並列**（結果は捨てる）
- 本計測: **30s × N 並列**（結果を JSON 保存）
- POST には `{"hello":"world"}` を `application/json` で投げる

`bench.sh` の環境変数で上書き可能:
- `DURATION` (デフォルト `30s`)
- `CONCURRENCY` (デフォルト `200`)
- `WARMUP_DURATION` (デフォルト `5s`)
- `WARMUP_CONCURRENCY` (デフォルト `50`)

### モード

| モード   | 起動方法                          | 対象             |
| -------- | --------------------------------- | ---------------- |
| `local`  | 各アプリを順次起動 → 計測 → 停止 | 全 4 アプリ      |
| `remote` | `targets.remote.json` の URL を直接叩く | デプロイ済 worker |

---

## 結果 (2026-05-02)

### バンドルサイズ・コールドスタート（`wrangler deploy` 出力）

| アプリ          | uncompressed | gzipped       | Worker Startup Time |
| --------------- | ------------ | ------------- | ------------------- |
| workerd-hono    | 61.70 KiB    | **15.14 KiB** | **6 ms**            |
| workerd-elysia  | 840.32 KiB   | **154.88 KiB** | **34 ms**           |

→ Elysia は Hono の **約 10 倍 (gzip 後)** のサイズ、コールドスタートも **5.7 倍** 遅い。
   Free tier の 1 MB 上限に対して Elysia は 84% 占有しており、プラグインを追加する余地が薄い。

### Bench: local (`./bench.sh local` を `CONCURRENCY=50` で実行)

> wrangler dev は `200` 並列だと connection refused が出るため、ローカルは **50 並列で統一**。
> 実行: `CONCURRENCY=50 ./bench.sh local` / 全エンドポイント 100% success / `results/20260502-172812-local/`

| アプリ           | path        | rps        | p50 (ms) | p99 (ms) |
| ---------------- | ----------- | ---------- | -------- | -------- |
| **bun-elysia**   | `/`         | **82,481** |   0.535  |   1.408  |
|                  | `/json`     |    78,372  |   0.566  |   1.480  |
|                  | `/params`   |    77,541  |   0.563  |   1.587  |
|                  | `POST /echo` | 56,075    |   0.802  |   1.996  |
| **bun-hono**     | `/`         |    62,031  |   0.720  |   1.768  |
|                  | `/json`     |    57,582  |   0.756  |   2.076  |
|                  | `/params`   |    64,802  |   0.686  |   1.764  |
|                  | `POST /echo` | 52,306    |   0.871  |   1.970  |
| **workerd-elysia** | `/`       |     2,509  |  17.392  |  52.181  |
|                  | `/json`     |     2,320  |  19.044  |  55.713  |
|                  | `/params`   |     1,161  |  35.415  | 153.156  |
|                  | `POST /echo` |   647     |  69.759  | 274.244  |
| **workerd-hono** | `/`         |     2,709  |  16.155  |  45.894  |
|                  | `/json`     |     2,700  |  16.108  |  48.670  |
|                  | `/params`   |     2,720  |  16.068  |  45.525  |
|                  | `POST /echo` |  2,477    |  17.426  |  51.922  |

### Bench: remote (デプロイ済 Workers, `./bench.sh remote` 200 並列)

> 実行: `./bench.sh remote` / `results/20260502-170047-remote/`
> 注: 各アプリの最初に叩いた `/` は TLS 初期接続・コールドスタート・workers.dev 側の DDoS 緩和の影響で遅い（**外れ値**として除外推奨）

| アプリ           | path        | rps        | p50 (ms) | p99 (ms) | 備考           |
| ---------------- | ----------- | ---------- | -------- | -------- | -------------- |
| **workerd-hono** | `/`         |     1,762  |  13.801  | 297.564  | 初回外れ値     |
|                  | `/json`     |    13,688  |  13.553  |  27.983  |                |
|                  | `/params`   |    14,201  |  13.217  |  25.655  |                |
|                  | `POST /echo` | 14,284    |  13.211  |  25.004  |                |
| **workerd-elysia** | `/`       |     1,397  |  13.776  |1098.981  | 初回外れ値     |
|                  | `/json`     |    14,013  |  13.377  |  23.571  |                |
|                  | `/params`   |    14,267  |  13.188  |  23.080  |                |
|                  | `POST /echo` | 14,239    |  13.171  |  23.363  |                |

> ⚠️ **Free tier (100k req/day) を一回の bench で 30 倍以上消費する**ので、再計測は paid プラン or 並列度・時間を絞ること。

---

## 結論

1. **Bun ネイティブでは Elysia が Hono より ~25% 速い**（local 50 並列で 78K vs 58K rps レベル）。Elysia の "Bun 最適化で速い" は実測でも裏付けられる。
2. **Workers (workerd) では Hono ≈ Elysia がほぼ同等**（remote 14K rps レベル / `/`, `/json`, `/params`, `POST /echo` で大きな差なし）。
   - Bun でのフレームワーク差は workerd に乗せると消える。
   - 「Elysia は Bun だから速い」が改めて確認された。
3. **絶対値で見ると workerd-remote は Bun ネイティブの 1/6 〜 1/12 倍（14K vs 56K-82K）**。Workers のスループット要件があるなら Bun を直接使う方が圧倒的に有利。
4. **Workers 上のフレームワーク選定基準は性能ではなく、バンドルサイズ・DX・型安全のような軸で決めるべき**。Hono は **gzip 15 KiB / startup 6 ms** で Elysia (155 KiB / 34 ms) より圧倒的に軽い。

### local データの注意点（Elysia / wrangler dev の挙動）

- `workerd-elysia` の `/params`, `POST /echo` は計測順が後ろになるほど rps が落ちている (2509 → 1161 → 647)。`workerd-hono` は同じ順番でも 2477〜2720 で安定。
- `wrangler dev` (Miniflare) のサンプル抽出特性が、Elysia の AOT で生成された巨大な handler コードと相性が悪い可能性。**production deploy 経由 (remote) の数値ではこの劣化は出ていない** (14K rps で安定)。
- → ローカル数値は「相対比較」用とし、絶対値の評価は **remote** に頼ること。

---

## Elysia 2 リリース時の再計測手順

Elysia 2 が npm に publish されたら、以下の手順で再計測する:

```bash
# 1. 両 Elysia アプリのバージョンを上げる
cd apps/workerd-elysia && bun add elysia@2
cd ../bun-elysia      && bun add elysia@2

# 2. 動作確認 (静的値ハンドラ禁止の制約は v2 でも残る可能性があるので注意)
bunx wrangler dev --port 8788 --ip 127.0.0.1   # workerd-elysia
PORT=3001 bun run index.ts                     # bun-elysia

# 3. ローカルベンチ
cd ../..
CONCURRENCY=50 ./bench.sh local
./summarize.sh

# 4. (任意) 本番ベンチ
cd apps/workerd-hono && bunx wrangler deploy
cd ../workerd-elysia && bunx wrangler deploy
# URL を targets.remote.json に書く
cd ../..
./bench.sh remote
./summarize.sh

# 5. 計測後はワーカー削除（Free tier の quota 圧迫を避ける）
cd apps/workerd-hono && bunx wrangler delete
cd ../workerd-elysia && bunx wrangler delete
```

**比較したい主な数値**:
- バンドルサイズ (`wrangler deploy` 出力 `Total Upload`)
- Worker Startup Time (同 `Worker Startup Time`)
- 本記録の rps / p50 / p99 と、特に **workerd 上での Elysia の数値が Hono に追いつくか／追い越すか**

公式アナウンスでは「Runtime (serving request) gets a bit faster too」とあるので、リクエスト処理パスの最適化が workerd 上の Hono との差にどれくらい現れるかが見どころ。

---

## 既知の制約・注意点

### Elysia × Cloudflare Workers の制約

[公式 Caveat](https://elysiajs.com/integrations/cloudflare-worker) より:

1. `Elysia.file` / Static Plugin は `fs` 依存のため動かない
2. OpenAPI Type Gen も同様に動かない
3. **サーバ起動前に `Response` を定義することができない** (Workers のグローバルスコープ制約)
4. **静的値ハンドラ (`.get('/', 'Hello')`) は使えない** (#3 の派生) → **必ず関数 (`.get('/', () => 'Hello')`)** で書く
5. `nodejs_compat` フラグは不要（Elysia は Node 組み込みを使わない）

→ 全 4 アプリで関数ハンドラに統一しているのはこの制約のため。

### `wrangler dev` のローカル並列限界

- `200` 並列だと connection refused が頻発し、特に Elysia 側で connection accept キューが溢れる。
- 本リポでは local を `CONCURRENCY=50` に下げて運用している。
- ただし wrangler dev は本番 workerd と同じ JS エンジンを使うものの、**Miniflare ↔ workerd の IPC オーバーヘッド** がスループットの上限を作っているため、フレームワークの上限値を見るには **デプロイ後 (remote)** の数値で判断する方が正確。

### Free tier の quota

- Cloudflare Workers Free tier は **100,000 リクエスト/日**。
- このベンチ (30s × 200c × 4 endpoint × 2 app ≒ 340 万リクエスト) は 1 回で 1 日上限の 30 倍以上を消費する。
- 再計測する場合は paid プラン化、または `DURATION` / `CONCURRENCY` を絞ること。

---

## コマンド早見表

```bash
# 依存インストール
brew install oha jq
cd apps/workerd-hono   && bun install
cd ../workerd-elysia   && bun install
cd ../bun-hono         && bun install
cd ../bun-elysia       && bun install
cd ../..

# ローカル全 4 アプリベンチ (推奨: 50 並列)
CONCURRENCY=50 ./bench.sh local

# 結果集計（最新 results/* を自動選択）
./summarize.sh

# デプロイして remote bench
cd apps/workerd-hono   && bunx wrangler deploy && cd ../..
cd apps/workerd-elysia && bunx wrangler deploy && cd ../..
# 出力された URL を targets.remote.json に転記
./bench.sh remote
./summarize.sh

# クリーンアップ
cd apps/workerd-hono   && bunx wrangler delete && cd ../..
cd apps/workerd-elysia && bunx wrangler delete && cd ../..
```
