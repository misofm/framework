# Event payloads

Events are sufficient for indexing: an indexer never needs a secondary lookup.
Each package README lists its own events.

## Music extensions

An indexer that sees every event of the music extensions, plus the transaction
envelope, can build and keep current its index of every extension value
without reading object storage or making an RPC call.

Extension events identify the changed subject by its object ID
(`composition_id`, `recording_id`, or `release_id`). Composition and Recording
events carry no share type parameters; authorization uses the subject's
matching admin capability, not a currency type.

- **Set and add events** carry the new value in full: titles, kinds, version
  names, descriptions, the compressed lyrics bytes, language lists, advisory
  enums, cover-art blob IDs, and each added credit with its display name and
  roles (instrument names and levels included).
- **Remove and clear events** carry the key of what was removed (language,
  party, genre, or track index); the indexer already holds the prior value.
- **Derived state** is left to replay where the stream alone determines it:
  list order follows the ordered add/remove events, and a record's presence
  (`has_credits`, `has_cover_art`) follows from whether any replayed entry
  remains.
- Equal sets and absent clears emit nothing, so every event is a transition.
  Capability IDs, senders, timestamps, and other envelope data are not
  duplicated in payloads.

There is no payload byte cap below Sui's 250 KiB per-event limit. The largest
events are `CompositionLyricsSetEvent` (32,806 bytes for a 32,768-byte body),
`ReleaseDescriptionSetEvent` (8,226 bytes for an 8,192-byte description), and
`RecordingCreditAddedEvent` (1,307 bytes for a 200-byte display name and ten
instrumentalist roles with 100-byte instrument names).

Each package README lists its current events, fields, and payload sizes. Those
sizes describe BCS payload bytes, excluding the transaction and event envelope;
they are not gas or throughput measurements.

Indexers use the event types of the package generation they follow and read
the subject ID from each event. Old event types remain associated with their
previous deployments. Core publication and release tracks do not make
metadata events evidence of economic ownership or licensing.

## Party extensions

### Rule

An indexer that sees every event of the party extensions, plus the transaction
envelope, can build and keep current its index of every party field they
manage without reading object storage or making an RPC call:

- **Set** events carry the full new value (bios, CTA lists).
- **Add/remove** events carry the full entry (tag, `ArtistRole`, genre ID and
  name).
- **Clear/remove-field** events carry only the key (`party_id`); the indexer
  already holds the old value.
- Equal-value replacements and absent clears emit nothing; a first attachment,
  including an explicitly empty value, emits.
- One event per action. IDs use `ID`; enums are emitted as values, never
  numeric codes. Sender, digest and checkpoint data stay in the envelope.

There is no byte cap beyond Sui's 250 KiB per-event limit; every bound below
is far under it.

### All declared events

| Package | Event | Fields (declaration order) |
|---|---|---|
| `party_group` | `PartyMemberAddedEvent`, `PartyGroupInviteDeclinedEvent` | `group_id: ID`, `member_id: ID`, `invite_id: ID` |
| `party_group` | `PartyMemberRemovedEvent`, `PartyGroupJoinedEvent`, `PartyGroupLeftEvent` | `group_id: ID`, `member_id: ID` |
| `party_genre` | `PartyGenreAddedEvent` | `party_id: ID`, `genre_id: ID`, `genre_name: String` |
| `party_genre` | `PartyGenreRemovedEvent` | `party_id: ID`, `genre_id: ID` |
| `party_profile` | `PartyProfileSetEvent` | `party_id: ID`, `bio_short: String`, `bio_long: Option<String>`, `country: Option<String>`, `languages: vector<String>` |
| `party_profile` | `PartyProfileClearedEvent` | `party_id: ID` |

There are 9 declarations, all emitted.

`party_group` has no Group object: `group_id` and `member_id` are both Party IDs, and `invite_id` is the `PartyGroupInvite` object ID. Membership has two halves, the group's `PartyMemberKey(member_id)` and the member's `PartyGroupMembershipKey(group_id)`. `PartyMemberAddedEvent` and `PartyMemberRemovedEvent` track the group's half, and `PartyGroupJoinedEvent` and `PartyGroupLeftEvent` track the member's half. `PartyGroupInviteDeclinedEvent` records the invite's deletion without joining. Apply all deltas in transaction order; a Party is a member only while both halves are present.

### Derived values

- Set sizes and `has_*` flags follow from the add/remove/clear stream.

### BCS payload bounds

Serialized payload bytes (type tags excluded). An `ID` or `u256` is 32 bytes;
strings and vectors carry a ULEB128 length; `Option` has a one-byte prefix.

| Event | Maximum bytes | Derivation |
|---|---:|---|
| `PartyMemberAddedEvent`, `PartyGroupInviteDeclinedEvent` | 96 | Three IDs; sizes do not depend on member or invitation counts |
| `PartyMemberRemovedEvent`, `PartyGroupJoinedEvent`, `PartyGroupLeftEvent` | 64 | Two IDs |
| `PartyCtasSetEvent` | 41,294 | `32 + (1 + 20 × (1 + 60)) + (2 + 20 × (2 + 2000))`; 34 when empty |
| `PartyCtasClearedEvent` | 32 | party ID |
| `PartyGenreAddedEvent` | 129 | `64 + 1 + 64` (genre names ≤64 B) |
| `PartyGenreRemovedEvent` | 64 | two IDs |
| `PartyMediaSetEvent` | 64 | ID + `u256` |
| `PartyMediaClearedEvent` | 32 | party ID |
| `PartyProfileSetEvent` | 8,564 | `32 + (2 + 300) + (1 + 2 + 8192) + (1 + 1 + 2) + (1 + 10 × 3)` |
| `PartyProfileClearedEvent` | 32 | party ID |
| `PartyRoleAddedEvent`, `PartyRoleRemovedEvent` | 94 | `32 + 1` variant `+ 1 + 60` for `Custom`; 33 for canonical roles |
| `PartyRolesClearedEvent` | 32 | party ID |
| `PartyTagAddedEvent`, `PartyTagRemovedEvent` | 83 | `32 + 1 + 50` |
| `PartyTagsClearedEvent` | 32 | party ID |

Tests serialize the maximum-content events and assert these sizes.
