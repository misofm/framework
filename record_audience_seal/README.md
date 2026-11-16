# record_audience_seal

Reusable Seal audiences of Record holders. A `RecordAudience` is a shared
object holding, per release, the edition and number bounds whose holders may
decrypt, edited by whoever holds its `RecordAudienceAdminCap`. Data is
encrypted to the audience's ID, so editing the rules changes who can fetch keys
for everything already encrypted to it, with no re-encryption: an artist adds
a new album to "All my albums" once. Audiences belong to no Party or release;
anyone can create one and use it for any data. The `record_audience` module
holds the audience and its rules; the `seal` module holds the Seal policy.

## What it stores

- `RecordAudience`, a shared object:

  | Field | Type | Meaning |
  |---|---|---|
  | `rules` | `Table<ID, RecordAudienceRule>` | Release ID to its rule, at most `MAX_RULES` (1000) |

- `RecordAudienceAdminCap { audience_id }`, `key + store`, one per audience,
  returned by `new`. It can be transferred or wrapped.
- `RecordAudienceRule { edition_min, edition_max, number_min, number_max }`,
  each an inclusive `Option` bound where `None` is unbounded. Built with
  `new_rule`, which requires `min <= max` when both are set.
- One rule per release; setting it again replaces it in place. Removing it
  reclaims the entry. Audiences are never deleted.

The Seal identity, after the package ID Seal prefixes, is 64 bytes:

| Field | Type | Meaning |
|---|---|---|
| `audience_id` | `address` | The audience |
| `nonce` | `u256` | Distinguishes data under the same audience; not checked |

## API

### Writes (cap-gated)

Both take the audience's `&RecordAudienceAdminCap`.

| Function | Description | Aborts |
|---|---|---|
| `set_rule(audience, cap, release_id, rule)` | Sets the release's rule; emits `RecordAudienceRuleSetEvent`, nothing when the rule is unchanged | `EUnauthorized` (0), `ETooManyRules` (1) |
| `remove_rule(audience, cap, release_id)` | Removes the release's rule; emits `RecordAudienceRuleRemovedEvent`, nothing when absent | `EUnauthorized` (0) |

### Constructors

| Function | Returns | Aborts |
|---|---|---|
| `new(ctx)` | Shares an empty `RecordAudience` and returns its `RecordAudienceAdminCap`; emits `RecordAudienceCreatedEvent` | none |
| `new_rule(edition_min, edition_max, number_min, number_max)` | `RecordAudienceRule` | `EInvalidRange` (2) |

### Views

| Function | Returns |
|---|---|
| `admin_cap_audience_id(cap)` | `ID` of the cap's audience |
| `rule_count(audience)` | `u64` |
| `has_rule(audience, release_id)` | `bool` |
| `rule(audience, release_id)` | `RecordAudienceRule`; aborts `ERuleNotFound` (3) if absent |
| `edition_min(rule)`, `edition_max(rule)` | `Option<u16>` |
| `number_min(rule)`, `number_max(rule)` | `Option<u32>` |
| `max_rules()` | `u64`, 1000 |

### Seal policy

| Function | Description | Aborts |
|---|---|---|
| `seal::seal_approve(id, audience, access, ctx)` | Passes when `id` is this audience's, the caller is the `RecordAccess` owner, and the audience has a rule for its release whose bounds hold its edition and number | `EWrongAudience` (0), `ENotOwner` (1), `ENoMatchingRule` (2), all at `seal`; `EOutOfRange` at `sui::bcs` |

## Events

| Event | When | Payload |
|---|---|---|
| `RecordAudienceCreatedEvent` | `new` | `audience_id: ID`, `admin_cap_id: ID` |
| `RecordAudienceRuleSetEvent` | `set_rule` with a new or changed rule | `audience_id: ID`, `release_id: ID`, `rule: RecordAudienceRule` |
| `RecordAudienceRuleRemovedEvent` | `remove_rule` of a present rule | `audience_id: ID`, `release_id: ID` |

## Errors

`record_audience`:

| Code | Constant | Condition |
|---|---|---|
| 0 | `EUnauthorized` | The cap belongs to another audience |
| 1 | `ETooManyRules` | Adding a rule to an audience that already has 1000 |
| 2 | `EInvalidRange` | A bound's minimum is above its maximum |
| 3 | `ERuleNotFound` | `rule` for a release without one |

`seal`:

| Code | Constant | Condition |
|---|---|---|
| 0 | `EWrongAudience` | The identity names another audience or has bytes after the nonce |
| 1 | `ENotOwner` | Key request from an address other than the `RecordAccess` owner |
| 2 | `ENoMatchingRule` | No rule for the Record's release, or its edition or number is out of bounds |

A truncated identity aborts with `EOutOfRange` (0) at `sui::bcs`.

## Dependencies

- [`record_access`](../record_access), by local path: the `RecordAccess` whose
  owner, release, edition, and number the policy checks.

## Integrator notes

- **Seal PTBs call only `seal::seal_approve`,** with `id` as a pure input and the
  shared `RecordAudience` and the holder's shared `RecordAccess` as objects.
  The caller is the session key's address.
- **Use a new nonce for each piece of data.** A key fetched for an identity
  opens everything encrypted to it.
- **Edits apply to past data.** Adding a release opens everything already
  encrypted to the audience to its holders; removing one stops new key
  requests, but keys already fetched keep working.
- **Encrypt only to audiences whose cap you hold.** The cap holder decides who
  can read; another holder can widen or narrow it at any time.
- **Encryption is permissionless.** Anyone can encrypt to any audience; trust
  content by where it is listed, not by its identity.
- **Estimated reach is derived, not stored.** Count the Records whose release,
  edition, and number match a rule, from `record` events and the audience's
  rule events. Holders without a `RecordAccess` are counted but cannot decrypt
  until they create one.
- **Key servers read the full node's latest state,** so a rule change may take
  a moment to apply across servers.

## Build and test

```sh
sui move build --lint --warnings-are-errors
sui move build --lint --warnings-are-errors --build-env mainnet
sui move test --coverage --lint --warnings-are-errors
sui move coverage summary
```
