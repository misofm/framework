# record_access

A Record's access token. A `RecordAccess` is derived from its Record and
shared, and names the address that last proved it owned the Record. The Record
stays the thing that is owned and can be kept anywhere (an address, a Player, a
Kiosk); Seal policies such as [`record_audience_seal`](../record_audience_seal) read only
the `RecordAccess`, so how Records are stored never affects what was
encrypted. It has no policy of its own, so each policy package decides its
rules without changing this one.

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

## Events

| Event | When | Payload |
|---|---|---|
| `RecordAccessCreatedEvent` | `new` | `record_access_id: ID`, `record_id: ID`, `owner: address` |
| `RecordAccessClaimedEvent` | `claim` by a new owner; not emitted when the owner is unchanged | `record_access_id: ID`, `record_id: ID`, `owner: address` |

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EWrongRecord` | `claim` with a Record the access was not derived from |

A second `new` for a Record aborts with `EObjectAlreadyExists` (0) at
`sui::derived_object`.

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
- **Policies check `owner` against the key request's sender,** the session
  key's address. Key servers read the full node's latest state, so a claim may
  take a moment to apply across servers.
