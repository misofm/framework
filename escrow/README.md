# escrow

A two-step, peer-to-peer transfer of any `Item: key + store`. The sender puts
the item in escrow for one recipient; the recipient accepts or declines; only
after an accept can the sender complete the transfer, and the sender can cancel
and take the item back at any point before that. Nothing moves to an address
that has not agreed to take it, so a typo in the recipient address costs
nothing. The package is protocol-agnostic: it knows nothing about parties or
works. There is no docs.miso.fm page yet, so the facts are below.

```toml
escrow = { git = "https://github.com/misofm/framework.git", subdir = "escrow", rev = "<commit>" }
```

## What it stores

- **`Escrow<Item>`** (`key, store`): `item`, `nonce`, `sender`, `recipient` and
  `state`. Its UID is `derived_object::claim(registry, EscrowKey(item_id))`, so
  its ID is a pure function of the registry ID and the item's ID. It is stored
  as a dynamic object field of the registry under `EscrowKey(item_id)`, and is
  never shared or returned.
- **`EscrowSenderCap<Item>`** and **`EscrowRecipientCap<Item>`** (`key` only):
  `item_id` and `nonce`. `Item` is a phantom of the escrowed item's type.
- **`EscrowRegistry`** (`key`), shared by `init`: `next_nonce`, the nonce the
  next escrow gets.
- **`EscrowState`** (`copy, drop, store`): `Pending`, `Accepted` or `Declined`.
- **Teardown.** `complete` and `cancel` remove the escrow, release its derived
  UID and delete the sender cap, so the registry keeps no record of a finished
  escrow and the same item can be escrowed again at the same ID.
- No capacities: an item is in at most one escrow, because the escrow holds it.

| State | Reached by | Recipient cap | Sender cap |
|---|---|---|---|
| Pending | `new` | `accept`, `decline` | `cancel` |
| Accepted | `accept` | deleted | `complete`, `cancel` |
| Declined | `decline` | deleted | `cancel` |

## API

### Writes (cap-gated)

| Function | Description | Aborts |
|---|---|---|
| `new(registry, item, recipient, ctx)` | Escrows `item` for `recipient` (Pending) and sends each side its cap. Takes no cap: the item by value is the authority. | `ESelfTransfer` |
| `accept(registry, recipient_cap)` | Pending to Accepted; deletes the recipient cap | `EStaleCap`, `EWrongState`; `EFieldDoesNotExist` at `sui::dynamic_field` once the escrow was cancelled |
| `decline(registry, recipient_cap)` | Pending to Declined; deletes the recipient cap | as `accept` |
| `complete(registry, sender_cap)` | From Accepted: removes and releases the escrow, deletes the sender cap and sends the item to `recipient` | `EWrongState` |
| `cancel(registry, sender_cap)` | From any state: removes and releases the escrow, deletes the sender cap and sends the item back to `sender` | none |
| `burn_recipient_cap(registry, recipient_cap)` | Deletes a recipient cap whose escrow was cancelled: no escrow of the item exists, or the one that does has another nonce | `EEscrowPending` |

### Views

| Function | Returns |
|---|---|
| `derive_address(registry, item_id)` | The escrow's address for that item, whether or not it exists |
| `exists(registry, item_id)` | Whether the item is in escrow |
| `borrow<Item>(registry, item_id)` | `&Escrow<Item>`; aborts `EFieldDoesNotExist` at `sui::dynamic_field` when the item isn't in escrow, `EFieldTypeMismatch` for another `Item` |
| `nonce(self)`, `sender(self)`, `recipient(self)`, `state(self)` | The escrow's fields |
| `escrow_state_is_pending(state)`, `escrow_state_is_accepted(state)`, `escrow_state_is_declined(state)` | Which `EscrowState` it is; also `state.is_pending()` and so on |

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

`item_type` is `type_name::with_defining_ids<Item>()`. The `nonce` names one
escrow: `escrow_id` repeats when an item is escrowed again, the nonce never
does. A `Pending` state in `EscrowCancelledEvent` means the recipient cap is
still outstanding until it is burned.

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `ESelfTransfer` | `new` with `recipient` equal to the sender |
| 1 | `EStaleCap` | `accept` or `decline` with the recipient cap of a cancelled escrow while a later escrow of the same item is live |
| 2 | `EWrongState` | `complete` before the recipient accepted (Pending or Declined); also guards `accept` and `decline` against a non-Pending escrow |
| 3 | `EEscrowPending` | `burn_recipient_cap` with the cap of a live escrow; use `decline` instead |
| 1 | `EFieldDoesNotExist` at `sui::dynamic_field` | `accept` or `decline` with the recipient cap of a cancelled escrow and no later escrow; `borrow` of an item not in escrow; any cap with a registry other than the one it was issued by |

