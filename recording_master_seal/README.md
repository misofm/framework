# recording_master_seal

**Legacy.** New masters are sealed to
[`recording_master_access`](../recording_master_access); this policy covers
only masters already sealed to it.

The Seal policy for a recording's encrypted masters. The enclave Seal-encrypts
each master's data key to an identity naming the recording and the master's
Walrus blob. `seal_approve` releases the key to whoever holds the recording's
`RecordingAdminCap`, while the recording still holds a master under that blob
ID. The identity names the recording, not just the blob, because blob IDs are
public and anyone can attach an `Audio` with someone else's blob ID to a
recording of their own.

## What it stores

Nothing. The policy reads [`recording_master`](../recording_master)'s
dynamic fields.

The Seal identity, after the package ID that Seal prefixes, is 64 bytes:

| Bytes | Field | Encoding |
|---|---|---|
| 0–31 | `recording_id` | `bcs(address)`: the Recording's object ID, as is |
| 32–63 | `blob_id` | `bcs(u256)`: little-endian, the raw 32 bytes of the Walrus blob ID |

For example, recording
`0xc0c0…c0` and blob ID `0x000102…1f` (written as a number) give
`c0c0…c0 1f1e1d…00`. The blob ID bytes are the base64url-decoded Walrus blob
ID string. A Walrus blob ID read on chain as a `u256` encodes to the same
bytes.

## API

### Seal policy

| Function | Description | Aborts |
|---|---|---|
| `seal_approve<RecordingShare>(id, recording, cap)` | Passes when `id` names `recording` and a blob that `recording` holds as a master. `cap` is the recording's `&RecordingAdminCap<RecordingShare>` | `EWrongRecording` (0), `EInvalidIdentity` (1), `EMasterNotFound` (2); `EOutOfRange` at `sui::bcs` |

It is `entry` and not `public`, as Seal requires.

## Events

None: the policy changes no state.

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EWrongRecording` | The identity's first 32 bytes are not `recording`'s ID |
| 1 | `EInvalidIdentity` | Bytes follow the blob ID |
| 2 | `EMasterNotFound` | `recording` holds no master under the identity's blob ID |

An identity shorter than 64 bytes aborts with `EOutOfRange` (0) at
`sui::bcs`.

## Dependencies

- [`recording_master`](../recording_master), by local path: `has_master`.
- [`miso_music`](https://github.com/misofm/music-protocol) at
  `430424a678f2387090850417eacbaa1bb46d1fb7`: `Recording` and
  `RecordingAdminCap`.
- [`audio`](../audio), by local path, and
  [`ori`](https://github.com/unconfirmedlabs/ori) (`move` subdirectory) at
  `a3a134ae69a4861030a05ae22f21e67a7b91faf9`: used only by the tests, to build
  masters. The package manifest has no dev-dependencies section.

## Integrator notes

- **The caller must own the cap directly.** Seal key servers dry-run the PTB
  with the requester's address as sender, and an owned object only resolves
  for its owner. `RecordingShare` binds the cap to the recording, because core
  allows one Recording per share type. A cap held by a Party or a `vault` can't
  approve yet; that is a later extension.
- **Seal PTBs call only `seal_approve`,** with `id` as a pure input, the shared
  `Recording<RecordingShare>` and the owned cap as objects, and
  `RecordingShare` as the type argument.
- **The encrypting side must know the recording ID.** It is
  `miso_music::recording::derive_address<RecordingShare>(registry)`, which is
  known once the share type is published, before the Recording exists.
- **Removing the master stops new key requests.** Keys already fetched keep
  working. Transferring the cap moves the right to decrypt.
- **Key servers read the full node's latest state,** so a change to a master
  may take a moment to apply across servers.
- **Encryption is permissionless.** Anyone can encrypt anything to any
  identity. Trust a master by its verified `Audio`, not by its identity.

## Deployments

Testnet `0xf2452914718b6f8d3cadef6e04d390fb66b496e7e5095de67b254eecbd77b6fb`
(tx `D5YrCfpZrWLkYbxrz62pVVi4qQwkm5imZu9wxsinsWP6`). This is the package ID
Seal prefixes to the identity, so the enclave pins it. Mainnet `0xc88ec196f164c160a32cc5f8a87915906c66091838ac96b40104608bc494ca47`
(tx `AqiaQNg11cMwZNouJUFpsgQdY5cLw1iH1jC1VttDB2Ys`).

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
