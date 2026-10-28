# Event payload policy

An indexer that sees every event of these packages, plus the transaction
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
- **Cascades** emit their own events: `recording_credits::remove_credit`
  emits the artist-removed event for each designation it ends before
  `RecordingCreditRemovedEvent`.
- **Derived state** is left to replay where the stream alone determines it:
  list order and the primary genre (index 0) follow the ordered add/remove
  events, and a record's presence (`has_credits`, `has_genres`,
  `has_cover_art`) follows from whether any replayed entry remains.
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
