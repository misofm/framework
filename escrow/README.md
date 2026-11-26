# escrow

A two-step, peer-to-peer transfer of any `T: key + store`. The sender puts the
item in escrow for one recipient; the recipient accepts or declines; only after
an accept can the sender complete the transfer, and the sender can cancel and
take the item back at any point before that. Nothing moves to an address that
has not agreed to take it, so a typo in the recipient address costs nothing.
The package is protocol-agnostic: it knows nothing about parties or works.

## What it stores

- **`EscrowRegistry`** (`key`), shared by `init`: `id` and `next_nonce: u64`,
  the nonce the next escrow gets.
- **`Escrow<T>`** (`key, store`): `item: T`, `nonce`, `sender`, `recipient` and
  `state: EscrowState`. Its UID is `derived_object::claim(registry, EscrowKey(item_id))`,
  so its ID is a pure function of the registry ID and the item's ID. It is
  stored as a dynamic object field of the registry under `EscrowKey(item_id)`,
  and is never shared or returned.
- **`EscrowState`** (`copy, drop, store`): `Pending`, `Accepted` or `Declined`.
- **`EscrowSenderCap<T>`** and **`EscrowRecipientCap<T>`** (`key` only):
  `escrow_id`, `item_id` and `nonce`. `new` sends them with `transfer::transfer`
  to the sender and the recipient. Without `store` they can't be transferred,
  wrapped, shared or frozen, so each stays with its address. `T` is a phantom
  of the escrowed item's type.
- **Teardown.** `complete` and `cancel` remove the escrow, `derived_object::release`
  its UID and delete the sender cap, so the registry keeps no record of a
  finished escrow and the same item can be escrowed again at the same ID.
- No limits: one escrow per item, and an item can be in at most one escrow
  because the escrow holds it.

| State | Reached by | Recipient cap | Sender cap |
|---|---|---|---|
| Pending | `new` | `accept`, `decline` | `cancel` |
| Accepted | `accept` | deleted | `complete`, `cancel` |
| Declined | `decline` | deleted | `cancel` |

## API

### Writes (cap-gated)

| Function | Description | Aborts |
|---|---|---|
| `new<T>(registry: &mut EscrowRegistry, item: T, recipient: address, ctx: &mut TxContext)` | Escrows `item` for `recipient` (Pending) and sends both caps. Not cap-gated: the item by value is the authority. | `ESelfTransfer`; `derived_object::EObjectAlreadyExists` is unreachable, since an escrowed item can't be passed again |
| `accept<T>(registry: &mut EscrowRegistry, recipient_cap: EscrowRecipientCap<T>)` | Pending to Accepted; deletes the recipient cap | `EEscrowNotFound`, `EStaleCap`, `EWrongState` |
| `decline<T>(registry: &mut EscrowRegistry, recipient_cap: EscrowRecipientCap<T>)` | Pending to Declined; deletes the recipient cap | `EEscrowNotFound`, `EStaleCap`, `EWrongState` |
| `complete<T>(registry: &mut EscrowRegistry, sender_cap: EscrowSenderCap<T>)` | From Accepted: removes and releases the escrow, deletes the sender cap and sends the item to `recipient` | `EWrongState` |
| `cancel<T>(registry: &mut EscrowRegistry, sender_cap: EscrowSenderCap<T>)` | From any state: removes and releases the escrow, deletes the sender cap and sends the item back to `sender` | none |
| `burn_recipient_cap<T>(registry: &EscrowRegistry, recipient_cap: EscrowRecipientCap<T>)` | Deletes a recipient cap whose escrow was cancelled: no escrow of the item exists, or the one that does has another nonce | `EEscrowPending` |

### Views

| Function | Returns |
|---|---|
| `derive_address(registry, item_id)` | The escrow's address for that item, whether or not it exists |
| `exists(registry, item_id)` | Whether the item is in escrow |
| `borrow<T>(registry, item_id)` | `&Escrow<T>`; aborts `EEscrowNotFound` when the item isn't in escrow |
| `escrow.nonce()`, `escrow.sender()`, `escrow.recipient()`, `escrow.state()` | The escrow's fields |
| `state.is_pending()`, `state.is_accepted()`, `state.is_declined()` | Which `EscrowState` it is |

There is no view of the item itself: see Integrator notes.

## Events

| Event | When | Payload |
|---|---|---|
| `EscrowCreatedEvent` | `new` | `escrow_id`, `item_id`, `item_type: TypeName`, `nonce`, `sender`, `recipient`, `sender_cap_id`, `recipient_cap_id` |
| `EscrowAcceptedEvent` | `accept` | `escrow_id`, `item_id`, `nonce`, `sender`, `recipient` |
| `EscrowDeclinedEvent` | `decline` | `escrow_id`, `item_id`, `nonce`, `sender`, `recipient` |
| `EscrowCompletedEvent` | `complete`; the item went to `recipient` | `escrow_id`, `item_id`, `nonce`, `sender`, `recipient` |
| `EscrowCancelledEvent` | `cancel`; the item went back to `sender` | `escrow_id`, `item_id`, `nonce`, `sender`, `recipient`, `state: EscrowState` (the state it was cancelled from) |
| `EscrowRecipientCapBurnedEvent` | `burn_recipient_cap` | `escrow_id`, `item_id`, `nonce`, `recipient_cap_id` |

