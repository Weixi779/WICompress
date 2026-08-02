# WICompress 2.0 Image Pipeline

状态：内部编排边界已冻结并实施；Process 与 Target 的校验、决策、执行和反馈搜索均由
请求级 `ImagePipeline` 持有。

本文是 WICompress 2.0 内部图片执行架构的单一来源。它定义一次 terminal 调用由谁持有
输入、检查结果、工作像素和执行决策，也明确哪些已有中间层不再属于最终架构。

本文替代其他文档中关于 `Resolver`、`Solver`、`WIExecutionPlan`、
`WIImageExecutor` 和独立 Execution Core 的目标架构描述。其他文档中的公共 Domain、
ImageIO、Rendering、输出合同和当前实施状态仍然有效。

相关文档：

- [`V2_DOMAIN_MODEL_CN.md`](V2_DOMAIN_MODEL_CN.md)：Process、Target 与共享 Output
  Domain。
- [`V2_IMAGE_PROCESS_CN.md`](V2_IMAGE_PROCESS_CN.md)：确定性正向处理合同。
- [`V2_COMPRESSION_TARGET_CN.md`](V2_COMPRESSION_TARGET_CN.md)：硬字节上限与候选搜索
  合同。
- [`V2_IMAGE_IO_CN.md`](V2_IMAGE_IO_CN.md)：encoded representation 基础能力。
- [`V2_IMAGE_RENDERING_CN.md`](V2_IMAGE_RENDERING_CN.md)：像素绘制基础能力。

## 核心结论

一次 `Data` 或文件 URL terminal 调用直接进入一个内部 `ImagePipeline`：

```text
Data / file URL + Process / Target
    -> WICompressor public terminal
    -> package-only ImagePipeline terminal
         -> validate source-independent input
         -> create ImageIO source when needed
         -> inspect original input at most once
         -> hold ImageDescriptor
         -> choose and execute operations
         -> encoded Data
         -> WIResult
```

`ImagePipeline` 是本次请求唯一的状态和编排所有者。它知道：

- 原始 encoded input。
- ImageIO inspection 产生的 `ImageDescriptor`。
- 外部传入的 Process 或 Target。
- 当前是否需要 decode、Rendering、source transcode 或重新 encode。
- Target 搜索当前使用的 geometry、quality 和候选结果。
- 哪个工作 `CGImage` 可以在后续编码尝试中安全复用。

它不公开，不提供扩展节点，也不要求外部理解内部阶段。

## Inspect 是动作，ImageDescriptor 是事实

ImageIO inspection 的概念合同是：

```swift
inspect(input) -> ImageDescriptor
```

`Inspect` 是一个同步动作，不建立长期存在的 `Inspector` 对象。`ImageDescriptor` 是该动作
产生的稳定值，至少承载：

- container format 与 type identifier。
- encoded byte count。
- oriented pixel size 与 orientation。
- frame count。
- Alpha、metadata 和 gain-map 等已经落地的 source facts。

Color 不属于必须提前读取的 ImageDescriptor 字段。只有 output 决策需要比较 source color
时，Pipeline 才通过 ImageIO source 按需读取。

Decode/encode capability 属于当前运行环境和具体 `UTType`；source transcode capability
还取决于 source、destination 与 transcode options。它们都由 Pipeline 在相关决定具体后
查询 ImageIO，不复制进 ImageDescriptor。

Pipeline 可以先完成不依赖 source 的配置校验，再创建 ImageIO source。进入
source-dependent 阶段后，原始输入至多 inspect 一次，并在整个调用期间持有该
`ImageDescriptor`。最终 encoded data 为了构造 `WIResult` 所做的结果检查不算重复检查原始
输入。

## 两种算法，一个 Pipeline

`WIImageProcess` 与 `WICompressionTarget` 仍然是两条公共产品线，但不是两套内部
架构。

### Process

Process 是一次确定性算法：

```text
ImageDescriptor + WIImageProcess
    -> validate declared intent
    -> calculate concrete geometry and output
    -> choose return-original / source-transcode / render
    -> execute once
    -> WIResult
```

调用方决定 resizing、crop、quality 和 output。Pipeline 只解释并执行这些确定要求，
不搜索 byte count。

### Target

Target 是一次带反馈的压缩算法：

