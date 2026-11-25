# recording_master_access

Who may decrypt a recording's encrypted masters. New masters' data keys are
Seal-encrypted under this package's ID (it supersedes
[`recording_master_seal`](../recording_master_seal)). The recording's owner may
always decrypt them. An enclave may decrypt one master only while the owner's
grant for it stands: a grant names the enclave type, the master, opaque terms
the enclave must repeat, and the version of the enclave's policy at grant
time, so it trusts exactly the image that policy trusted when the owner
granted it. The package knows nothing about formats or ranges; the terms are
the enclave package's business.

## What it stores

- Key: `RecordingMasterGrantKey<Enclave>(master_blob_id: u256)`, local to this
  package, one per enclave type and master, replaced in place.
- Value: `RecordingMasterGrant { terms: vector<u8>, policy_version: u64 }`.
  `terms` is at most 64 bytes. Revoking or consuming removes the field.

The Seal identity, after the package ID that Seal prefixes, is 64 bytes:

| Bytes | Field | Encoding |
|---|---|---|
| 0–31 | `recording_id` | `bcs(address)`: the Recording's object ID, as is |
| 32–63 | `master_blob_id` | `bcs(u256)`: little-endian, the raw 32 bytes of the master's Walrus blob ID |

## API

### Writes (cap-gated)

Each takes the recording's `&RecordingAdminCap<RecordingShare>`, which the
share type binds to the recording, so a wrong cap does not type-check.

| Function | Description | Aborts |
|---|---|---|
| `grant<RecordingShare, Enclave>(recording, cap, policy: &EnclavePolicy<Enclave>, master_blob_id, terms)` | Grants `Enclave` the master under `terms`, at `policy.version()`; emits `RecordingMasterGrantedEvent<Enclave>`. An equal grant: no-op | `EMasterNotFound` (2), `ETermsTooLong` (3) |
| `revoke<RecordingShare, Enclave>(recording, cap, master_blob_id)` | Removes the grant; emits `RecordingMasterGrantRevokedEvent<Enclave>`. None: no-op | none |
| `consume<RecordingShare, Enclave>(recording, cap, master_blob_id): RecordingMasterGrant` | Removes the grant and returns it; emits `RecordingMasterGrantConsumedEvent<Enclave>`. For the enclave package's verify step | `EGrantNotFound` (4) |

### Seal policy

Both are `entry` and not `public`, as Seal requires.

| Function | Passes when | Aborts |
|---|---|---|
| `seal_approve<RecordingShare>(id, recording, cap)` | `id` names `recording` and a blob it holds as a master; the caller owns the recording's cap | `EWrongRecording` (0), `EInvalidIdentity` (1), `EMasterNotFound` (2); `EOutOfRange` at `sui::bcs` |
| `seal_approve_enclave<RecordingShare, Enclave>(id, recording, policy: &EnclavePolicy<Enclave>, pk, terms)` | The same identity checks; a grant of `Enclave` for that master with exactly `terms`; `policy.version()` equal to the grant's `policy_version`, and `pk` registered at that version; the sender is `pk`'s Ed25519 Sui address, `blake2b256(0x00 ‖ pk)` | as `seal_approve`, plus `EGrantNotFound` (4), `ETermsMismatch` (5), `EImageChanged` (6), `EEnclaveNotCurrent` (7), `EWrongSender` (8) |

### Views

| Function | Returns |
|---|---|
| `has_grant<RecordingShare, Enclave>(recording, master_blob_id)` | `bool` |
| `grant_terms<RecordingShare, Enclave>(recording, master_blob_id)` | `&vector<u8>`; aborts `EGrantNotFound` (4) if absent |
| `grant_policy_version<RecordingShare, Enclave>(recording, master_blob_id)` | `u64`; aborts `EGrantNotFound` (4) if absent |
| `terms(grant)`, `policy_version(grant)` | a consumed grant's fields |
| `max_terms_length()` | `u64`, 64 |

## Events

| Event | When | Payload |
|---|---|---|
| `RecordingMasterGrantedEvent<Enclave>` | `grant` sets or changes a grant | `recording_id: ID`, `master_blob_id: u256`, `policy_id: ID`, `policy_version: u64`, `terms: vector<u8>` |
| `RecordingMasterGrantRevokedEvent<Enclave>` | `revoke` removes one | `recording_id: ID`, `master_blob_id: u256` |
| `RecordingMasterGrantConsumedEvent<Enclave>` | `consume` removes one | `recording_id: ID`, `master_blob_id: u256` |

