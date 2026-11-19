# recording_master

A recording's masters: attested [`audio::Audio`](../audio) values stored on a
`miso_music::recording::Recording` as dynamic fields. Each one is keyed by the
verifier type and the Walrus blob ID of its file, and written through the
recording's cap-gated `uid_mut`. A recording holds one master per verifier and
blob, so its mixes (stereo, immersive and so on) sit side by side, and a
master can be found by the verifier a reader trusts without reading the
others. The recording holds the `Audio` itself, which is what
[`recording_master_access`](../recording_master_access) checks before anyone
may decrypt it.

## What it stores

- Key: `RecordingMasterKey<MasterVerifier>(blob_id: u256)`, local to this
  package, one per verifier type and blob.
- Value: the `Audio<MasterVerifier, Format, Layout>` itself, holding the format,
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
| `add_master<RecordingShare, MasterVerifier, Format, Layout>(recording, cap, audio)` | Stores `audio` under its verifier type and blob ID; emits `RecordingMasterAddedEvent` | `EMasterAlreadyAdded` (1) |
| `remove_master<RecordingShare, MasterVerifier, Format, Layout>(recording, cap, blob_id): Audio<MasterVerifier, Format, Layout>` | Removes and returns that master; emits `RecordingMasterRemovedEvent` | `EMasterNotFound` (0); `EFieldTypeMismatch` at `sui::dynamic_field` if its format or layout are other types |

### Views

| Function | Returns |
|---|---|
| `has_master<RecordingShare, MasterVerifier>(recording, blob_id)` | `bool`: whether a master of that verifier is stored under that blob ID |
| `master<RecordingShare, MasterVerifier, Format, Layout>(recording, blob_id)` | `&Audio<MasterVerifier, Format, Layout>`; aborts `EMasterNotFound` (0) if that verifier has none there, `EFieldTypeMismatch` at `sui::dynamic_field` if its format or layout are other types |

## Events

| Event | When | Payload |
|---|---|---|
| `RecordingMasterAddedEvent<MasterVerifier, Format, Layout>` | `add_master` | `recording_id: ID`, `blob_id: u256` |
| `RecordingMasterRemovedEvent<MasterVerifier, Format, Layout>` | `remove_master` | `recording_id: ID`, `blob_id: u256` |

The type parameters name the master's verifier, format and layout, so an
indexer can follow only the types it trusts.

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EMasterNotFound` | `remove_master` or `master` with no master of that verifier under that blob ID |
| 1 | `EMasterAlreadyAdded` | `add_master` when that verifier already has a master under that blob ID |

Reading or removing a master with the right verifier but other format or
layout types aborts with `EFieldTypeMismatch` (2) at `sui::dynamic_field`.

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
- **Trust by verifier.** Anyone may attach a master under a verifier type of
  their own to a recording they administer. Look masters up under the
  verifier you trust (`has_master<_, AudioVerifier>`), which no other
  verifier's master can shadow.
- **Removing a master stops new key requests** through
  `recording_master_access`. Keys already fetched keep working.
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

This is the third generation: its key is typed by verifier. The second keyed
masters by blob ID alone (`RecordingMasterKey(u256)`) and stays published on
testnet at `0x75cb941c7f7b7c946faa62a0d630a20796e9414a185dff7b0173ecb86c7f114e`.
The first stored `true` under
`RecordingMasterKey(audio_id)`, pointing at a frozen `Audio` object, and stays
published on mainnet at
`0xa4bc24667942bc1049380b8765be422e2256f3ef9bb0cdf34c627be1b44f53f1`.
`Published.toml` records the current generation per network.

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
