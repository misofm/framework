# recording_master

A recording's masters: attested [`audio::Audio`](../audio) values stored on a
`miso_music::recording::Recording` as dynamic fields. Each one is keyed by the
Walrus blob ID of its file and written through the recording's cap-gated
`uid_mut`. A recording holds one master per blob, so its mixes (stereo,
immersive and so on) sit side by side. The recording holds the `Audio` itself,
which is what [`recording_master_seal`](../recording_master_seal) checks before
the master's owner may decrypt it.

## What it stores

- Key: `RecordingMasterKey(blob_id: u256)`, local to this package, one per
  blob.
- Value: the `Audio<AudioVerifier, Format, Layout>` itself, holding the format,
  the layout and the `WalrusBlob` with its sealed key.
- Masters are the recording owner's own data. The owner can remove one and gets
  the `Audio` back, to store elsewhere, attach again or drop. Removing reclaims
  the field.

## API

### Writes (cap-gated)

Both take the recording's `&RecordingAdminCap<RecordingShare>`, which the
share type binds to the recording.

| Function | Description | Aborts |
|---|---|---|
| `add_master<RecordingShare, AudioVerifier, Format, Layout>(recording, cap, audio)` | Stores `audio` under its blob ID; emits `RecordingMasterAddedEvent` | `EMasterAlreadyAdded` (1) |
| `remove_master<RecordingShare, AudioVerifier, Format, Layout>(recording, cap, blob_id): Audio<AudioVerifier, Format, Layout>` | Removes and returns that master; emits `RecordingMasterRemovedEvent` | `EMasterNotFound` (0); `EFieldTypeMismatch` at `sui::dynamic_field` if the master has other types |

### Views

| Function | Returns |
|---|---|
| `has_master<RecordingShare>(recording, blob_id)` | `bool`: whether a master of any type is stored under that blob ID |
| `master<RecordingShare, AudioVerifier, Format, Layout>(recording, blob_id)` | `&Audio<AudioVerifier, Format, Layout>`; aborts `EMasterNotFound` (0) if absent, `EFieldTypeMismatch` at `sui::dynamic_field` if it has other types |

## Events

| Event | When | Payload |
|---|---|---|
| `RecordingMasterAddedEvent<AudioVerifier, Format, Layout>` | `add_master` | `recording_id: ID`, `blob_id: u256` |
| `RecordingMasterRemovedEvent<AudioVerifier, Format, Layout>` | `remove_master` | `recording_id: ID`, `blob_id: u256` |

The type parameters name the master's verifier, format and layout, so an
indexer can follow only the types it trusts.

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EMasterNotFound` | `remove_master` or `master` with no master under that blob ID |
| 1 | `EMasterAlreadyAdded` | `add_master` when that blob ID is already a master, whatever its types |

Reading or removing a master as the wrong types aborts with
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

- **Attach in the verifying PTB.** `audio_verifier::verify_audio` returns the
  `Audio` by value. Pass it to `add_master` in the same transaction. `Audio`
  has no `copy`, so it can't be stored twice from one verification. A replayed
  verification can still produce another, which is why access is bound to the
  recording by the Seal identity, not by the blob.
- **Facts come from the verifier's event.** The master events carry only the
  recording, the blob ID and the types. For `AudioVerifier`, read the format,
  layout and sealed key from `audio_verifier::AudioVerifiedEvent`, joined on
  `data.blob_id`. Or read the dynamic field directly.
- **Pass the exact types to remove or read.** For Miso's verifier, they are
  `<AudioVerifier, Pcm, ChannelLayout>`. The type parameters of the added
  event say what they were.
- **Removing a master stops new key requests** through
  `recording_master_seal`. Keys already fetched keep working.
- **Blob lifetime is the owner's concern.** Walrus storage expires unless it
  is extended. This package neither holds nor extends the `Blob` object.

## Build and test

```sh
sui move build --lint --warnings-are-errors
sui move build --lint --warnings-are-errors --build-env mainnet
sui move test --coverage --lint --warnings-are-errors
sui move coverage summary
```

## Generations

This is the second generation. The first stored `true` under
`RecordingMasterKey(audio_id)`, pointing at a frozen `Audio` object, and stays
published on mainnet at
`0xa4bc24667942bc1049380b8765be422e2256f3ef9bb0cdf34c627be1b44f53f1`.
`Published.toml` records the current generation per network.

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
