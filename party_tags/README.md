# party_tags

Free-form tags for a party — moods, scenes, and descriptors ("ambient",
"deconstructed club", "leftfield pop"). The uncurated sibling to
`party_genre`: genres reference a canonical, shared vocabulary; tags are
whatever the artist types.

The set mechanics — storage, duplicate and capacity checks, field
reclamation — live in the shared `typed_set` primitive; this package keeps
only what is tag-specific: length validation, the capacity, and the typed
events. Tags are stored exactly as given, so dedupe is exact-match and
normalization for search or display is a client concern. Writes are gated by
the `PartyAdminCap` through `party::uid_mut(cap)`; views are permissionless.

## What it stores

- Key: `PartyTagsKey` — a unit struct local to this package, so the tag set never
  collides with another consumer's set on the same `UID`.
- Value: a bare `VecSet<String>` under that key, managed through `typed_set`
  — no wrapper struct.
- Limits: a tag is 1–50 bytes (`MAX_TAG_LENGTH`); a party carries at most 30
  tags (`MAX_TAGS`).
- Reclamation: removing the last tag drops the whole dynamic field — an empty
  set is indistinguishable from none, and the storage rebate goes back to the
  payer.

## API

All writes require the matching `PartyAdminCap`. `add_tag` validates empty and
overlong tags before authorization; after those checks, a wrong cap aborts with
`EUnauthorized` at `miso_party::party`. Views are permissionless.

### Writes (cap-gated)

| Function | Description | Aborts |
|---|---|---|
| `add_tag(party, cap, tag)` | Add a tag; empty/length checks run here, set checks in `typed_set` | `EEmptyTag` (0), `ETagTooLong` (1); `EDuplicateItem` (0) and `EMaxItemsExceeded` (2) at `typed_set::typed_set` |
| `remove_tag(party, cap, tag)` | Remove a tag; reclaims the field when the last tag leaves | `EItemNotPresent` (1) at `typed_set::typed_set` |
| `clear_tags(party, cap)` | Remove the entire tag set | — (no-op when none is set) |

### Views

| Function | Returns |
|---|---|
| `has_tags(party)` | Whether the party carries any tags |
| `has_tag(party, tag)` | Whether the party carries the given tag |
| `tags(party)` | `vector<String>` — the party's tags, in insertion order; aborts `ENoTags` (2) when the party has none |

## Events

| Event | When | Payload |
|---|---|---|
| `PartyTagAddedEvent` | `add_tag` succeeds | `party_id: ID`, `tag: String` (at most 83 bytes) |
| `PartyTagRemovedEvent` | `remove_tag` succeeds | `party_id: ID`, `tag: String` (at most 83 bytes) |
| `PartyTagsClearedEvent` | `clear_tags` removes an existing set (not emitted on the no-op path) | `party_id: ID` (32 bytes) |

## Errors

Local to this package (abort location `party_tags::party_tags`):

| Code | Constant | Condition |
|---|---|---|
| 0 | `EEmptyTag` | `add_tag` with an empty tag |
| 1 | `ETagTooLong` | `add_tag` with a tag over `MAX_TAG_LENGTH` (50 bytes) |
| 2 | `ENoTags` | `tags` with no tags set |

Surfaced from `typed_set` (abort location `typed_set::typed_set`):

| Code | Constant | Condition |
|---|---|---|
| 0 | `EDuplicateItem` | `add_tag` with a tag the party already carries |
| 1 | `EItemNotPresent` | `remove_tag` for a tag that is not carried (or no set at all) |
| 2 | `EMaxItemsExceeded` | `add_tag` when the party already carries `MAX_TAGS` (30) |

## Dependencies

- [`miso_party`](https://github.com/misofm/party-protocol) at
  `238315acd356460f60df078eca1273461722bf33` — the authorization core.
- [`typed_set`](https://github.com/unconfirmedlabs/typed_set) at
  `b37474cbde166b7ddf8a3b615cd89f90182ace6f` — dynamic-field set storage,
  duplicate/not-present/capacity aborts, and field reclamation.

Both are exact Git pins; this manifest has no local-path dependencies.

## Integrator notes

- **Exact-match dedupe.** Tags are stored as typed: "Ambient" and "ambient"
  are two different tags. Case-folding and trimming for search or display
  happen client-side; the chain will not normalize for you.
- **Untrusted input.** A tag is free-form artist input, bounded only at 50
  bytes — sanitize before rendering.
- **Events carry the tag.** An indexer maintains the ordered set from
  `PartyTagAddedEvent` / `PartyTagRemovedEvent` alone; on `PartyTagsClearedEvent`, drop the
  whole set.
- **`has_tags` means "carries tags"**, not "has ever tagged" — the field is
  reclaimed when the last tag leaves.
- `tags()` returns insertion order, not alphabetical — sort client-side if
  the display needs it.
