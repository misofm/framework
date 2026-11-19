# audio_transcoder

`verify_transcode` creates an
[`audio::Audio<AudioTranscoder, AacHls, ChannelLayout>`](../audio): an
encrypted AAC-LC HLS ladder, transcoded from a recording's attested master
inside a Nautilus (AWS Nitro) enclave and checked on Sui. The enclave in
[`misofm/audio-transcoder-enclave`](https://github.com/misofm/audio-transcoder-enclave)
fetches the master's key through
[`recording_master_access`](../recording_master_access), decodes the FLAC and
recomputes its PCM digest, and encodes the ladder with a pinned FFmpeg. It
encrypts each HLS file under a fresh data key, stores them as one Walrus
quilt, and Seal-encrypts that key to the
[`recording_transcode_access`](../recording_transcode_access) identity.
It also cuts an unencrypted preview, `preview.m4a`, from the range the owner
requested. `verify_transcode` requires the recording to hold an
[`audio_verifier`](../audio_verifier) master with the same PCM digest, and the
owner's transcode request
([`recording_transcode`](../recording_transcode)) to name exactly the preview
range, so an `AudioTranscoder` transcode always descends from an attested
master of that recording, cut where its owner asked.

## What it stores

- One shared [`enclave::EnclavePolicy<AUDIO_TRANSCODER>`](../enclave), created
  by `init` with its PCRs unset. Its `EnclavePolicyAdminCap<AUDIO_TRANSCODER>`
  goes to the publisher.
- `verify_transcode` stores nothing. It returns the `Audio` for the caller to
  store, typically with `recording_transcode::add_transcode` in the same PTB.

## API

### Public

| Function | Description | Aborts |
|---|---|---|
| `verify_transcode<RecordingShare>(policy, recording, master_blob_id, bitrates_kbps, sample_rate_hz, source_pcm_digest, manifest, channel_layout, preview_start_sample, preview_end_sample, quilt_blob_id, sealed_dek, pk, timestamp_ms, signature): Audio<AudioTranscoder, AacHls, ChannelLayout>` | Checks the enclave's intent-0 signature over the facts. Requires `recording`'s `AudioVerifier` master under `master_blob_id` to have `Pcm.digest == source_pcm_digest`, and its `AUDIO_TRANSCODER` transcode request to be `[preview_start_sample, preview_end_sample)`. Builds the `AacHls`, the `ChannelLayout` and `WalrusBlob { quilt_blob_id, Encrypted { sealed_dek } }`, emits `TranscodeVerifiedEvent` and returns the `Audio` | `EEnclaveNotRegistered`, `EStaleEnclave`, `EInvalidSignature` at `enclave::enclave`; `EMasterNotFound` at `recording_master`; `EFieldTypeMismatch` at `sui::dynamic_field`; `ESourceMismatch` (0); `ERequestNotFound` at `recording_transcode`; `EPreviewMismatch` (1); any `audio_format_aac_hls` or `audio_channel_layout` error; `EEmptySealedDek` at `ori::confidentiality` |

The policy's own functions (`register`, `set_pcrs`, `remove_stale`) are in
[`enclave`](../enclave).

## The signed payload

The enclave signs `bcs(IntentMessage { intent: 0, timestamp_ms: u64, payload: TranscodePayload })`
with Ed25519:

```move
public struct TranscodePayload has copy, drop {
    bitrates_kbps: vector<u16>,
    sample_rate_hz: u32,
    source_pcm_digest: vector<u8>,
    manifest: vector<u8>,
    channel_layout: vector<u8>,
    preview_start_sample: u64,
    preview_end_sample: u64,
    quilt_blob_id: u256,
    sealed_dek: vector<u8>,
}
```

| Field | BCS |
|---|---|
| `intent` | 1 byte, `0x00` |
| `timestamp_ms` | 8 bytes, little-endian |
| `bitrates_kbps` | ULEB128 count, then 2 bytes little-endian each |
| `sample_rate_hz` | 4 bytes, little-endian |
| `source_pcm_digest` | ULEB128 length (`0x20`), then 32 bytes |
| `manifest` | ULEB128 length (`0x20`), then 32 bytes |
| `channel_layout` | ULEB128 length, then one WAVE channel-mask code per channel |
| `preview_start_sample`, `preview_end_sample` | 8 bytes each, little-endian: the preview's master range (the same bytes as a nested `Preview { start_sample, end_sample }`) |
| `quilt_blob_id` | 32 bytes, little-endian `u256`: the raw Walrus blob ID bytes |
| `sealed_dek` | ULEB128 length, then the Seal `EncryptedObject` bytes |

- **No recording ID and no master blob ID are signed.** The enclave reads the
  recording from the identity of the master's sealed key, which the key
  servers enforce, and uses it for the listener identity. The on-chain link
  to the master is the PCM digest, checked against `recording`.
- **Test vector.** `tests/audio_transcoder_tests.move` pins the payload, the
  intent message and a signature from the fixed seed `[7; 32]` (public key
  `ea4a6c63…d22c`).

## Events

| Event | When | Payload |
|---|---|---|
| `TranscodeVerifiedEvent` | `verify_transcode` succeeds | `pk: vector<u8>`, `policy_version: u64`, `verified_at_ms: u64`, `recording_id: ID`, `master_blob_id: u256`, `format: AacHls`, `layout: ChannelLayout`, `data: WalrusBlob` |

`enclave` emits the policy and registration events.

## Errors

| Code | Constant | Location | Condition |
|---|---|---|---|
| 0 | `ESourceMismatch` | `audio_transcoder` | The master's `Pcm.digest` is not `source_pcm_digest` |
| 1 | `EPreviewMismatch` | `audio_transcoder` | The owner's request names another range than the signed preview |
| 2 | `ERequestNotFound` | `recording_transcode` | The recording has no `AUDIO_TRANSCODER` request for that master |
| 0 | `EMasterNotFound` | `recording_master` | `recording` has no master under `master_blob_id` |
| 2 | `EFieldTypeMismatch` | `sui::dynamic_field` | That master is not `Audio<AudioVerifier, Pcm, ChannelLayout>` |
| 10 | `EEnclaveNotRegistered` | `enclave::enclave` | `pk` is not registered on the policy |
| 11 | `EStaleEnclave` | `enclave::enclave` | `pk` was registered under older PCRs |
| 13 | `EInvalidSignature` | `enclave::enclave` | The signature does not cover these facts, this timestamp and intent 0 under `pk` |
| 0–5 | `ENoBitrates` … `EInvalidPreview` | `audio_format_aac_hls` | Malformed format facts |
| 0–2 | `EInvalidLength`, `EInvalidSpeaker`, `EDuplicateSpeaker` | `audio_channel_layout` | Malformed layout |
| clever error | `EEmptySealedDek` | `ori::confidentiality` | `sealed_dek` is empty |

The signature is checked first, then the master and the request, then the
facts.

## Dependencies

- [`audio`](../audio), by local path: `Audio` and `new`.
- [`audio_format_aac_hls`](../audio_format_aac_hls), by local path: `AacHls`.
- [`audio_channel_layout`](../audio_channel_layout), by local path:
  `ChannelLayout`.
- [`recording_master`](../recording_master), by local path: `master`.
- [`recording_transcode`](../recording_transcode), by local path: the owner's
  transcode `request`.
- [`audio_verifier`](../audio_verifier) and
  [`audio_format_pcm`](../audio_format_pcm), by local path: the master's
  types, `AudioVerifier` and `Pcm`. This pins those generations.
- [`enclave`](../enclave), by local path: the policy and signature checks.
- [`miso_music`](https://github.com/misofm/music-protocol) at
  `430424a678f2387090850417eacbaa1bb46d1fb7`: `Recording`.
- [`ori`](https://github.com/unconfirmedlabs/ori) (`move` subdirectory) at
  `a3a134ae69a4861030a05ae22f21e67a7b91faf9`: `WalrusBlob` and
  `Confidentiality`.

## Integrator notes

- **Approving this policy trusts its admin indefinitely.** A recording owner
  lets the transcoder read a master by approving
  `EnclavePolicy<AUDIO_TRANSCODER>` with
  `recording_master_access::approve_enclave`. Whoever holds this policy's
  `EnclavePolicyAdminCap` can call `set_pcrs` at any time to trust a
  different image, which can then register and decrypt every master that
  approved the policy. There is no delay and no per-recording consent to the
  new image. Revoking the approval stops new key requests only.
- **Two witness types.** `AUDIO_TRANSCODER` is the one-time witness that owns
  the enclave policy. `AudioTranscoder` is the witness passed to
  `audio::new`.
- **Request, then one upload, one PTB.** The owner first requests the
  transcode with its preview range
  (`recording_transcode::request_transcode<_, AUDIO_TRANSCODER>`), usually in
  the publish transaction. The job's host stores the quilt on Walrus and
  checks its blob ID. Then the owner calls `verify_transcode` and
  `recording_transcode::add_transcode<_, AUDIO_TRANSCODER, …>` with the
  returned `Audio`, in one PTB, which also closes the request.
- **Replays are harmless.** The same signature verifies again for any
  recording holding an attested master of the same PCM, and yields an
  identical `Audio`. Its sealed key names the original recording, so a copy
  attached elsewhere can't be decrypted through that other recording.
- **No freshness check.** `timestamp_ms` is the enclave's clock, provided by
  the host, and is only reported in the event.
- **Length limit.** A Walrus quilt holds at most 666 patches. With three
  renditions, each with an init segment and a playlist, plus a master
  playlist, the inventory and the preview, that is at most 218 segments per
  rendition. The enclave picks a segment length of 6 to 10 seconds and
  refuses masters longer than 2,179,976 ms (about 36.3 minutes).
- **The preview is public.** `preview.m4a` is the requested range, AAC-LC
  160 kbps stereo, a plain MP4 with faststart, stored unencrypted in the
  quilt and listed in its inventory. Anyone can play it from an aggregator by
  quilt ID; only the HLS tiers are sealed.
- **Determinism.** The same master gives byte-identical plaintext files. The
  quilt and its blob ID differ on every run, because the data key is random.
- **Indexers** read every fact of a transcode from `TranscodeVerifiedEvent`.
  Join it with `recording_transcode` events on `data.blob_id`.

## Operating the policy

1. Publish. `init` sends the `EnclavePolicyAdminCap<AUDIO_TRANSCODER>` to the
   publisher. With the ephemeral-signer `publish` tool, pass
   `--created-objects-recipient <address>`, or the cap is lost.
2. Build the enclave image, record its PCRs, and call
   `enclave::enclave::set_pcrs`.
3. Boot the enclave and fetch its attestation document. Anyone can register
   it, with no cap: in one PTB, call
   `sui::nitro_attestation::load_nitro_attestation`, then
   `enclave::enclave::register`.
4. To rotate the image, call `set_pcrs` and then `register` the new enclave.
   Every old key stops verifying, and stops passing
   `recording_master_access::seal_approve_enclave`, at once.

## Deployments

Testnet `0xe3311902951e77db5a8260c7e5060f5f183af164f4af2bfa65c39fc6a37e0535`
(tx `BvNfDnF9tzsgjdih2AWxL1LfWqnQGgLrmzoV9woT9FT2`). Its shared
`EnclavePolicy<AUDIO_TRANSCODER>` is
`0x549033b7dfc4713c45b01a9db069c4df8e28f2795b038250ec5b2b500b38fe2a`, created
at version 0 with its PCRs unset. Its `EnclavePolicyAdminCap` is
`0xaf014cada1b31789477b41cf0fd787a2d2c5d17b0d5a72366d05ad91805251d1`, forwarded
to `0x2ee0659d5ae261319c4e9b8103cebab8506f3ee5f9fc51c919d04ff786c322b8`. It is
not on mainnet yet.

## Build and test

```sh
sui move build --lint --warnings-are-errors
sui move build --lint --warnings-are-errors --build-env mainnet
sui move test --coverage --lint --warnings-are-errors
sui move coverage summary
```

This package has not been audited.

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
