# Enclave

A Sui Move library for verifying [AWS Nitro Enclave](https://aws.amazon.com/ec2/nitro/nitro-enclaves/) attestations and enclave-signed intent messages on-chain. It is the on-chain half of [nautilus-rust](https://github.com/unconfirmedlabs/nautilus-rust), and it works with any [Nautilus](https://github.com/MystenLabs/nautilus) enclave through Sui's native `NitroAttestationDocument`.

It supersedes `unconfirmedlabs/kagi`. It is a new package: no on-chain state is migrated.

```
 Nitro attestation document
            |
            v  register (anyone)
 EnclavePolicy<App> ---------------------> verify_signature(policy, pk, ...)
   PCR0/1/2 + version                        key usable only if its
   EnclaveKey(pk) -> version                 version == policy version
```

## How trust works

- **One policy per App.** `new<App>(otw, ctx)` takes a one-time witness, so it runs once, in the App's `init`, and aborts `ENotOneTimeWitness` for any other type. It returns the `EnclavePolicy<App>` and its `EnclavePolicyAdminCap<App>`. The policy has `key` only, so `share` is the only way to keep it.
- **The policy is the single statement of which image is trusted.** It holds the image's PCR0, PCR1 and PCR2 and a `version`.
- **PCRs start unset** at version 0, because they are known only once the image is built, after the package is published. A real document's PCRs are never empty, so nothing can register until `set_pcrs` is called (`register` aborts `EInvalidPcrs`).
- **`set_pcrs` (admin cap) checks and versions the PCRs.** Each PCR must be 48 bytes, SHA-384 (`EInvalidPcrLength`), and not all zeros (`EDebugPcrs`). A debug-mode enclave reports all-zero PCRs and its memory is readable from the host, so a policy can never admit one. Setting the current PCRs again aborts `ESamePcrs`, so `version` only moves on a real change.
- **A PCR change is the kill switch.** Each `set_pcrs` increments `version`. Every key registered under an older version stops verifying at once (`EStaleEnclave`), so old keys are retired atomically with the change.
- **Registration is permissionless.** Anyone holding a valid attestation document whose PCR0, PCR1 and PCR2 (matched by index) equal the policy's current PCRs can call `register`. It stores `EnclaveKey(pk) -> version` as a dynamic field on the policy. The public key must be a 32-byte Ed25519 key.
- **The admin cap can stay cold.** Routine boots and re-registrations need no cap, so the cap can live in a multisig. Rotating to a new image is one PTB: `[set_pcrs, register]`.
- **`verify_signature` reads the policy** by shared, read-only reference, together with the signer's `pk`. It aborts `EEnclaveNotRegistered` for an unknown key, `EStaleEnclave` for a key registered under another version, and `EInvalidSignature` for a bad signature.
- **Removing keys.** `revoke` (admin cap) removes any one key, for example a compromised one. `remove_stale` (anyone) removes a key registered under an older version and aborts `ENotStale` for a current one.
- **Rollback A -> B -> A needs no reboot.** After rolling the PCRs back, call `remove_stale` for the key, then `register` it again with an attestation document from the still-running enclave. It is stored under the new version.
- **The admin cap is a derived object of the policy** (`EnclavePolicyAdminCapKey()`). It stores no policy ID: `set_pcrs` and `revoke` derive the cap address from the policy and compare it with the cap's ID, aborting `EUnauthorized` otherwise. `derive_admin_cap_address` and the SDK's `derivePolicyAdminCapId` compute it offline.
- **Domain separation is the `intent` byte.** Give each kind of message its own intent value.
- **`timestamp_ms` comes from the enclave's clock,** which the host provides. Treat it as the time the enclave claims, not as attested time.

## Usage

```move
module my_app::my_app;

use enclave::enclave::{Self, EnclavePolicy};

public struct MY_APP() has drop;

public struct MyPayload has copy, drop {
    value: u64,
}

const MY_INTENT: u8 = 0;
const ADMIN: address = @0xA11CE;

fun init(otw: MY_APP, ctx: &mut TxContext) {
    let (policy, cap) = enclave::new(otw, ctx);
    policy.share();
    transfer::public_transfer(cap, ADMIN);
}

public fun consume(
    policy: &EnclavePolicy<MY_APP>,
    pk: vector<u8>,
    value: u64,
    timestamp_ms: u64,
    signature: vector<u8>,
) {
    policy.verify_signature(pk, MY_INTENT, timestamp_ms, MyPayload { value }, &signature);
}
```

- **Send the `EnclavePolicyAdminCap` to an address your app chooses,** such as a multisig. `ADMIN` above is a placeholder; replace it with your own admin address.
  > **Warning:** if the package is published by an ephemeral or throwaway signer, a cap sent to `ctx.sender()` is lost forever. The policy then can never set PCRs or revoke a key.
- **Take `EnclavePolicy<MY_APP>`, never a generic `EnclavePolicy<T>`.** A generic parameter would let a key registered for any other app sign for yours.
- **Register without a wrapper.** In one PTB, get the document from `sui::nitro_attestation::load_nitro_attestation(bytes, clock)`, which checks the AWS certificate chain at the clock's time, and pass it to `enclave::register`.
- **Deployment order:**
  1. Publish the package.
  2. Build the enclave image and record its PCRs.
  3. Call `set_pcrs` with the admin cap.
  4. Boot the enclave and `register` it (anyone may submit the transaction).

## API

All functions are in `enclave::enclave`.

### Public functions

| Function | Who may call | What it does |
|---|---|---|
| `new<App>(otw, ctx)` | the App's `init` | Creates the policy for `App` with unset PCRs at version 0, and returns it with its `EnclavePolicyAdminCap`. Aborts `ENotOneTimeWitness`. Emits `EnclavePolicyCreatedEvent`. |
| `share(self)` | anyone | Shares the policy. |
| `register(self, document)` | anyone | Checks the document's PCR0, PCR1 and PCR2 against the policy and stores `EnclaveKey(pk) -> version` for its 32-byte public key. Emits `EnclaveRegisteredEvent`. |
| `remove_stale(self, pk)` | anyone | Removes a key registered under an older version. Emits `StaleEnclaveRemovedEvent`. |
| `verify_signature(self, pk, intent, timestamp_ms, payload, signature)` | anyone | Checks that `pk` is registered under the current version and that `signature` is its Ed25519 signature over `bcs(IntentMessage { intent, timestamp_ms, payload })`. |
| `create_intent_message(intent, timestamp_ms, payload)` | anyone | Builds the `IntentMessage` that `verify_signature` checks. |

### View functions

| Function | Who may call | What it does |
|---|---|---|
| `version(self)` | anyone | The current policy version. |
| `pcr0(self)`, `pcr1(self)`, `pcr2(self)` | anyone | The trusted PCRs; empty until the first `set_pcrs`. |
| `is_registered(self, pk)` | anyone | Whether `pk` has a registration, current or stale. |
| `registered_version(self, pk)` | anyone | The version `pk` was registered under. Aborts `EEnclaveNotRegistered`. |
| `derive_admin_cap_address(self)` | anyone | The address of the policy's `EnclavePolicyAdminCap`. |

### Admin functions

| Function | Who may call | What it does |
|---|---|---|
| `set_pcrs(self, cap, pcr0, pcr1, pcr2)` | the cap holder | Sets the trusted PCRs and increments `version`, making every existing key stale. Emits `EnclavePolicyPcrsSetEvent`. |
| `revoke(self, cap, pk)` | the cap holder | Removes one key, current or stale. Emits `EnclaveRevokedEvent`. |

### Test-only functions

For downstream packages' unit tests, since Sui can't build an attestation document there.

| Function | What it does |
|---|---|
| `new_for_testing<App>(ctx)` | Creates a policy and its cap without a one-time witness. |
| `register_for_testing(self, pk, version)` | Stores `EnclaveKey(pk) -> version` directly, with the same duplicate and 32-byte key checks as `register`. |

## Errors

| Code | Name | Raised by |
|---|---|---|
| 0 | `ENotOneTimeWitness` | `new` |
| 1 | `EUnauthorized` | `set_pcrs`, `revoke`, with another policy's cap |
| 2 | `EInvalidPcrLength` | `set_pcrs`, for a PCR that isn't 48 bytes |
| 3 | `EDebugPcrs` | `set_pcrs`, for an all-zero PCR |
| 4 | `ESamePcrs` | `set_pcrs`, for the current PCRs |
| 5 | `EInvalidPcrs` | `register`, when the document's PCRs differ from the policy's (always while unset) |
| 6 | `EMissingPcr` | `register`, for a document without PCR0, PCR1 or PCR2 |
| 7 | `EMissingPublicKey` | `register`, for a document without a public key |
| 8 | `EInvalidPublicKeyLength` | `register`, `register_for_testing`, for a key that isn't 32 bytes |
| 9 | `EEnclaveAlreadyRegistered` | `register`, `register_for_testing`, for a key that is already registered |
| 10 | `EEnclaveNotRegistered` | `verify_signature`, `registered_version`, `revoke`, `remove_stale`, for an unregistered key |
| 11 | `EStaleEnclave` | `verify_signature`, for a key registered under another version |
| 12 | `ENotStale` | `remove_stale`, for a key registered under the current version |
| 13 | `EInvalidSignature` | `verify_signature` |

## Events

| Event | Fields | Emitted by |
|---|---|---|
| `EnclavePolicyCreatedEvent<App>` | `policy_id` | `new` |
| `EnclavePolicyPcrsSetEvent<App>` | `policy_id`, `version` (the new version), `pcr0`, `pcr1`, `pcr2` | `set_pcrs` |
| `EnclaveRegisteredEvent<App>` | `policy_id`, `pk`, `version` | `register` |
| `EnclaveRevokedEvent<App>` | `policy_id`, `pk`, `version` (the key's registered version) | `revoke` |
| `StaleEnclaveRemovedEvent<App>` | `policy_id`, `pk`, `version` (the key's registered version) | `remove_stale` |

## Intent messages

```
┌────────┬──────────────────┬───────────────┐
│ intent │ timestamp_ms     │ payload       │
│ u8     │ u64 little-end.  │ BCS of P      │
└────────┴──────────────────┴───────────────┘
```

nautilus-rust's `NautilusContext::sign_intent` signs exactly this layout. The test `intent_message_layout_matches_nautilus_rust` pins the shared vector `0020b1d110960100000d53616e204672616e636973636f0d00000000000000` (intent 0, timestamp 1744038900000, payload `{ location: "San Francisco", temperature: 13 }`).

## Non-goals

- **No replay protection.** A valid signature verifies any number of times. Callers dedupe, for example by timestamp or by a nonce in the payload.
- **No freshness check.** `verify_signature` takes no `Clock` and does not compare `timestamp_ms` with chain time.
- **The intent namespace belongs to the image, not the App.** If the same image is registered under two policies, its signatures are valid under both. Use distinct intents or distinct images per App if that matters.
- **No account binding.** PCR3 and PCR4 are not checked, so an enclave running the trusted image in any AWS account can register.

## TypeScript SDK

`sdk/` (`@misofm/enclave`) exports:

| Export | What it does |
|---|---|
| `derivePolicyAdminCapId(policyId, packageId)` | The `EnclavePolicyAdminCap` ID, the same value as `derive_admin_cap_address`. |
| `enclaveKeyFieldId(policyId, publicKey, packageId)` | The object ID of the `EnclaveKey(publicKey) -> u64` dynamic field on the policy. |
| `getRegisteredVersion(client, { policyId, publicKey, packageId })` | Reads that dynamic field over plain RPC; returns the version as a `bigint`, or `null` if the key has no registration. Transport failures reject. |
| `isKeyUsable(client, { policyId, publicKey, packageId, policyVersion })` | Whether the key is registered under `policyVersion`. |
| `EnclaveClient`, `EnclaveKeyRef` | Types. `EnclaveClient` is any Sui client exposing the core `getObjects` API (gRPC, GraphQL or JSON-RPC). |

- `packageId` is always required: it is the published enclave package that defines the key types.
- The zero-field `EnclavePolicyAdminCapKey` is encoded as Move encodes it, as one `dummy_field: bool` byte (`0x00`).
- `sdk/index.test.ts` pins the policy and admin cap IDs that the Move test `admin_cap_address_matches_the_pinned_vector` asserts, so the two implementations can't drift.

## Dependency

```toml
enclave = { git = "https://github.com/misofm/framework.git", subdir = "enclave", rev = "<commit>" }
```

## Deployments

Not yet published.

## Building and testing

```sh
sui move build
sui move test --coverage
sui move coverage summary
sui move build --lint --build-env mainnet

cd sdk && bun install && bun run test && bun run typecheck
```

The tests use a real Nitro attestation document from Mysten's weather example. The test corpus has no document that lacks a public key or a PCR, so `EMissingPublicKey`, `EInvalidPublicKeyLength` and `EMissingPcr` are tested through test-only wrappers of the private helpers that raise them.

## Contact

contact@miso.fm, including security reports.

## License

Apache-2.0, see [LICENSE.md](LICENSE.md), unlike the rest of misofm/framework, which is FSL-1.1-ALv2. Copyright Miso Labs, Inc.
