# party_profile

A party's editable profile card — the free-form identity fields a profile page
renders: a short bio, an optional long bio, an optional country, and language
tags. The whole card is stored as one `Profile` dynamic field on the party's
UID and written in a single call (`set_profile`) — there are no per-field
setters. Only cohesive identity fields live here: typed or collection-shaped
concerns (roles, tags, genres, media, links) each have their own extension,
the party's name lives in `party_name`, and the join
date comes from the party's creation event (the indexer has it for free).
`country` and `languages` use validated code primitives (`country_code`,
`language_code`), so a stored value is always a real code. Each changed set
emits the full card, an existing clear emits the party ID; equal replacements
and absent clears are silent.

## What it stores

- Key: `PartyProfileKey()` (unit struct — one profile per party).
- Value: `Profile { bio_short: String, bio_long: Option<String>,
  country: Option<CountryCode>, languages: vector<LanguageCode> }`.
- Limits: `bio_short` 1–300 bytes (the only required field); `bio_long`
  1–8192 bytes when present (a storage backstop sized like `release_description`, not an editorial limit); up to 10 language tags, no duplicates.
- `set_profile` replaces in place — the card is overwritten, never stacked.
  `clear_profile` removes the dynamic field entirely (storage reclaimed) and
  is a no-op when no profile is set.

## API

All writes require `&PartyAdminCap` for the exact party; a wrong cap aborts
with `EUnauthorized` at `miso_party::party`.

### Writes (cap-gated)

| Function | Description | Aborts |
|---|---|---|
| `set_profile(party, cap, bio_short, bio_long, country, languages)` | Create or replace the whole profile card in one call; changed values emit the full card | validation errors below, all checked before authorization; wrong cap at `miso_party::party` |
| `clear_profile(party, cap)` | Remove the profile and emit `PartyProfileClearedEvent`; no-op when none is set (no event then) | wrong cap at `miso_party::party` |

### Views

| Function | Returns |
|---|---|
| `has_profile(party)` | `bool` — whether the party has a profile |
| `profile(party)` | `&Profile` — borrows the card; aborts `ENoProfile` (5) when none is set |
| `bio_short(&Profile)` | `String` |
| `bio_long(&Profile)` | `Option<String>` |
| `country(&Profile)` | `Option<CountryCode>` |
| `languages(&Profile)` | `vector<LanguageCode>` |

## Events

| Event | When | Payload |
|---|---|---|
| `PartyProfileSetEvent` | Profile created or replaced via `set_profile` when the complete value changes | `party_id: ID`, `bio_short: String`, `bio_long: Option<String>`, `country: Option<String>`, `languages: vector<String>` — at most 8,564 bytes |
| `PartyProfileClearedEvent` | Existing profile removed via `clear_profile` — not emitted when the call is a no-op | `party_id: ID` (32 bytes) |

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EEmptyBioShort` | `bio_short` is empty |
| 1 | `EBioShortTooLong` | `bio_short` exceeds 300 bytes |
| 2 | `EEmptyBioLong` | `bio_long` is `some("")` — empty when provided |
| 3 | `EBioLongTooLong` | `bio_long` exceeds 8192 bytes |
| 4 | `ETooManyLanguages` | More than 10 language tags |
| 5 | `ENoProfile` | `profile()` with no profile set |
| 6 | `ELanguageAlreadyListed` | A language tag appears more than once |

Both writes also surface `EUnauthorized` (0) at `miso_party::party` on a
wrong cap.

## Dependencies

- [`miso_party`](https://github.com/misofm/party-protocol) at
  `b2bd65ad735f4f94a62fb574a3a612fe1f0802c1` — the `Party` authorization
  core.
- [`country_code`](https://github.com/unconfirmedlabs/country_code) at
  `b4c92cb7f772879335344d7b6499b5fa4eafef56` — validated `CountryCode`.
- [`language_code`](https://github.com/unconfirmedlabs/language_code) at
  `61542357f3d2ff989d120185046def7cf6c8bdcb` — validated `LanguageCode`;
  every value is a real ISO 639-1 code by construction, so only count and
  duplicates are checked here.

All are exact Git pins; this manifest has no local-path dependencies.

## Integrator notes

- **Whole-card replace.** Editing one field means re-sending the entire card:
  read the current profile, modify client-side, call `set_profile`. There is
  no partial update.
- **Lengths are bytes, not characters.** `bio_short` (300) and `bio_long`
  (8192) bound the UTF-8 byte length, so multibyte text reaches the limit
  sooner. Validate before sending to avoid aborts.
- **Free text is untrusted input.** `bio_short` / `bio_long` are
  user-controlled strings — sanitize before rendering.
- **The display name is not here.** Read it from `party_name`; the join date
  comes from the party's creation event. Do not expect either in
  `Profile`.
- **Events carry the whole card.** `PartyProfileSetEvent` holds every field,
  bios included, with `country` and `languages` as plain code strings (the
  stored `Profile` keeps the typed `CountryCode` and `LanguageCode`). Max
  32 + 302 + 8,195 + 4 + 31 = 8,564 bytes, far below Sui's 250 KiB event
  limit, so an indexer never re-reads the profile. Equal replacement and
  absent clear remain silent after authorization.
