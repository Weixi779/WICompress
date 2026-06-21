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

| Fixture | 尺寸/特征 | Luban ratio → 输出 | 用途 |
|---|---|---|---|
| `real_heic_4032x3024_o1_gps_hdr.heic` | o1, GPS+EXIF+**HDR gain map** | 2 → 2016×1512 | HEIC 保格式;metadata/gain-map 保真路径基线 |
| `real_heic_4032x3024_o6_gps_hdr.heic` | **o6**, GPS+gain map | 2 → 1512×2016(展示) | **方向修正**(宽高对调)+ HEIC 保真 |
| `real_heic_5712x4284_o6_gps_hdr.heic` | 超大, o6, gain map | 4 → 1071×1428 | 大图 + ratio 4 分支 + 方向 |
| `real_heic_3001x2458_alpha_circle.heic` | **透明(alpha)**, sRGB | 2 → 1500×1228(HEIC 偶数对齐) | HEIC 圆形抠图透明保留;未来 alpha 处理基线 |
| `real_jpeg_2098x1350_landscape.jpg` | landscape | 2 → 1049×675 | JPEG 正常下采样(明显压小) |
| `real_jpeg_738x1302_recompressed.jpg` | 已按 ~q0.55 存过, ratio 1 | 1 → 738×1302(不缩放) | **关键用例**:q0.6 重编码反而变大 → 验 `returnOriginal`/size 兜底 |
| `real_jpeg_1155x1251_nearsquare.jpg` | 近方形 | 1 → 1155×1251 | JPEG ratio 1 不缩放 |
| `real_png_814x386_wide.png` | 不透明截图 | 1 → 814×386 | PNG default 分支 + ratio 1 |
| `real_png_1476x298_pano.png` | 不透明, 超宽 | 2 → 738×149 | PNG default 分支(aspect<0.5)+ ratio 2 |
| `real_png_1928x464_pano.png` | 不透明, 超宽 | 2 → 964×232 | 旧 UIKit 路径会变大、ImageIO 会压小的对照样本 |
| `real_png_1086x1630_alpha.png` | **透明(alpha)** | 1 → 1086×1630 | PNG 透明保留;未来 PNG→JPEG 铺底色的输入 |
| `synthetic_tiny_1x1.png` | 1×1 退化 | 1 → 1×1 | 极小边界,防 pipeline 崩 |

## 备注

- iPhone 来源真实图多为 **Display P3** → 正好用来锁「色彩 profile 保留」；`circle` 透明 HEIC 是 sRGB，用来覆盖另一类来源。
- **HDR gain map**:三张相机 HEIC 带 gain map → 未来 gain-map preserve 特性的基线。
- `recompressed` 那张是**故意保留**的「已压缩小图」:它是唯一能触发「重编码反而变大」的样本,别替换。详见 `docs/PLAN_v1.0.0.md` §13。
- 多帧/动图样本 `real_gif_555x555_4frames.gif` 用于
  `animatedSourceUnsupported` 抛错测试；它不参与普通 Data API 自动发现契约。
- 文件用 `.copy`(见 `Package.swift`)保字节;精确 Luban 边界由 `LubanRatioTests` 单元覆盖,不在此重复。
