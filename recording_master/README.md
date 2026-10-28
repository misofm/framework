# `recording_master`

Audio masters for a `miso_music::recording::Recording`: references from the
recording to canonical [`audio::Audio<AudioVerifier>`](https://github.com/misofm/audio)
objects, written as dynamic fields through the recording's cap-gated
`uid_mut`. A recording holds one master per Audio, so its mixes (stereo,
immersive and so on) sit side by side, and several verifiers' Audio for the
same sound can all be attached. A `ReleaseLicense` on the recording covers
every master attached to it.

## What it stores

- Key: `RecordingMasterKey(audio_id)`, a positional struct local to this
  package. The Audio's ID already fixes its verifier type and facts, so the
  key needs nothing else.
- Value: `true`. The facts and the files live on the shared Audio, which
  anyone can read; the recording stores only that it uses it.
- Masters are written once. There is no remove or replace, and the package is
  published immutable.

## API

`add_master` requires the recording's `&RecordingAdminCap<RecordingShare>`,
which is bound to the recording by its share type. Views are permissionless.

| Function | Description |
|---|---|
| `add_master<AudioVerifier, RecordingShare>(recording, cap, audio)` | Attaches `&audio` as a master; attaching it again neither writes nor emits |
| `has_master<RecordingShare>(recording, audio_id)` | Whether that Audio is attached |

Nothing aborts beyond the cap's type check. `add_master` takes the Audio
itself, so it works on a new Audio before `audio::share`, in the same
transaction as `audio_verifier::verify_audio`.

## Events

| Event | Fields |
|---|---|
| `RecordingMasterAddedEvent<AudioVerifier>` | `recording_id: ID`, `audio_id: ID`, `channels: u8`, `bit_depth: u8`, `sample_rate_hz: u32`, `samples_per_channel: u64`, `pcm_digest: vector<u8>` |

The event copies the Audio's facts so indexers don't need a second lookup.
The Audio's files are in audio's `AudioEncodingRegisteredEvent<AudioVerifier, AudioEncodingVerifier>`.

## Dependencies

- [`miso_music`](https://github.com/misofm/music-protocol) at
  `a41c811a6c232ad05fe10c8c506cb972a87e0a77`: `Recording`,
  `RecordingAdminCap` and `uid_mut`.
- [`audio`](https://github.com/misofm/audio) at
  `875fc7dab55c8bfca2eadbb74290db42a17f0ea5`: the `Audio<AudioVerifier>`
  object.

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
```
