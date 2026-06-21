# 图像处理基础笔记（WICompress 踩坑整理）

> 这是做 WICompress（ImageIO 图片压缩库）过程中沉淀的图像处理基础知识。
> 重点在「为什么」，以及那些**只有真正动手才会撞到的坑**。可作为 blog 素材。
> 文中带「实测」标记的结论，都是本项目用纯 `ImageIO`（无 UIKit）在真机/真图上验证过的。

---

## 0. 一句话主线

**一个颜色数值（`#FF0000` / `(255,0,0)`）是一个「没有单位的数字」，色彩空间就是那个单位。**

几乎所有图像处理的色彩 bug，本质都是「单位搞错了」或「该换算时没换算」。

---

## 1. 为什么平时用 hex / HSL 从没遇到色彩空间问题

不是没有，是被隐藏了，两个原因：

1. **全员默认 sRGB**：Web/CSS 规范直接规定 hex 颜色就是 sRGB。所有人（浏览器、设计稿、多数显示器）都默认 sRGB —— 单位统一了，就不用写单位。
2. **HSL / HSV / HSB 根本不是独立色彩空间**：它们只是把 sRGB 立方体换成「色相/饱和度/明度」的**柱坐标**，底层还是同一个 sRGB。换坐标 ≠ 换空间。

所以你日常活在「全员 sRGB」的舒适区里。一旦进入广色域（P3）的真实世界，问题才浮现。

---

## 2. 一个 RGB 色彩空间到底是什么

底层只由三个参数定义：

1. **三原色（primaries）**：最红的红 / 最绿的绿 / 最蓝的蓝 在 CIE 色度图上的坐标 —— 决定色域三角形的三个**顶点**（色域大小/形状）。
2. **白点（white point）**：`R=G=B=1` 时是哪种白，例如 D65（≈6500K 日光）。
3. **传递函数（transfer function / TRC，俗称 gamma）**：存储数值 ↔ 真实线性光强 之间的非线性曲线。

把这三样打包成文件结构 = **ICC profile**（图片里那张「单位标签」）。
所谓「sRGB 图 / P3 图」的差别，本质就是这三个参数不同。

---

## 3. 常见色彩空间

### RGB 显示/工作空间（日常）

| 空间 | 色域 | 白点 | gamma | 场景 |
|---|---|---|---|---|
| **sRGB** | 基准（=Rec.709 原色） | D65 | sRGB 分段曲线（≈2.2） | Web / 默认 |
| **Display P3** | 比 sRGB 宽 ~25%（红绿更艳） | D65 | **与 sRGB 同曲线** | Apple 设备 |
| **Adobe RGB** | 绿青方向更宽 | D65 | ≈2.2 | 印刷/摄影 |
| **Rec.709** | =sRGB 色域 | D65 | 略不同 | HDTV |
| **Rec.2020** | 极宽 | D65 | PQ / HLG（HDR） | 4K / HDR 容器 |
| **DCI-P3** | =Display P3 原色 | DCI 白（偏绿） | 2.6 | 数字电影 |
| **ProPhoto RGB** | 巨大（含不可见色） | D50 | 1.8 | 16-bit 修图 |

> 关键：**Display P3 和 sRGB 只差「原色」一项**，白点和曲线都一样。
> 这就是「灰阶和黑白对得上、只有饱和色分叉」的根因。

### 参考空间（数学中转站，不直接显示）

- **CIE XYZ**：设备无关，基于 1931 年人眼三种视锥响应。**所有空间互转都从它中转**，是「绝对真值」。
- **CIE xyY**：那张马蹄形色度图。
- **CIELAB (L\*a\*b\*)**：近似感知均匀，用来算色差 ΔE 与做转换。

### 容易误会的（其实不是独立空间）

- **HSL / HSV / HSB**：sRGB 的柱坐标再参数化，底层仍是 sRGB。

### 其他模型

- **YCbCr / YUV**：亮度 + 色度，JPEG/视频内部用（可对色度子采样压缩）。由 RGB 经矩阵线性变换得到。
- **CMYK**：减色，印刷用，强设备相关。
- **HDR**：Rec.2020 + **PQ（ST 2084）** = HDR10；**HLG** = 广播 HDR。

---

## 4. 底层实现：所有转换都经过 XYZ 这个中枢

```
编码 RGB(空间1)
  ──[空间1 传递函数的逆]──▶  线性 RGB(空间1)        // 去 gamma
  ──[3×3 矩阵 M1]──────────▶  XYZ                    // 设备无关
  ──[白点不同则色适应, Bradford]─▶ XYZ'              // 可选
  ──[3×3 矩阵 M2⁻¹]────────▶  线性 RGB(空间2)
  ──[空间2 传递函数]────────▶  编码 RGB(空间2)        // 重新加 gamma
```

### (a) 3×3 矩阵是数学内核

由原色 + 白点推导。sRGB 的「线性 RGB → XYZ」：

```
X     0.4124  0.3576  0.1805     R
Y  =  0.2126  0.7152  0.0722  ×  G
Z     0.0193  0.1192  0.9505     B
```

