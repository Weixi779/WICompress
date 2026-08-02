# WICompress Roadmap

This file contains only confirmed follow-up areas after 2.0. It is not a release
contract. Current behavior belongs in the
[architecture documentation](architecture/README.md).

## Animated images

- Explore a separate stateful session for frame timing, disposal, incremental
  decode, and memory-aware caching.
- Define inspection, processing, and encoding contracts before exposing an
  animated API. Static operations must continue rejecting animation instead of
  silently processing frame zero.

## Metadata

- Extend the modeled metadata vocabulary only when fixtures and production use
  cases can define preservation, removal, transcode, and render behavior.
- Evaluate key-level metadata selection for namespaces such as XMP and PNG text
  without exposing raw ImageIO property dictionaries as the primary API.

## Decode efficiency

- Investigate crop-aware downsampling. A crop currently tends to decode the
  complete image; a future implementation could calculate the minimum source
  sampling density required by the crop and destination before decoding.

Any algorithmic change should be measured with the
[target-compression benchmark](../benchmarks/target-compression/README.md)
instead of becoming a speculative production option.
