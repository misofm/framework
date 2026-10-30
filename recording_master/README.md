# `recording_master`

Audio masters for a `miso_music::recording::Recording`: references from the
recording to canonical [`audio::Audio<AudioVerifier>`](../audio)
objects, written as dynamic fields through the recording's cap-gated
`uid_mut`. A recording holds one master per Audio, so its mixes (stereo,
immersive and so on) sit side by side, and several verifiers' Audio for the
same sound can all be attached. A release authorization by the recording covers
every master attached to it.

## What it stores

- Key: `RecordingMasterKey(audio_id)`, a positional struct local to this
  package. The Audio's ID already fixes its verifier type and facts, so the
  key needs nothing else.
- Value: `true`. The facts live on the frozen Audio, which anyone can read;
  the recording stores only that it uses it.
- Masters are the recording owner's own claim, so the owner can remove one,
  for example one attached by mistake, and attach it again later.

## API

`add_master` and `remove_master` require the recording's `&RecordingAdminCap<RecordingShare>`,
which is bound to the recording by its share type. Views are permissionless.

| Function | Description |
|---|---|
| `add_master<RecordingShare, AudioVerifier>(recording, cap, audio)` | Attaches `&audio` as a master; aborts `EMasterAlreadyAdded` (1) if it is already attached |
| `remove_master<RecordingShare, AudioVerifier>(recording, cap, audio_id)` | Detaches that Audio, with the caller naming its verifier for the event; aborts `EMasterNotFound` (0) if it isn't attached |
| `has_master<RecordingShare>(recording, audio_id)` | Whether that Audio is attached |

`add_master` takes the Audio
itself, so it works on a new Audio before `audio.freeze()`, in the same
transaction as `audio_verifier::verify_audio`.

## Events

| Event | Fields |
|---|---|
| `RecordingMasterAddedEvent<AudioVerifier>` | `recording_id: ID`, `audio_id: ID` |
| `RecordingMasterRemovedEvent<AudioVerifier>` | `recording_id: ID`, `audio_id: ID` |

The Audio's facts are in audio's `AudioCreatedEvent<AudioVerifier>`, emitted
once when the Audio was created. Indexers join them on `audio_id`; the facts never change. The verifier type
parameter lets indexers follow only the verifiers they trust. `remove_master`
takes only the Audio's ID, so the caller names the verifier type for the
removal event; it is not checked on-chain.

## Dependencies

- [`miso_music`](https://github.com/misofm/music-protocol) at
  `bc547c79a2d3a6db6543ba7b12260ce70b93731c`: `Recording`,
  `RecordingAdminCap` and `uid_mut`.
- [`audio`](../audio), by local path: the `Audio<AudioVerifier>` object.

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