中间那行（Y = 亮度）系数 **0.2126 / 0.7152 / 0.0722** = 著名的「亮度权重」：绿色对人眼亮度感知贡献最大。
**P3 因原色不同，这个矩阵数字也不同 —— 这就是 sRGB 与非 sRGB 在代码里最实质的区别。**

### (b) gamma（传递函数）为什么存在

- **历史**：CRT 的电压-亮度天生幂律。
- **感知**：人眼对暗部更敏感。非线性存储把更多编码位分给暗部，8-bit 才不会在阴影出现**色带（banding）**；直接存线性到 8-bit，暗部会断层。

sRGB 曲线不是纯 2.2，而是**分段**：近黑一小段线性（×12.92），其余 `1.055·x^(1/2.4) − 0.055`。

### (c) 线性 vs 编码 —— 一个易踩的陷阱

**混合 / 缩放 / 合成** 这类运算，数学上应在**线性空间**做。
直接在 gamma 编码值上做 alpha 混合，边缘会发暗（暗边纹）。
（铺纯黑/白除外，见第 6 节。）

### (d) 色域映射 / 渲染意图

源颜色在目标空间**超出色域**（P3 鲜红塞进 sRGB）时：要么裁剪（clip），要么按感知整体压缩（perceptual）。这个选择叫 **rendering intent**。

### (e) ICC profile 与系统

ICC profile 就是把「原色+白点+曲线」打包的数据：简单的是矩阵型（matrix/TRC），复杂的（打印机/CMYK）是查找表型（LUT）。
干这些活的系统组件：**ColorSync（Apple）/ ICM（Windows）**；Apple API 层是 `CGColorSpace`。

---

## 5. 为什么白和黑是「免费」的

色彩空间的差别主要在**色域的「形状」**（最红的红能多艳，即 primaries），而**不在对角线两端**：

- sRGB / P3 共享同一**白点（D65）**和同一条 **gamma 曲线**。
- 所以 **黑 `(0,0,0)`＝没有光**、**白 `(1,1,1)`＝最亮的白**，在哪个空间都是同一个物理颜色。
- sRGB 与 P3 之间，**整条灰阶**（r=g=b）也都对得上。
- **只有饱和的彩色会因空间不同而分叉。**

> 类比：色域是一块橡皮糖，不同空间把它往饱和方向拉大/缩小，但**两个尖端（纯黑、纯白）钉死不动**。

**实践含义**：铺白/铺黑底色无需知道图是 sRGB 还是 P3，直接填 `(1,1,1)/(0,0,0)` 即可；
但只要铺一个**品牌色**，就立刻要回答「哪个空间的色、要不要先换算到这张图的空间」—— 这才是「铺色很难配置」的真身。

---

## 6. 保存图片时的坑：Assign vs Convert，以及 profile ≠ metadata

保存 = **像素** + **嵌入的 profile**，两者必须一致。两个独立操作，混淆即 bug：

- **Assign / 打标签**：像素数字**不动**，只换 profile —— 改变「这堆数字的含义」。用错 = 颜色当场变。
- **Convert / 转换**：为**保持外观**，把像素数字**重新计算**到目标空间 —— 数字变了，看起来一样。

第三种翻车：保存时**不嵌 profile**（untagged）→ 消费者默认按 sRGB 解释 → 若像素本是 P3，发灰发闷。

### 对压缩库最关键的一条：色彩 profile 不是 EXIF/GPS 那种可拆 metadata

- 我们「strip metadata」去掉的是 **EXIF / GPS / TIFF 字典**。
- **色彩 profile 跟着 `CGImage.colorSpace` 走，是像素本体的一部分**，不随 metadata 剥离。

> **实测**：`redrawBitmap` 路径（解码→重绘→重编码）**丢了 GPS，却完整保留 Display P3 + depth**。
> 即 **strip metadata ≠ 丢色彩**，ImageIO 默认会把源色彩空间带到输出。

**唯一人为风险点**：将来「铺底色 / PNG→JPEG」时，必须在**源图自己的色彩空间**里建 `CGContext` 合成，否则会变成「在 sRGB 上下文里画 P3 内容」→ 偷偷转换或贴错标签。

---

## 7. 「降级」难在哪：SDR 容易，HDR 才是硬骨头

- **SDR 之间的色域降级（P3 → sRGB）**：装不下的鲜艳色做**色域映射**（clip 或 perceptual）。有损但 ColorSync/ImageIO 自动做。主流三格式 JPEG（APP2）/ PNG（iCCP）/ HEIC **都能嵌 ICC profile**，所以「格式不支持某 profile」对我们基本不存在。
- **HDR → SDR**：需要**色调映射（tone mapping）**，可能产生色带，是真正麻烦的一档。

HDR 这档的优雅解法 = **Gain Map**，见下一节。

---

## 8. Gain Map（自适应 HDR）详解

### 它解决什么

传统 HDR（HDR10 的 PQ / HLG）把**绝对亮度**编进传递函数，整张图都是 HDR 编码。
问题：SDR 屏幕/老阅读器必须自己 tone-map，处理不当就发灰/失真，**不向后兼容**。