`item_type` is `type_name::with_defining_ids<T>()`. The `nonce` names one
escrow: `escrow_id` repeats when an item is escrowed again, the nonce never
does. A `Pending` state in `EscrowCancelledEvent` means the recipient cap is
still outstanding until it is burned.

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `ESelfTransfer` | `new` with `recipient` equal to the sender |
| 1 | `EEscrowNotFound` | The item is not in escrow: `borrow`, or `accept`/`decline` with the recipient cap of a cancelled escrow |
| 2 | `EStaleCap` | `accept`/`decline` with the recipient cap of a cancelled escrow while a later escrow of the same item is live |
| 3 | `EWrongState` | `complete` before the recipient accepted (Pending or Declined); also guards `accept`/`decline` against a non-Pending escrow |
| 4 | `EEscrowPending` | `burn_recipient_cap` with the cap of a live escrow; use `decline` instead |

`borrow<T>` with a `T` other than the item's type aborts with
`EFieldTypeMismatch` at `sui::dynamic_field`. The cap functions can't hit it:
a cap's `T` is the item's type.

## Dependencies

None beyond the Sui framework and Move stdlib (`derived_object`,
`dynamic_object_field`, `event`, `type_name`).

## Integrator notes

- **Finding escrows.** A sender's outgoing escrows are the
  `EscrowSenderCap<T>` objects it owns; a recipient's inbox is its
  `EscrowRecipientCap<T>` objects. List owned objects filtered by the struct
  type without type parameters to get every `T`. Each cap carries `item_id`
  and `escrow_id`; the escrow object can be fetched by `escrow_id` (also
  `derive_address(registry, item_id)`), and its type `Escrow<T>` gives `T`.
- **The nonce prevents stale caps.** The registry hands each escrow the next
  `u64` nonce, and the escrow and both caps record it. Every cap function finds
  the escrow by the cap's `item_id` and aborts `EStaleCap` unless the nonces
  match. Because a cancelled escrow's ID is released, a re-escrow of the same
  item gets the same `escrow_id`; without the nonce, the first recipient's cap
  would act on the new escrow.
- **Which caps can be stale.** The sender cap is deleted with its escrow, so
  it is never stale. The recipient cap is deleted by `accept` and `decline`,
  so it outlives its escrow only when the sender cancels while Pending. A cap
  that matches its escrow therefore always finds it Pending; the
  `EWrongState` check in `accept` and `decline` is defensive.
- **Cleaning up.** The holder of a stale recipient cap calls
  `burn_recipient_cap` for its storage rebate. There is no way to burn a
  sender cap except `complete` or `cancel`.
- **The item is not readable while escrowed.** It is wrapped in the escrow, so
  it can't be fetched by its own ID, and there is deliberately no `&T` view:
  some packages authorize with a reference to a capability (`&Cap`), and a
  public `&T` would let anyone use an escrowed capability. Clients read the
  escrow object's contents off-chain.
- **Account addresses only.** Caps have no `store`, so an object address (a
  Party, a Player) can never receive one: a recipient that is an object can
  never accept, and the sender can only cancel. The sender is always the
  transaction signer.
- **Objects sent to the escrow's address are not recoverable** through this
  package; it has no receive function.
- **The registry is one shared object.** Every write takes it mutably, so all
  escrows serialize on it; `burn_recipient_cap` and the views take it
  immutably.
- **No expiry and no Clock.** A Pending or Accepted escrow lasts until the
  sender cancels or completes it.
- **Rebuilding from events.** `EscrowCreatedEvent` carries every stored field.
  Accepted and Declined set the state; Completed and Cancelled end the escrow.
  Key escrows by `nonce` (or by `escrow_id` in event order).

## Build and test

```sh
sui move build --lint --warnings-are-errors --build-env testnet
sui move build --lint --warnings-are-errors --build-env mainnet
sui move test --coverage --lint --warnings-are-errors
sui move coverage summary
```

This package has not been audited.

## Deployments

Testnet `0x62b270e99556b3b6a0707bdc29b655c7ae53e6a6778edd766a8a9890cef0743a`
(tx `4BEiYN1JBT9Pw6ZiBxUpea3gifbyBV1uyjdqW4Weu5RB`), immutable. Its shared
`EscrowRegistry` is
`0xbf76c52782365780bf21bab3746ceb725afbf70f6321dc662c66ae6d852b36b8`. Not
published on mainnet.

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
