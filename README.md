# Miso Framework

Everything Miso builds on Sui on top of the neutral protocol primitives ([`music-protocol`](https://github.com/misofm/music-protocol), [`party-protocol`](https://github.com/misofm/party-protocol), [`share`](https://github.com/misofm/share)): the economic model for music, metadata extensions for works and parties, Records and their sale, the listener's Player, and the shared libraries they use.

## Packages

Each directory is a separate Move package with its own manifest, published and versioned on its own.

### Economics

| Package | What it does |
|---|---|
| [`royalty_pool`](royalty_pool) | One pool per work per currency. Holders stake the work's share coin and claim their pro-rata cut of everything paid in. |
| [`recording_license`](recording_license) | A composition's standing license to record it. The recording pays the composition's rate as a stake in its own pool. |
| [`release_license`](release_license) | A recording's license for a release. The release sets a split, recordings authorize it by hash, and revenue is forwarded to each track's pool. |
| [`royalty_lock`](royalty_lock) | Locks a stake and directs a share of its royalties to a recipient until an amount is repaid or a term ends, then returns the stake. For advances paid off-chain and for pledges. |
| [`royalty_advance`](royalty_advance) | An on-chain offer: a provider's payment, exchanged for a `royalty_lock` on the rights holder's stake. |

### Music extensions

Optional typed data on a `miso_music` `Composition`, `Recording`, or `Release`, one concern per package.

| Package | What it does |
|---|---|
| [`composition_credits`](composition_credits) | Songwriting and publishing attribution keyed by Party ID. |
| [`composition_lyrics`](composition_lyrics) | Zstd-compressed lyrics keyed by ISO 639-1 language code. |
| [`composition_title`](composition_title) | The composition's preferred title. |
| [`recording_advisory`](recording_advisory) | Explicit, not-explicit, or cleaned advisory classification. |
| [`recording_credits`](recording_credits) | Performance and production credits with primary and featured artist designations. |
| [`recording_genre`](recording_genre) | Ordered genre classification of the master, primary first. |
| [`recording_language`](recording_language) | Ordered ISO 639-1 language metadata; an empty list explicitly denotes instrumental content. |
| [`recording_master`](recording_master) | Verified audio masters, one per distinct audio and verifier, written once. |
| [`recording_version`](recording_version) | Name of this particular take, such as Live or Radio Edit. |
| [`release_cover_art`](release_cover_art) | Release-level cover art with optional per-track overrides. |
| [`release_credits`](release_credits) | Primary and featured top-line artist billing keyed by Party ID. |
| [`release_description`](release_description) | Bounded free-text editorial description. |
| [`release_genre`](release_genre) | Ordered release-level genre classification, primary first. |
| [`release_kind`](release_kind) | Bounded free-text release classification such as Album, EP, or Mixtape. |
| [`release_title`](release_title) | The release's preferred title. |

### Party extensions and actions

Profile slices and relations on a `miso_party` `Party`, plus the `party_wallet` Action. Phasing is in [ROADMAP.md](ROADMAP.md).

| Package | What it does |
|---|---|
| [`party_name`](party_name) | Display name: one `String`. |
| [`party_profile`](party_profile) | Profile card: `bio_short`, `bio_long`, `country`, `languages`. |
| [`party_genre`](party_genre) | Genre-id set, proven at write time against the `genre` vocabulary. |
| [`party_roles`](party_roles) | Artist-type set: Artist/Producer/DJ/Composer/Songwriter/Band/Label/Collective + `Custom`. |
| [`party_tags`](party_tags) | Free-form tag set (moods, scenes, descriptors). |
| [`party_media`](party_media) | Imagery: one Walrus quilt blob id. |
| [`party_cta`](party_cta) | Ordered external call-to-action links (`{ label, url }`, position is priority). |
| [`party_group`](party_group) | Optional shared group state, bounded invitations and members, consent, exit, and removal. |
| [`party_wallet`](party_wallet) | Receive Party-addressed `key + store` objects and coins, or redeem Party accumulator funds, returning every asset to the caller. |

### Records

| Package | What it does |
|---|---|
| [`record`](record) | The Record lifecycle: one `Pressing` per edition of a Release, one numbered `Record` per purchase. |
| [`record_shop`](record_shop) | First-party fixed/floor-price sales of Records, with proceeds forwarded to the tracks' royalty pools. |

### Player

| Package | What it does |
|---|---|
| [`miso_player`](miso_player) | A listener's on-chain root: one slim, non-transferable `Player` per address, which other packages extend. |

### Libraries

Shared building blocks. They attach nothing themselves.

| Package | What it does |
|---|---|
| [`credit`](credit) | `Credit<Role>`: a party's credit on a work, a display name with one or more roles. |
| [`genre`](genre) | A canonical genre vocabulary as first-class on-chain objects. |
| [`cover_art`](cover_art) | The `CoverArt` value type: a still image plus an optional animation, each a Walrus reference. |
| [`vault`](vault) | Generic capability custody and temporary exact-return leases. |
| [`release_track_data`](release_track_data) | `ReleaseTrackData<Data>`: one value per track of a release, aligned to its tracklist by construction. |
| [`release_track_iterator`](release_track_iterator) | `ReleaseTrackIterator<Witness>`: a witness-gated hot potato that walks a release's tracklist, one typed call per track. |

## Economic principles

- **Compositions and recordings earn.** Releases route revenue to them and earn nothing themselves.
- **Revenue enters at the work that was consumed.** A whole-release sale enters through the release. A stream or single-track sale pays the recording.
- **A derivative work pays its sources through a license the source grants.** Anyone may create the derivative. The license is what agrees its terms.
- **Payment never waits on authorization.** Authorization says what a source approved. It never blocks money owed to it.
- **The party granting a right stores it.** Each authorization is written by the work that grants it, and no one else can.
- **Shares are BPS.**

## Extensions, Actions, and Plugins

- **Extension**: a persistent, namespaced data slice attached to a work or a `Party` as a dynamic field. Each package owns its own key, writes go through the object's cap-gated `uid_mut`, and reads are permissionless. Extensions do not custody capabilities, automate administrative authority, or route economic value.
- **Action**: public business logic that accepts the raw capability and returns caller-controlled assets for composition in the same PTB. Actions define no plugin witnesses, installation records, recipient policy, or Vault custody. A caller may hold the capability directly or borrow it from a [`vault`](vault), call the Action, and return it before the transaction ends.
- **Plugin**: installed, permissionless automation backed by a capability Vault: a separate entry-only package that calls an Action rather than reimplementing it.

There is intentionally no Party wallet plugin. Every useful `party_wallet` operation returns an object or `Balance` controlled by the caller, so permissionless automation would create an extraction path rather than a safe crank.

- Never send the sole matching `PartyAdminCap` to its own Party inbox: receiving from that inbox requires the same cap, creating a circular authorization lock.
- `party_wallet` can receive only `key + store` objects. Objects without `store` sent to the Party address are unrecoverable through this API.

Every state change emits an event that carries everything an indexer needs; see [EVENT_PAYLOADS.md](EVENT_PAYLOADS.md). Stored URLs are untrusted input: frontends must sanitize them before rendering.

## Using a package

Depend on one package by its directory, pinned to an exact commit:

```toml
release_license = { git = "https://github.com/misofm/framework.git", subdir = "release_license", rev = "<commit>" }
```

Packages in this repository depend on each other by local path, for example `credit = { local = "../credit" }`. Dependencies outside it are pinned to full 40-character commit SHAs.

Every package is released by publishing a fresh package identity and making it immutable; none is upgraded in place. A retained `Published.toml` records a prior generation and may not match pending source.

## Build and test

```sh
cd <package>
sui move build
sui move test
```

Contributor rules are in [AGENTS.md](AGENTS.md).

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md) (FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version becomes Apache-2.0 two years after its release.
