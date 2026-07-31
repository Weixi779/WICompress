# WICompress 2.0 Target Compression

状态：Target Domain、Sizing、共享 Output 与执行计划边界已实施。

本文记录 `WICompressionTarget` 在 2.0 中已经接受的职责、输入组合、结果保证与非目标。
后续实现可以依赖这些结论，不需要重新打开 1.x `geometry`、`preference` 或平台 preset
的讨论。

内部状态与编排已经由
[`V2_IMAGE_PIPELINE_CN.md`](V2_IMAGE_PIPELINE_CN.md) 重新冻结；本文关于独立
Resolver、Solver 和 ExecutionPlan 的描述仅记录当前实现，不再代表目标架构。

跨产品线边界以 [`V2_DOMAIN_MODEL_CN.md`](V2_DOMAIN_MODEL_CN.md) 为准。能力全集、
外部平台调研和设计取舍证据保留在
[`V2_CAPABILITY_MAP_CN.md`](V2_CAPABILITY_MAP_CN.md)；本文不重复调研过程。
Crop 与 resize 的执行合同见
[`V2_IMAGE_RASTER_CN.md`](V2_IMAGE_RASTER_CN.md)。

## 产品职责

Target Compression 服务一个明确场景：外部系统对 encoded image data 给出硬字节上限，
调用方需要在发送或上传前得到满足该上限的图片。

```text
source image + target contract
    -> solver 反推尺寸与有损质量
    -> encoded result
```

它与 `WIImageProcess` 保持两条公共产品线：

| Domain | 调用方决定 | 库决定 | 成功合同 |
|---|---|---|---|
| `WIImageProcess` | 确定的处理尺寸、裁剪和 quality | 如何执行 ImageIO/Core Graphics pipeline | 按声明处理一次，不保证 byte count |
| `WICompressionTarget` | maxBytes、sizing、immutable output requirements | candidate scale、quality、尝试和选择 | 最终 `byteCount <= maxBytes` |

Target 不继承、不包装 `WIImageProcess`。两条线只在 internal execution plan 汇合。

## 公共信息分组

Target 只包含三组外部事实：

```swift
WICompressionTarget(
    maxBytes: ...,
    sizing: ...,
    output: ...
)
```

### maxBytes

- `maxBytes` 必须大于零。
- 它是 Target 最核心的硬约束。
- 成功结果必须满足 `data.count <= maxBytes`。
- 不能以 warning、diagnostic 或“最接近结果”代替该保证。

### sizing

Sizing 由两个正交的可选输入组成：

```swift
WICompressionSizing(
    maximumPixelSize: ...,
    aspectRatio: ...
)
```

以下可观察语义已经冻结并实现。

#### maximumPixelSize

- 表示 base candidate 的最大像素边界，不是最终精确尺寸。
- 保持比例，只缩小，不放大。
- solver 为满足 `maxBytes` 可以继续产生更小的候选。

#### aspectRatio

- 只接受调用方已经决定好的具体比例。
- 它是输出形状约束，不是 soft preference。
- 源图比例不满足时，使用该比例的最大内接矩形裁剪。
- 裁切携带 normalized anchor，默认是 `.center`。
- anchor 使用左上原点的图片坐标，`x/y` 必须位于 `0...1`。
- 不公开九宫格 alignment enum、fit、fill 或任意 crop mode。

### output

Target 使用与 `WIImageProcess` 相同的共享 Output Domain。完整合同见
[`V2_DOMAIN_MODEL_CN.md`](V2_DOMAIN_MODEL_CN.md)。

Target 的默认 Output 面向分享和上传：

```text
representation: PNG when Alpha, otherwise JPEG
metadata: strip
color space: convert to sRGB
```

调用方可以显式选择 preserve source representation、JPEG、JPEG with opaque background、
PNG、HEIC，以及 preserve/convert color space。JPEG 遇到透明源时默认失败；Alpha flatten
必须显式声明不透明背景。

Quality 不属于 Output；它由 Target solver 所有，并且不能在搜索期间改变 representation、
metadata 或 color-space 合同。

## 当前实施状态

- `WICompressionTarget.output` 已统一为共享 `WIImageOutput`，不再维护重复的
  `WICompressionOutput`。
- Target 默认 Output 已按冻结合同实现：Alpha 源输出 PNG，否则输出 JPEG；strip
  metadata；转换到 sRGB。
- `WICompressionSizing` 的四种输入组合、normalized anchor 和一次性 crop/base-size
  解析已实现。
- Public `geometry`、candidate `preference`、canvas placement 及其旧 resolver 已删除。
- Target resolver 与 solver 直接产出共享 `WIExecutionPlan`，不再经过旧
  `WIWritePlan` adapter。
- Data 与 file URL 使用同一 file-backed pipeline；原始字节只在 passthrough 时按需读取。
- Byte-search 算法保持原有平衡选择行为，本次只收紧 Domain 与执行边界。

## Sizing 组合真值表

两个可选输入形成四种完整状态：

| maximumPixelSize | aspectRatio | Base candidate |
|---|---|---|
| 无 | 无 | 使用源图的 oriented display pixel size |
| 无 | 有 | 在源图内按 anchor 取该比例的最大内接矩形 |
| 有 | 无 | 保持源比例，等比限制到 maximum pixel size |
| 有 | 有 | 先按 anchor 取最大内接裁剪，再等比限制到 maximum pixel size |

