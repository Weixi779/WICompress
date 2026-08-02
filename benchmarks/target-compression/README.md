# Target Compression Benchmark

English | [简体中文](README_CN.md)

This macOS developer executable builds reproducible black-box evidence for
`WICompressionTarget`. It measures the real output of the public
`WICompressor.compress` terminal without exposing strategies, search parameters,
or internal candidate traces through the production API. It is repository
developer tooling, not part of the supported public library surface.

The benchmark and unit tests have different responsibilities. Tests freeze
correctness contracts; the benchmark records output shape, quality, and
execution cost for the same inputs in the same environment. It does not enforce
volatile performance thresholds in CI.

## Run

Run the default four-image smoke corpus. It explicitly writes JPEG and uses
budgets equal to `0.5` and `0.2` of each source's encoded byte count:

```sh
swift run -c release TargetCompressionBenchmark
```

Quickly exercise every encoding branch with a bpp budget:

```sh
swift run -c release TargetCompressionBenchmark \
  --input Tests/WICompressTests/Resources/real_jpeg_2098x1350_landscape.jpg \
  --representations jpeg,heic,png \
  --bpp 0.5 \
  --runs 1 \
  --warmup 0
```

Run a formal JPEG AI CfE measurement:

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

`data/`, `results/`, and `artifacts/` are ignored by default, so local corpora,
reports, and encoded outputs are not committed. Default fixtures are located
relative to the Package checkout; a relative custom `--input` is resolved from
the current working directory. Artifacts are written to a filename-safe
strategy subdirectory under `--artifacts`, preventing baseline and candidate
runs from overwriting one another when they share an artifact root. Filenames
include both a readable budget and the exact integer or IEEE-754 bit-pattern
identity, so similar but nonidentical ratio/bpp cases remain distinct.

## Compare

Production code has no benchmark strategy switch. Run the baseline and
candidate revisions separately, then compare their schema-v2 JSON reports
offline:

```sh
swift run -c release TargetCompressionBenchmark compare \
  --baseline benchmarks/target-compression/results/baseline.json \
  --candidate benchmarks/target-compression/results/candidate.json \
  --json benchmarks/target-compression/results/comparison.json
```

For a behavior-preserving structural refactor, add:

```sh
--require-identical-output
```

This requires every paired case to have the same status and the same stable,
nonempty output signature. A signature includes format, pixel size, byte count,
and SHA-256. Two failed cases with no output are not treated as strict
equivalence. The comparator also rejects different schemas, case sets, quality
protocols, build configurations, operating systems, or architectures. Results
with different CPUs, Swift versions, run counts, or warmup counts can still be
compared, but timing deltas are disabled.

Reports record an ordered content fingerprint for the Package, production
Sources, and benchmark Sources. If either report comes from a dirty worktree,
the comparator also disables timing; clean revisions before and after a change
are required for a reproducible performance comparison. Dirty reports can
still compare hard limits, outputs, dimensions, and quality. A strict
comparison writes and prints its report, including mismatch keys, before
exiting with a nonzero status. Comparison JSON distinguishes measured values,
exact matches, unavailable values, measurement failures, and missing quality.
PSNR/SSIM report absolute differences only; other linear metrics also report
relative percentages.

## Corpus

Without `--input`, the benchmark uses the existing JPEG, HEIC, transparent PNG,
and opaque PNG test resources. They provide platform and correctness smoke
coverage, not evidence for algorithm-quality conclusions.

Formal corpora are managed by the [corpora manifest](corpora/README.md):

- JPEG AI CfE 16: a fast review set;
- CLIC 2020 Professional validation: 41 images;
- CLIC 2020 Mobile validation: 61 images.

The repository stores only official URLs, integrity locks, and the local fetch
script—not images or ZIP archives. The script validates HTTP responses, archive
or extracted-image checksums, ZIP members, file counts, and directory shape.
Nothing is downloaded unless a corpus is requested. Mobile and JPEG AI have no
clear redistribution grant, so they must not be added to Git, Git LFS, release
artifacts, or mirrors.

