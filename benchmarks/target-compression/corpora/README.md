# Benchmark corpora

[简体中文](README_CN.md)

This directory stores only corpus provenance, license boundaries, and
integrity locks. It contains no images or ZIP archives. `fetch-corpora.sh`
downloads requested data into the Git-ignored `../data/corpora/` directory.

```sh
./benchmarks/target-compression/fetch-corpora.sh --list
./benchmarks/target-compression/fetch-corpora.sh jpeg-ai-cfe
./benchmarks/target-compression/fetch-corpora.sh clic-professional-valid
./benchmarks/target-compression/fetch-corpora.sh clic-mobile-valid
```

With no corpus argument, the script prints usage and exits; it does not
silently download the two CLIC archives (about 355 MB). Pass `all` explicitly
to fetch every corpus. Each corpus is validated in a temporary directory on
the destination volume before an atomic move. Validation covers HTTP response,
archive or image checksums, ZIP member names, file count, and flat directory
shape. Download and extraction obey byte limits from the lock. A global lock
prevents concurrent installation.

Completed directories contain a hidden integrity receipt bound to the current
corpus-lock fingerprint. A later run recomputes the content digest and reuses a
matching installation without overwriting it. Network transfer has no arbitrary
total timeout; it fails only after staying below 1 KiB/s for 60 seconds.

## Integrity provenance

- CLIC archive byte lengths and MD5 values come from the corresponding Google
  Cloud Storage object metadata.
- JPEG AI publishes MD5 values for the 16 extracted PNGs, but no upstream ZIP
  checksum. The lock therefore does not present a locally computed ZIP digest
  as upstream provenance. Some archives contain optional `__MACOSX/` and matching
  `._PNG` AppleDouble entries; the script allows only the target PNGs and those
  exact macOS metadata members, then validates image content with the official
  PNG MD5 values. ZIP HTTP `Content-Length` and post-MD5 PNG lengths are local
  observation locks dated 2026-08-02. They constrain resources before checksum
  validation and are not represented as upstream checksums.
- A CLIC archive checksum covers its complete contents. The script additionally
  requires exactly 41 or 61 uniquely named flat PNGs and enforces a 1 GiB
  pre-extraction limit. JPEG AI locks each PNG's exact name, length, and MD5.

## License and redistribution boundary

- CLIC Professional includes the
  [Unsplash License](https://data.vision.ee.ethz.ch/cvl/clic/LICENSE_professional_2020.txt),
  which permits copying and distribution under its terms. This repository
  still provides only a local fetch script and does not redistribute images.
- The official CLIC Mobile page does not state a clear redistribution grant;
  its status is `unknown`.
- JPEG AI CfE provides public downloads and checksums but no clear redistribution
  grant; its status is `unknown`. Public availability is not redistribution
  permission.

Downloaders remain responsible for confirming the upstream terms in effect at
the time of use. WICompress's Apache-2.0 license does not cover these images.