概念上可以写成：

```text
00 -> source
01 -> anchored aspect-ratio crop
10 -> maximum pixel size
11 -> anchored aspect-ratio crop + maximum pixel size
```

这只是组合关系，不实现为 bitmask。

### 只给 aspectRatio 时

不使用额外尺寸启发式。比例只决定形状，源图决定最大的 base scale。

例如源图为 `4000 × 3000`：

```text
aspectRatio 1:1 -> crop size 3000 × 3000
aspectRatio 5:4 -> crop size 3750 × 3000
```

anchor 只改变这块区域在源图中的 origin，不改变 crop size。得到 base candidate 后，
solver 才根据 `maxBytes` 继续等比缩小。

## Solver 所有权

Sizing 只解析一次：

```text
source facts
  -> resolve concrete aspect ratio + anchor once
  -> fixed crop rect
  -> clamp maximum pixel size once
  -> base candidate
  -> search uniform scale + quality
  -> encode / measure
```

因此 solver 不再搜索彼此独立的 width 和 height，也不再区分 1.x hard/soft geometry。
它也不参与裁切决策：调用方没有声明 aspect ratio 时不裁切；声明后，crop rect 在搜索前
固定。solver 只能缩放该裁切结果，不能为了更容易满足 `maxBytes` 改变 ratio、anchor、
crop rect 或额外丢弃画面内容。

内部拥有：

- quality profile 与搜索方式。
- uniform scale candidate。
- 编码尝试次数和 resource budget。
- 首次候选估算。
- 候选选择和未来 benchmark 校准。

这些参数不进入 public API。2.1/2.2 可以替换算法而不迁移调用方。

## Passthrough、结果与失败

### Passthrough

只有源数据同时满足以下条件时才可以直接返回：

- `data.count <= maxBytes`。
- 不超过 maximum pixel size。
- 已满足具体 aspect ratio；否则仍需按 anchor 裁剪和重编码。
- 已满足全部 immutable output requirements。

### Result

Target 保留结构化结果，因为实际输出由 solver 决定。结果至少需要让调用方取得：

- encoded `Data`。
- 实际 pixel size。
- 实际 format。
- byte count。

### Failure

当 immutable output requirements 下不存在满足 `maxBytes` 的结果时，返回明确的
`unsatisfiable` 错误。不能静默改格式、破坏 Alpha、放弃 metadata/output 合同或返回
超限数据。

## 已接受

- `WICompressionTarget` 与 `WIImageProcess` 分开。
- Target 的公共事实是 `maxBytes + sizing + output`。
- Sizing 使用 maximum pixel size 与 concrete aspect ratio 两个正交输入。
- 四种 sizing 组合都有确定语义。
- 只给 ratio 时使用源图最大内接裁剪，不使用尺寸启发式。
- Aspect-ratio crop 使用 normalized anchor，默认 `.center`。
- Target 不隐式 upscale。
- Target 与 Process 共享 Output Domain，但使用独立默认值。
- Target 默认使用 Alpha-aware PNG/JPEG、strip metadata 和 sRGB。
- Quality 不属于 Output，由 solver 所有。
- Sizing 解析后，solver 只搜索统一缩放系数与 quality，不改变固定 crop。
- Public API 不暴露 candidate preference 或 solver 参数。
- 不提供微信、QQ、微博、抖音等平台 preset。
- 成功必须满足 hard byte limit。

## 已拒绝

- 继续使用 1.x `geometry`、`fit`、`fill`、`fitInside` 和 alignment Domain。
- Public `balanced`、`preserveResolution`、`preserveFidelity`。
- `preferredAspectRatio` 等无法验证是否满足的 soft preference。
- 直接接受 allowed aspect-ratio range 并由库决定裁向哪一侧。
- 任意像素约束表达式或平台规则 DSL。
- 让调用方在库外编写 byte-search 循环。
- Public Processor Chain、全局单例或平台分享 preset。

## 延后

- Target 是否支持 exact final pixel size。
- 最小像素尺寸与 upscale。
- 任意 source pixel rect、content-aware crop 和 canvas placement。
- Target diagnostics 与搜索轨迹。
- PNG palette quantization 等新的有损能力。
- 基于数据集与 benchmark 的 solver 算法升级。

## 实施依赖

Target、Process、Output、ImageIO 与 Raster 的职责现在都已经冻结。实施仍不能把 Target
重新接回 1.x Policy 或旧 geometry path；应由新合同自然导出 execution core：

```text
1. 建立 package-only ImageIO 与 Raster primitive
   inspect -> resolve -> render -> encode -> encoded result

2. 实现 pure sizing/crop resolution
   source size + optional maximum + optional ratio/anchor -> fixed crop + base pixel size

3. 实现 Target solver
   scale + quality candidates -> execution core -> measure/select

4. 删除 1.x target paths
   geometry resolver、preference ranking 和对应兼容分支
```

以上四步已完成。后续工作是补齐异步 terminal、迁移文档与删除 2.0 不再保留的旧
Process compatibility surface，不重新引入旧 Target Domain。
