# audio_format_pcm

The `Pcm` value type: the facts of some integer linear PCM audio, which are
its channel count, bit depth, sample rate, length and a BLAKE3 digest of the
decoded samples. It is the `Format` of an
[`audio::Audio`](../audio). It is its own package so that `audio` stays
format-agnostic: float PCM or DSD would be another format package, not a
change to `audio`. Anyone can build a `Pcm`. Only the `Audio` that holds it is
attested, by its verifier.

## What it stores

Nothing: `Pcm` is a `copy + drop + store` value.

```move
public struct Pcm has copy, drop, store {
    channels: u8,
    bit_depth: u8,
    sample_rate_hz: u32,
    samples_per_channel: u64,
    digest: vector<u8>,
}
```

| Field | Rule |
|---|---|
| `channels` | at least 1 |
| `bit_depth` | 1 to 32 |
| `sample_rate_hz` | at least 1 |
| `samples_per_channel` | at least 1, and at most `u64::MAX / 1000`, so the duration in milliseconds fits in a `u64` |
| `digest` | exactly 32 bytes |

The field order is frame shape, then time, then content. It is the same as
the first five fields of `audio_verifier`'s signed `AudioPayload`.

## API

### Constructors

| Function | Returns | Aborts |
|---|---|---|
| `new(channels, bit_depth, sample_rate_hz, samples_per_channel, digest)` | `Pcm` | `EZeroChannels` (0), `EInvalidBitDepth` (1), `EZeroSampleRate` (2), `EZeroSamplesPerChannel` (3), `EInvalidDuration` (4), `EInvalidDigestLength` (5) |

### Views

| Function | Returns |
|---|---|
| `channels(pcm)` | `u8` |
| `bit_depth(pcm)` | `u8` |
| `sample_rate_hz(pcm)` | `u32` |
| `samples_per_channel(pcm)` | `u64` |
| `digest(pcm)` | `&vector<u8>`, 32 bytes |
| `duration_ms(pcm)` | `u64`, `samples_per_channel * 1000 / sample_rate_hz` rounded down; never aborts, because `new` bounds the length |

## Events

None: a value type changes no state.

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EZeroChannels` | `channels` is 0 |
| 1 | `EInvalidBitDepth` | `bit_depth` is 0 or above 32 |
| 2 | `EZeroSampleRate` | `sample_rate_hz` is 0 |
| 3 | `EZeroSamplesPerChannel` | `samples_per_channel` is 0 |
| 4 | `EInvalidDuration` | `samples_per_channel` is above `u64::MAX / 1000` |
| 5 | `EInvalidDigestLength` | `digest` is not 32 bytes |

## Dependencies

None beyond the Sui framework.

## Integrator notes

- **The digest.** `digest` is unkeyed BLAKE3, with the default 32-byte
  output, over the decoded PCM interleaved by sample frame. Each sample is a
  signed integer of `ceil(bit_depth / 8)` bytes: little-endian, two's
  complement, right-aligned and sign-extended within those bytes. It hashes
  the samples, not the file, so the same PCM gives the same digest in any
  container or codec. It does not cover the channel count, bit depth or sample
  rate, which is why they are fields.
- **Integer linear PCM only.** `bit_depth` is the integer sample width.
  Floating-point PCM and DSD are not `Pcm`.
- **`new` checks the shape only.** A `Pcm` proves nothing by itself. Trust the
  `Audio<SomeVerifier, Pcm, _>` that holds it, and pin the verifier type.
- **Check a file against a `Pcm`** by decoding it and comparing the BLAKE3
  digest of its PCM, computed as above, with `digest`.

## Build and test

```sh
sui move build --lint --warnings-are-errors
sui move build --lint --warnings-are-errors --build-env mainnet
sui move test --coverage --lint --warnings-are-errors
sui move coverage summary
```

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
