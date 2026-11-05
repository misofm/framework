# record

The Miso Record package owns the complete Record lifecycle on Sui. A `Pressing` is
one numbered edition of a Miso Release; a `Record` is one numbered copy within
that edition. External Distributor packages validate different sales mechanics.

```move
public struct Pressing has key {
    id: UID,
    release_id: ID,
    edition: u16,
    supply: u32,
    max_supply: u32,
    distributors: VecSet<TypeName>,
}

public struct Record has key, store {
    id: UID,
    release_id: ID,
    pressing_id: ID,
    edition: u16,
    number: u32,
}
```

There is no singleton Registry, Table, Settings object, or package initializer.
Unrelated editions mutate unrelated Pressings and can sell concurrently.

The package is intended to be made immutable when published. Future lifecycle
designs ship as separate packages with explicit migration paths, so on-chain
objects do not carry package-upgrade versions.

## Deterministic editions and Records

Each Pressing is derived directly from its Release at `PressingKey(edition)`. The
Release's `ReleaseAdminCap` authorizes creation, and claiming the same edition twice
aborts. Editions must be created sequentially, starting at 1: for edition `n > 1`,
the Release must already contain the derived claim for edition `n - 1`. This does
not require that the previous edition has sold out or been shared.

```move
let (mut pressing, pressing_cap) = pressing::new(
    release,
    release_cap,
    1,
    500,
);
```

Edition numbers are `u16` values from 1 through 65,535. Record numbers are `u32`
values starting at 1. Every Pressing owns an independent
Record sequence, so Edition 1 Record 1 and Edition 2 Record 1 are both valid and have
different IDs.

```move
let pressing_address = pressing::derive_address(&release, edition);
let record_address = record::derive_address(&pressing, number);
```

The full identity chain is therefore:

```text
Release
└── PressingKey(edition) → Pressing
    └── RecordKey(number) → Record
```

## Supply

`max_supply` is a required positive `u32`, fixed when the Pressing is created. It
caps lifetime issuance across all distributors and currencies. Destroying a Record
does not restore capacity. Further issuance beyond the cap requires a new
edition.

`record::new` asks the Pressing for the next number, and the Pressing checks the cap before incrementing `supply`. Failed or unauthorized
presses do not consume a number because the transaction rolls back atomically.

## Distributors

Each Pressing authorizes its own small set of module-controlled Distributor witness
types. This permits concurrent distribution paths and edition-specific policy without
a global governance object:

```move
pressing.authorize_distributor<record_store::DistributorWitness>(&pressing_cap);
pressing.revoke_distributor<legacy_store::DistributorWitness>(&pressing_cap);
```

Authorizing an authorized type aborts with `EDistributorAlreadyAuthorized` (6),
and revoking a type that isn't authorized aborts with
`EDistributorNotAuthorized` (3), like every add and `revoke` in the framework. A new
Distributor can be authorized before the old one is revoked, preserving the edition's
existing sequence during migration.

A Distributor constructs its witness internally and consumes it immediately:

```move
public fun purchase(pressing: &mut Pressing): Record {
    record::new(pressing, DistributorWitness())
}
```

`record::new` returns the Record rather than transferring it. The Distributor remains free
to deliver it through any composable transaction flow. The Distributor validates
payment and sale state, and records any sale details, such as currency and
price, in its own events; `record` stores no purchase data.

The `Distributor` type is carried by the concrete
`record::RecordCreatedEvent<Distributor>` event type. It is not duplicated as a
serialized string in that payload.

## Stored lifecycle data

The package derives every Record field:

- `release_id`, `pressing_id`, and `edition` come from the Pressing.
- `number` is allocated from the Pressing's edition-local sequence.
- The Record UID is claimed at `RecordKey(number)` from the Pressing UID.

Neither the buyer nor the eventual recipient is stored: the returned Record
remains composable and may be given as a gift, so its current owner is the
only holder that matters on-chain. Indexers that need the buyer can read the
transaction sender of the `RecordCreatedEvent`.

Neither is the price. Access never depends on what was spent: gate on the
`pressing_id` or `edition`, and make a tier its own pressing or edition. A
Distributor reports the sale in its own event, as `record_sale` does.

## Ownership and extensions

`Record` has `key + store`, so callers use Sui's framework ownership operations
directly:

```move
transfer::public_transfer(record, recipient);
```

Records may also be wrapped, placed in compatible custody systems, shared, or frozen.
The Record module intentionally provides no redundant transfer wrapper and does not
enforce direct address ownership.

Consequently, an immutable `&Record` is not by itself proof that the transaction
sender owns it: shared and frozen Records are readable by non-owners. Any
ownership-gated policy must establish the relevant ownership mode independently.

Extensions may use mutable Record access:

```move
public fun uid(self: &Record): &UID
public fun uid_mut(self: &mut Record): &mut UID
```

Callers must detach extensions before destroying a Record or those dynamic fields
become inaccessible.

`Record::uid_mut` is open to any holder, so sharing a Record makes extension mutation
public. `Pressing::uid_mut` requires the `PressingAdminCap` and serves objects derived
from the Pressing, such as Distributor state.

## Events

An indexer can track every Pressing and Record from these events and the
transaction envelope alone. All payloads are fixed-size (BCS bytes below), far
under Sui's 250 KiB per-event limit.

| Event | Fields | Bytes |
|---|---|---|
| `PressingCreatedEvent` | `pressing_id`, `pressing_admin_cap_id`, `release_id`, `edition`, `max_supply` | 102 |
| `PressingDistributorAuthorizedEvent<Distributor>` | `pressing_id` | 32 |
| `PressingDistributorRevokedEvent<Distributor>` | `pressing_id` | 32 |
| `RecordCreatedEvent<Distributor>` | `record_id`, `pressing_id`, `release_id`, `edition`, `number` | 102 |
| `RecordDestroyedEvent` | `record_id` | 32 |

All IDs are `ID`. Distributor is a phantom type parameter on the event type. A
new Pressing has supply 0 and no distributors. `number` is also the Pressing's
supply after the press. The buyer is the transaction's sender.
Destruction joins to `RecordCreatedEvent` by `record_id` and does not change
supply. Sharing is silent, and distributor events fire only when the set
changes.

## Layout

```text
Move.toml
sources/
  pressing.move
  record.move
tests/
  pressing_event_tests.move
  record_tests.move
```

## Build

```bash
sui move test -e testnet
```

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
