# audio_verifier

`verify_audio` creates an
[`audio::Audio<AudioVerifier, Pcm, ChannelLayout>`](../audio): an encrypted
lossless master, measured and encrypted inside a Nautilus (AWS Nitro) enclave
and checked on Sui. The enclave in
[`misofm/audio-verifier-enclave`](https://github.com/misofm/audio-verifier-enclave)
does three things. It decodes the FLAC and measures its PCM and channel
layout. It encrypts the file under a fresh data key and Seal-encrypts that key
to the recording's [`recording_master_seal`](../recording_master_seal)
identity. Then it signs the facts, the Walrus blob ID of the ciphertext and the
sealed key. `AudioVerifier` is this package's witness: only a signature from
an enclave key registered on the current `EnclavePolicy<AUDIO_VERIFIER>` can
produce one.

## What it stores

- One shared [`enclave::EnclavePolicy<AUDIO_VERIFIER>`](../enclave), created
  by `init` with its PCRs unset. Its `EnclavePolicyAdminCap<AUDIO_VERIFIER>`
  goes to the publisher.
- `verify_audio` stores nothing. It returns the `Audio` for the caller to
  store, typically with `recording_master::add_master` in the same PTB.

## API

### Public

| Function | Description | Aborts |
|---|---|---|
| `verify_audio(policy, channels, bit_depth, sample_rate_hz, samples_per_channel, pcm_digest, channel_layout, blob_id, sealed_dek, pk, timestamp_ms, signature): Audio<AudioVerifier, Pcm, ChannelLayout>` | Checks the enclave's intent-0 signature over the facts. Builds the `Pcm`, the `ChannelLayout` and `WalrusBlob { blob_id, Encrypted { sealed_dek } }`, emits `AudioVerifiedEvent` and returns the `Audio` | `EEnclaveNotRegistered`, `EStaleEnclave`, `EInvalidSignature` at `enclave::enclave`; any `audio_format_pcm` error; `ELayoutMismatch` (0); any `audio_channel_layout` error; `EEmptySealedDek` at `ori::confidentiality` |

The policy's own functions (`register`, `set_pcrs`, `remove_stale`) are in
[`enclave`](../enclave).

## The signed payload

The enclave signs `bcs(IntentMessage { intent: 0, timestamp_ms: u64, payload: AudioPayload })`
with Ed25519:

```move
public struct AudioPayload has copy, drop {
    channels: u8,
    bit_depth: u8,
    sample_rate_hz: u32,
    samples_per_channel: u64,
    pcm_digest: vector<u8>,
    channel_layout: vector<u8>,
    blob_id: u256,
    sealed_dek: vector<u8>,
}
```

| Field | BCS |
|---|---|
| `intent` | 1 byte, `0x00` |
| `timestamp_ms` | 8 bytes, little-endian |
| `channels`, `bit_depth` | 1 byte each |
| `sample_rate_hz` | 4 bytes, little-endian |
| `samples_per_channel` | 8 bytes, little-endian |
| `pcm_digest` | ULEB128 length (`0x20`), then 32 bytes |
| `channel_layout` | ULEB128 length, then one code per channel |
| `blob_id` | 32 bytes, little-endian `u256`: the raw Walrus blob ID bytes |
| `sealed_dek` | ULEB128 length, then the Seal `EncryptedObject` bytes |

- **Intent 2 is reserved for the enclave's file binding.** With each
  measurement the enclave also signs, under intent 2 with the same timestamp,
  the size and SHA-256 of the plaintext file it received. The service that
  sent the file uses it to check that exactly that file was measured. It is
  checked off chain only and never passed to `verify_audio`. Intent 1, the
  retired Walrus encoding claim, stays unused.
- **Test vector.** `tests/audio_verifier_tests.move` pins the payload, the
  intent message and a signature from the fixed seed `[7; 32]` (public key
  `ea4a6c63…d22c`). The enclave's encoder is tested against the same bytes.

## Events

| Event | When | Payload |
|---|---|---|
| `AudioVerifiedEvent` | `verify_audio` succeeds | `pk: vector<u8>`, `policy_version: u64`, `verified_at_ms: u64`, `format: Pcm`, `layout: ChannelLayout`, `data: WalrusBlob` |

`enclave` emits the policy and registration events.

## Errors

| Code | Constant | Location | Condition |
|---|---|---|---|
| 0 | `ELayoutMismatch` | `audio_verifier` | `channel_layout` has a length other than `channels` |
| 10 | `EEnclaveNotRegistered` | `enclave::enclave` | `pk` is not registered on the policy |
| 11 | `EStaleEnclave` | `enclave::enclave` | `pk` was registered under older PCRs |
| 13 | `EInvalidSignature` | `enclave::enclave` | The signature does not cover these facts, this timestamp and intent 0 under `pk` |
| 0–5 | `EZeroChannels` … `EInvalidDigestLength` | `audio_format_pcm` | Malformed PCM facts |
| 1, 2 | `EInvalidSpeaker`, `EDuplicateSpeaker` | `audio_channel_layout` | Malformed layout |
| clever error | `EEmptySealedDek` | `ori::confidentiality` | `sealed_dek` is empty |

The signature is checked first, so a fact error means the enclave signed
malformed facts.

## Dependencies

- [`audio`](../audio), by local path: `Audio` and `new`.
- [`audio_format_pcm`](../audio_format_pcm), by local path: `Pcm`.
- [`audio_channel_layout`](../audio_channel_layout), by local path:
  `ChannelLayout`.
- [`enclave`](../enclave), by local path: the policy and signature checks.
- [`ori`](https://github.com/unconfirmedlabs/ori) (`move` subdirectory) at
  `a3a134ae69a4861030a05ae22f21e67a7b91faf9`: `WalrusBlob` and
  `Confidentiality`.

## Integrator notes

- **Two witness types.** `AUDIO_VERIFIER` is the one-time witness that owns
  the enclave policy. `AudioVerifier` is the witness passed to `audio::new`. It
  is separate because Sui does not allow packing a one-time witness outside
  `init`.
- **The policy type is fixed.** `verify_audio` takes
  `EnclavePolicy<AUDIO_VERIFIER>` only, so a key registered for another app
  can't sign. A key registered under older PCRs stops verifying as soon as
  the PCRs change.
- **One upload, one PTB.** Call `verify_audio` with the enclave's response,
  then `recording_master::add_master` with the returned `Audio`. The host must
  upload the ciphertext to Walrus and check that the stored blob ID equals the
  signed `blob_id` first.
- **Replays are harmless.** The same signature verifies again and yields an
  identical `Audio`. Nothing binds a verification to a recording. Access is
  bound instead by the Seal identity, which names the recording the enclave
  was told: someone else's copy of the `Audio` can't decrypt anything.
- **No freshness check.** `timestamp_ms` is the enclave's clock, provided by
  the host, and is only reported in the event.
- **Audio from a retired image stays valid.** It was measured by an image that
  was trusted at the time. A consumer that wants to reject it can track it by
  `pk` and `policy_version` from `AudioVerifiedEvent`.
- **Indexers** read every fact of an `Audio` from `AudioVerifiedEvent`. Join
  it with `recording_master` events on `data.blob_id`.

## Operating the policy

1. Publish. `init` sends the `EnclavePolicyAdminCap<AUDIO_VERIFIER>` to the
   publisher. With the ephemeral-signer `publish` tool, pass
   `--created-objects-recipient <address>`, or the cap is lost. The cap is
   `key + store` and is needed only to change PCRs.
2. Build the enclave image, record its PCRs, and call
   `enclave::enclave::set_pcrs`.
3. Boot the enclave and fetch its attestation document. Anyone can register
   it, with no cap: in one PTB, call
   `sui::nitro_attestation::load_nitro_attestation`, then
   `enclave::enclave::register`.
4. To rotate the image, call `set_pcrs` and then `register` the new enclave, in
   one PTB. Every old key stops verifying at once. Anyone can delete old keys
   with `remove_stale`.

## Build and test

```sh
sui move build --lint --warnings-are-errors
sui move build --lint --warnings-are-errors --build-env mainnet
sui move test --coverage --lint --warnings-are-errors
sui move coverage summary
```

This package has not been audited.

## Generations

This is the second generation. On testnet it is
`0x79cb3c048707800ea6219cf5f86ef22993837ccb912bba81035abc337e5454c0` (tx
`CGgQNfBZGVUMa4FLyMPPZ3BStmg4mCf4ybTCwkJFbuca`). Its shared
`EnclavePolicy<AUDIO_VERIFIER>` is
`0xeb9fdb274f4edbda86b322cbb876a4f92aa6b9e58964d6d5953ff0cead49160e`, still at
version 0 with its PCRs unset. Its `EnclavePolicyAdminCap` is
`0x499eb52d45d14e70a312202c5e651fc11658ed65a78056f3d047f2d5693619ba`, forwarded
to `0x2ee0659d5ae261319c4e9b8103cebab8506f3ee5f9fc51c919d04ff786c322b8`.
Mainnet is not republished yet.

The first generation created frozen, registry-derived
`Audio<AudioVerifier>` objects from five facts and stays published on mainnet
at `0xc547a01e2fcd7b126e94d6fa67172ea074e452a0534e31d52dbd0e7907bde35f`.
`Published.toml` records the current generation per network.

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
