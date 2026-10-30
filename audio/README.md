# miso-audio

[![License: FSL-1.1-ALv2](https://img.shields.io/badge/license-FSL--1.1--ALv2-blue.svg)](LICENSE.md)
[![Move](https://img.shields.io/badge/Move-2024-black.svg)](https://docs.sui.io/concepts/sui-move-concepts)

> One canonical, verified record per lossless audio on [Sui](https://sui.io).

`Audio<AudioVerifier>` is a shared object holding the facts an `AudioVerifier` type measured about some integer PCM audio: channels, bit depth, sample rate, samples per channel and a PCM digest. Only code holding an `AudioVerifier` witness can create one, so the type parameter names who measured the audio. There is no self-attested audio.

Audio records what the audio is, not who owns it. Anyone with a file can have it measured. Rights live elsewhere: recordings point at an Audio, they don't own it.

## Modules

- `audio::audio`: the registry, `Audio` and its facts.
- `audio::audio_encoding`: the files registered on an Audio.

## Objects

```move
public struct Audio<phantom AudioVerifier> has key {
    id: UID,
    channels: u8,
    bit_depth: u8,
    sample_rate_hz: u32,
    samples_per_channel: u64,
    pcm_digest: vector<u8>,
}
```

- **One Audio per verifier and facts.** Each Audio is a derived object of the shared `AudioRegistry`, claimed with the key `AudioKey<AudioVerifier>(channels, bit_depth, sample_rate_hz, samples_per_channel, pcm_digest)`, in that order: the shape of a frame, then time, then content, the same order as the verifier's signed payload. Its ID is a function of the registry ID, the verifier type and the five facts, so clients holding a file can find its Audio with `derive_address` and plain RPC. The digest alone doesn't commit to how the samples are played, so the same digest with other facts is other audio.
- **The facts never change.** Audio has no setters. It is shared rather than frozen only so encodings can be registered on it.
- **Encodings** are the files known to decode to the Audio: a dynamic field `AudioEncodingKey<AudioEncodingVerifier>(blob_id) → true` per unencrypted Walrus blob, identified by its `u256` blob ID, written once and never removed. Measuring audio and matching a file to it are separate claims, so an encoding is vouched for by its own `AudioEncodingVerifier` type. Any encoding verifier can register files on any Audio, but only under its own type; a verifier such as `audio_verifier` passes the same witness as both. Walrus blob IDs are content-addressed, so an expired file can be stored again under the same ID. The file's format is not stored; audio files identify themselves by their first bytes.
- Audio has only `key`, so it can't be wrapped, transferred or dropped. `new` returns it unshared, so the same transaction can register its first encoding and point records at it, and `share` is the only way to finish with it.

## API

| Function | Gate | What it does |
|---|---|---|
| `new<AudioVerifier: drop>(registry, witness, channels, bit_depth, sample_rate_hz, samples_per_channel, pcm_digest)` | witness | Checks the facts, claims the Audio from the registry and emits `AudioCreatedEvent`. Aborts with `derived_object::EObjectAlreadyExists` if it is already registered. |
| `audio_encoding::register_encoding<AudioVerifier, AudioEncodingVerifier: drop>(audio, witness, blob_id)` | encoding witness | Registers a blob as an encoding under the witness's type and emits `AudioEncodingRegisteredEvent`. Aborts with `EEncodingAlreadyRegistered` if that verifier already registered the blob. |
| `share<AudioVerifier>(audio)` | none | Shares a new Audio. |
| `derive_address<AudioVerifier>(registry_id, channels, bit_depth, sample_rate_hz, samples_per_channel, pcm_digest)` | none | The Audio's address for those facts. |
| `audio_encoding::has_encoding<AudioVerifier, AudioEncodingVerifier>(audio, blob_id)` | none | Whether that encoding verifier registered the blob. |

`uid` exposes the Audio's UID for reading; `uid_mut` is package-only, for `audio_encoding`.

Views: `channels`, `bit_depth`, `sample_rate_hz`, `samples_per_channel`, `pcm_digest`, and `duration_ms`, which rounds down and never aborts, because `new` bounds the duration.

| Fact | Rule | Error |
|---|---|---|
| `channels` | at least 1 | `EZeroChannels` (0) |
| `bit_depth` | 1 to 32 | `EInvalidBitDepth` (1) |
| `sample_rate_hz` | at least 1 | `EZeroSampleRate` (2) |
| `samples_per_channel` | at least 1, and the duration in milliseconds fits in a `u64` | `EZeroSamplesPerChannel` (3), `EInvalidDuration` (4) |
| `pcm_digest` | exactly 32 bytes | `EInvalidDigestLength` (5) |

`new` checks the shape of the facts only. Reading the file and computing the digest is the verifier's job.

## Trust

- **Pin the verifier types you trust.** Accept `Audio<SomeVerifier>`, never a generic `Audio<AudioVerifier>` treated as trusted: anyone can publish a package with a witness and vouch for anything.
- **Pin encoding verifiers too.** Read encodings with the `AudioEncodingVerifier` types you trust. Entries under other types are claims by whoever published them, and listing the Audio's dynamic fields shows each entry's type.
- Several verifiers can measure the same audio. Each gets its own Audio, because the verifier type is part of the key.

## Events

- `AudioCreatedEvent<AudioVerifier> { audio_id, channels, bit_depth, sample_rate_hz, samples_per_channel, pcm_digest }` from `new`.
- `audio_encoding::AudioEncodingRegisteredEvent<AudioVerifier, AudioEncodingVerifier> { audio_id, blob_id }` from `register_encoding`, once per encoding verifier and blob.

## Audio and the PCM digest

Audio means integer linear PCM: `bit_depth` is the integer sample width. Floating-point PCM and DSD are not Audio; if they are ever supported, they get their own types and keys.

`pcm_digest` is BLAKE3, with the default 32-byte output, over the decoded PCM, interleaved by sample frame. Each sample is a signed integer, little-endian, `ceil(bit_depth / 8)` bytes, two's complement, right-aligned (sign-extended within those bytes). It hashes the samples, not the file, so the same PCM gives the same digest in any format. It doesn't cover the channels, bit depth or sample rate, which is why they are part of the key.

## Install

Pin a commit:

```toml
[dependencies]
audio = { git = "https://github.com/misofm/audio.git", rev = "<commit>" }
```

The package depends only on the Sui framework.

## Build & test

```sh
sui move build
sui move test --coverage
```

## Deployments

This API has not been published. `init` shares the `AudioRegistry` at publish. The previous, self-attested API was published at:

- mainnet `0x73a989640258bd5d82e0ae23bcb6f874fae65c78aecc1781b9a702801a043d7e`
- testnet `0x7b143c3408e5fc8964e7ee696c9d4b63b6d0464347797e32bfa43275f09a3b08`

## Contributing

Issues and pull requests are welcome. By contributing you agree that your contributions are licensed under the project's FSL-1.1-ALv2 license.

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md) © Miso Labs, Inc.
