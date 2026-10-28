# Miso Party Extensions — Roadmap

Artist/entity profile pages are built by attaching stateful **extensions** to
the core [`miso_party::party::Party`](https://github.com/misofm/party-protocol) via
dynamic fields. Each state-attaching extension owns one coherent slice, gates
writes with the party's `PartyAdminCap`, and ships independently. Platform
links (social, music and pro profiles) were removed pending a redesign.

## Design principles

1. **Declare, don't duplicate.** The party stores only non-derivable identity the
   artist authors. Anything computable from Miso protocol objects (catalogue,
   credits, editions, counts) is **derived at read time**, never copied onto the
   party — a copy is a guaranteed-stale second source of truth.
2. **Reference, don't embed.** Media is a Walrus reference (a quilt blob id) or
   an external URL — never bytes on-chain. Links store the platform's native
   handle/id (URL rebuilt client-side), or a full URL where there is no handle.
3. **Many small extensions, not one mega-struct.** Move cannot add fields to a
   published struct without a migration. Independent extensions each own a slice
   and can be succeeded without touching the others. Every package publishes
   immutably; a changed data model is a new package plus an explicit migration,
   never an upgrade. This is why the roadmap is phased by extension, not by
   "v1 schema".
4. **Cap-gated writes, permissionless reads.** Writes go through
   `party.uid_mut(cap)`; views read `party.uid()`. The one exception is
   verification, which is gated by Miso's cap and lives *outside* the party.
5. **No PII/UI-state on-chain.** Emails, payout addresses, fees, and layout/theme
   config are off-chain or modeled as links; on-chain is permanent and public.
6. **Events are sufficient for indexing.** Set events carry the full new value,
   add/remove events the entry, clears the key, so an indexer never reads object
   storage. Equal-value replacements and absent clears are silent; an initial
   attachment, including an explicitly empty value, emits. See
   [EVENT_PAYLOADS.md](EVENT_PAYLOADS.md).

## Where each field lives

| Bucket | Rule | Examples |
|---|---|---|
| ✅ Declare (extension) | Artist-authored, non-derivable | bio, roles, tags, links, CTAs, featured pointers, verified badge |
| 🔗 Derive from protocol | Lives on Release/Composition/Recording + their extensions | catalogue, release metadata, credits/ISRC/UPC/splits, editions, collector & release counts, formats |
| 📦 Reference (Walrus) | Media is a ref, not bytes | avatar, header, gallery, embedded media |
| 🚫 Off-chain / indexer | UI state & computed values | theme/accent/layout/section order, toggles, completeness score, last-updated, moderation |
| ⚠️ Never raw on-chain | Permanent + public = privacy risk | booking/press/sync emails, phone, fees, payout/wallet addresses |

Two structural facts that remove large parts of the wishlist:
- **Membership is optional** — core `Party` is identity-only. `party_group` owns shared group relations outside the Party layout.
- **Catalogue is derived** — the page renders the artist's releases by querying
  protocol objects; the party only *pins* selected ones (`party_featured`).

---

## Group Membership — Implemented in This Source Generation

| Package | Owns | Notes |
|---|---|---|
| `party_group` | A shared Group derived from a Party, pending invitations, direct memberships, and consent events | Optional policy; uses `typed_set`, permits any Party as a member except the group owner itself, and does not infer recursive membership |

## Phase 0 — Shipped

| Package | Owns |
|---|---|
| [`unconfirmedlabs/typed_set`](https://github.com/unconfirmedlabs/typed_set) | Bounded-set primitive — one `VecSet<T>` per key type on any UID; dup/max checks, field reclamation on empty |
| `party_name` | Display name, moved out of core `Party` |
| `party_profile` (v1) | bio_short, bio_long, country (`country_code`), languages (`language_code`) |
| `party_genre` | Genre-id tag set, validated against the `genre` vocabulary (`&Genre`) |
| [`lib/genre`](../lib/genre) | Extracted vocabulary primitive (Sui-only), shared by releases + parties |

---

## Phase 1 — A legible artist page + link hub (shipped)

Turns a link list into a real profile: identity card, imagery, and prioritized
calls-to-action.

| Package | Owns | Notes |
|---|---|---|
| `party_profile` successor | pronouns, active_since | Ship a new immutable package with an explicit migration; never alter the published v1 layout |
| `party_roles` | Artist type set — Artist/Producer/DJ/Composer/Songwriter/Band/Label/Collective + `Custom` | Closed enum, mirrors `composition_party_role` |
| `party_tags` | Free-form moods/scenes (`VecSet<String>` via `typed_set`) | Uncurated sibling to `party_genre` |
| `party_media` | avatar + header as one Walrus quilt (`u256` blob id) | Patch roles ("avatar"/"header") are a client convention, derived off-chain |
| `party_cta` | Ordered off-Miso call-to-action links — slim `{ label, url }`, replace-whole-list | External URLs only; on-Miso actions go to `party_featured` (Phase 2) |

---

## Phase 2 — Miso-native differentiators, trust & conversion

The pieces a normal link hub can't have. The earlier Pressing-specific featured
pointer was retired; its replacement is the generalized, protocol-agnostic
design below.

| Package | Owns | Notes |
|---|---|---|
| `party_featured` | Interactive **references to Miso objects** — collect / listen-on-Miso / pin a release, composition, track, playlist by id | On-Miso counterpart to `party_cta`; renders live edition/sold-out state + in-app actions. Stores plain ids (no protocol dep) |
| `party_verification` | Miso-signed identity badge, issued from **outside** the party (derived object, `VerifierCap`-gated) | Design already scoped; name-snapshot + `verifier` id + revoke flag |
| `party_handle` | Unique slug/handle via a namespace registry (uniqueness, anti-squat) | Derived-object or registry-table keyed by slug |
| `party_featured` (commerce) | Campaign windows + commerce actions (drops, membership, tip jar) bound to Miso objects | Editions/sold-out remain **derived** from the object |

---

## Phase 3 — Professional depth, live & social proof

| Package | Owns | Notes |
|---|---|---|
| `party_events` | Tour dates/shows (date, venue, city, ticket link), availability-for, booking territories, rider **links** | Time-bound; client filters by now |
| `party_contact_link` | Booking / press / sync as **links** (contact forms), never raw emails | Privacy-safe |
| `party_identity_extras` | Aliases, former names, affiliations, collaborators (Party refs) | — |
| `party_about` | Influences, instruments, production tools, press quotes, awards | Social-proof lists; some inferable from releases |
| `party_media` (extend) | Press-photo gallery, embedded video/player | Walrus refs |

---

## Explicitly out of scope on-chain

- **Derived from protocol:** releases/singles/EPs, videos, mixes, remixes, live
  sessions; release title/type/date/artwork/label/formats/edition/collect status;
  credits/provenance (songwriter/producer/engineer, ISRC/UPC, splits); collector
  & supporter & release counts; component availability (stems/score/lyrics).
- **Optional relational extension:** band/collective membership, invitations, consent, and exit live in `party_group`, not core.
- **Off-chain / indexer:** page theme/accent/layout/section order, hide-show
  toggles, featured-media order, profile completeness score, last-updated,
  moderation status, "verified-links-only" (derived from verification stamps).
- **Party actions:** Composable raw-cap Party inbox receipt and accumulator
  withdrawal live in [`party_wallet`](party_wallet); they store no
  profile data. Permissionless Vault automation, when needed, lives separately
  as entry-only plugins that invoke Actions rather than reimplementing them.
- **Never raw on-chain (PII/payment):** booking/press/sync emails, phone, fees,
  payout/wallet addresses, private management contacts.
