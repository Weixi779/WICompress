# Target compression benchmark

这个 macOS developer executable 为 `WICompressionTarget` 建立可重复的黑盒基线。
它先测量当前公开 `WICompressor.compress` 的真实结果，暂不抽取搜索协议，也不改变生产算法。

Benchmark 与单元测试职责不同：测试固定正确性合同；benchmark 记录同一环境、同一输入下
的结果形态和执行成本，不在 CI 中设置易波动的性能阈值。

## Run

执行默认 smoke corpus：

```sh
swift run -c release TargetCompressionBenchmark
```

快速验证工具链：

```sh
swift run -c release TargetCompressionBenchmark \
  --input Tests/WICompressTests/Resources/real_jpeg_2098x1350_landscape.jpg \
  --ratios 0.5 \
  --runs 1 \
  --warmup 0
```

对本地真实图片目录执行完整测量：

```sh
swift run -c release TargetCompressionBenchmark \
  --input benchmarks/target-compression/data \
  --ratios 0.5,0.2 \
  --bytes 1048576,524288 \
  --runs 3 \
  --warmup 1 \
  --json benchmarks/target-compression/results/current.json \
  --artifacts benchmarks/target-compression/artifacts/current
```

`data/`、`results/` 与 `artifacts/` 默认忽略，不会把本地语料、测量结果或编码产物提交到仓库。
默认 corpus 从当前 Package checkout 定位，不依赖命令执行时的 working directory；自定义
`--input` 相对路径仍然相对于 working directory 解析。

## Corpus

未传 `--input` 时，默认 smoke corpus 使用现有测试资源中的四张真实图片：

- JPEG 照片；
- HEIC 照片；
- 带 Alpha 的 PNG；
- 不透明 PNG。

Smoke corpus 用于验证 JPEG、HEIF 与 PNG 三条路径和报告工具，不足以证明某个搜索算法更优。
真正选择算法时应传入更大的本地 corpus，并至少覆盖照片、截图与文字、渐变、高噪点/高细节、
Alpha、全景图、长图和已经重压缩过的输入。

输入 JPEG、HEIC/HEIF 和 PNG 会分别使用显式 JPEG、HEIC 和 PNG 输出。这样有损质量搜索与
PNG 尺寸搜索分别报告，不把不同 codec 的 quality 值当作同一视觉尺度。

## Scenarios

`--ratios` 使用 `(0, 1]` 内的值，根据每张源文件的 byte count 生成预算；`--bytes` 使用
绝对预算。两者可以同时提供。
默认预算为源文件的 `0.5` 和 `0.2`。所有场景使用：

```text
sizing: original
metadata: strip
color space: sRGB
representation: explicit source container family
```

因此输出尺寸是否变化由 Target 搜索决定；benchmark 不预先替算法指定 quality、缩放层级或
尝试次数。

## Metrics

终端表格和可选 JSON 报告记录：

- hard byte limit 是否满足；
- 输出 bytes 与预算利用率；
- 输出 format、pixel size 与相对像素面积；
- 多次执行的原始耗时和中位耗时；
- 同一 case 的输出签名是否稳定；
- 每次 run 的结构化成功/失败、输出事实与公开错误 code；
- 输入与代表输出的 SHA-256；
- schema、strategy、Release/Debug、OS、CPU、Swift、Git revision 与 dirty 状态。

输出签名包含 format、pixel size、byte count 与 SHA-256；同一环境下任意 encoded-byte 差异都会
记为 `outputSignatureUnstable`。这是 benchmark 用来发现回归的额外约束，不是公开压缩 API 的
字节确定性承诺。

计时包含一次完整公开压缩调用，包括 inspection、decode、render、encode 和结果 inspection。
输入文件读取、warmup、独立输出验证、artifact 写入、汇总与 JSON 编码不在计时范围内。
成功结果会在计时结束后重新通过 `WIImageIO` 完整 decode，并校验容器、尺寸、sRGB、
GPS/IPTC/MakerNote 与 hard byte limit。ImageIO 可能生成 destination Exif/TIFF facts，因此这里
不把它们误判为源隐私 metadata 残留。每个 case 串行运行，不与其他图片并发争用 CPU 或 ImageIO。

`passed` case 才会写 artifact。warmup 或独立验证失败也会成为结构化 case/run 结果；
`warmupFailed`、`failed`、`mixedOutcome`、`outputSignatureUnstable` 或 `limitViolation`
会保留完整报告并让 executable 以非零状态退出；指定 `--json` 时，JSON 会在退出前写完。

首版故意不提供单一“综合质量分数”。像素面积、预算利用率和耗时分别呈现；最终图片可以通过
`--artifacts` 保留给人工或后续感知指标工具比较。

## Current boundary

JSON schema 从 `1` 开始，当前 strategy ID 为 `current`。fixture 使用相对于 corpus 根目录的
路径与完整内容 hash 识别；artifact 文件名包含内容 hash、精确 budget 与 target bytes，避免
递归目录中的同名图片互相覆盖。

当前 benchmark 只能观察公开结果和完整 terminal 耗时，还不能读取 encode attempt、render
次数与候选轨迹。下一阶段可在本基线之上重新评估搜索逻辑的抽取方式，以及是否需要统一的
attempt/observation 测量边界。生产默认算法在数据支持替换前保持不变。
