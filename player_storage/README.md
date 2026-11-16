# player_storage

Objects kept inside a `Player`, each with a set of typed locks. A stored
object is wrapped in a dynamic field of the Player, can be lent by value
within one transaction even while locked, and leaves only through `withdraw`,
which refuses while any lock is held. Storage and
locks live in one package so the lock is enforced where the object is kept;
the extensions that lock (playtime, staking) stay separate packages.

## What it stores

- Key: `SlotKey(ID)`, the stored object's ID, on the Player's UID. The key is
  private to this package, so no other package can reach a slot through
  `player::uid_mut`.
- Value: `StorageSlot<Item> { item: Referent<Item>, locks: VecSet<TypeName> }`,
  for any `Item: key + store`. The `sui::borrow::Referent` holds the item and
  lends it out.
- `locks` holds the `TypeName` of each locker type, at most `MAX_LOCKS` (8),
  one per type.
- `withdraw` removes the slot and reclaims its storage. The number of stored
  objects is not bounded; each slot is fixed size apart from the item.

## API

### Writes (Player owner)

| Function | Description | Aborts |
|---|---|---|
| `store<Item>(player, item, ctx)` | Wraps `item` in a new slot and emits `ItemStoredEvent<Item>` | none |
| `withdraw<Item>(player, item_id)` | Returns the item and emits `ItemWithdrawnEvent<Item>` | `ELocked` (0); `EFieldDoesNotExist` / `EFieldTypeMismatch` at `sui::dynamic_field` |
| `lock<Item, Locker: drop>(player, item_id, witness)` | Adds `Locker`'s lock, returns `Lock<Item, Locker>`, emits `ItemLockedEvent<Item, Locker>` | `EAlreadyLocked` (1), `ETooManyLocks` (2); dynamic-field aborts as above |
| `unlock<Item, Locker>(player, item_id, lock)` | Consumes the `Lock`, removes `Locker`'s lock, emits `ItemUnlockedEvent<Item, Locker>` | dynamic-field aborts as above |
| `borrow<Item>(player, item_id)` | Lends the item by value with a `sui::borrow::Borrow` receipt, locked or not; emits nothing | dynamic-field aborts as above |
| `put_back<Item>(player, item, borrow)` | Returns a lent item to its slot; emits nothing | `EWrongValue` / `EWrongBorrow` at `sui::borrow`; dynamic-field aborts as above |

### Views

| Function | Returns |
|---|---|
| `has_item(player, item_id)` | `bool`, whether a slot exists |
| `locks<Item>(player, item_id)` | `&VecSet<TypeName>`, the current locker types |
| `max_locks()` | `u64`, 8 |

## Events

| Event | When | Payload |
|---|---|---|
| `ItemStoredEvent<Item>` | `store` | `player_id: ID`, `item_id: ID` |
| `ItemWithdrawnEvent<Item>` | `withdraw` | `player_id: ID`, `item_id: ID` |
| `ItemLockedEvent<Item, Locker>` | `lock` | `player_id: ID`, `item_id: ID` |
| `ItemUnlockedEvent<Item, Locker>` | `unlock` | `player_id: ID`, `item_id: ID` |

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `ELocked` | `withdraw` while any lock is held |
| 1 | `EAlreadyLocked` | `lock` by a locker type that already holds a lock on the item |
| 2 | `ETooManyLocks` | `lock` when the item already has `MAX_LOCKS` locks |

`EFieldDoesNotExist` (1) and `EFieldTypeMismatch` (2) surface from
`sui::dynamic_field` for an absent item or a wrong `Item` type. `EWrongBorrow`
(0) and `EWrongValue` (1) surface from `sui::borrow` when `put_back` gets
another item or another slot's receipt.

## Dependencies

- [`player`](../player), by local path: the `Player` whose UID holds the slots.

## Integrator notes

- **Holding the `Lock` is the authority to unlock.** `Lock<Item, Locker>` has
  only `store`: it cannot be copied or dropped, only this package creates one,
  and only `unlock` destroys it. Store it in the locking extension's own state.
- **The witness makes the locker type trustworthy.** Only the module that
  defines `Locker` can construct one, so a lock of type `Locker` was taken by
  that module.
- **Locks never expire.** An item stays locked until its locker calls
  `unlock`. A locker with no path to `unlock` strands the item for good, so
  only lock through extensions you trust; which ones is a client decision.
- **Locks stop withdrawal, not lending.** `borrow` works while locked, and the
  `Borrow` receipt has no abilities, so the transaction aborts unless the same
  item is put back. A lent item can be read, mutated, or passed by value, for
  example to `record_access::claim`, but cannot leave the Player.
- **Writes need `&mut Player`,** so only the Player's owner can store,
  withdraw, lock or unlock.
- **Stored objects are wrapped.** They are no longer top-level objects;
  follow them through the events, or read them off-chain through the
  Player's dynamic fields under the key type `SlotKey`.
