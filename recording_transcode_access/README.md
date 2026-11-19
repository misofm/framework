# recording_transcode_access

The listener Seal policy for a recording's transcodes. The transcoder enclave
Seal-encrypts each transcode's data key to an identity naming the recording,
the master and the transcode's quilt. The key is released to the recording's owner, and
to the owner of a [`record_access`](../record_access) token for any release
that the recording authorized through
[`release_license`](../release_license). One set of transcodes serves every
authorized release. The release itself is not trusted: anyone can create a
release listing any recording and mint Records of it, so the policy reads the
authorization the recording's admin wrote on their own Recording.

## What it stores

Nothing. The policy reads [`recording_transcode`](../recording_transcode)'s
and `release_license`'s dynamic fields.

The Seal identity, after the package ID that Seal prefixes, is 96 bytes:

| Bytes | Field | Encoding |
|---|---|---|
| 0–31 | `recording_id` | `bcs(address)`: the Recording's object ID, as is |
| 32–63 | `master_blob_id` | `bcs(u256)`: little-endian, the master's raw Walrus blob ID bytes |
| 64–95 | `quilt_blob_id` | `bcs(u256)`: little-endian, the quilt's raw Walrus blob ID bytes |

## API

### Seal policy

Both are `entry` and not `public`, as Seal requires.

| Function | Passes when | Aborts |
|---|---|---|
| `seal_approve_owner<RecordingShare, Transcoder>(id, recording, cap)` | `id` names `recording`, and the recording's `Transcoder` transcode under that master has that quilt; the caller owns the recording's cap | `EWrongRecording` (0), `EInvalidIdentity` (1), `ETranscodeNotFound` (2), `EStaleQuilt` (3); `EOutOfRange` at `sui::bcs`; `EFieldTypeMismatch` at `sui::dynamic_field` for another transcoder |
| `seal_approve_record<RecordingShare, Transcoder>(id, recording, access: &RecordAccess)` | The same identity checks; `access.owner()` is the sender; `release_license::has_release_authorization(recording, access.release_id())` | as `seal_approve_owner`, plus `ENotOwner` (4), `EReleaseNotAuthorized` (5) |

## Events

None: the policy changes no state.

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EWrongRecording` | The identity's first 32 bytes are not `recording`'s ID |
| 1 | `EInvalidIdentity` | Bytes follow the quilt blob ID |
| 2 | `ETranscodeNotFound` | `recording` holds no transcode under the identity's master |
| 3 | `EStaleQuilt` | The master's transcode is another quilt (replaced since) |
| 4 | `ENotOwner` | The sender is not the `RecordAccess` owner |
| 5 | `EReleaseNotAuthorized` | The recording has no authorization for the Record's release |

An identity shorter than 96 bytes aborts with `EOutOfRange` (0) at
`sui::bcs`.

## Dependencies

- [`recording_transcode`](../recording_transcode), by local path:
  `has_transcode` and `transcode`.
- [`release_license`](../release_license), by local path:
  `has_release_authorization`. The policy pins this generation; a new
  `release_license` generation needs a new policy package.
- [`record_access`](../record_access), by local path: `RecordAccess`,
  `owner` and `release_id`.
- [`miso_music`](https://github.com/misofm/music-protocol) at
  `430424a678f2387090850417eacbaa1bb46d1fb7`: `Recording` and
  `RecordingAdminCap`.
- [`audio`](../audio) and [`recording_master`](../recording_master), by local path;
  [`ori`](https://github.com/unconfirmedlabs/ori) (`move` subdirectory) at
  `a3a134ae69a4861030a05ae22f21e67a7b91faf9`; and
  [`bps`](https://github.com/unconfirmedlabs/bps) at
  `4ca1972a67d35c972ca567de7b08315e3778e52b`: used only by the tests, to
  build transcodes and licenses. The package manifest has no
  dev-dependencies section.

## Integrator notes

- **Claim the token before the first decrypt.** A Record holder needs a
  `RecordAccess` naming them as owner: `record_access::new` creates it on the
  first use of a Record, and `record_access::claim` moves it to the Record's
  new owner. Its address is `record_access::derive_address(record_id)`.
- **A fetched key is permanent.** Seal releases the data key, and the client
  can keep it. Selling the Record, revoking the authorization or removing the
  transcode stops new key requests only.
- **Revoked authorizations.** `release_license::revoke` only works before the
  license is fully authorized. After that, the authorization, and so access
  for that release's Record holders, is permanent.
- **Seal PTBs** call only one of the two functions, with `id` as a pure
  input, the shared `Recording<RecordingShare>` and either the owned cap or
  the shared `RecordAccess` as objects, and `RecordingShare` and `Transcoder`
  as the type arguments.
- **The owner must hold the cap directly,** because key servers dry-run the
  PTB with the requester as sender.
- **The preview is not covered.** The transcode's preview is its own plain
  blob that plays for anyone; only the quilt uses the listener key.
- **`Transcoder` is the record's type,** `audio_transcoder::AudioTranscoder`
  for Miso's transcoder. A replaced transcode's identity stops passing
  (`EStaleQuilt`).
- **Trust the transcode by type.** Anyone can encrypt anything to any
  identity. A client should play only `RecordingTranscode<AudioTranscoder>`
  records; each patch authenticates under the listener key with its
  identifier as associated data.
- **Key servers read the full node's latest state,** so a change may take a
  moment to apply across servers.

## Deployments

Testnet `0xaa308283ca1fbc25d7b4f8044ed27f64777bea0ce6a075afa1d62553d2dd9b85`
(tx `7MXA9gmhC4ZLiCWF4kn63ZP6StemSHzrn9mYJ5RkRYAh`). This is the package ID
Seal prefixes to the identity, so the transcoder enclave pins it. The first
generation (a 64-byte identity) stays published on testnet at
`0x426648c4b6adecaf01b9365af988ece29f8d69dde0204fe3021d0e57f0c64afe`. Not on
mainnet yet.

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
