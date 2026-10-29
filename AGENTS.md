# AGENTS.md — Working on the Miso Framework

Guidance for agents (and humans) building or documenting packages in this
repository. Read [README.md](README.md) for the package overview and the
Extension / Action / Plugin split, [ROADMAP.md](ROADMAP.md) for the party
extension phasing, and [EVENT_PAYLOADS.md](EVENT_PAYLOADS.md) for the event
rule. A package may add its own `CLAUDE.md` with package-specific rules.

## Repository shape

Every top-level directory is one independently versioned and published Sui Move
package with its own `Move.toml`, `Move.lock`, `Published.toml` where deployed,
`sources/`, `tests/`, `README.md`, and `LICENSE.md`. Run Move commands from the
package directory. Audits live in the separate `misofm/audits` repository.

- **Extensions** (`composition_*`, `recording_*`, `release_*` metadata, and
  `party_*` profile packages) attach one slice of data to a `miso_music`
  `Composition`, `Recording`, or `Release`, or a `miso_party` `Party`, as a
  dynamic field. Every write goes through the object's cap-gated `uid_mut`.
- **Relational extensions** (`party_group`) store each side of a relationship
  on that side's own Party, written through its `uid_mut(cap)`. They do not
  route value or custody capabilities.
- **Actions** (`party_wallet`) accept a raw capability and return assets to the
  caller.