```text
ImageDescriptor + WICompressionTarget
    -> validate hard contract
    -> calculate fixed crop and base size
    -> try return-original when fully satisfied
    -> propose scale and quality candidate
    -> rasterize when geometry changes
    -> encode and observe byte count
    -> update search state
    -> select a result within maxBytes
    -> WIResult
```

Target 搜索不是一组纯 input/output mapper。真实 encoded byte count 只有执行 encode
后才能观察，因此完整算法天然包含执行和反馈。无需为了形式纯粹，把“提出候选”“执行”
和“观察结果”拆成不同架构层。

## Pipeline 状态

Pipeline 只持有具有真实生命周期的状态：

```text
ImagePipeline
├── original input       immutable encoded source
├── descriptor           immutable inspected facts
├── working image        optional reusable CGImage
└── target search state  only while running Target
```

这里不使用一个类型不断变化的通用 `lastResult`，也不引入只包装这些字段的
`ImageContainer`。

### 原始输入不可变

Target 每次 encode 产生的 `Data` 只是候选结果，不能成为下一轮输入。否则搜索会变成
反复压缩上一次结果：

- 候选之间不再基于同一源图，无法公平比较。
- JPEG/HEIC 会产生代际损失。
- metadata、color 和像素误差会随尝试次数累积。
- 搜索顺序会改变最终视觉结果。

因此原始输入在一次 Pipeline 生命周期内始终不变。

### Working image 可以复用

Pipeline 可以按真实成本复用中间像素：

- 只有 quality 变化时，复用相同 geometry 的 working `CGImage` 再次 encode。
- geometry 变化时，从原始 source 重新 decode/rasterize。
- return-original 与 source-transcode 不创建 working image。
- working image 只属于当前 Pipeline，不跨 terminal、Task 或调用方共享。

是否以属性、局部值或小型私有缓存表达，由实现复杂度决定；它不升级为公共
`ImageResource`。

## 基础能力边界

抽出 ImageIO 与 Rendering 后，Pipeline 不再自己处理底层框架细节。

### ImageIO

ImageIO 模块拥有 encoded representation 的固有能力：

```text
inspect  encoded input -> ImageDescriptor
decode   encoded input -> CGImage
transcode encoded input -> Data
encode   CGImage       -> Data
```

Pipeline 自己持有请求级原始 `Data` / file URL，并通过 `ImageReader` 使用 encoded
source。ImageIO 模块内部使用 `CGImageSource`、`CGImageDestination` 和 typed options；
file-backed ImageReader 仍应避免无条件把完整文件读入内存。

ImageIO 不知道：

- `WIImageProcess`。
- `WICompressionTarget`。
- passthrough 是否满足产品合同。
- Luban、candidate scale、quality search 或 ranking。
- 哪一步应当成为本次请求的下一步。

### Rendering

Rendering 模块拥有 `CGImage -> CGImage` 的像素执行：

- orientation normalization。
- crop 与 resize。
- canvas、background 与 Alpha flatten。
- color-space conversion。
- sampling 与 bitmap memory safety。

Rendering 不解释 Process、Target、resizing intent 或 byte budget。Pipeline 在调用 Rendering
前已经计算出 concrete geometry 和 output facts。

## 执行不是固定直线

完整像素改写的能力顺序是：

```text
Inspect -> Decode -> Rendering -> Encode
```

但它不是要求所有请求依次经过四个 Stage 的公共或内部 chain。Pipeline 根据合同选择最短
且语义正确的路径：

```text
return original:
    Inspect -> original Data

source transcode:
    Inspect -> ImageIO transcode -> Data

pixel rewrite:
    Inspect -> Decode -> Rendering -> Encode -> Data
```

因此不建立 `InspectStage`、`DecodeStage`、`RenderingStage` 或 `EncodeStage`。这些名称描述
能力，不构成需要注册、替换或串联的对象体系。

## 被删除的架构层

### Inspector

**Reject。** 没有独立生命周期或可替换实现。一个 inspect function 和一个
`ImageDescriptor` 已经完整表达边界。

### Process Resolver / Target Resolver

**Reject。** 当前 Resolver 同时承担校验、geometry 计算、output 解释、优化判断和执行
分支选择。这些决定都需要 Pipeline 已经持有的完整请求事实，没有第二个真实所有者。

