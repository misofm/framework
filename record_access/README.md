# record_access

A Record's access token and the Seal policy that reads it. A `RecordAccess`
is derived from its Record and shared, and names the address that last proved
it owned the Record. The Record stays the thing that is owned and can be kept
anywhere (an address, a Player, a Kiosk); the Seal policy reads only the
`RecordAccess`, so how Records are stored never affects what was encrypted.
The access rule is written into the Seal identity itself, so anyone can
encrypt for the owners of a release, an edition, or a range of Records with no
on-chain setup.

## What it stores

- `RecordAccess`, a shared object derived from the Record's UID at
  `RecordAccessKey()`, one per Record:

  | Field | Type | Meaning |
  |---|---|---|
  | `release_id` | `ID` | The Record's release |
  | `edition` | `u16` | The Record's edition |
  | `number` | `u32` | The Record's number |
  | `owner` | `address` | The last address to prove ownership |

- Release, edition, and number are copied from the Record, which never
  changes them. Only `owner` changes, through `claim`. Nothing is removed.

The Seal identity, after the package ID Seal prefixes, is the BCS
concatenation:

| Field | Type | Meaning |
|---|---|---|
| `release_id` | `address` | The release |
| `edition_min`, `edition_max` | `Option<u16>` | Inclusive edition range; `None` is unbounded |
| `number_min`, `number_max` | `Option<u32>` | Inclusive number range; `None` is unbounded |
| `from_ms` | `Option<u64>` | Keys are released from this Clock time on |
| `until_ms` | `Option<u64>` | Keys are released only before this Clock time |
| `nonce` | `u256` | Distinguishes data under the same rule; not checked |

## API

### Writes (Record holder)

Both take the Record by value and return it, which only its owner can do: a
shared Record cannot be returned, and a frozen one cannot be passed by value.

| Function | Description | Aborts |
|---|---|---|
| `new(record, ctx)` | Creates and shares the Record's `RecordAccess` with the caller as `owner`; emits `RecordAccessCreatedEvent` | `EObjectAlreadyExists` at `sui::derived_object` |
| `claim(access, record, ctx)` | Sets `owner` to the caller; emits `RecordAccessClaimedEvent` when the owner changes | `EWrongRecord` (0) |

### Views

| Function | Returns |
|---|---|
| `release_id(access)` | `ID` |
| `edition(access)` | `u16` |
| `number(access)` | `u32` |
| `owner(access)` | `address` |
| `derive_address(record_id)` | `address` of the Record's `RecordAccess` |

### Seal policy

| Function | Description | Aborts |
|---|---|---|
| `seal_approve(id, access, clock, ctx)` | Passes when the caller is `owner` and the access matches the rule in `id` | `ENotOwner` (1) through `ETrailingBytes` (7); `EOutOfRange` at `sui::bcs` |

## Events

| Event | When | Payload |
|---|---|---|
| `RecordAccessCreatedEvent` | `new` | `record_access_id: ID`, `record_id: ID`, `owner: address` |
| `RecordAccessClaimedEvent` | `claim` by a new owner; not emitted when the owner is unchanged | `record_access_id: ID`, `record_id: ID`, `owner: address` |

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EWrongRecord` | `claim` with a Record the access was not derived from |
| 1 | `ENotOwner` | Key request from an address other than `owner` |
| 2 | `EWrongRelease` | The Record belongs to another release |
| 3 | `EEditionOutOfRange` | The edition is outside the range |
| 4 | `ENumberOutOfRange` | The number is outside the range |
| 5 | `ENotYetOpen` | Before `from_ms` |
| 6 | `EClosed` | At or after `until_ms` |
| 7 | `ETrailingBytes` | The identity has bytes after the nonce |

A second `new` for a Record aborts with `EObjectAlreadyExists` (0) at
`sui::derived_object`. A truncated identity aborts with `EOutOfRange` (0) at
`sui::bcs`.

## Dependencies

- [`record`](../record), by local path: the `Record` whose UID derives the
  access and whose release, edition, and number it copies.

## Integrator notes

- **Create and claim when a Record changes hands.** A first sale can call
  `new` in the purchase PTB. After a transfer, the new owner calls `claim`
  once. Until then the previous owner keeps access, which matters little: they
  could have fetched every key while they owned it.
- **Claim before storing.** A Record kept in a `player_storage` slot must be
  withdrawn to be passed by value; claim right after acquiring it, before any
  extension locks it.
- **Find the access from the Record ID** with `derive_address(record_id)`; no
  index is needed.
- **Seal PTBs call only `seal_approve`,** with `id` as a pure input and the
  shared `RecordAccess` and `0x6` Clock as objects. The caller is the session
  key's address.
- **Encryption is permissionless.** The identity says who can decrypt, not who
  published; trust content by where it is listed.
- **Use a new nonce for each piece of data.** A key fetched for an identity
  opens everything encrypted to it.
- **`until_ms` only stops new key requests.** A key fetched before the window
  closes keeps working.
- **Key servers read the full node's latest state,** so a claim or a time
  bound may take a moment to apply across servers.
