# miso-audio

[![License: FSL-1.1-ALv2](https://img.shields.io/badge/license-FSL--1.1--ALv2-blue.svg)](LICENSE.md)
[![Move](https://img.shields.io/badge/Move-2024-black.svg)](https://docs.sui.io/concepts/sui-move-concepts)

> One canonical, verified record per lossless audio on [Sui](https://sui.io).

`Audio<AudioVerifier>` is a shared object holding the facts an `AudioVerifier` type measured about some integer PCM audio: channels, bit depth, sample rate, samples per channel and a PCM digest. Only code holding an `AudioVerifier` witness can create one, so the type parameter names who measured the audio. There is no self-attested audio.

Audio records what the audio is, not who owns it. Anyone with a file can have it measured. Rights live elsewhere: recordings point at an Audio, they don't own it.

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
- **The facts never change.** Audio has no setters. It is shared rather than frozen so other packages can attach data to it.
- **Anyone can attach data.** `uid_mut` is public and ungated. Other packages add dynamic fields under their own key types, such as [`audio_encoding`](../audio_encoding) for the files that decode to the Audio. Only the module that defines a key type can construct it, so only that module can write, change or remove fields under it.
- Audio has only `key`, so it can't be wrapped, transferred or dropped. `new` returns it unshared, so the same transaction can attach its first data and point records at it, and `share` is the only way to finish with it.

## API

| Function | Gate | What it does |
|---|---|---|
| `new<AudioVerifier: drop>(registry, witness, channels, bit_depth, sample_rate_hz, samples_per_channel, pcm_digest)` | witness | Checks the facts, claims the Audio from the registry and emits `AudioCreatedEvent`. Aborts with `derived_object::EObjectAlreadyExists` if it is already registered. |
| `share<AudioVerifier>(audio)` | none | Shares a new Audio. |
| `uid_mut<AudioVerifier>(audio)` | none | The Audio's UID, for attaching data under the caller's own key types. |
| `derive_address<AudioVerifier>(registry, channels, bit_depth, sample_rate_hz, samples_per_channel, pcm_digest)` | none | The Audio's address for those facts. |

`uid` exposes the Audio's UID for reading.

Views: `channels`, `bit_depth`, `sample_rate_hz`, `samples_per_channel`, `pcm_digest`, and `duration_ms`, which rounds down and never aborts, because `new` bounds the duration.

| Fact | Rule | Error |
|---|---|---|
| `channels` | at least 1 | `EZeroChannels` (0) |
| `bit_depth` | 1 to 32 | `EInvalidBitDepth` (1) |
| `sample_rate_hz` | at least 1 | `EZeroSampleRate` (2) |
| `samples_per_channel` | at least 1, and at most `u64::MAX / 1000`, so the duration in milliseconds fits in a `u64` | `EZeroSamplesPerChannel` (3), `EInvalidDuration` (4) |
| `pcm_digest` | exactly 32 bytes | `EInvalidDigestLength` (5) |

`new` checks the shape of the facts only. Reading the file and computing the digest is the verifier's job.

## Trust

- **Pin the verifier types you trust.** Accept `Audio<SomeVerifier>`, never a generic `Audio<AudioVerifier>` treated as trusted: anyone can publish a package with a witness and vouch for anything.
- **Trust attached data by its key type.** A dynamic field on an Audio is a claim by the module that defines its key type. Read fields only under key types, and verifier type parameters, you trust. Listing the Audio's dynamic fields shows each entry's type; entries under other types are claims by whoever published them.
- **Never send assets to an Audio's address.** `uid_mut` is open to everyone, and it is enough to receive objects and withdraw funds held at the Audio's address, so anyone can take them.
- Several verifiers can measure the same audio. Each gets its own Audio, because the verifier type is part of the key.

## Events

- `AudioCreatedEvent<AudioVerifier> { audio_id, channels, bit_depth, sample_rate_hz, samples_per_channel, pcm_digest }` from `new`.

## Audio and the PCM digest

Audio means integer linear PCM: `bit_depth` is the integer sample width. Floating-point PCM and DSD are not Audio; if they are ever supported, they get their own types and keys.

`pcm_digest` is BLAKE3, with the default 32-byte output, over the decoded PCM, interleaved by sample frame. Each sample is a signed integer, little-endian, `ceil(bit_depth / 8)` bytes, two's complement, right-aligned (sign-extended within those bytes). It hashes the samples, not the file, so the same PCM gives the same digest in any format. It doesn't cover the channels, bit depth or sample rate, which is why they are part of the key.

## Install

Pin a commit:

```toml
[dependencies]
audio = { git = "https://github.com/misofm/framework.git", subdir = "audio", rev = "<commit>" }
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
