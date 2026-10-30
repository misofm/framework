# miso-audio

[![License: FSL-1.1-ALv2](https://img.shields.io/badge/license-FSL--1.1--ALv2-blue.svg)](LICENSE.md)
[![Move](https://img.shields.io/badge/Move-2024-black.svg)](https://docs.sui.io/concepts/sui-move-concepts)

> One canonical, verified record per lossless audio on [Sui](https://sui.io).

`Audio<AudioVerifier>` is a frozen object holding the facts an `AudioVerifier` type measured about some integer PCM audio: channels, bit depth, sample rate, samples per channel and a PCM digest. Only code holding an `AudioVerifier` witness can create one, so the type parameter names who measured the audio. There is no self-attested audio.

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
- **The facts never change, and nothing attaches to an Audio.** Audio has no owner or admin to vouch for attached data, so it is frozen and exposes no UID. Curated data about a sound belongs to the recording that uses it, or to a separate object keyed by the Audio's ID.
- **Files are not on-chain.** Any number of files decode to the same PCM, so no file is canonical. Check a file against an Audio by decoding it and comparing the BLAKE3 digest of its PCM with `pcm_digest`.
- Audio has only `key`, so it can't be wrapped, transferred or dropped. `new` returns it unfrozen, so the same transaction can point records at it, and `freeze` is the only way to finish with it. Frozen objects are read without consensus.

## API

| Function | Gate | What it does |
|---|---|---|
| `new<AudioVerifier: drop>(registry, witness, channels, bit_depth, sample_rate_hz, samples_per_channel, pcm_digest)` | witness | Checks the facts, claims the Audio from the registry and emits `AudioCreatedEvent`. Aborts with `derived_object::EObjectAlreadyExists` if it is already registered. |
| `freeze_audio<AudioVerifier>(audio)`, alias `audio.freeze()` | none | Freezes a new Audio. |
| `derive_address<AudioVerifier>(registry, channels, bit_depth, sample_rate_hz, samples_per_channel, pcm_digest)` | none | The Audio's address for those facts. |

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
- **Never send assets to an Audio's address.** A frozen Audio exposes no UID, so anything sent there can never be received or withdrawn.
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
