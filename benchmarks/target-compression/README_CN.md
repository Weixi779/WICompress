# Target Compression Benchmark

[English](README.md) | 简体中文

这个 macOS developer executable 为 `WICompressionTarget` 建立可重复的黑盒证据。
它测量公开 `WICompressor.compress` 的真实结果，不向生产 API 暴露 strategy、搜索参数或
内部候选轨迹。它是仓库内的开发工具，不属于受支持的 public library surface。

Benchmark 与单元测试职责不同：测试固定正确性合同；benchmark 记录同一环境、同一输入下
的输出形态、质量和执行成本，不在 CI 中设置易波动的性能阈值。

## Run

执行默认四图 smoke corpus。默认显式输出 JPEG，预算为源文件字节数的 `0.5` 和 `0.2`：

```sh
swift run -c release TargetCompressionBenchmark
```

快速验证全部编码分支与 bpp budget：

```sh
swift run -c release TargetCompressionBenchmark \
  --input Tests/WICompressTests/Resources/real_jpeg_2098x1350_landscape.jpg \
  --representations jpeg,heic,png \
  --bpp 0.5 \
  --runs 1 \
  --warmup 0
```

正式测量 JPEG AI CfE：

```sh
./benchmarks/target-compression/fetch-corpora.sh jpeg-ai-cfe

swift run -c release TargetCompressionBenchmark \
  --input benchmarks/target-compression/data/corpora/jpeg-ai-cfe \
  --representations jpeg,heic \
  --bpp 0.15,0.3,0.6,1.0 \
  --runs 3 \
  --warmup 1 \
  --strategy-id current \
  --json benchmarks/target-compression/results/current.json \
  --artifacts benchmarks/target-compression/artifacts
```

`data/`、`results/` 与 `artifacts/` 默认忽略，不会把本地语料、测量结果或编码产物提交到
仓库。默认 fixture 从 Package checkout 定位；自定义 `--input` 相对路径相对于当前 working
directory 解析。Artifact 会写入 `--artifacts` 下经过文件名安全处理的 strategy 子目录，避免
baseline 与 candidate 复用根目录时互相覆盖；文件名同时携带可读 budget 和精确的整数或
IEEE-754 bit-pattern identity，接近但不相同的 ratio/bpp case 也不会互相覆盖。

## Compare

生产代码不提供 benchmark strategy switch。应在 baseline 与 candidate revision 分别运行，
再离线比较两份 schema-v2 JSON：

```sh
swift run -c release TargetCompressionBenchmark compare \
  --baseline benchmarks/target-compression/results/baseline.json \
  --candidate benchmarks/target-compression/results/candidate.json \
  --json benchmarks/target-compression/results/comparison.json
```

仅做等价结构重构时增加：

```sh
--require-identical-output
```

它要求每个配对 case 的状态以及稳定、非空 output signature 全部相同；signature 包含 format、
pixel size、byte count 与 SHA-256。两侧都失败且都没有输出，不会被误判为严格等价。
Comparator 还会拒绝不同 schema、case 集合、quality protocol、build configuration、OS 或
architecture。CPU、Swift、run/warmup 数量不一致时仍可比较结果，但会禁用 timing delta。
报告会记录 Package、生产 Sources 与 benchmark Sources 的有序内容 fingerprint。只要任一报告
来自 dirty worktree，Comparator 也会禁用 timing；提交前后的 clean revision 才能形成可重建的
正式性能对照。dirty 报告仍可比较 hard limit、输出、尺寸与质量。
Strict comparison 会先打印并写出包含 mismatch keys 的 comparison report，再以非零状态结束。
Comparison JSON 还会区分 measured、exact match、unavailable、measurement failure 与 missing
quality；PSNR/SSIM 只报告绝对差，其他线性指标同时报告相对百分比。

## Corpus

未传 `--input` 时使用现有测试资源中的 JPEG、HEIC、透明 PNG 和不透明 PNG，负责平台和
正确性 smoke，不承担算法质量结论。

正式 corpus 由 [corpora manifest](corpora/README_CN.md) 管理：

- JPEG AI CfE 16：快速评审集；
- CLIC 2020 Professional validation：41 张；
- CLIC 2020 Mobile validation：61 张。

