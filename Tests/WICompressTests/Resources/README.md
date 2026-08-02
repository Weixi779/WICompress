# Test Fixtures

Real image fixtures for WICompress characterization tests. **Drop images here and they are
picked up automatically** — no code change needed (auto-discovered by extension:
`jpg`, `jpeg`, `png`, `heic`, `heif`).

Each fixture pins the observable contract of the compressor: output **format** +
output **display dimensions** (orientation-aware). These are stable invariants
that must survive ImageIO core changes (see `docs/PLAN_v1.0.0.md`).

Naming: `real_<format>_<WxH>_<trait>.<ext>` — `<trait>` flags what makes the
fixture interesting (orientation / gps / hdr / alpha / recompressed).
`synthetic_*` are generated edge cases.

## Fixtures and what each one covers

| Fixture | 尺寸/特征 | 默认 Luban 2 输出 | 用途 |
|---|---|---|---|
| `real_heic_4032x3024_o1_gps_hdr.heic` | o1, GPS+EXIF+**HDR gain map** | 1920×1440 | HEIC 保格式;metadata/gain-map 保真路径基线 |
| `real_heic_4032x3024_o6_gps_hdr.heic` | **o6**, GPS+gain map | 1440×1920(展示) | **方向修正**(宽高对调)+ HEIC 保真 |
| `real_heic_5712x4284_o6_gps_hdr.heic` | 超大, o6, gain map | 1440×1920(展示) | 大图 + 1440 短边基线 + 方向 |
| `real_heic_3001x2458_alpha_circle.heic` | **透明(alpha)**, sRGB | 1758×1440 | HEIC 圆形抠图透明保留;未来 alpha 处理基线 |
| `real_jpeg_2098x1350_landscape.jpg` | landscape | 2098×1350(不缩放) | JPEG 只做 quality/metadata 处理的默认路径 |
| `real_jpeg_738x1302_recompressed.jpg` | 已按 ~q0.55 存过 | 738×1302(不缩放) | **关键用例**:q0.6 重编码反而变大 → 验 `returnOriginal`/size 兜底 |
| `real_jpeg_1155x1251_nearsquare.jpg` | 近方形、奇数尺寸 | 1154×1250 | 偶数尺寸规范化 |
| `real_png_814x386_wide.png` | 不透明截图 | 814×386(不缩放) | PNG default 分支 |
| `real_png_1476x298_pano.png` | 不透明, 超宽 | 1476×298(不缩放) | 普通宽图不被过度缩小 |
| `real_png_1928x464_pano.png` | 不透明, 超宽 | 1928×464(不缩放) | 普通宽图不被过度缩小 |
| `real_png_1086x1630_alpha.png` | **透明(alpha)** | 1086×1630(不缩放) | PNG 透明保留;未来 PNG→JPEG 铺底色的输入 |
| `synthetic_tiny_1x1.png` | 1×1 退化 | 1×1 | 不放大极小图,防 pipeline 崩 |

## 备注

- iPhone 来源真实图多为 **Display P3** → 正好用来锁「色彩 profile 保留」；`circle` 透明 HEIC 是 sRGB，用来覆盖另一类来源。
- **HDR gain map**:三张相机 HEIC 带 gain map → 未来 gain-map preserve 特性的基线。
- `recompressed` 那张是**故意保留**的「已压缩小图」:它是唯一能触发「重编码反而变大」的样本,别替换。详见 `docs/PLAN_v1.0.0.md` §13。
- 多帧/动图样本 `real_gif_555x555_4frames.gif` 用于
  `animatedSourceUnsupported` 抛错测试；它不参与普通 Data API 自动发现契约。
- 文件用 `.copy`(见 `Package.swift`)保字节;修复版 Luban 1 ratio 由
  `LubanRatioTests` 覆盖，Luban 2 与默认切换由 `WIImageProcessTests` 覆盖。