自然独立的尺寸或颜色计算可以保留为小函数，但不再包装成架构级 Resolver。

### ExecutionPlan

**Reject。** 它主要用于把 Resolver 的决定搬运给另一个无状态 Executor。当决策与执行
都归 Pipeline 所有后，不再存在需要跨越的边界。

若局部代码需要临时保存一组 concrete parameters，可以使用局部值或私有小值类型；这不
重新定义为共享 Execution Plan。

### ImageExecutor

**Reject。** Pipeline 已经拥有执行顺序、source 生命周期和 working image，再保留一个
Executor 会产生两个执行所有者。

### CompressionSolver

**Reject as architecture。** Target 搜索有真实行为，但它是
`ImagePipeline.compress(to:)` 内部算法，而不是与 Pipeline 并列的服务。

如果搜索状态复杂到局部变量已经无法清楚表达，可以保留一个私有 search state value。
它只负责候选状态和数学，不接管 source、ImageIO、Rendering 或整个请求生命周期。

## Algorithm 的位置

纯粹性不是拆层目标。只有天然是纯计算、能够独立命名并确实降低理解成本的部分才保留为
算法函数，例如：

- crop rect 与目标像素尺寸计算。
- 根据 byte-distance 推导下一候选 scale。
- lossy quality profile。
- feasible candidate ranking。
- checked arithmetic 与资源上限计算。

完整 Target 压缩必须调用 encode 并观察结果，因此不是纯函数。把它强行包装成
`Solver -> Resolver -> Plan -> Executor` 不会让算法更正确，只会隐藏反馈循环。

算法目录和类型名也不构成架构承诺。小计算可以靠近唯一调用方；只有出现真实复用或独立
变化压力时再提取。

## 对外扩展边界

Pipeline 本身完全封闭：

- 不 public。
- 不使用 `WI` 公共品牌前缀。
- 不提供 stage protocol、processor registry 或插件。
- 不允许调用方插入任意 decode、Rendering 或 encode 节点。
- 不公开 working `CGImage`、Pipeline 内部 ImageReader 或 Pipeline 生命周期。

外部扩展发生在已经冻结的 Domain 插槽，例如 `WIImageResizing`：

```text
source PixelSize -> caller or built-in resizing -> concrete PixelSize
```

外部扩展只产出 Pipeline 能验证的具体事实，不获得内部编排控制权。新增扩展点必须由
真实调用场景证明，不能因为 Pipeline 内部恰好存在某一步就自动公开。

## 同步与异步

ImagePipeline 的基础执行保持同步、有序。同步 terminal 在当前调用上下文运行；异步
terminal 使用 Swift 6.2 `@concurrent`，让同一条同步 Pipeline 在 concurrent executor
运行而不占用 caller actor。它仍属于调用方原有的 structured Task，不创建
`Task.detached`，因此 Task priority、Task-local values 与 cancellation context 能自然继承。

Pipeline 内部不把 inspect、decode、Rendering 或 encode 设计成多个 public suspension
point，也不在 ImageIO/Rendering 中建立 queue、actor 或 Task。同步与异步入口必须共享
完全相同的 Pipeline 语义；2.0 不提供 public executor、queue 或 cancellation token。

取消采用 cooperative checkpoints：

- 创建/检查输入前。
- inspect 与 Process/Target 决策阶段之间。
- decode、thumbnail、Rendering、transcode、encode 与最终结果检查前后。
- Target 每次 prepare 与 encode attempt 前后。

ImageIO 与 Core Graphics 没有可供当前架构转交的取消句柄，因此已经开始的单次同步调用
可能先完成，Pipeline 会在返回后立即观察取消。异步 terminal 原样抛
`CancellationError`，不把取消映射为 `WICompressError`；图片处理失败仍保持
`WICompressError`。Swift 目前不能在签名上表达两种 typed error 的 union，因此 async
overload 使用普通 `async throws`。同步 terminal 关闭 Task cancellation 检查，继续使用
`throws(WICompressError)`，即使从已取消 Task 中同步调用也不改变原有语义。

## 决策记录

### Accept