仓库只保存官方 URL、完整性锁和本地获取脚本，不保存图片或 ZIP。脚本校验 HTTP、archive
或解压图片 checksum、ZIP 成员、文件数量与目录形态；不传 corpus 时不会自动下载。Mobile
与 JPEG AI 没有明确的再分发授权，因此不得进入 Git、Git LFS、Release artifact 或镜像。

## Scenarios

一个 case 是：

```text
fixture × requested representation × budget
```

`--representations` 接受 `jpeg`、`heic`、`png`，与源容器完全独立。JPEG 固定使用白色背景，
所有场景使用：

```text
sizing: original
metadata: strip
color space: sRGB
representation: explicit
```

预算可以组合使用：

- `--ratios`：源 encoded bytes 的比例，用于历史产品回归；
- `--bytes`：绝对字节限制，用于分享 SDK 等硬性合同；
- `--bpp`：基于 display-oriented source pixel area 的 bits per pixel。

bpp 始终使用源图面积，而不是输出面积：

```text
targetBytes = floor(sourceWidth × sourceHeight × requestedBPP / 8)
actualBPP = outputBytes × 8 / (sourceWidth × sourceHeight)
```

因此算法通过缩图节省字节时，码率数字不会被输出面积反向“美化”；空间分辨率损失由
`pixelAreaRatio` 单独表达。

## Metrics

终端表格和 JSON 报告记录：

- hard byte limit 与预算利用率；
- output format、pixel size、actual bpp 与 pixel-area ratio；
- 多次运行的原始耗时、中位耗时和稳定输出签名；
- RGB MSE / PSNR 与 luma SSIM；
- 输入、输出 SHA-256；
- schema、strategy、OS、CPU、Swift、Git revision 与 dirty 状态。

质量计算完全位于计时区外。协议固定为：

1. ImageIO 解码 source/output，并显式应用 EXIF orientation；
2. 转换为 8-bit sRGB；
3. 用 benchmark 自己的 vImage high-quality scaler 将 pristine source 缩到实际输出尺寸；
4. 计算 RGB MSE/PSNR；
5. 使用 BT.709 luma、11×11 Gaussian、σ=1.5 的 valid-window SSIM。

它不复用 production `ImageRenderer`，避免候选算法与参考图同时变化而掩盖回归。若
source 或 output 存在非不透明像素，当前协议不计算感知指标并记录原因；仅仅携带一个
全不透明 Alpha channel 不会被误判。小于 11×11 时仍计算 PSNR，SSIM 为 unavailable。
精确像素匹配使用 `exactMatch = true`，PSNR 保持 `null`，避免把 infinity 写进 JSON。

单个标准化 RGBA 像素面上限为 256 MiB，并在真正 decode 前按 inspection dimensions
检查。SSIM 的 signals、horizontal ring 与 statistics 另有合计 256 MiB 的 workspace 上限，
所有乘法和加法先检查溢出；任一上限超出都会成为 `qualityMeasurementFailed`，避免极端输入
让 benchmark 自身失去可执行性。

PSNR/SSIM 只评价最终分辨率下的编码与渲染误差，不惩罚缩图，因此必须和
`pixelAreaRatio` 一起阅读。本工具不生成单一综合分数。

## Validation and Status

计时包含一次完整公开压缩调用。输入读取、warmup、独立输出验证、质量计算、artifact 写入
与 JSON 编码不在计时范围内。成功结果会在计时后通过 `WIImageIO` 完整 decode，并校验容器、
尺寸、orientation、sRGB、隐私 metadata 与 hard byte limit。

同一 case 的输出签名包含 format、pixel size、byte count 与 SHA-256。任何 encoded-byte 差异
都会成为 `outputSignatureUnstable`；这是 benchmark 的回归约束，不是公开 API 的字节确定性
承诺。质量协议自身失败会成为 `qualityMeasurementFailed`，保留已验证输出与计时，但让命令
以非零状态结束。启用 `--artifacts` 时，这类 case 仍会保存 validated compression output，
用于诊断质量测量失败。

JSON schema 当前为 `2`。fixture 由 corpus-relative path 与完整内容 hash 共同识别；配对 key 还包含
requested representation、原始 budget 值与 resolved target bytes。

当前工具只能观察完整 terminal 耗时，不能读取 encode attempt、render 次数或候选轨迹。
生产算法是否更换，必须由同一 corpus、同一协议、同一环境下的配对报告决定。