- **Libraries** (`credit`, `genre`, `cover_art`, `vault`, `release_track_data`,
  `release_track_iterator`) attach nothing themselves. `credit`, `genre`,
  `cover_art`, and `vault` are protocol-agnostic: no `miso_music`, no
  `miso_party`. If a mechanism knows what a party or work is, it is not one of
  those. The bounded-set primitive is the immutable external package
  [`unconfirmedlabs/typed_set`](https://github.com/unconfirmedlabs/typed_set).
- **Economics, records, and the player** (`royalty_*`, `recording_license`,
  `release_license`, `record`, `record_shop`, `miso_player`) follow the same
  rules where they apply.

## Adding a package

1. **Check the scope first.** A party extension should already be scoped to a
   phase in the ROADMAP. If a package duplicates something derivable from
   protocol objects, stop: derived state is read, not stored.
2. **One package per concern, one key.** Each package defines one
   package-private key named for what it stores (`RecordingGenreKey(ID)`,
   `CompositionLyricsKey(LanguageCode)`,
   `RecordingMasterKey(audio_id)`), never a generic
   `ExtensionKey()`, so a schema change to one attribute never forces a data
   migration of another. Keys take parameters only where a package stores
   several values.
3. **Use a primitive before writing mechanics.** A bounded set of anything:
   depend on `typed_set` and keep only your element type, domain validation,
   capacity constant, and typed events. Write raw `df::add`/`borrow`/`remove`
   only when no primitive fits.
4. **Keep it slim.** One slice, the smallest API that covers the feature. No
   speculative configurability, no helper functions with one call site, no
   unused public surface.
5. **Keep operational workflows out of extensions.** Composable functionality
   that consumes a raw admin capability belongs in an Action package such as
   [`party_wallet`](party_wallet). Permissionless Vault automation belongs in a
   separate entry-only plugin that calls an Action.
6. **Gate every write with the cap.** State-attaching writes take the matching
   admin capability and go through `uid_mut(cap)` before mutation or event
   emission. Relational writes in `party_group` are two-sided: each Party's
   admin writes its own half on its own Party through `uid_mut(cap)`, and no
   write requests the other participant's cap. Reads are permissionless.
7. **Bound everything stored.** Max lengths on strings, max counts on
   collections.
8. **Use exact dependency provenance.** Packages in this repository depend on
   each other by local path (`genre = { local = "../genre" }`). Every
   dependency outside it is a Git dependency pinned to a full 40-character
   commit SHA, never `main` or `master`. Packages publish immutably; changed
   data models require a new package and explicit migration, not an upgrade.
9. **Emit an event for each actual state change**, carrying the subject's
   `ID` (`party_id`, `composition_id`, `recording_id`, `release_id`). An
   indexer must be able to rebuild every field from events alone: set events
   carry the full new value, add/remove events the entry, clears only the key.
   Equal-value replacements and absent clears emit nothing; the first
   attachment, including an explicitly empty value, emits. Enum values, never
   numeric codes. See [EVENT_PAYLOADS.md](EVENT_PAYLOADS.md).
10. **Tests:** happy path and each validation abort. Every state-attaching
    extension also needs a wrong-cap test
    (`expected_failure(abort_code = party::EUnauthorized)` or
    `release::EUnauthorized`). Reference the real error constant through the
    imported module; Move infers the location, so do not add `location =` or
    mirror error constants in test files. Use `location = <imported module>`
    only for aborts with no named constant, and reference
    `typed_set::typed_set::EDuplicateItem` and friends for set-mechanics
    aborts.
11. **Document** (below): package README, root README row, and, for party
    extensions, the ROADMAP row.
12. **Verify:** strict Testnet and Mainnet lint builds plus
    `sui move test --coverage`; every production module must report 100%
    instruction coverage.

Retain `Published.toml` as deployment provenance. It records a prior immutable
generation and may not match pending source. Fresh publication goes through the
admin CLI with `--allow-republish`; only a confirmed successful transaction may
replace the target network block.

## Documenting a package

Four artifacts, in this order:

### 1. Package `README.md` (required, in the package folder)

Use this exact section order. Omit a section only when it would be empty, and
say so inline (e.g. "none — set aborts come from `typed_set`") rather than
leaving the reader guessing.

```markdown
# <package_name>

<2–4 sentences: what slice this owns, why it exists as its own package, and
any load-bearing design decision (e.g. proven-at-write-time,
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
<Direct deps and why: local path in this repository, or the external Git pin.>

## Integrator notes
<What a client/indexer must know that is not in the code: URL rebuilding from
handles, untrusted-input sanitization, quilt patch identifier conventions,
re-read-on-event, commit-settled balances, etc.>
```

### 2. Root `README.md` row

Add the package to the correct section table, one line: what it owns, no
mechanics. Group by role, not by name.

### 3. `ROADMAP.md` row (party extensions)

Add or update the package's row in its phase table. If the roadmap described
the package aspirationally and reality differs, the roadmap loses; update it.

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
- Numbers in docs (limits, codes) must match the code; when they disagree,
  the docs are wrong, always.
- Never document a function that does not exist; never leave a documented
  behavior unverified (`sui move test` green is the bar).

## Move layout

- Use Move 2024 syntax.
- Import modules, functions, and types with `use`; never write fully
  qualified `address::module::member` paths inline.
- Sections in order: Imports, Errors, Constants, Structs, Enums, Events,
  Method Aliases, Public Functions, View Functions, Admin Functions, Package
  Functions, Private Functions, Test Functions (`// === Name ===`). Omit empty
  sections. Dynamic-field keys come last in Structs.
- Cap-gated functions go under Admin Functions; `init`, when present, is the
  first Public Function; `public(package)` functions go under Package Functions.
- Imports in one block ordered std, sui, external packages, this package.
- Errors are plain `u64` constants numbered from 0 in declaration order.
- Lines stay within 100 columns.

## Sui development resources

Install community-maintained skills for Sui development:

```sh
npx skills https://github.com/MystenLabs/skills
```

When unsure about Move patterns or Sui APIs, consult these sources. Do not
guess or extrapolate from other blockchains. Use the Sui documentation MCP
server at `https://sui.mcp.kapa.ai` when it is available.

- Move Book: https://move-book.com (use https://move-book.com/llms.txt)
- Sui Docs: https://docs.sui.io (use https://docs.sui.io/llms.txt)
- Sui Move examples: https://github.com/MystenLabs/sui/tree/main/examples/move
