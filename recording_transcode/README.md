# recording_transcode

A recording's transcodes: [`audio::Audio`](../audio) values for listeners,
stored on a `miso_music::recording::Recording` as dynamic fields. Each one is
keyed by the Walrus blob ID of its quilt and written through the recording's
cap-gated `uid_mut`. It mirrors [`recording_master`](../recording_master) in a
separate namespace, so masters and transcodes never collide and the listener
Seal policy, [`recording_transcode_access`](../recording_transcode_access),
can check one without the other. One set of transcodes serves every release
that contains the recording.

## What it stores

- Key: `RecordingTranscodeKey(quilt_blob_id: u256)`, local to this package,
  one per quilt.
- Value: the `Audio<AudioVerifier, Format, Layout>` itself. For Miso's
  transcoder it is `Audio<AudioTranscoder, AacHls, ChannelLayout>`.
- The owner can remove a transcode and gets the `Audio` back. Removing
  reclaims the field.

## API

### Writes (cap-gated)

Both take the recording's `&RecordingAdminCap<RecordingShare>`, which the
share type binds to the recording, so a wrong cap does not type-check.

| Function | Description | Aborts |
|---|---|---|
| `add_transcode<RecordingShare, AudioVerifier, Format, Layout>(recording, cap, audio)` | Stores `audio` under its quilt's blob ID; emits `RecordingTranscodeAddedEvent` | `ETranscodeAlreadyAdded` (1) |
| `remove_transcode<RecordingShare, AudioVerifier, Format, Layout>(recording, cap, quilt_blob_id): Audio<AudioVerifier, Format, Layout>` | Removes and returns that transcode; emits `RecordingTranscodeRemovedEvent` | `ETranscodeNotFound` (0); `EFieldTypeMismatch` at `sui::dynamic_field` if the transcode has other types |

### Views

| Function | Returns |
|---|---|
| `has_transcode<RecordingShare>(recording, quilt_blob_id)` | `bool`: whether a transcode of any type is stored under that blob ID |
| `transcode<RecordingShare, AudioVerifier, Format, Layout>(recording, quilt_blob_id)` | `&Audio<AudioVerifier, Format, Layout>`; aborts `ETranscodeNotFound` (0) if absent, `EFieldTypeMismatch` at `sui::dynamic_field` if it has other types |

## Events

| Event | When | Payload |
|---|---|---|
| `RecordingTranscodeAddedEvent<AudioVerifier, Format, Layout>` | `add_transcode` | `recording_id: ID`, `quilt_blob_id: u256` |
| `RecordingTranscodeRemovedEvent<AudioVerifier, Format, Layout>` | `remove_transcode` | `recording_id: ID`, `quilt_blob_id: u256` |

The type parameters name the transcode's verifier, format and layout, so an
indexer can follow only the types it trusts.

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `ETranscodeNotFound` | `remove_transcode` or `transcode` with no transcode under that blob ID |
| 1 | `ETranscodeAlreadyAdded` | `add_transcode` when that blob ID is already a transcode, whatever its types |

Reading or removing a transcode as the wrong types aborts with
`EFieldTypeMismatch` (2) at `sui::dynamic_field`.

## Dependencies

- [`miso_music`](https://github.com/misofm/music-protocol) at
  `430424a678f2387090850417eacbaa1bb46d1fb7`: `Recording`,
  `RecordingAdminCap` and `uid_mut`.
- [`audio`](../audio), by local path: `Audio`.
- [`ori`](https://github.com/unconfirmedlabs/ori) (`move` subdirectory) at
  `a3a134ae69a4861030a05ae22f21e67a7b91faf9`: reads the blob ID from the
  `WalrusBlob`.

## Integrator notes

- **Generic on purpose; trust by type.** `add_transcode` accepts any
  `Audio`, with no check against the masters. The link to the master is
  enforced where the `Audio` is made: `audio_transcoder::verify_transcode`
  only returns one when the recording holds an attested master with the same
  PCM digest. Clients and indexers should trust only
  `AudioVerifier = audio_transcoder::AudioTranscoder`.
- **Attach in the verifying PTB.** Call `verify_transcode`, then pass its
  `Audio` to `add_transcode` in the same transaction.
- **Facts come from the verifier's event.** For `AudioTranscoder`, read the
  format, layout, sealed key and source master from
  `audio_transcoder::TranscodeVerifiedEvent`, joined on `data.blob_id`, or
  read the dynamic field.
- **Removing a transcode stops new key requests** through
  `recording_transcode_access`. Keys already fetched keep working.
- **Blob lifetime is the owner's concern.** This package neither holds nor
  extends the Walrus `Blob` object.

## Deployments

Testnet `0x1b21766c7b3c4c0962f87654741e7197674419313cce6d28800c407d7bd2d429`
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
