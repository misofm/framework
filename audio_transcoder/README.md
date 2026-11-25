# audio_transcoder

The transcoder Miso trusts: its enclave policy, the owner's request for a
transcode, and `verify_transcode`, which turns the enclave's signed result
into a [`recording_transcode::RecordingTranscode<AudioTranscoder>`](../recording_transcode).
The enclave in
[`misofm/audio-transcoder-enclave`](https://github.com/misofm/audio-transcoder-enclave)
fetches the master's key through
[`recording_master_access`](../recording_master_access) under the owner's
grant, decodes the FLAC and checks its PCM digest, encodes AAC-LC HLS at 96,
160 and 256 kbps with a pinned FFmpeg, encrypts each file under a fresh
listener key as one Walrus quilt, Seal-encrypts that key to
[`recording_transcode_access`](../recording_transcode_access), cuts a plain
preview from the granted range as its own blob, and signs the result.

## What it stores

- One shared [`enclave::EnclavePolicy<AUDIO_TRANSCODER>`](../enclave), created
  by `init` with its PCRs unset. Its `EnclavePolicyAdminCap<AUDIO_TRANSCODER>`
  goes to the publisher.
- `request_transcode` writes a `recording_master_access` grant of
  `AUDIO_TRANSCODER` on the recording; `verify_transcode` consumes it. Nothing
  else is stored here.

## API

### Writes (cap-gated)

| Function | Description | Aborts |
|---|---|---|
| `request_transcode<RecordingShare>(recording, cap, policy, master_blob_id, start_sample, end_sample)` | Grants the transcoder the `AudioVerifier` master, with the preview range as `terms = bcs(start_sample) ++ bcs(end_sample)`, at the policy's current version | `EInvalidRange` (0) unless `start_sample < end_sample <= samples_per_channel`; `EMasterNotFound` at `recording_master`; `EFieldTypeMismatch` at `sui::dynamic_field` |
| `verify_transcode<RecordingShare>(policy, recording, cap, recording_id, master_blob_id, source_pcm_digest, quilt_blob_id, sealed_dek, preview_start_sample, preview_end_sample, preview_blob_id, pk, timestamp_ms, signature): RecordingTranscode<AudioTranscoder>` | Checks the enclave's intent-0 signature, that `recording_id` is `recording`, that its `AudioVerifier` master's `Pcm.digest` is `source_pcm_digest`, and that the grant's terms are the signed range; consumes the grant, emits `TranscodeVerifiedEvent` and returns the record | `EEnclaveNotRegistered`, `EStaleEnclave`, `EInvalidSignature` at `enclave::enclave`; `EWrongRecording` (1); `EMasterNotFound` at `recording_master`; `EFieldTypeMismatch` at `sui::dynamic_field`; `ESourceMismatch` (2); `EGrantNotFound` at `recording_master_access`; `ERangeMismatch` (3); `EEmptySealedDek` at `ori::confidentiality` |

Revoke a pending request with `recording_master_access::revoke<_,
AUDIO_TRANSCODER>`. The policy's own functions (`register`, `set_pcrs`,
`remove_stale`) are in [`enclave`](../enclave).

### Views

| Function | Returns |
|---|---|
| `transcode_terms(start_sample, end_sample)` | `vector<u8>`: the grant terms of a range, two little-endian `u64`s |

## The signed payload

The enclave signs `bcs(IntentMessage { intent: 0, timestamp_ms: u64, payload: TranscodePayload })`
with Ed25519:

```move
public struct TranscodePayload has copy, drop {
    recording_id: address,
    master_blob_id: u256,
    source_pcm_digest: vector<u8>,
    quilt_blob_id: u256,
    sealed_dek: vector<u8>,
    preview_start_sample: u64,
    preview_end_sample: u64,
    preview_blob_id: u256,
}
```

| Field | BCS |
|---|---|
| `intent` | 1 byte, `0x00` |
| `timestamp_ms` | 8 bytes, little-endian |
| `recording_id` | 32 bytes, the object ID as is |
| `master_blob_id`, `quilt_blob_id`, `preview_blob_id` | 32 bytes each, little-endian `u256`: the raw Walrus blob ID bytes |
| `source_pcm_digest` | ULEB128 length (`0x20`), then 32 bytes |
| `sealed_dek` | ULEB128 length, then the Seal `EncryptedObject` bytes |
| `preview_start_sample`, `preview_end_sample` | 8 bytes each, little-endian, in the master's samples |

- The enclave takes `recording_id` and `master_blob_id` from the identity of
  the master's sealed key, which the key servers enforce, and the range from
  its own key request.
- **Test vector.** `tests/audio_transcoder_tests.move` pins the payload, the
  intent message and a signature from the fixed seed `[7; 32]` (public key
  `ea4a6c63…d22c`).

## Events

| Event | When | Payload |
|---|---|---|
| `TranscodeVerifiedEvent` | `verify_transcode` succeeds | `pk: vector<u8>`, `policy_version: u64`, `verified_at_ms: u64`, `recording_id: ID`, `master_blob_id: u256`, `data: WalrusBlob`, `preview: RecordingPreview` |

`recording_master_access` emits the grant events; `enclave` the policy and
registration events.

## Errors

