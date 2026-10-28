# `recording_master`

Audio masters for a `miso_music::recording::Recording`: verified
[`audio::Audio<AudioVerifier>`](https://github.com/misofm/audio) values
stored as dynamic fields on the recording and written through its cap-gated
`uid_mut`. A recording holds one master per distinct audio and verifier, so
its mixes (stereo, immersive and so on) sit side by side, and several
verifiers can attest the same audio. A `ReleaseLicense` on the recording
covers every master attached to it.

## What it stores

- Key: `RecordingMasterKey<AudioVerifier>(pcm_digest)`, a positional struct
  local to this package, parameterized because each master is identified by
  its verifier type and its audio's PCM digest.
- Value: the `Audio<AudioVerifier>` itself.
- Masters are written once. There is no remove or replace, and the package is
  published immutable.

## API

`add_master` requires the recording's `&RecordingAdminCap<RecordingShare>`,
which is bound to the recording by its share type. Views are permissionless.

| Function | Description | Aborts |
|---|---|---|
| `add_master<AudioVerifier, RecordingShare>(recording, cap, audio)` | Attaches `audio` under its verifier and PCM digest; adding an equal master again neither writes nor emits | `EMasterExists` (1) for different audio under an existing key |
| `has_master<AudioVerifier, RecordingShare>(recording, pcm_digest)` | Whether that verifier's master for that digest is attached | none |
| `master<AudioVerifier, RecordingShare>(recording, pcm_digest)` | The attached `&Audio<AudioVerifier>` | `ENoMaster` (0) |

## Events

| Event | Fields | BCS bytes |
|---|---|---|
| `RecordingMasterAddedEvent<AudioVerifier>` | `recording_id: ID`, `audio: Audio<AudioVerifier>` | 112 |

The event carries the full stored value. The audio's `format` is not part of
`Audio`; it is in audio's `AudioCreatedEvent<AudioVerifier>`, emitted when the
value was created.

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `ENoMaster` | `master` with nothing attached under that verifier and digest |
| 1 | `EMasterExists` | `add_master` with different audio under an existing verifier and digest |

## Dependencies

- [`miso_music`](https://github.com/misofm/music-protocol) at
  `a41c811a6c232ad05fe10c8c506cb972a87e0a77`: `Recording`,
  `RecordingAdminCap` and `uid_mut`.
- [`audio`](https://github.com/misofm/audio) at
  `66aa27eccc6692fb026393655b2b82934bbf5207`: the `Audio<AudioVerifier>`
  value type.
- [`ori`](https://github.com/unconfirmedlabs/ori) at
  `effc16a7f4efc334ffa8f39effcc9e7bbc3f837c`, test mode only: blob fixtures.

## Publishing

Every change is published as a fresh, immutable package identity; nothing is
upgraded in place. This package has not been published or audited.

## Build and test

```sh
sui move build --lint --warnings-are-errors
sui move build --lint --warnings-are-errors --build-env mainnet
sui move test --coverage --lint --warnings-are-errors
sui move coverage summary
sui move test --build-env mainnet
sui move format --print-width 100 --tab-width 4 --auto-group-imports none --check sources tests
```