The type parameter names the enclave type. Equal grants and absent revocations
emit nothing.

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EWrongRecording` | The identity's first 32 bytes are not `recording`'s ID |
| 1 | `EInvalidIdentity` | Bytes follow the master blob ID |
| 2 | `EMasterNotFound` | `recording` holds no master under that blob ID |
| 3 | `ETermsTooLong` | `terms` is longer than 64 bytes |
| 4 | `EGrantNotFound` | No grant of `Enclave` for that master |
| 5 | `ETermsMismatch` | The request's `terms` are not the granted ones |
| 6 | `EImageChanged` | The policy trusts another image (`set_pcrs`) than when the grant was made |
| 7 | `EEnclaveNotCurrent` | `pk` is not registered on the policy at the grant's version |
| 8 | `EWrongSender` | The sender is not `pk`'s Sui address |

An identity shorter than 64 bytes aborts with `EOutOfRange` (0) at
`sui::bcs`.

## Dependencies

- [`recording_master`](../recording_master), by local path: `has_master`.
- [`enclave`](../enclave), by local path: `EnclavePolicy`, `version`,
  `is_registered` and `registered_version`.
- [`miso_music`](https://github.com/misofm/music-protocol) at
  `430424a678f2387090850417eacbaa1bb46d1fb7`: `Recording`,
  `RecordingAdminCap` and `uid_mut`.
- [`audio`](../audio), by local path, and
  [`ori`](https://github.com/unconfirmedlabs/ori) (`move` subdirectory) at
  `a3a134ae69a4861030a05ae22f21e67a7b91faf9`: used only by the tests, to build
  masters. The package manifest has no dev-dependencies section.

## Integrator notes

- **A grant trusts exactly the image trusted at grant time.** It records the
  policy's version; if the policy's admin calls `set_pcrs` to trust another
  image, the grant stops working and the owner grants again. Any issuer using
  the `enclave` library works the same way.
- **One grant, one job.** The enclave package consumes the grant when it
  verifies the job's result (`audio_transcoder::verify_transcode`), so each
  grant decrypts for one job. A Seal answer already fetched before a revoke
  can still run that job, for as long as the enclave keeps it (the
  transcoder: at most 10 minutes).
- **Terms are public.** Every grant's terms are in its event and on the
  recording for good.
- **The enclave's own key certifies its Seal session.** An enclave holds a
  per-boot Ed25519 key, registered on its policy from an attestation. It signs
  the Seal session-key certificate with that key, so the requester address is
  `blake2b256(0x00 ‖ pk)`. The enclave never signs a Sui transaction with this
  key.
- **Seal PTBs** call only one of the two functions, with `id`, `pk` and
  `terms` as pure inputs, the shared `Recording<RecordingShare>` and either
  the owned cap or the shared `EnclavePolicy<Enclave>` as objects, and
  `RecordingShare` (plus `Enclave`) as type arguments. No `Clock`.
- **The owner must hold the cap directly.** Seal key servers dry-run the PTB
  with the requester as sender, and an owned object only resolves for its
  owner.
- **Key servers read the full node's latest state,** so a grant or revoke may
  take a moment to apply across servers.

## Build and test

```sh
sui move build --lint --warnings-are-errors
sui move build --lint --warnings-are-errors --build-env mainnet
sui move test --coverage --lint --warnings-are-errors
sui move coverage summary
```

## Deployments

Testnet `0xc370c70e65b1aa16f429b90dc1ee7080fb4090ddb1b3c914adc32b8b430f0270`
(tx `7M1f8XvfBi444phKTMEpYiLsF4iaSFbtaEGuC4z12EJv`). This is the package ID
Seal prefixes to the identity, so the master enclave pins it. The first
generation, with standing approvals by policy ID, stays published on testnet
at `0xfb09173cd7bb894eb5175d78e15365ece3c2c391aa6df2c3c92b107d810d7784`. Mainnet `0xe0262111397c8bfbef7ec8b785e249ce6b4eaf03c63cc4caf11b99fb38ebc0ec`
(tx `AqiaQNg11cMwZNouJUFpsgQdY5cLw1iH1jC1VttDB2Ys`).

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
