# 并发与取消

同步与异步入口共用完全相同的请求和结果模型。

## async 上下文中的 overload 解析

在 async 上下文中，Swift 会优先选择同名 async overload。2.0 之前写在 async
function 中的同步调用，升级后必须增加 `await`；单纯省略它不会选中同步
overload。如果确实要阻塞式同步执行，应在非 async helper 中调用，或显式绑定
同步函数 overload。

## 不占用调用方 Actor

Process 与 Target 都为 Data 和文件输入提供 async overload：

```swift
let processed = try await WICompressor.process(data, using: process)
let constrained = try await WICompressor.compress(data, to: target)
```

异步入口不会让压缩 Pipeline 占用调用方 actor。调用结束后，调用方按照正常 actor
隔离规则恢复执行。

## 协作式取消

Pipeline 阶段之间与 Target 搜索尝试之间会检查取消。已经进入 ImageIO 或 Core
Graphics 的单次调用可能先执行完成，随后才响应取消。

```swift
let task = Task {
    try await WICompressor.compress(data, to: target)
}

task.cancel()

do {
    _ = try await task.value
} catch is CancellationError {
    // 外层 Task 请求了取消。
} catch let error as WICompressError {
    // 图片请求执行失败。
} catch {
    // Task.value 使用非类型化 throws，因此还需要处理组合任务中的其他错误。
}
```

异步入口使用普通 `async throws`，因为它既可能抛出标准 `CancellationError`，也可能
抛出 ``WICompressError``。WICompress 不会把取消包装成自己的错误类型。

## 需要时使用同步入口

同步 overload 会在当前调用上下文中完整执行：

```swift
let result = try WICompressor.process(data, using: process)
```

同步方法保留 typed `throws(WICompressError)`，不会观察外层 Task 的取消。如果图片工作
成本较高，应由应用把同步调用放到合适的执行上下文。

WICompress 不提供全局队列、共享 compressor 或 executor registry。调度实现细节见
[架构文档](https://github.com/Weixi779/WICompress/blob/main/docs/architecture/README_CN.md)。
