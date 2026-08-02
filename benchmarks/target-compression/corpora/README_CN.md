# Benchmark corpora

[English](README.md) | 简体中文

本目录只保存 corpus 来源、许可边界与完整性锁，不保存任何图片或 ZIP。实际内容由
`fetch-corpora.sh` 下载到已被 Git 忽略的 `../data/corpora/`。

```sh
./benchmarks/target-compression/fetch-corpora.sh --list
./benchmarks/target-compression/fetch-corpora.sh jpeg-ai-cfe
./benchmarks/target-compression/fetch-corpora.sh clic-professional-valid
./benchmarks/target-compression/fetch-corpora.sh clic-mobile-valid
```

不传 corpus 时脚本只显示用法并退出，不会默认下载约 355 MB 的两份 CLIC archive。
必须显式传入 `all` 才会获取全部语料。每个 corpus 先在同一 data volume 的临时目录完成
HTTP、archive 或图片 checksum、ZIP 成员名称、文件数量与扁平目录验证，然后才原子移动到
最终目录。下载与解压都有 lock 中的字节上限；全局排他锁阻止并发安装。完成目录带有隐藏的
完整性收据，绑定当前 corpus lock 指纹；再次执行会重新计算内容摘要并幂等复用，绝不会覆盖
已有目标。网络传输没有不合理的固定总时长，只会在持续 60 秒低于 1 KiB/s 时判定为停滞。

## 完整性来源

- CLIC archive 的 byte length 与 MD5 来自对应 Google Cloud Storage object metadata。
- JPEG AI 官方只发布了解压后 16 张 PNG 的 MD5。ZIP 没有 upstream checksum，因此 lock
  不为 ZIP 声称自制 checksum；部分 archive 还包含可选的 `__MACOSX/` 与对应 `._PNG`
  AppleDouble 项。脚本逐成员只允许目标 PNG 和这些精确的 macOS metadata，并以官方 PNG
  MD5 验证真正的图片内容。ZIP 的 HTTP `Content-Length` 以及通过官方 MD5 后的 PNG 长度是
  2026-08-02 的本地观测锁，只用于在 checksum 之前限制资源消耗，不冒充上游 checksum。
- CLIC archive checksum 已经固定全部内容；脚本另外要求其中恰好为 41/61 个名称唯一的
  flat PNG，并在解压前执行 1 GiB 安全上限。JPEG AI 则锁定每一张 PNG 的精确名称、长度与
  MD5。

## 许可与再分发边界

- CLIC Professional 官方附带
  [Unsplash License](https://data.vision.ee.ethz.ch/cvl/clic/LICENSE_professional_2020.txt)，
  允许在其条款下复制与分发。本项目仍只提供本地获取脚本，不再分发图片。
- CLIC Mobile 的官方页面没有给出明确的再分发许可，状态记为 `unknown`。
- JPEG AI CfE 页面提供公开下载与 checksum，但没有给出明确的再分发授权，状态记为
  `unknown`。公开可下载不等于获得再分发许可。

下载与使用者仍需自行确认上游当时有效的条款；WICompress 的 Apache-2.0 不覆盖这些图片。
