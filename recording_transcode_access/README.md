# recording_transcode_access

The listener Seal policy for a recording's transcodes. The transcoder enclave
Seal-encrypts each transcode's data key to an identity naming the recording
and the transcode's quilt. The key is released to the recording's owner, and
to the owner of a [`record_access`](../record_access) token for any release
that the recording authorized through
[`release_license`](../release_license). One set of transcodes serves every
authorized release. The release itself is not trusted: anyone can create a
release listing any recording and mint Records of it, so the policy reads the
authorization the recording's admin wrote on their own Recording.

## What it stores

Nothing. The policy reads [`recording_transcode`](../recording_transcode)'s
and `release_license`'s dynamic fields.

The Seal identity, after the package ID that Seal prefixes, is 64 bytes:

| Bytes | Field | Encoding |
|---|---|---|
| 0–31 | `recording_id` | `bcs(address)`: the Recording's object ID, as is |
| 32–63 | `quilt_blob_id` | `bcs(u256)`: little-endian, the raw 32 bytes of the quilt's Walrus blob ID |

## API

### Seal policy

Both are `entry` and not `public`, as Seal requires.

| Function | Passes when | Aborts |
|---|---|---|
| `seal_approve_owner<RecordingShare>(id, recording, cap)` | `id` names `recording` and a quilt it holds as a transcode; the caller owns the recording's cap | `EWrongRecording` (0), `EInvalidIdentity` (1), `ETranscodeNotFound` (2); `EOutOfRange` at `sui::bcs` |
| `seal_approve_record<RecordingShare>(id, recording, access: &RecordAccess)` | The same identity checks; `access.owner()` is the sender; `release_license::has_release_authorization(recording, access.release_id())` | as `seal_approve_owner`, plus `ENotOwner` (3), `EReleaseNotAuthorized` (4) |

## Events

None: the policy changes no state.

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EWrongRecording` | The identity's first 32 bytes are not `recording`'s ID |
| 1 | `EInvalidIdentity` | Bytes follow the quilt blob ID |
| 2 | `ETranscodeNotFound` | `recording` holds no transcode under the identity's quilt blob ID |
| 3 | `ENotOwner` | The sender is not the `RecordAccess` owner |
| 4 | `EReleaseNotAuthorized` | The recording has no authorization for the Record's release |

An identity shorter than 64 bytes aborts with `EOutOfRange` (0) at
`sui::bcs`.

## Dependencies

- [`recording_transcode`](../recording_transcode), by local path:
  `has_transcode`.
- [`release_license`](../release_license), by local path:
  `has_release_authorization`. The policy pins this generation; a new
  `release_license` generation needs a new policy package.
- [`record_access`](../record_access), by local path: `RecordAccess`,
  `owner` and `release_id`.
- [`miso_music`](https://github.com/misofm/music-protocol) at
  `430424a678f2387090850417eacbaa1bb46d1fb7`: `Recording` and
  `RecordingAdminCap`.
- [`audio`](../audio), by local path;
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
  the shared `RecordAccess` as objects, and `RecordingShare` as the type
  argument.
- **The owner must hold the cap directly,** because key servers dry-run the
  PTB with the requester as sender.
- **Trust the transcode by type.** Anyone can encrypt anything to any
  identity, and the owner can attach any `Audio` with `add_transcode`. A
  client should play only `Audio<AudioTranscoder, AacHls, ChannelLayout>`
  transcodes and check each decrypted file against the attested `manifest`.
- **Key servers read the full node's latest state,** so a change may take a
  moment to apply across servers.

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