## Scenarios

A case is:

```text
fixture × requested representation × budget
```

`--representations` accepts `jpeg`, `heic`, and `png`, independently of the
source container. JPEG always uses a white background. Every scenario uses:

```text
sizing: original
metadata: strip
color space: sRGB
representation: explicit
```

Budget sources can be combined:

- `--ratios`: a fraction of source encoded bytes for historical product
  regressions;
- `--bytes`: an absolute byte ceiling for contracts such as sharing SDKs;
- `--bpp`: bits per pixel based on display-oriented source pixel area.

bpp always uses source area rather than output area:

```text
targetBytes = floor(sourceWidth × sourceHeight × requestedBPP / 8)
actualBPP = outputBytes × 8 / (sourceWidth × sourceHeight)
```

When an algorithm saves bytes by reducing dimensions, the smaller output area
therefore cannot make its bitrate appear artificially better. Spatial
resolution loss is reported separately as `pixelAreaRatio`.

## Metrics

The terminal table and JSON reports record:

- hard byte-limit correctness and budget utilization;
- output format, pixel size, actual bpp, and pixel-area ratio;
- raw timings from repeated runs, median timing, and stable output signatures;
- RGB MSE / PSNR and luma SSIM;
- input and output SHA-256;
- schema, strategy, OS, CPU, Swift, Git revision, and dirty state.

Quality measurement is entirely outside the timed region. The protocol is
fixed:

1. Decode source and output with ImageIO and explicitly apply EXIF orientation.
2. Convert to 8-bit sRGB.
3. Scale the pristine source to the actual output dimensions with the
   benchmark's own high-quality vImage scaler.
4. Compute RGB MSE/PSNR.
5. Compute valid-window SSIM using BT.709 luma and an 11×11 Gaussian with
   σ=1.5.

The quality path does not reuse the production `ImageRenderer`; otherwise a
candidate algorithm and its reference image could change together and conceal
a regression. When source or output contains nonopaque pixels, the current
protocol records why perceptual metrics are unavailable. Merely carrying a
fully opaque alpha channel does not trigger this exclusion. Images smaller than
11×11 still receive PSNR, while SSIM is unavailable. Exact pixel matches use
`exactMatch = true` and keep PSNR `null` instead of encoding infinity in JSON.

A normalized RGBA surface is limited to 256 MiB and is checked against
inspection dimensions before decode. SSIM signals, the horizontal ring, and
statistics have a separate combined 256 MiB workspace limit. Every addition
and multiplication is checked for overflow. Exceeding any limit produces
`qualityMeasurementFailed`, preventing extreme inputs from exhausting the
benchmark process.

PSNR/SSIM evaluate encoding and rendering error at the final output resolution;
they do not penalize downscaling. Read them together with `pixelAreaRatio`. The
tool does not produce a single composite score.

## Validation and Status

Timing covers one complete public compression call. Input reading, warmup,
independent output validation, quality measurement, artifact writing, and JSON
encoding are outside the timed region. After timing, every successful result is
fully decoded through `WIImageIO` and checked for container, dimensions,
orientation, sRGB, privacy-sensitive metadata, and the hard byte limit.

Each case's output signature contains format, pixel size, byte count, and
SHA-256. Any encoded-byte difference becomes `outputSignatureUnstable`. This is
a benchmark regression constraint, not a public promise of encoded-byte
determinism. A quality-protocol failure becomes `qualityMeasurementFailed`; the
validated output and timings remain in the report, but the command exits with a
nonzero status. With `--artifacts`, these cases still save their validated
compression output for diagnosing quality-measurement failures.

The current JSON schema is `2`. A fixture is identified by both its
corpus-relative path and full-content hash. Its pairing key also includes the
requested representation, original budget value, and resolved target bytes.

The tool currently observes complete terminal duration only. It cannot read
encode attempts, render counts, or internal candidate traces. A production
algorithm change must be decided from paired reports using the same corpus,
protocol, and environment.
