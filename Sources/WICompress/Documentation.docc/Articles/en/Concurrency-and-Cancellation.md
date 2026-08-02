# Concurrency and Cancellation

Choose a synchronous or asynchronous terminal without changing the request or result model.

## Resolve overloads in async contexts

Swift prefers the same-name async overload when the call appears in an async context.
Code that used a synchronous terminal inside an async function before 2.0 must add
`await`; simply omitting it no longer selects the synchronous overload. If blocking,
synchronous execution is intentional, make that call from a non-async helper or
explicitly bind the synchronous function overload.

## Run away from the caller's actor

Every Process and Target terminal has an async overload for Data and file input:

```swift
let processed = try await WICompressor.process(data, using: process)
let constrained = try await WICompressor.compress(data, to: target)
```

Async terminals run the compression pipeline without occupying the caller's actor.
After the call finishes, normal actor isolation determines where the caller resumes.

## Cancel cooperative work

Cancellation is observed between pipeline stages and between Target search attempts.
An ImageIO or Core Graphics call already in progress may finish before cancellation
takes effect.

```swift
let task = Task {
    try await WICompressor.compress(data, to: target)
}

task.cancel()

do {
    _ = try await task.value
} catch is CancellationError {
    // The surrounding task requested cancellation.
} catch let error as WICompressError {
    // The image request failed.
} catch {
    // Task.value uses untyped throws, so callers must handle any composed failure.
}
```

Async overloads use ordinary `async throws` because they can produce both the standard
`CancellationError` and ``WICompressError``. Cancellation is not wrapped as a library
error.

## Use synchronous terminals when appropriate

The synchronous overloads execute in the current calling context:

```swift
let result = try WICompressor.process(data, using: process)
```

They retain typed `throws(WICompressError)` and do not observe cancellation of a
surrounding task. Move a synchronous call to an execution context appropriate for
your application if it may perform expensive image work.

WICompress does not expose a global queue, shared compressor, or executor registry.
Scheduling implementation details remain in the
[architecture documentation](https://github.com/Weixi779/WICompress/blob/main/docs/architecture/README.md).