| Code | Constant | Location | Condition |
|---|---|---|---|
| 0 | `EInvalidRange` | `audio_transcoder` | A requested range that is empty or past the master |
| 1 | `EWrongRecording` | `audio_transcoder` | The signed `recording_id` is another recording |
| 2 | `ESourceMismatch` | `audio_transcoder` | The master's `Pcm.digest` is not `source_pcm_digest` |
| 3 | `ERangeMismatch` | `audio_transcoder` | The grant's terms are not the signed range |
| 0 | `EMasterNotFound` | `recording_master` | No master under `master_blob_id` |
| 2 | `EFieldTypeMismatch` | `sui::dynamic_field` | That master is not `Audio<AudioVerifier, Pcm, ChannelLayout>` |
| 4 | `EGrantNotFound` | `recording_master_access` | No pending request for that master |
| 10 | `EEnclaveNotRegistered` | `enclave::enclave` | `pk` is not registered on the policy |
| 11 | `EStaleEnclave` | `enclave::enclave` | `pk` was registered under older PCRs |
| 13 | `EInvalidSignature` | `enclave::enclave` | The signature does not cover these facts, this timestamp and intent 0 under `pk` |
| clever error | `EEmptySealedDek` | `ori::confidentiality` | `sealed_dek` is empty |

## Dependencies

- [`recording_master_access`](../recording_master_access), by local path:
  `grant` and `consume`.
- [`recording_transcode`](../recording_transcode), by local path: the
  `RecordingTranscode` record it builds.
- [`recording_master`](../recording_master), [`audio_verifier`](../audio_verifier),
  [`audio_format_pcm`](../audio_format_pcm) and
  [`audio_channel_layout`](../audio_channel_layout), by local path: the
  attested master and its `Pcm`. This pins those generations.
- [`enclave`](../enclave), by local path: the policy and signature checks.
- [`miso_music`](https://github.com/misofm/music-protocol) at
  `430424a678f2387090850417eacbaa1bb46d1fb7`: `Recording` and
  `RecordingAdminCap`.
- [`ori`](https://github.com/unconfirmedlabs/ori) (`move` subdirectory) at
  `a3a134ae69a4861030a05ae22f21e67a7b91faf9`: `WalrusBlob` and
  `Confidentiality`.
- [`audio`](../audio), by local path: used only by the tests.

## Integrator notes

- **Publish flow, two owner transactions.**
  1. Publish the recording with `add_master` and `request_transcode` (Studio
     requests 30 seconds from the start, or half the recording if shorter).
  2. When the job is done: `verify_transcode`, then
     `recording_transcode::add_transcode` with the returned record, in one
     PTB.
- **A grant trusts exactly the image trusted at grant time.** If the policy's
  admin trusts another image, a pending request stops working and the owner
  requests again.
- **One request, one job.** `verify_transcode` consumes the grant, so a
  signed result verifies once. A revoke stops new key requests; a key the
  enclave already fetched can still run that job for up to 10 minutes.
- **The preview is public, and so is its range.** The preview is a plain
  Walrus blob; every requested range stays in the grant events for good. The
  same range on the same image gives the same preview blob ID.
- **Length limit.** A Walrus quilt holds at most 666 patches. With three
  renditions, each with an init segment and a playlist, plus the master
  playlist, that is at most 219 segments per rendition; the enclave picks a
  segment length of 6 to 10 seconds and refuses masters longer than about 36
  minutes.
- **Determinism.** The same master gives byte-identical plaintext files. The
  quilt and its blob ID differ on every run, because the data key is random.
- **No freshness check.** `timestamp_ms` is the enclave's clock, provided by
  the host, and is only reported in the event.
- **Indexers** read every fact of a transcode from `TranscodeVerifiedEvent`
  and `recording_transcode`'s set event.

## Operating the policy

1. Publish. `init` sends the `EnclavePolicyAdminCap<AUDIO_TRANSCODER>` to the
   publisher. With the ephemeral-signer `publish` tool, pass
   `--created-objects-recipient <address>`, or the cap is lost.
2. Build the enclave image, record its PCRs, and call
   `enclave::enclave::set_pcrs`.
3. Boot the enclave and register its attestation: in one PTB,
   `sui::nitro_attestation::load_nitro_attestation`, then
   `enclave::enclave::register`. Anyone can register.
4. Rotating the image (`set_pcrs`) retires every old key and every pending
   grant made under the old version.

## Build and test

```sh
sui move build --lint --warnings-are-errors
sui move build --lint --warnings-are-errors --build-env mainnet
sui move test --coverage --lint --warnings-are-errors
sui move coverage summary
```

This package has not been audited.

## Deployments

Testnet `0x2b6d8a371ad2e7c46ebaa356562640f776fb9e64a69a5798faed993028addded`
(tx `7MXA9gmhC4ZLiCWF4kn63ZP6StemSHzrn9mYJ5RkRYAh`). Its shared
`EnclavePolicy<AUDIO_TRANSCODER>` is
`0x5c2944050c4ecc3525c5d44f8e028d4a401a11b1fe92a3f9fb03d1af674eca2b`, created
at version 0 with its PCRs unset. Its `EnclavePolicyAdminCap` is
`0x0fe8d93507bfa503c8bafc09c4da00ba94775a917f090069e78deb99030a655b`,
forwarded to `0x2ee0659d5ae261319c4e9b8103cebab8506f3ee5f9fc51c919d04ff786c322b8`.
The first generation stays published on testnet at
`0xe3311902951e77db5a8260c7e5060f5f183af164f4af2bfa65c39fc6a37e0535`. Mainnet `0x4c62677c4946cc0c2c6d33faad4bc4c293011728947343aa7f34b5b0065be51f`
(tx `EpKYiosubKzhZAiUZnYHasQ2vV3sPmko8bsgWyaH8qAP`). Its shared policy is
`0xcc0e5daec62efa6243a9cb50676b6f04310355c1d29bdabaf0115e724eb0e70e`, at
version 0 with its PCRs unset. Its cap is
`0x8065ec73ce62133e61d40a1af87d107ea1cd2546262c822aafa1ea5ba65457c6`,
forwarded to `0x2ee0659d5ae261319c4e9b8103cebab8506f3ee5f9fc51c919d04ff786c322b8`.

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