- `ImagePipeline` 是一次 terminal 调用唯一的状态与编排所有者。
- Data、file URL 与已经建立自身不变量的外部意图直接进入 Pipeline。
- Inspect 是函数；每次请求至多 inspect 原始输入一次，并由 Pipeline 持有输出的
  `ImageDescriptor`。
- Process 与 Target 是同一个 Pipeline 内的两种算法。
- ImageIO 与 Rendering 是独立基础能力，不拥有产品执行顺序。
- Target 候选始终从原始输入派生，encoded candidate 不回灌为下一轮输入。
- geometry 相同而只有 quality 变化时可以复用 working `CGImage`。
- 外部扩展只产生 concrete Domain facts，不扩展 Pipeline。
- Target 的 passthrough、反馈搜索与最终 hard byte check 已由 Pipeline 直接持有，不再
  经过架构级中间类型；source-independent hard constraints 在 Domain 构造时完成。

### Reject

- 独立 `Inspector`。
- 架构级 Process Resolver、Target Resolver、ExecutionPlan、ImageExecutor 和
  CompressionSolver。
- 通用 mutable `lastResult` 或额外 `ImageContainer`。
- 固定 Stage chain、开放 Pipeline、插件和 processor registry。
- 为了测试或形式完整建立没有第二实现和生命周期的 protocol。
- 把完整 Target 反馈算法伪装成纯 mapper。

## 当前实施状态

- `WICompressor` 的 Process 与 Target terminal 均直接调用 package-only
  `ImagePipeline`；不存在第二个 package terminal 转发类型。
- Process 数值偏好在 Domain 中完成规范化；Target、ratio 与 scale 的硬不变量在构造时
  建立，Pipeline 不再重复验证这些事实。
- Process 的 crop、resizing、output 分支选择与结果生成已经迁入 Pipeline。
- Target 的固定 crop/base size 解析、passthrough、候选搜索、
  working image 复用、候选选择与 hard byte check 已经迁入 Pipeline。
- 架构级 Process/Target Resolver、`WIExecutionPlan`、`WIImageExecutor` 与
  `WICompressionSolver` 已删除。
- `Algorithm/` 保留 Process/Target geometry 等纯计算；Target 私有目录保存反馈搜索状态、
  size estimation、quality profile 和 candidate ranking。
- Target Search 只接收 byte budget、基础尺寸与固定尺寸编码闭包，不认识 Pipeline、ImageIO、
  Rendering、metadata 或 output，不能成为第二执行 owner。
- 同步与异步 Data/file Process/Target terminal 已共享上述实现；async overload 使用
  `@concurrent` 与 cooperative cancellation，sync overload 保持 typed throws 和原执行语义。

### Defer

- working image 是否需要一个按 geometry 标识的私有缓存值。
- crop 路径的解码采样优化：根据 crop rect 与最终 destination size 计算满足输出采样密度的
  最小整图 thumbnail，按实际 thumbnail 尺寸映射 source rect 后再交给 Rendering。当前仍完整
  解码 crop source；本轮 Rendering 重构不改变既有解码与画质语义。
- 未来是否发布独立 Rendering product。
- 新的像素 backend、动图和 HDR execution。

这些延后项不影响当前 Pipeline 所有权，也不能作为提前建立抽象的理由。

## 非目标

- 不重新设计已冻结的 Process、Target、Output 公共合同。
- 不添加新的图片处理需求。
- 不公开 Pipeline 或中间图片资源。
- 不建立通用图片工作流框架。
- 不用架构重构顺带升级 Target 搜索算法。
- 不要求 return-original、source-transcode 和 pixel rewrite 经过同一组形式化 Stage。
- 不为了目录对称保留空 Service、Manager、Resolver、Executor 或 protocol。

## 重新打开条件

只有出现以下证据时，才重新讨论已拒绝的抽象：

- 存在第二个真实编排消费者，并且执行顺序与 WICompress 明确分叉。
- Pipeline 状态已经无法由单一请求生命周期一致维护。
- 同一组决策规则在多个真实所有者之间发生重复和行为漂移。
- 搜索状态具有独立生命周期、需要跨请求持久化，或出现第二种真实实现。
- 外部调用方确实需要组合自定义操作，而现有 Domain 插槽无法表达其当前生产需求。

“以后可能扩展”“测试更方便”或“架构图更完整”不构成重新打开证据。
