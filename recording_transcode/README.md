# recording_transcode

A recording's current transcode for listeners, per master: an encrypted
Walrus quilt of HLS files and a plain preview blob, stored on a
`miso_music::recording::Recording` under the master's blob ID and written
through the recording's cap-gated `uid_mut`. Following
[`ori`](https://github.com/unconfirmedlabs/ori), the quilt is a `WalrusBlob`
whose confidentiality covers the whole quilt. The record is typed by the
transcoder that vouched for it; only that transcoder's package can build one.
One transcode serves every release that contains the recording.

## What it stores

- Key: `RecordingTranscodeKey(master_blob_id: u256)`, local to this package,
  one per master, replaced in place.
- Value:
  ```move
  public struct RecordingTranscode<phantom Transcoder> has store, drop {
      data: WalrusBlob,          // the quilt: blob_id = quilt ID, Encrypted { sealed_dek }
      preview: RecordingPreview,
  }
  public struct RecordingPreview has copy, drop, store {
      start_sample: u64,         // in the master's samples
      end_sample: u64,
      data: WalrusBlob,          // a separate plain blob
  }
  ```
- The owner can remove a transcode and gets it back. Removing reclaims the
  field.

## API

### Constructors

| Function | Returns | Aborts |
|---|---|---|
| `new<Transcoder>(witness: Transcoder, data, preview)` | `RecordingTranscode<Transcoder>`: only code holding the `Transcoder` witness builds one | `EUnencryptedTranscode` (2) when `data` is not encrypted |
| `new_preview(start_sample, end_sample, data)` | `RecordingPreview` | `EInvalidRange` (4) unless `start_sample < end_sample`; `EEncryptedPreview` (3) when `data` is encrypted |

### Writes (cap-gated)

Both take the recording's `&RecordingAdminCap<RecordingShare>`, which the
share type binds to the recording, so a wrong cap does not type-check.

| Function | Description | Aborts |
|---|---|---|
| `add_transcode<RecordingShare, Transcoder>(recording, cap, master_blob_id, transcode)` | Stores or replaces the master's transcode; emits `RecordingTranscodeSetEvent<Transcoder>`. An equal one: no-op | `EMasterNotFound` (1); `ETranscodeOfAnotherType` (5) when the master's transcode is another transcoder's |
| `remove_transcode<RecordingShare, Transcoder>(recording, cap, master_blob_id): RecordingTranscode<Transcoder>` | Removes and returns it; emits `RecordingTranscodeRemovedEvent<Transcoder>` | `ETranscodeNotFound` (0); `EFieldTypeMismatch` at `sui::dynamic_field` for another transcoder |

### Views

| Function | Returns |
|---|---|
| `has_transcode<RecordingShare>(recording, master_blob_id)` | `bool`, whatever its transcoder |
| `transcode<RecordingShare, Transcoder>(recording, master_blob_id)` | `&RecordingTranscode<Transcoder>`; aborts `ETranscodeNotFound` (0) if absent, `EFieldTypeMismatch` at `sui::dynamic_field` for another transcoder |
| `data(transcode)`, `preview(transcode)` | `&WalrusBlob`, `&RecordingPreview` |
| `start_sample(preview)`, `end_sample(preview)`, `preview_data(preview)` | `u64`, `u64`, `&WalrusBlob` |

## Events

| Event | When | Payload |
|---|---|---|
| `RecordingTranscodeSetEvent<Transcoder>` | `add_transcode` stores or changes one | `recording_id: ID`, `master_blob_id: u256`, `data: WalrusBlob`, `preview: RecordingPreview` |
| `RecordingTranscodeRemovedEvent<Transcoder>` | `remove_transcode` | `recording_id: ID`, `master_blob_id: u256` |

The type parameter names the transcoder, so an indexer can follow only the
ones it trusts.

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `ETranscodeNotFound` | No transcode under that master |
| 1 | `EMasterNotFound` | `add_transcode` for a blob the recording holds no master under |
| 2 | `EUnencryptedTranscode` | `new` with an unencrypted quilt |
| 3 | `EEncryptedPreview` | `new_preview` with an encrypted blob |
| 4 | `EInvalidRange` | `new_preview` with `start_sample >= end_sample` |
| 5 | `ETranscodeOfAnotherType` | `add_transcode` over another transcoder's transcode: remove it first |

## Dependencies

- [`miso_music`](https://github.com/misofm/music-protocol) at
  `430424a678f2387090850417eacbaa1bb46d1fb7`: `Recording`,
  `RecordingAdminCap` and `uid_mut`.
- [`recording_master`](../recording_master), by local path: `has_master`.
- [`ori`](https://github.com/unconfirmedlabs/ori) (`move` subdirectory) at
  `a3a134ae69a4861030a05ae22f21e67a7b91faf9`: `WalrusBlob` and its
  confidentiality.
- [`audio`](../audio), by local path: used only by the tests, to build
  masters. The package manifest has no dev-dependencies section.

## Integrator notes

- **Trust by type.** Anyone can publish a witness type and attach records
  under it to a recording they administer. Trust only
  `Transcoder = audio_transcoder::AudioTranscoder`, whose record
  `audio_transcoder::verify_transcode` builds from an attested job.
- **No format on chain.** The tiers, rates and file list live in the quilt's
  playlists (`master.m3u8` and the media playlists). Each encrypted patch is
  authenticated by Tink, with its identifier as associated data; the preview
  is content-addressed by its blob ID.
- **The preview is public.** `preview.data` is a plain blob anyone can play,
  cut from the master range the owner granted. Every range ever granted is
  public for good.
- **Replacing a transcode** keeps the old quilt and preview on Walrus until
  they expire; the listener identity names the quilt, so a stale one stops
  decrypting (`recording_transcode_access`).
- **Removing a transcode stops new key requests.** Keys already fetched keep
  working.
- **Blob lifetime is the owner's concern.** This package neither holds nor
  extends the Walrus `Blob` objects.

## Build and test

```sh
sui move build --lint --warnings-are-errors
sui move build --lint --warnings-are-errors --build-env mainnet
sui move test --coverage --lint --warnings-are-errors
sui move coverage summary
```

## Deployments

Testnet `0x320e7a2834aa6a0d7d677a71c9d68d12fbb7f7917ffb4c5879cedfc0b3e58373`
(tx `7M1f8XvfBi444phKTMEpYiLsF4iaSFbtaEGuC4z12EJv`). The first generation,
which stored `Audio` values by quilt ID, stays published on testnet at
`0x1b21766c7b3c4c0962f87654741e7197674419313cce6d28800c407d7bd2d429`. Mainnet `0x7a83dd22131cad38ded582a5cb5527e1ab95eec3c748e934585d6da4f61da563`
(tx `AqiaQNg11cMwZNouJUFpsgQdY5cLw1iH1jC1VttDB2Ys`).

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
