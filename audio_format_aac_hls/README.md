# audio_format_aac_hls

The `AacHls` value type: the facts of an AAC-LC HLS ladder, which are its
bitrates, its output sample rate, the BLAKE3 digest of the PCM it was encoded
from, a BLAKE3 digest of its file inventory, and the range of the master its
plaintext preview was cut from. It is the `Format` of an
[`audio::Audio`](../audio) whose data is a Walrus quilt, one patch per HLS
file. It is its own package so that `audio` stays format-agnostic. Anyone can
build an `AacHls`. Only the `Audio` that holds it is attested, by its
verifier, such as [`audio_transcoder`](../audio_transcoder).

## What it stores

Nothing: `AacHls` is a `copy + drop + store` value.

```move
public struct AacHls has copy, drop, store {
    bitrates_kbps: vector<u16>,
    sample_rate_hz: u32,
    source_pcm_digest: vector<u8>,
    manifest: vector<u8>,
    preview: Preview,
}

public struct Preview has copy, drop, store {
    start_sample: u64,
    end_sample: u64,
}
```

| Field | Rule |
|---|---|
| `bitrates_kbps` | 1 to 8 renditions, each above 0, strictly ascending |
| `sample_rate_hz` | at least 1 |
| `source_pcm_digest` | exactly 32 bytes |
| `manifest` | exactly 32 bytes |
| `preview` | `start_sample < end_sample`, in the master's samples |

The channel count is not a field: the `Audio`'s layout carries it.

## API

### Constructors

| Function | Returns | Aborts |
|---|---|---|
| `new(bitrates_kbps, sample_rate_hz, source_pcm_digest, manifest, preview_start_sample, preview_end_sample)` | `AacHls` | `ENoBitrates` (0), `ETooManyBitrates` (1), `EUnorderedBitrates` (2), `EZeroSampleRate` (3), `EInvalidDigestLength` (4), `EInvalidPreview` (5) |

### Views

| Function | Returns |
|---|---|
| `bitrates_kbps(format)` | `&vector<u16>`, ascending |
| `sample_rate_hz(format)` | `u32` |
| `source_pcm_digest(format)` | `&vector<u8>`, 32 bytes |
| `manifest(format)` | `&vector<u8>`, 32 bytes |
| `preview(format)` | `&Preview` |
| `start_sample(preview)`, `end_sample(preview)` | `u64`, in the master's samples |
| `max_bitrates()` | `u64`, 8 |

## Events

None: a value type changes no state.

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `ENoBitrates` | `bitrates_kbps` is empty |
| 1 | `ETooManyBitrates` | `bitrates_kbps` has more than 8 entries |
| 2 | `EUnorderedBitrates` | A bitrate is 0, or the bitrates are not strictly ascending |
| 3 | `EZeroSampleRate` | `sample_rate_hz` is 0 |
| 4 | `EInvalidDigestLength` | `source_pcm_digest` or `manifest` is not 32 bytes |
| 5 | `EInvalidPreview` | `preview_start_sample >= preview_end_sample` |

## Dependencies

None beyond the Sui framework.

## Integrator notes

- **`source_pcm_digest`** is the [`audio_format_pcm`](../audio_format_pcm)
  `Pcm.digest` of the master the ladder was encoded from, in the same layout.
  It names the PCM, not a blob, so any copy of the same master matches.
- **`manifest`** is unkeyed BLAKE3 over the BCS of
  `vector<(identifier: String, size: u64, blake3: vector<u8>)>`: one entry per
  plaintext HLS file (playlists and segments), sorted by identifier in
  byte order. `size` is the plaintext length and `blake3` its 32-byte digest.
  The quilt also stores this inventory as a patch, so a client can check every
  file it decrypts against it.
- **`preview`** names the master range `[start_sample, end_sample)`, counted
  at the master's sample rate, that the quilt's `preview.m4a` was cut from: a
  plain (non-fragmented) MP4 with faststart, AAC-LC 160 kbps stereo,
  **unencrypted**, listed in the inventory like every other file. It plays
  straight from an aggregator, `GET /v1/blobs/by-quilt-id/{quilt_id}/preview.m4a`.
- **`sample_rate_hz`** is the rate of the encoded AAC, which may differ from
  the master's: Miso's transcoder resamples rates above 48 kHz to 48 kHz, or to
  44.1 kHz for the 88.2/176.4 kHz family.
- **`new` checks the shape only.** An `AacHls` proves nothing by itself.
  Trust the `Audio<SomeVerifier, AacHls, _>` that holds it, and pin the
  verifier type.

## Deployments

Testnet `0x03b51f8a7a0d198efbb41c75dec1d4d7a2d352dbe61533ff4e42817e63752c5e`
(tx `DfLByqFWH68GzM3T1jGp9AiCHq3ie5hbYUDJwaRPgqSq`). It is not on mainnet yet.

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
