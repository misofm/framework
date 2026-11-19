# recording_transcode

A recording's transcodes for listeners, and the owner's requests for them.
A transcode is an [`audio::Audio`](../audio) stored on a
`miso_music::recording::Recording` under its Walrus quilt's blob ID. A request
is the owner's go-ahead for one enclave type to transcode one master, with the
preview range to cut; [`recording_master_access`](../recording_master_access)
releases the master's key to that enclave only while the request stands, and
[`audio_transcoder`](../audio_transcoder) only verifies a transcode whose
preview is the requested one. Both live here, in a namespace apart from the
masters. One set of transcodes serves every release that contains the
recording.

## What it stores

- `RecordingTranscodeRequestKey<Enclave>(master_blob_id: u256)` →
  `TranscodeRequest { start_sample: u64, end_sample: u64 }`: one per enclave
  type and master, replaced in place. The range is in the master's samples,
  `start_sample < end_sample <= samples_per_channel` of its `AudioVerifier`
  `Pcm`.
- `RecordingTranscodeKey(quilt_blob_id: u256)` → the `Audio<Transcoder,
  Format, Layout>` itself. For Miso's transcoder it is `Audio<AudioTranscoder,
  AacHls, ChannelLayout>`.
- `add_transcode` removes the request it answers. The owner can remove a
  transcode and gets the `Audio` back. Removing reclaims the field.

## API

### Writes (cap-gated)

Each takes the recording's `&RecordingAdminCap<RecordingShare>`, which the
share type binds to the recording, so a wrong cap does not type-check.

| Function | Description | Aborts |
|---|---|---|
| `request_transcode<RecordingShare, Enclave>(recording, cap, master_blob_id, start_sample, end_sample)` | Requests a transcode of the `AudioVerifier` master by `Enclave`, with that preview range; emits `RecordingTranscodeRequestedEvent<Enclave>`. The same range again: no-op | `EMasterNotFound` at `recording_master`; `EFieldTypeMismatch` at `sui::dynamic_field`; `EInvalidRange` (3) |
| `add_transcode<RecordingShare, Enclave, Transcoder, Format, Layout>(recording, cap, master_blob_id, audio)` | Stores `audio` under its quilt's blob ID and removes `Enclave`'s request for the master, if any; emits `RecordingTranscodeRequestRemovedEvent<Enclave>` (when one was removed), then `RecordingTranscodeAddedEvent` | `ETranscodeAlreadyAdded` (1) |
| `remove_transcode<RecordingShare, Transcoder, Format, Layout>(recording, cap, quilt_blob_id): Audio<Transcoder, Format, Layout>` | Removes and returns that transcode; emits `RecordingTranscodeRemovedEvent` | `ETranscodeNotFound` (0); `EFieldTypeMismatch` at `sui::dynamic_field` if it has other types |

### Views

| Function | Returns |
|---|---|
| `has_request<RecordingShare, Enclave>(recording, master_blob_id)` | `bool` |
| `request<RecordingShare, Enclave>(recording, master_blob_id)` | `TranscodeRequest`; aborts `ERequestNotFound` (2) if absent |
| `start_sample(request)`, `end_sample(request)` | `u64` |
| `has_transcode<RecordingShare>(recording, quilt_blob_id)` | `bool`: whether a transcode of any type is stored under that blob ID |
| `transcode<RecordingShare, Transcoder, Format, Layout>(recording, quilt_blob_id)` | `&Audio<Transcoder, Format, Layout>`; aborts `ETranscodeNotFound` (0) if absent, `EFieldTypeMismatch` at `sui::dynamic_field` if it has other types |

## Events

| Event | When | Payload |
|---|---|---|
| `RecordingTranscodeRequestedEvent<Enclave>` | `request_transcode` sets or changes a request | `recording_id: ID`, `master_blob_id: u256`, `start_sample: u64`, `end_sample: u64` |
| `RecordingTranscodeRequestRemovedEvent<Enclave>` | `add_transcode` removes a request | `recording_id: ID`, `master_blob_id: u256` |
| `RecordingTranscodeAddedEvent<Transcoder, Format, Layout>` | `add_transcode` | `recording_id: ID`, `master_blob_id: u256`, `quilt_blob_id: u256` |
| `RecordingTranscodeRemovedEvent<Transcoder, Format, Layout>` | `remove_transcode` | `recording_id: ID`, `quilt_blob_id: u256` |

The type parameters name the enclave a request is for, and a transcode's
verifier, format and layout, so an indexer can follow only the types it trusts.

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `ETranscodeNotFound` | `remove_transcode` or `transcode` with no transcode under that blob ID |
| 1 | `ETranscodeAlreadyAdded` | `add_transcode` when that blob ID is already a transcode, whatever its types |
| 2 | `ERequestNotFound` | `request` with no request of that enclave for that master |
| 3 | `EInvalidRange` | `start_sample >= end_sample`, or `end_sample` is past the master's `samples_per_channel` |

From primitives: a request for a master the recording does not hold as an
`AudioVerifier` master aborts `EMasterNotFound` (0) at `recording_master`, or
`EFieldTypeMismatch` (2) at `sui::dynamic_field` when it is not a
`Pcm`/`ChannelLayout` master.

## Dependencies

- [`miso_music`](https://github.com/misofm/music-protocol) at
  `430424a678f2387090850417eacbaa1bb46d1fb7`: `Recording`,
  `RecordingAdminCap` and `uid_mut`.
- [`audio`](../audio), by local path: `Audio`.
- [`recording_master`](../recording_master), by local path: the master a
  request names, read as `Audio<AudioVerifier, Pcm, ChannelLayout>` from
  [`audio_verifier`](../audio_verifier), [`audio_format_pcm`](../audio_format_pcm)
  and [`audio_channel_layout`](../audio_channel_layout). This pins those
  generations.
- [`ori`](https://github.com/unconfirmedlabs/ori) (`move` subdirectory) at
  `a3a134ae69a4861030a05ae22f21e67a7b91faf9`: reads the blob ID from the
  `WalrusBlob`.
- [`enclave`](../enclave), by local path: used only by the tests, to verify
  masters. The package manifest has no dev-dependencies section.

## Integrator notes

- **Publish flow.** One owner transaction publishes the master, approves the
  transcoder (`recording_master_access::approve_enclave`) and requests the
  transcode with its preview range. Once the job is done, a second calls
  `audio_transcoder::verify_transcode` and `add_transcode`, which closes the
  request.
- **Generic on purpose; trust by type.** `add_transcode` accepts any `Audio`.
  The link to the master and the request is enforced where the `Audio` is
  made: `verify_transcode` only returns one for an attested master with the
  same PCM digest and a request equal to its preview. Trust only
  `Transcoder = audio_transcoder::AudioTranscoder`.
- **`Enclave` is the policy's type**, `audio_transcoder::AUDIO_TRANSCODER`
  for Miso's transcoder, not the `Audio`'s witness: a one-time witness can't
  be packed outside `init`, so the two are different types.
- **The preview range is the owner's choice.** There is no on-chain default
  and no length rule. Studio requests 30 seconds from the start, or half the
  recording if it is shorter. The preview itself is stored unencrypted in the
  quilt (`preview.m4a`).
- **Facts come from the verifier's event.** For `AudioTranscoder`, read the
  format, layout, sealed key and source master from
  `audio_transcoder::TranscodeVerifiedEvent`, joined on `data.blob_id`.
- **Removing a transcode stops new key requests** through
  `recording_transcode_access`. Keys already fetched keep working.
- **Blob lifetime is the owner's concern.** This package neither holds nor
  extends the Walrus `Blob` object.

## Build and test

```sh
sui move build --lint --warnings-are-errors
sui move build --lint --warnings-are-errors --build-env mainnet
sui move test --coverage --lint --warnings-are-errors
sui move coverage summary
```

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
