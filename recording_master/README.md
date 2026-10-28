# `recording_master`

Audio masters for a `miso_music::recording::Recording`: references from the
recording to canonical [`audio::Audio<AudioVerifier>`](https://github.com/misofm/audio)
objects, written as dynamic fields through the recording's cap-gated
`uid_mut`. A recording holds one master per Audio, so its mixes (stereo,
immersive and so on) sit side by side, and several verifiers' Audio for the
same sound can all be attached. A release authorization by the recording covers
every master attached to it.

## What it stores

- Key: `RecordingMasterKey(audio_id)`, a positional struct local to this
  package. The Audio's ID already fixes its verifier type and facts, so the
  key needs nothing else.
- Value: `true`. The facts and the files live on the shared Audio, which
  anyone can read; the recording stores only that it uses it.
- Masters are the recording owner's own claim, so the owner can remove one,
  for example one attached by mistake, and attach it again later.

## API

`add_master` and `remove_master` require the recording's `&RecordingAdminCap<RecordingShare>`,
which is bound to the recording by its share type. Views are permissionless.

| Function | Description |
|---|---|
| `add_master<AudioVerifier, RecordingShare>(recording, cap, audio)` | Attaches `&audio` as a master; attaching it again neither writes nor emits |
| `remove_master<RecordingShare>(recording, cap, audio_id)` | Detaches that Audio; aborts `ENoMaster` (0) if it isn't attached |
| `has_master<RecordingShare>(recording, audio_id)` | Whether that Audio is attached |

`add_master` takes the Audio
itself, so it works on a new Audio before `audio::share`, in the same
transaction as `audio_verifier::verify_audio`.

## Events

| Event | Fields |
|---|---|
| `RecordingMasterAddedEvent<AudioVerifier>` | `recording_id: ID`, `audio_id: ID` |
| `RecordingMasterRemovedEvent` | `recording_id: ID`, `audio_id: ID` |

The Audio's facts are in audio's `AudioCreatedEvent<AudioVerifier>`, emitted
once when the Audio was created, and its files in
`audio_encoding::AudioEncodingRegisteredEvent<AudioVerifier, AudioEncodingVerifier>`.
Indexers join them on `audio_id`; the facts never change. The verifier type
parameter lets indexers follow only the verifiers they trust. `remove_master`
takes only the Audio's ID, so its event has no verifier type; the matching add
event has it.

## Dependencies

- [`miso_music`](https://github.com/misofm/music-protocol) at
  `a41c811a6c232ad05fe10c8c506cb972a87e0a77`: `Recording`,
  `RecordingAdminCap` and `uid_mut`.
- [`audio`](https://github.com/misofm/audio) at
  `49783e9b29ffff3d10ce5e0adf22ab86a7a542a0`: the `Audio<AudioVerifier>`
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
