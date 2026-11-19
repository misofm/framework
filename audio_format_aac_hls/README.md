# audio_format_aac_hls

**Unused.** Design v3 keeps no format or manifest on chain: a transcode is a
[`recording_transcode::RecordingTranscode`](../recording_transcode). This
package stays for the record of its testnet publish.

The `AacHls` value type: the facts of an AAC-LC HLS ladder, which are its
bitrates, its output sample rate, the BLAKE3 digest of the PCM it was encoded
from, and a BLAKE3 digest of its file inventory. It is the `Format` of an
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
}
```

| Field | Rule |
|---|---|
| `bitrates_kbps` | 1 to 8 renditions, each above 0, strictly ascending |
| `sample_rate_hz` | at least 1 |
| `source_pcm_digest` | exactly 32 bytes |
| `manifest` | exactly 32 bytes |

The channel count is not a field: the `Audio`'s layout carries it.

## API

### Constructors

| Function | Returns | Aborts |
|---|---|---|
| `new(bitrates_kbps, sample_rate_hz, source_pcm_digest, manifest)` | `AacHls` | `ENoBitrates` (0), `ETooManyBitrates` (1), `EUnorderedBitrates` (2), `EZeroSampleRate` (3), `EInvalidDigestLength` (4) |

### Views

| Function | Returns |
|---|---|
| `bitrates_kbps(format)` | `&vector<u16>`, ascending |
| `sample_rate_hz(format)` | `u32` |
| `source_pcm_digest(format)` | `&vector<u8>`, 32 bytes |
| `manifest(format)` | `&vector<u8>`, 32 bytes |
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
