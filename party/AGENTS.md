# AGENTS.md — Working on Miso Party Extensions

Guidance for agents (and humans) building or documenting extensions in
`party/`, the party domain of the `misofm/framework` repository. Read [ROADMAP.md](ROADMAP.md) for design principles and phasing,
and [README.md](README.md) for the architecture and package overview.

## Repository shape

- `../lib/*` — protocol-agnostic primitives shared across the repository
  (`credit`, `genre`, `cover_art`, `vault`). They depend only on the Sui
  framework and external primitives: no `miso_party`, no Miso. `party_genre`
  uses [`genre`](../lib/genre). The bounded-set primitive is the immutable
  external package
  [`unconfirmedlabs/typed_set`](https://github.com/unconfirmedlabs/typed_set).
  If a mechanism knows what a party is, it does not belong in `lib/`.
- State-attaching `party_*` packages (`party_cta`, `party_genre`,
  `party_media`, `party_profile`, `party_roles`, and `party_tags`) attach one slice to a `Party` via dynamic fields. Every write
  is gated by `PartyAdminCap` through `party::uid_mut(cap)`.
- `party_group` is a relational extension: it owns optional shared `Group` state derived from a Party. Creation uses `uid_mut(cap)`; relation operations use `party::authorize(cap)` on the group owner or consenting member. It does not route value or custody capabilities.
- `party_wallet` is an Action package: raw-`PartyAdminCap`, custody-agnostic
  wallet operations. It stores no profile data.
- Every package is self-contained: `Move.toml`, `sources/`, `tests/`,
  `README.md`.

## Adding a new extension

1. **Check the ROADMAP first.** The extension should already be scoped to a
   phase with a defined slice. If it duplicates something derivable from
   protocol objects, stop — derived state is read, not stored.
2. **Use a primitive before writing mechanics.** A bounded set of anything →
   depend on `typed_set` and keep only your element type, domain validation,
   capacity constant, and typed events. Only write raw `df::add`/`borrow`/`remove` when no primitive
   fits (single-value fields like `party_media` and `party_profile`).
3. **Keep it slim.** One slice, one key, the smallest API that covers the
   feature. No speculative configurability, no helper functions with one call
   site, no unused public surface.
4. **Keep operational workflows out.** Profile extensions attach data to `Party`. The `party_group` relational extension owns optional membership and consent state; this is a data-model policy removed from core, not an Actions wrapper. Composable
   functionality that consumes a raw `PartyAdminCap` belongs in an Action
   package such as [`party_wallet`](party_wallet).
   Permissionless Vault automation belongs in an entry-only plugin that calls
   an Action. Do not put operational workflows in an extension.
5. **Gate every state-attaching write with the cap.** Relational writes in `party_group` mutate its own `Group` and authorize the relevant Party through `party::authorize(cap)`; they must not request the other participant's cap or expose the Group UID. Those writes take
   `&PartyAdminCap` and go through `party::uid_mut(cap)` before mutation or
   event emission.
6. **Bound everything stored.** Max lengths on strings, max counts on
   collections.
7. **Use exact dependency provenance.** Packages in this repository depend on
   each other by local path (`genre = { local = "../../lib/genre" }`). Every
   dependency outside it is a Git dependency pinned to a full 40-character
   commit SHA, never `main` or `master`. Packages publish immutably; changed
   data models require a new package and explicit migration, not an upgrade.
8. **Emit an event for each actual state change**, carrying `party_id` (`ID`).
   An indexer must be able to rebuild every field from events alone: set
   events carry the full new value (bios, CTA lists), add/remove
   events carry the entry, clears carry only the key. Equal-value replacements
   and absent clears emit nothing; the first attachment, including an
   explicitly empty value, emits. Enum values, never numeric codes. See
   [EVENT_PAYLOADS.md](EVENT_PAYLOADS.md).
9. **Tests:** happy path and each validation abort. Every state-attaching
   extension also needs a wrong-cap test
   (`expected_failure(abort_code = party::EUnauthorized)`). Reference real
   constants, including `typed_set::typed_set::EDuplicateItem` and friends for
   set-mechanics aborts; use `location =` only for aborts without a named
   constant.
10. **Document** (below): package README, root README row, ROADMAP row.
11. **Verify:** strict Testnet and Mainnet lint builds plus
    `sui move test --coverage`; every production module must report 100%
    instruction coverage.

Retain `Published.toml`. It records a prior immutable generation and may not
match pending source. Fresh publication goes through the admin CLI with
`--allow-republish`; only a confirmed successful transaction may replace the
target network block.

## Documenting an extension

Four artifacts, in this order:

### 1. Package `README.md` (required, in the package folder)

Use this exact section order. Omit a section only when it would be empty —
and say so inline (e.g. "none — set aborts come from `typed_set`") rather than
leaving the reader guessing.

```markdown
# <package_name>

<2–4 sentences: what slice of the profile this owns, why it exists as its own
package, and any load-bearing design decision (e.g. proven-at-write-time,
replace-in-place, client convention).>

## What it stores
<Dynamic-field key type(s), value type and shape, limits/capacities, and the
reclamation/replacement semantics. One short list or table.>

## API
### Writes (cap-gated)
| Function | Description | Aborts |
### Views
| Function | Returns |

## Events
| Event | When | Payload |

## Errors
| Code | Constant | Condition |
<Include aborts that surface from primitives, marked with their location.>

## Dependencies
<Direct deps and why. Note anything unusual (protocol deps, git pins).>

## Integrator notes
<What a client/indexer must know that is not in the code: URL rebuilding from
handles, untrusted-input sanitization, quilt patch identifier conventions,
re-read-on-event, commit-settled balances, etc.>
```

### 2. `README.md` rows

Add the package to the correct table (Primitives vs. Extensions) in
`party/README.md` and to the `party` rows of the repository root `README.md`,
one line: what it owns, no mechanics. Keep alphabetical-ish grouping by role, not by
name.

### 3. `ROADMAP.md` row

Add or update the package's row in its phase table. If the roadmap described
the package aspirationally and reality differs, the roadmap loses — update it.

### 4. No comments in Move code

`.move` files carry no comments except the column-0 license header and
top-level `// === Section ===` markers. Facts the code cannot state
(invariants, bounds, call order, trust assumptions, Sui runtime behavior,
non-obvious aborts, why something is absent) go in the package README as short
bullets (Integrator notes). After any refactor, update those bullets.

## Style rules

- Plain, precise prose. No marketing voice, no emoji.
- Code identifiers stay in `backticks`; packages in bold only on first
  mention in a section if emphasis is truly needed.
- Tables over paragraphs for API/event/error surfaces.
- Numbers in docs (limits, codes) must match the code — when they disagree,
  the docs are wrong, always.
- Never document a function that does not exist; never leave a documented
  behavior unverified (`sui move test` green is the bar).

## Move layout

- Sections in order: Imports, Errors, Constants, Structs, Enums, Events,
  Method Aliases, Public Functions, View Functions, Admin Functions, Package
  Functions, Private Functions, Test Functions (`// === Name ===`). Omit empty
  sections. Dynamic-field keys come last in Structs.
- Cap-gated functions go under Admin Functions; `init`, when present, is the
  first Public Function; `public(package)` functions go under Package Functions.
- Imports in one block ordered std, sui, external packages, this package.
- Errors are plain `u64` constants numbered from 0 in declaration order.
- Lines stay within 100 columns.
