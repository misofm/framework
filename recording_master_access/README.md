# recording_master_access

Who may decrypt a recording's encrypted masters: its owner, and the enclaves
the owner approves. It replaces [`recording_master_seal`](../recording_master_seal)
for new masters, whose keys are Seal-encrypted under this package's ID. The
owner approves an [`enclave::EnclavePolicy`](../enclave) by its object ID, and
any enclave key registered under that policy's current PCRs may then fetch
the master's key, for example the transcoder in
[`audio_transcoder`](../audio_transcoder). Approval names a policy, never an
address, so an image rotation needs no new approval.

## What it stores

- Key: `RecordingMasterAccessKey()`, local to this package.
- Value: a [`typed_set`](https://github.com/unconfirmedlabs/typed_set) set of
  approved policy `ID`s on the `Recording`, at most 16. Revoking the last one
  reclaims the field.

The Seal identity, after the package ID that Seal prefixes, is 64 bytes, the
same as `recording_master_seal`'s:

| Bytes | Field | Encoding |
|---|---|---|
| 0–31 | `recording_id` | `bcs(address)`: the Recording's object ID, as is |
| 32–63 | `blob_id` | `bcs(u256)`: little-endian, the raw 32 bytes of the master's Walrus blob ID |

## API

### Writes (cap-gated)

Both take the recording's `&RecordingAdminCap<RecordingShare>`, which the
share type binds to the recording, so a wrong cap does not type-check.

| Function | Description | Aborts |
|---|---|---|
| `approve_enclave<RecordingShare, App>(recording, cap, policy: &EnclavePolicy<App>)` | Approves the policy's ID; emits `RecordingMasterEnclaveApprovedEvent`. Already approved: no-op | `EMaxItemsExceeded` at `typed_set::typed_set` past 16 |
| `revoke_enclave<RecordingShare>(recording, cap, policy_id: ID)` | Removes the approval; emits `RecordingMasterEnclaveRevokedEvent`. Not approved: no-op | none |

### Seal policy

Both are `entry` and not `public`, as Seal requires.

| Function | Passes when | Aborts |
|---|---|---|
| `seal_approve<RecordingShare>(id, recording, cap)` | `id` names `recording` and a blob it holds as a master; the caller owns the recording's cap | `EWrongRecording` (0), `EInvalidIdentity` (1), `EMasterNotFound` (2); `EOutOfRange` at `sui::bcs` |
| `seal_approve_enclave<RecordingShare, App>(id, recording, policy, pk)` | The same identity checks; `object::id(policy)` is approved on `recording`; `pk` is registered on `policy` under its current version; the sender is `pk`'s Ed25519 Sui address, `blake2b256(0x00 ‖ pk)` | as `seal_approve`, plus `EEnclaveNotApproved` (3), `EEnclaveNotCurrent` (4), `EWrongSender` (5) |

### Views

| Function | Returns |
|---|---|
| `is_approved<RecordingShare>(recording, policy_id)` | `bool` |
| `approved_enclaves<RecordingShare>(recording)` | `vector<ID>`, in approval order; empty if none |
| `max_approved_enclaves()` | `u64`, 16 |

## Events

| Event | When | Payload |
|---|---|---|
| `RecordingMasterEnclaveApprovedEvent` | `approve_enclave` adds a policy | `recording_id: ID`, `policy_id: ID` |
| `RecordingMasterEnclaveRevokedEvent` | `revoke_enclave` removes a policy | `recording_id: ID`, `policy_id: ID` |

Repeated approvals and absent revocations emit nothing.

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EWrongRecording` | The identity's first 32 bytes are not `recording`'s ID |
| 1 | `EInvalidIdentity` | Bytes follow the blob ID |
| 2 | `EMasterNotFound` | `recording` holds no master under the identity's blob ID |
| 3 | `EEnclaveNotApproved` | The owner has not approved this policy on `recording` |
| 4 | `EEnclaveNotCurrent` | `pk` is not registered on the policy, or was registered under older PCRs |
| 5 | `EWrongSender` | The sender is not `pk`'s Sui address |

From primitives: an identity shorter than 64 bytes aborts with `EOutOfRange`
(0) at `sui::bcs`; a seventeenth approval aborts with `EMaxItemsExceeded` (2)
at `typed_set::typed_set`.

## Dependencies

- [`recording_master`](../recording_master), by local path: `has_master`.
- [`enclave`](../enclave), by local path: `EnclavePolicy`, `version`,
  `is_registered` and `registered_version`.
- [`miso_music`](https://github.com/misofm/music-protocol) at
  `430424a678f2387090850417eacbaa1bb46d1fb7`: `Recording`,
  `RecordingAdminCap` and `uid_mut`.
- [`typed_set`](https://github.com/unconfirmedlabs/typed_set) at
  `b37474cbde166b7ddf8a3b615cd89f90182ace6f`: the bounded set.
- [`audio`](../audio), by local path, and
  [`ori`](https://github.com/unconfirmedlabs/ori) (`move` subdirectory) at
  `a3a134ae69a4861030a05ae22f21e67a7b91faf9`: used only by the tests, to build
  masters. The package manifest has no dev-dependencies section.

## Integrator notes

- **Approving a policy trusts its admin indefinitely.** The holder of the
  policy's `EnclavePolicyAdminCap` can call `set_pcrs` at any time and point
  the policy at a different image, which can then register and fetch the keys
  of every master that approves the policy. Approve only policies whose admin
  you trust, and revoke when that changes. Revoking stops new key requests;
  keys already fetched keep working.
- **The enclave's own key certifies its Seal session.** An enclave holds a
  per-boot Ed25519 key, registered on its policy from an attestation. It signs
  the Seal session-key certificate with that key, so the requester address is
  `blake2b256(0x00 ‖ pk)`, and `seal_approve_enclave` binds the sender to the
  `pk` it names. The enclave never signs a Sui transaction with this key.
- **Seal PTBs** call only one of the two functions, with `id` and (for the
  enclave) `pk` as pure inputs, the shared `Recording<RecordingShare>` and
  either the owned cap or the shared `EnclavePolicy<App>` as objects, and
  `RecordingShare` (plus `App`) as type arguments.
- **The owner must hold the cap directly.** Seal key servers dry-run the PTB
  with the requester as sender, and an owned object only resolves for its
  owner.
- **Encrypt new masters to this package.** The master enclave Seal-encrypts
  the data key with this package's ID and the 64-byte identity above. Masters
  sealed to `recording_master_seal` stay readable only through that package.
- **Removing the master stops new key requests** for its blob, through both
  functions.
- **Key servers read the full node's latest state,** so an approval or
  revocation may take a moment to apply across servers.

## Deployments

Testnet `0xfb09173cd7bb894eb5175d78e15365ece3c2c391aa6df2c3c92b107d810d7784`
(tx `DfLByqFWH68GzM3T1jGp9AiCHq3ie5hbYUDJwaRPgqSq`). This is the package ID Seal
prefixes to the identity, so the master enclave pins it. It is not on mainnet
yet.

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
