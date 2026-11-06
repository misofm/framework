# audio_verifier (Move package)

`verify_audio` creates an [`audio::Audio<AudioVerifier>`](https://github.com/misofm/framework/tree/main/audio), the canonical record of lossless audio measured inside a Nautilus (AWS Nitro) enclave and checked on Sui. `AudioVerifier` is this package's witness, and only a signature from an enclave key registered on the current `EnclavePolicy<AUDIO_VERIFIER>` can produce one. Consumers that trust this enclave pin `Audio<audio_verifier::audio_verifier::AudioVerifier>`.

There is no docs.miso.fm page yet, so the facts are below.

```toml
audio_verifier = { git = "https://github.com/misofm/framework.git", subdir = "audio_verifier", rev = "<commit>" }
```

## API

| Function | Who may call | What it does |
|---|---|---|
| `init` | publish | Creates the one [`enclave::EnclavePolicy<AUDIO_VERIFIER>`](../enclave), with its PCRs unset, shares it and sends its `EnclavePolicyAdminCap` to Miso's admin address, `0x2ee0659d5ae261319c4e9b8103cebab8506f3ee5f9fc51c919d04ff786c322b8`. |
| `verify_audio(registry, policy, pk, channels, bit_depth, sample_rate_hz, samples_per_channel, pcm_digest, timestamp_ms, signature)` | anyone | Checks the audio signature from enclave key `pk`, creates the `Audio<AudioVerifier>` from the registry and returns it unfrozen: point records at it, then call `audio.freeze()`. Aborts `enclave::enclave::EEnclaveNotRegistered` for an unknown key, `EStaleEnclave` for a key from a retired image, `EInvalidSignature`, `derived_object::EObjectAlreadyExists` if the audio is already registered, or another `audio::audio` error if the facts are malformed. |

- **Two types, one package.** `AUDIO_VERIFIER` is the one-time witness that owns the enclave policy. `AudioVerifier` is the witness passed to `audio::new`; it is separate because Sui does not allow packing a one-time witness outside `init`.
- **One signed payload**, `bcs(IntentMessage { intent: 0, timestamp_ms, payload })` with `AudioPayload { channels: u8, bit_depth: u8, sample_rate_hz: u32, samples_per_channel: u64, pcm_digest: vector<u8> }`. A signature under any other intent does not verify.
- **One measurement, one Audio.** The enclave's `/process_data` returns the signed facts. For new audio, in one PTB: `verify_audio`, any records such as `recording_master::add_master`, then `audio.freeze()`. Before uploading, derive the Audio's address with `audio::derive_address` and read it; if it exists, the audio is already registered. If two uploads race, the loser aborts with `EObjectAlreadyExists`.
- **Files are not on-chain.** The enclave decodes the uploaded file to measure it but signs nothing about the file. Anyone can check a file against an Audio by decoding it and comparing the BLAKE3 digest of its PCM with `pcm_digest`.
- **The policy type is fixed.** `verify_audio` takes `EnclavePolicy<AUDIO_VERIFIER>` only, so a key registered for another app can't sign. A key registered under an older PCR version stops verifying the moment the PCRs change.
- **No freshness check.** The facts describe the audio and don't go stale. Replaying a signature can only recreate audio that already exists, which aborts. `timestamp_ms` is the enclave's own clock time, provided by the host, so it's kept in the events only.
- **What it proves:** what the audio is, not who made it or who holds rights to it. Anyone can point their own object at the `Audio<AudioVerifier>`. Authorship and duplicate detection belong in curation.
- **Audio from a retired image stays valid.** It was measured by an image that was trusted at the time. A consumer that wants to reject it has to track it by `pk` and `policy_version` from the events.

## Operating the policy

1. Publish. `init` sends the `EnclavePolicyAdminCap<AUDIO_VERIFIER>` to Miso's admin address, not the publisher, so an ephemeral publisher loses nothing. The cap is `key + store`, so its holder can later move it to long-term custody, such as a multisig, with `transfer::public_transfer`. It is needed only to change PCRs.
2. Build the enclave image from [`misofm/audio-verifier-enclave`](https://github.com/misofm/audio-verifier-enclave), record its PCRs, and call `enclave::enclave::set_pcrs`.
3. Boot the enclave and fetch its attestation document. Anyone can register it: in one PTB, call `sui::nitro_attestation::load_nitro_attestation`, then `enclave::enclave::register`. No cap is needed.
4. To rotate the image: in one PTB, call `set_pcrs`, then `register` the new enclave. Every old key stops verifying at once. Anyone can delete old keys with `remove_stale` to reclaim storage.

## Events

- `AudioVerifiedEvent { pk, policy_version, verified_at_ms, audio_id }` and `audio::audio::AudioCreatedEvent<AudioVerifier>` from `verify_audio`.
- `enclave` emits the policy and registration events.

## Layout and testing

```
sources/audio_verifier.move        the module
tests/audio_verifier_tests.move    unit tests, including the cross-language signing vector
```

The tests check that `bcs(AudioPayload)` and its intent message match `vectors/audio_intent.json` in [`misofm/audio-verifier-enclave`](https://github.com/misofm/audio-verifier-enclave), which the Rust crate generates. They verify the vector's signature, from the fixed seed `[7; 32]`, through `enclave`, reject the same payload signed under another intent, a key from a retired image and an unregistered key, and freeze the Audio.

```sh
sui move build
sui move test --coverage
```

This package has not been audited.

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
