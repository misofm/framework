# recording_master_access

Who may decrypt a recording's encrypted masters: its owner, and the enclaves
the owner approves. New masters' keys are Seal-encrypted under this package's
ID; it replaces [`recording_master_seal`](../recording_master_seal). The owner
approves an [`enclave::EnclavePolicy<Enclave>`](../enclave) by its `Enclave`
type: a one-time witness creates each policy, so a type names exactly one. A
key registered under that policy's current PCRs may then fetch a master's key,
but only for a transcode the owner requested, with exactly the requested
preview range (see [`recording_transcode`](../recording_transcode)).

## What it stores

- Key: `RecordingMasterAccessKey<Enclave>()`, local to this package, one per
  approved enclave type.
- Value: the approved `EnclavePolicy<Enclave>`'s `ID`. Revoking removes the
  field.

The Seal identity, after the package ID that Seal prefixes, is 64 bytes:

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
| `approve_enclave<RecordingShare, Enclave>(recording, cap, policy: &EnclavePolicy<Enclave>)` | Approves the policy; emits `RecordingMasterEnclaveApprovedEvent<Enclave>`. Already approved: no-op | none |
| `revoke_enclave<RecordingShare, Enclave>(recording, cap)` | Removes the approval; emits `RecordingMasterEnclaveRevokedEvent<Enclave>`. Not approved: no-op | none |

### Seal policy

Both are `entry` and not `public`, as Seal requires.

| Function | Passes when | Aborts |
|---|---|---|
| `seal_approve<RecordingShare>(id, recording, cap)` | `id` names `recording` and a blob it holds as an `AudioVerifier` master; the caller owns the recording's cap | `EWrongRecording` (0), `EInvalidIdentity` (1), `EMasterNotFound` (2); `EOutOfRange` at `sui::bcs` |
| `seal_approve_enclave<RecordingShare, Enclave>(id, recording, policy, pk, start_sample, end_sample)` | The same identity checks; `policy` is the approved `EnclavePolicy<Enclave>`; `pk` is registered on it under its current version; the sender is `pk`'s Ed25519 Sui address, `blake2b256(0x00 ‖ pk)`; and the recording holds a transcode request of `Enclave` for the identity's blob with exactly `[start_sample, end_sample)` | as `seal_approve`, plus `EEnclaveNotApproved` (3), `EEnclaveNotCurrent` (4), `EWrongSender` (5), `ERequestMismatch` (6) |

### Views

| Function | Returns |
|---|---|
| `is_approved<RecordingShare, Enclave>(recording)` | `bool` |
| `approved_policy<RecordingShare, Enclave>(recording)` | `Option<ID>`: the approved policy |

## Events

| Event | When | Payload |
|---|---|---|
| `RecordingMasterEnclaveApprovedEvent<Enclave>` | `approve_enclave` adds an approval | `recording_id: ID`, `policy_id: ID` |
| `RecordingMasterEnclaveRevokedEvent<Enclave>` | `revoke_enclave` removes one | `recording_id: ID`, `policy_id: ID` |

The type parameter names the enclave type. Repeated approvals and absent
revocations emit nothing.

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EWrongRecording` | The identity's first 32 bytes are not `recording`'s ID |
| 1 | `EInvalidIdentity` | Bytes follow the blob ID |
| 2 | `EMasterNotFound` | `recording` holds no `AudioVerifier` master under the identity's blob ID |
| 3 | `EEnclaveNotApproved` | The owner has not approved `Enclave`, or `policy` is not the approved one |
| 4 | `EEnclaveNotCurrent` | `pk` is not registered on the policy, or was registered under older PCRs |
| 5 | `EWrongSender` | The sender is not `pk`'s Sui address |
| 6 | `ERequestMismatch` | No transcode request of `Enclave` for that master, or another range |

An identity shorter than 64 bytes aborts with `EOutOfRange` (0) at
`sui::bcs`.

## Dependencies

- [`recording_master`](../recording_master), by local path: `has_master`.
- [`audio_verifier`](../audio_verifier), by local path: `AudioVerifier`, the
  only master verifier these policies accept. This pins its generation.
- [`recording_transcode`](../recording_transcode), by local path: the
  transcode request (`has_request`, `request`).
- [`enclave`](../enclave), by local path: `EnclavePolicy`, `version`,
  `is_registered` and `registered_version`.
- [`miso_music`](https://github.com/misofm/music-protocol) at
  `430424a678f2387090850417eacbaa1bb46d1fb7`: `Recording`,
  `RecordingAdminCap` and `uid_mut`.
- [`audio`](../audio), [`audio_format_pcm`](../audio_format_pcm) and
  [`audio_channel_layout`](../audio_channel_layout), by local path, and
  [`ori`](https://github.com/unconfirmedlabs/ori) (`move` subdirectory) at
  `a3a134ae69a4861030a05ae22f21e67a7b91faf9`: used only by the tests, to build
  masters. The package manifest has no dev-dependencies section.

## Integrator notes

- **Approving a policy trusts its admin indefinitely.** The holder of the
  policy's `EnclavePolicyAdminCap` can call `set_pcrs` at any time and point
  the policy at a different image, which can then register and fetch the keys
  of every master the owner asked it to transcode. Approve only policies whose
  admin you trust, and revoke when that changes. Revoking stops new key
  requests; keys already fetched keep working.
- **One key per requested job.** An approved enclave gets a master's key only
  while the owner's request for it stands, and only for that preview range,
  which the enclave writes into its own key request. `add_transcode` removes
  the request, so a stored transcode closes the window.
- **The enclave's own key certifies its Seal session.** An enclave holds a
  per-boot Ed25519 key, registered on its policy from an attestation. It signs
  the Seal session-key certificate with that key, so the requester address is
  `blake2b256(0x00 ‖ pk)`, and `seal_approve_enclave` binds the sender to the
  `pk` it names. The enclave never signs a Sui transaction with this key.
- **Seal PTBs** call only one of the two functions, with `id`, `pk` and the
  range as pure inputs, the shared `Recording<RecordingShare>` and either the
  owned cap or the shared `EnclavePolicy<Enclave>` as objects, and
  `RecordingShare` (plus `Enclave`) as type arguments.
- **The owner must hold the cap directly.** Seal key servers dry-run the PTB
  with the requester as sender, and an owned object only resolves for its
  owner.
- **Encrypt new masters to this package**, with the 64-byte identity above.
  Masters sealed to `recording_master_seal` stay readable only through that
  package.
- **Key servers read the full node's latest state,** so an approval,
  revocation or request may take a moment to apply across servers.

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
