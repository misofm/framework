# player_record_access

A Seal access policy that lets a Record unlock encrypted data. The rule is
written into the Seal identity itself: a release, optional edition and number
ranges, and an optional time window. The package stores nothing, so anyone can
encrypt anything for the holders of a release, an edition, or a range of
Records, with no on-chain setup. The Record must be kept in the requester's
`Player` through `player_storage`, which is what proves the requester holds it.

## What it stores

Nothing. The identity, after the package ID Seal prefixes, is the BCS
concatenation:

| Field | Type | Meaning |
|---|---|---|
| `release_id` | `address` | The Record's release |
| `edition_min`, `edition_max` | `Option<u16>` | Inclusive edition range; `None` is unbounded |
| `number_min`, `number_max` | `Option<u32>` | Inclusive Record number range; `None` is unbounded |
| `from_ms` | `Option<u64>` | Keys are released from this Clock time on |
| `until_ms` | `Option<u64>` | Keys are released only before this Clock time |
| `nonce` | `u256` | Distinguishes data under the same rule; not checked |

The identity must be exactly this long: trailing bytes abort.

## API

### Writes (cap-gated)

None.

### Views

None. The only function is the Seal entry point:

| Function | Description | Aborts |
|---|---|---|
| `seal_approve(id, player, record_id, clock)` | Passes when the Record stored in `player` under `record_id` matches the rule in `id` | every error below; `EFieldDoesNotExist` / `EFieldTypeMismatch` at `sui::dynamic_field`; `EOutOfRange` at `sui::bcs` |

## Events

None.

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EWrongRelease` | The Record belongs to another release |
| 1 | `EEditionOutOfRange` | The Record's edition is outside the range |
| 2 | `ENumberOutOfRange` | The Record's number is outside the range |
| 3 | `ENotYetOpen` | Before `from_ms` |
| 4 | `EClosed` | At or after `until_ms` |
| 5 | `ETrailingBytes` | The identity has bytes after the nonce |

A truncated identity aborts with `EOutOfRange` (0) at `sui::bcs`. A Record not
stored in the Player aborts at `sui::dynamic_field`.

## Dependencies

- [`player`](../player), by local path: the `Player` the requester owns.
- [`player_storage`](../player_storage), by local path: where the Record is
  kept and borrowed from.
- [`record`](../record), by local path: the `Record`'s release, edition, and
  number.

## Integrator notes

- **Holding is proven through the Player.** Seal's key servers simulate the
  request as the session key's address, and an owned `&Player` input only
  passes for its owner. A Record held directly by an address, or anywhere
  other than `player_storage`, unlocks nothing.
- **Never share or freeze a Player.** A shared or frozen Player would pass for
  anyone, and a shared one can be emptied by anyone.
- **Encryption is permissionless.** Anyone can encrypt for any rule, so the
  identity says who can decrypt, not who published. Trust content by where it
  is listed, for example a blob ID published by the recording's owner.
- **Use a new nonce for each piece of data.** A key fetched for an identity
  opens everything ever encrypted to it.
- **`until_ms` only stops new key requests.** A key fetched before the window
  closes keeps working.
- **Time comes from the full node's Clock** at simulation, so a request close
  to `from_ms` or `until_ms` can go either way across key servers.
- **A Record just stored may not pass at once.** Key servers read the full
  node's latest state.
- **Seal PTBs call only `seal_approve`.** Every argument must be a transaction
  input: `id` and `record_id` as pure values, the Player and `0x6` Clock as
  objects.
