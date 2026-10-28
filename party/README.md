# Miso Party Extensions

Artist/entity profile pages on Sui, built as small, independent Move packages.
This directory is the `party` domain of [`misofm/framework`](../README.md).
The state-attaching profile **extensions** each add one coherent slice to a core
[`miso_party::party::Party`](https://github.com/misofm/party-protocol) as a
dynamic field — bio, roles, tags, imagery, and CTAs. Every package publishes
immutably and evolves through a new package when necessary; many small packages
beat one mega-struct.

Design principles, the field-placement rules (declare vs. derive vs. reference
vs. off-chain), and the phasing live in [ROADMAP.md](ROADMAP.md). The process
for documenting an extension — required reading before adding one — lives in
[AGENTS.md](AGENTS.md).

## Architecture

- **Optional group relations.** `party_group` owns a derived, shared `Group` object per Party. Its membership and invitation storage, bounds, consent rules, and events are outside core. It authorizes group and member operations through the matching Party capabilities without mutating either Party.

- **One slice per state-attaching extension.** Each such package owns its
  dynamic-field key(s) and values on the party's `UID`. Distinct key types
  prevent collisions.
- **Cap-gated state.** Every state-attaching write goes through
  `party::uid_mut(cap)`, and its views are permissionless.
- **Shared primitives do the mechanics.** Immutable
  [`unconfirmedlabs/typed_set`](https://github.com/unconfirmedlabs/typed_set)
  stores one bounded `VecSet<T>` per key type on any `UID`. Extensions keep
  only their domain types, validation, and events — never re-implement storage.
- **Reference, don't embed.** Media is a Walrus blob id. Nothing large or
  derivable is copied on-chain.

## Packages

### Primitives (object-agnostic, no Miso dependencies)

| Package | Owns |
|---|---|
| [`unconfirmedlabs/typed_set`](https://github.com/unconfirmedlabs/typed_set) | One bounded `VecSet<T>` per key type per `UID` — init-on-add, dup/max checks, field reclamation |
| [`genre`](../lib/genre) | The canonical genre vocabulary, shared with the music extensions |

### State-attaching extensions (gated by `PartyAdminCap`)

| Package | Owns |
|---|---|
| [`party_name`](party_name) | Display name: one `String` |
| [`party_profile`](party_profile) | Profile card: `bio_short`, `bio_long`, `country`, `languages` (validated code types) |
| [`party_genre`](party_genre) | Genre-id set, proven at write time against the `genre` vocabulary |
| [`party_roles`](party_roles) | Artist-type set: Artist/Producer/DJ/Composer/Songwriter/Band/Label/Collective + `Custom` |
| [`party_tags`](party_tags) | Free-form tag set (moods, scenes, descriptors) |
| [`party_media`](party_media) | Imagery: one Walrus quilt blob id (avatar/header are quilt patches, a client convention) |
| [`party_cta`](party_cta) | Ordered external call-to-action links (`{ label, url }`, position is priority) |

### Relational extensions

| Package | Owns |
|---|---|
| [`party_group`](party_group) | Optional shared group state, bounded invitations and members, consent, exit, and removal |

Group relations describe an optional relationship model. Payment, custody, and
other operational Party workflows are not profile extensions; they are Actions.

### Actions (raw `PartyAdminCap`, custody-agnostic)

| Package | Owns |
|---|---|
| [`party_wallet`](party_wallet) | Receive Party-addressed `key + store` objects and coins, or redeem Party accumulator funds, returning every asset to the caller |

## Extensions, Actions, and Plugins

The Party packages separate three kinds of package:

- **Extension**: a persistent, namespaced data slice attached to a `Party`.
- **Action**: public business logic that accepts the raw capability and returns
  caller-controlled assets for composition in the same PTB. Actions define no
  plugin witnesses, installation records, recipient policy, or Vault custody. A
  caller may hold a `PartyAdminCap` directly or borrow it from any compatible
  custody system such as [`vault`](../lib/vault), call an Action, and return the
  cap before the transaction ends.
- **Plugin**: installed, permissionless automation backed by a capability
  Vault. A plugin is a separate entry-only package that calls an Action rather
  than reimplementing it.

There is intentionally no Party wallet plugin. Every useful `party_wallet`
operation returns an object or `Balance` controlled by the caller, so
permissionless automation would create an extraction path rather than a safe
crank.

- Never send the sole matching `PartyAdminCap` to its own Party inbox:
  receiving from that inbox requires the same cap, creating a circular
  authorization lock.
- `party_wallet` can receive only `key + store` objects. Objects without
  `store` sent to the Party address are unrecoverable through this API.

## Conventions

- **Events are sufficient for indexing.** Dynamic-field mutations are not
  observable off-chain, so every state change emits an event carrying
  `party_id`, and an indexer never needs a secondary lookup: set events carry
  the full new value, add/remove events the entry, clears the key. See
  [EVENT_PAYLOADS.md](EVENT_PAYLOADS.md) for the inventory and payload bounds.
- **Validation is split on purpose.** Primitives enforce set mechanics
  (duplicate / not-present / over-max — aborts come from `typed_set` with its
  codes). Extensions enforce domain rules
  (non-empty, length, vocabulary proofs) before calling in. Format rules for
  handles and URLs are deliberately *not* on-chain — they change over time and
  belong to the app layer.
- **Stored URLs are untrusted input.** Frontends must sanitize before
  rendering (e.g. reject `javascript:` URLs).
- **Dependencies are exact.** Packages in this repository depend on each other
  by local path. Every dependency outside it is a Git dependency pinned to a
  full 40-character commit SHA, never `main` or `master`.
- **Packages are immutable.** No extension relies on an upgrade path. A future
  incompatible data model ships as a new package with an explicit migration.
- **State-attaching tests always include the wrong cap.** Every state-attaching
  extension has an `expected_failure` test proving another party's
  `PartyAdminCap` aborts (`EUnauthorized` at `miso_party::party`).

## Published metadata

Every package's retained `Published.toml` records a prior immutable Testnet
generation. Where the pending source or dependency inputs differ, that block is
historical metadata—not an identity for the pending bytecode. A fresh immutable
stack publication uses the admin CLI with `--allow-republish`; it replaces only
the target network block, and only after the transaction is confirmed
successful.

## Build & test

Each package is independent. From a package directory, such as
`party/party_name`:

```bash
sui move build
sui move test
```

## License

[Functional Source License 1.1, ALv2 Future License](../LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.

## Group-Extension Source Generation

State-attaching packages now pin the identity-only Party core at
`4648895667e94103481f2f59354d62ad021a792e`. Their tests use `party::new(ctx)`.
The constructor no longer takes `PartyKind` or a name, and `PartyCreatedEvent` no
longer contains `is_group` or `name`; the name lives in [`party_name`](party_name). Existing deployed package records are retained unchanged;
this branch does not publish a new on-chain generation.

Group applications use the optional [`party_group`](party_group) package. Its
shared `Group` owns the canonical direct-member and pending-invite sets for that
extension generation. A group need not impose its storage model on core Party.