Gain Map 换了思路：**一张文件里同时存两套信息**，按显示能力自适应。

### 结构

一个支持 gain map 的 JPEG/HEIC 里有：

1. **基底图（base，SDR）**：任何阅读器都能正常显示的普通 SDR 图。
2. **增益图（gain map）**：逐像素记录「要增亮多少」才能还原 HDR，通常**对数编码**，且常以**较低分辨率**存储（增益变化平滑，省空间）。
3. **元数据**：headroom（亮度余量）等还原参数。

### 还原与「自适应」

概念公式（实际遵循 ISO 21496-1 / Apple 实现）：

```
HDR_pixel ≈ SDR_pixel × 2^( gain(map) × f(显示器headroom) )
```

- **SDR 屏 / 老阅读器**：忽略 gain map，直接显示基底图 —— 完全正常，无裁剪。
- **HDR 屏 / 新阅读器**：套用 gain map → 还原 HDR。
- **部分 headroom 的屏**：只套用**部分增益** → 平滑过渡，**没有硬切断**。

这就是它叫「自适应 HDR」的原因：**支持就亮，不支持就退回 SDR 基底，同一份文件两头都不翻车** —— 把「降级」做成了自动优雅回退。

### 生态

- Apple：iOS 14 起的 Smart HDR 照片；`kCGImageDestinationPreserveGainMap`（iOS 14.1+）；辅助数据类型 `kCGImageAuxiliaryDataTypeHDRGainMap`；iOS 18 起对齐 ISO HDR。
- Android：**Ultra HDR**（同样是 base + gain map）。
- 标准：**ISO 21496-1**（2024）统一了 gain map 格式。

### 为什么它对压缩库特别棘手

- gain map 是一张**独立的辅助图**，有自己的分辨率和元数据。主图若被下采样/重编码，gain map 必须**一致处理**（同步缩放、保留元数据），否则失配。
- **实测**：
  - `AddImage(cgImage)`（重绘路径）→ **gain map 丢失**（连同 GPS）。
  - `AddImageFromSource` + `kCGImageDestinationPreserveGainMap` → **gain map 保留**（连同 GPS、orientation tag）。
- 这正是「保真就得用拷贝路径、控像素就得用重绘路径」这一矛盾的来源。

---

## 9. 两条 ImageIO 写入路径（本项目的核心抽象）

> **实测对照**（同一张 `4032×3024 o=6 gps=✓ gainMap=✓` 的 HEIC，目标长边 2016）：

| | **A `AddImage`（重绘）** | **B `AddImageFromSource`（拷贝）** |
|---|---|---|
| resize | 缩略图 `maxPixelSize` | props `kCGImageDestinationImageMaxPixelSize` |
| 方向 | 烤进像素，tag 归 1（→1512×2016） | 保留 tag（→2016×1512 o6） |
| metadata / GPS | **丢失** | **保留** |
| gain map / HDR | **丢失** | **保留**（`PreserveGainMap`） |
| 色彩 profile (P3) | **保留** | **保留** |
| 适合 | strip / 上传压缩 / 格式转换 | 保真 / HDR |

核心结论：**越想保真，操作越融合**（收敛成一次 `AddImageFromSource`）；**越想控像素，越得用重绘并手动贴回丢掉的东西**。
所以 ImageIO 真正的中心抽象不是「七段流水线」，而是「**本次该选哪条写入路径**」。

---

## 10. 踩坑速查（结论汇总）

1. 颜色值没有单位，色彩空间就是单位；多数色彩 bug = 单位错或漏换算。
2. hex/HSL 没事，是因为全员默认 sRGB + HSL 只是 sRGB 的换坐标。
3. 一个 RGB 空间 = 原色 + 白点 + 传递函数；打包成 ICC profile。
4. 所有转换经 XYZ 中转；3×3 矩阵 + gamma 曲线是内核。
5. **白/黑跨空间无歧义**，任意颜色才需要色彩空间（铺底色设计的分水岭）。
6. 合成/缩放理想在**线性空间**做；gamma 空间做 alpha 混合会有暗边。
7. 保存分 **Assign（贴标签）/ Convert（转像素）**，别混；untagged 会被当 sRGB。
8. **色彩 profile ≠ EXIF/GPS metadata**：strip metadata 不丢色彩（实测 P3 保留）。
9. 降级：SDR 色域映射 ImageIO 自动兜；**HDR→SDR 才是硬骨头**。
10. **Gain Map** = SDR 基底 + 增益图，自适应优雅降级；但跨重编码易失配，重绘路径会直接丢。
11. ImageIO 只有两条真实写入路径（重绘 / 拷贝），policy 组合替你选路。

---

## 参考

- Apple ImageIO：`CGImageSource` / `CGImageDestination` / `CGColorSpace` / `kCGImageAuxiliaryDataTypeHDRGainMap` / `kCGImageDestinationPreserveGainMap`
- 标准：sRGB（IEC 61966-2-1）、Display P3、Rec.709 / Rec.2020、ISO 21496-1（Gain Map）
- 相关：CIE 1931 XYZ、CIELAB、ICC profile 规范、Android Ultra HDR