## Dependencies

None beyond the Sui framework and Move stdlib (`derived_object`,
`dynamic_object_field`, `event`, `type_name`).

## Integrator notes

- **Finding escrows.** A sender's outgoing escrows are the
  `EscrowSenderCap<Item>` objects it owns; a recipient's inbox is its
  `EscrowRecipientCap<Item>` objects. List owned objects filtered by the struct
  type without type parameters to get every `Item`. Each cap's `item_id` gives
  the escrow at `derive_address(registry, item_id)`, which can be fetched as an
  object.
- **The nonce prevents stale caps.** The registry hands each escrow the next
  `u64` nonce, and the escrow and both caps record it. Every cap function finds
  the escrow by the cap's `item_id` and aborts `EStaleCap` unless the nonces
  match. Because a cancelled escrow's ID is released, a re-escrow of the same
  item gets the same `escrow_id`; without the nonce, the first recipient's cap
  would act on the new escrow.
- **Two bindings, two jobs.** The caps' phantom `Item` is not authority: many
  objects share a type. It names the item's type for the generic calls and for
  inbox listings. Authority is the `item_id` and `nonce` binding.
- **Which caps can be stale.** The sender cap is deleted with its escrow, so
  it is never stale. The recipient cap is deleted by `accept` and `decline`,
  so it outlives its escrow only when the sender cancels while Pending. A cap
  that matches its escrow therefore always finds it Pending; the `EWrongState`
  check in `accept` and `decline` is defensive.
- **Cleaning up.** The holder of a stale recipient cap calls
  `burn_recipient_cap` for its storage rebate. A sender cap ends only with
  `complete` or `cancel`.
- **Transfers are the mechanic.** `new` sends the caps with
  `transfer::transfer` because they have no `store`, so a caller could not send
  them on. `complete` and `cancel` send the item with `transfer::public_transfer`
  to the stored recipient or sender, so no caller chooses where it goes. None of
  these functions returns a value.
- **Released, not claim-once.** Derived children are normally permanent
  identity. An escrow is the exception: `complete` and `cancel` call
  `derived_object::release` so the item can be escrowed again, which the nonce
  makes safe. The escrow is never shared, so `release` cannot hit
  `ESharedObjectRelease`.
- **The item is not readable while escrowed.** It is wrapped in the escrow, so
  it can't be fetched by its own ID, and there is deliberately no `&Item` view:
  some packages authorize with a reference to a capability, and a public
  `&Item` would let anyone use an escrowed capability. Clients read the escrow
  object's contents off-chain.
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
  Key escrows by `nonce`.

## Build and test

```sh
sui move build --lint --warnings-are-errors --build-env testnet
sui move build --lint --warnings-are-errors --build-env mainnet
sui move test --coverage --lint --warnings-are-errors
sui move coverage summary
```

This package has not been audited.

## Deployments

Testnet `0x01b13c44138c2e9f73b5000519994b284db83c77680e4af82a3ffd41687a0fb4`
(tx `8NnKwEDfxsVb22bfco6xGFUhdJEs6FMeUP6o1Zbcm7Yi`), immutable. Its shared
`EscrowRegistry` is
`0x15b03521499649863885211c44b640bd1603e304179529d97d0898d4b7b24667`. The
first generation, superseded before use, stays published on testnet at
`0x62b270e99556b3b6a0707bdc29b655c7ae53e6a6778edd766a8a9890cef0743a` with
registry `0xbf76c52782365780bf21bab3746ceb725afbf70f6321dc662c66ae6d852b36b8`.
Mainnet `0x4aea154ff446a3799d378d652b6fb62eb0e9ea00a163f6a820bed4913a4154e6`
(tx `qm8nRyV3A5hS9gQ6GDe5EurNtBsLZXjkiyJypqcEUCg`), `EscrowRegistry`
`0xda532cd2ae88288f0145ca65086981737fe112da23980318ad156b701a583351`.

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
