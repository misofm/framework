# `audio_encoding`

The files known to decode to a canonical [`audio::Audio<AudioVerifier>`](../audio).

Each encoding is a dynamic field on the Audio, `AudioEncodingKey<AudioEncodingVerifier>(blob_id) → true`. There is one per unencrypted Walrus blob, identified by its `u256` blob ID, and it is written once and never removed.

Measuring audio and matching a file to it are separate claims, so an encoding is vouched for by its own `AudioEncodingVerifier` type. Any encoding verifier can register files on any Audio, but only under its own type. A verifier such as `audio_verifier` passes the same witness as both.

Walrus blob IDs are content-addressed, so an expired file can be stored again under the same ID. The file's format is not stored: audio files identify themselves by their first bytes.

## API

| Function | Gate | What it does |
|---|---|---|
| `register_encoding<AudioVerifier, AudioEncodingVerifier: drop>(audio, witness, blob_id)` | encoding witness | Registers a blob as an encoding under the witness's type and emits `AudioEncodingRegisteredEvent`. Aborts with `EEncodingAlreadyRegistered` (0) if that verifier already registered the blob. |
| `has_encoding<AudioVerifier, AudioEncodingVerifier>(audio, blob_id)` | none | Whether that encoding verifier registered the blob. |

## Trust

Read encodings only under the `AudioEncodingVerifier` types you trust. Entries under other types are claims by whoever published them.

## Events

- `AudioEncodingRegisteredEvent<AudioVerifier, AudioEncodingVerifier> { audio_id, blob_id }` from `register_encoding`, once per encoding verifier and blob.

## Install

```toml
[dependencies]
audio_encoding = { git = "https://github.com/misofm/framework.git", subdir = "audio_encoding", rev = "<commit>" }
```

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md) © Miso Labs, Inc.
