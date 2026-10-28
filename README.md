# Miso Framework

Everything Miso builds on Sui on top of the neutral protocol primitives ([`music-protocol`](https://github.com/misofm/music-protocol), [`party-protocol`](https://github.com/misofm/party-protocol), [`share`](https://github.com/misofm/share)): the economic model for music, metadata extensions for works and parties, Records and their sale, the listener's Player, and the shared libraries they use.

## Packages

Each package directory is a separate Move package with its own manifest, published and versioned on its own. Packages are grouped by domain.

| Domain | Package | What it does |
|---|---|---|
| [`economics`](economics) | [`royalty_pool`](economics/royalty_pool) | One pool per work per currency. Holders stake the work's share coin and claim their pro-rata cut of everything paid in. |
| | [`recording_license`](economics/recording_license) | A composition's standing license to record it. The recording pays the composition's rate as a stake in its own pool. |
| | [`release_license`](economics/release_license) | A recording's license for a release. The release sets a split, recordings authorize it by hash, and revenue is forwarded to each track's pool. |
| | [`royalty_lock`](economics/royalty_lock) | Locks a stake and directs a share of its royalties to a recipient until an amount is repaid or a term ends, then returns the stake. For advances paid off-chain and for pledges. |
| | [`royalty_advance`](economics/royalty_advance) | An on-chain offer: a provider's payment, exchanged for a `royalty_lock` on the rights holder's stake. |
| [`music`](music) | [`composition_credits`](music/composition_credits) | Songwriting and publishing attribution keyed by Party ID. |
| | [`composition_lyrics`](music/composition_lyrics) | Zstd-compressed lyrics keyed by ISO 639-1 language code. |
| | [`composition_title`](music/composition_title) | The composition's preferred title. |
| | [`recording_advisory`](music/recording_advisory) | Explicit, not-explicit, or cleaned advisory classification. |
| | [`recording_credits`](music/recording_credits) | Performance and production credits with primary and featured artist designations. |
| | [`recording_genre`](music/recording_genre) | Ordered genre classification of the master, primary first. |
| | [`recording_language`](music/recording_language) | Ordered ISO 639-1 language metadata; an empty list explicitly denotes instrumental content. |
| | [`recording_master`](music/recording_master) | Verified audio masters, one per distinct audio and verifier, written once. |
| | [`recording_version`](music/recording_version) | Name of this particular take, such as Live or Radio Edit. |
| | [`release_cover_art`](music/release_cover_art) | Release-level cover art with optional per-track overrides. |
| | [`release_credits`](music/release_credits) | Primary and featured top-line artist billing keyed by Party ID. |
| | [`release_description`](music/release_description) | Bounded free-text editorial description. |
| | [`release_genre`](music/release_genre) | Ordered release-level genre classification, primary first. |
| | [`release_kind`](music/release_kind) | Bounded free-text release classification such as Album, EP, or Mixtape. |
| | [`release_title`](music/release_title) | The release's preferred title. |
| | [`release_track_data`](music/release_track_data) | `ReleaseTrackData<Data>`: one value per track of a release, aligned to its tracklist by construction. |
| | [`release_track_iterator`](music/release_track_iterator) | `ReleaseTrackIterator<Witness>`: a witness-gated hot potato that walks a release's tracklist, one typed call per track. |
| [`party`](party) | [`party_name`](party/party_name) | Display name: one `String`. |
| | [`party_profile`](party/party_profile) | Profile card: `bio_short`, `bio_long`, `country`, `languages`. |
| | [`party_genre`](party/party_genre) | Genre-id set, proven at write time against the `genre` vocabulary. |
| | [`party_roles`](party/party_roles) | Artist-type set: Artist/Producer/DJ/Composer/Songwriter/Band/Label/Collective + `Custom`. |
| | [`party_tags`](party/party_tags) | Free-form tag set (moods, scenes, descriptors). |
| | [`party_media`](party/party_media) | Imagery: one Walrus quilt blob id. |
| | [`party_cta`](party/party_cta) | Ordered external call-to-action links (`{ label, url }`, position is priority). |
| | [`party_group`](party/party_group) | Optional shared group state, bounded invitations and members, consent, exit, and removal. |
| | [`party_wallet`](party/party_wallet) | Receive Party-addressed `key + store` objects and coins, or redeem Party accumulator funds, returning every asset to the caller. |
| [`record`](record) | [`record`](record/record) | The Record lifecycle: one `Pressing` per edition of a Release, one numbered `Record` per purchase. |
| | [`record_shop`](record/record_shop) | First-party fixed/floor-price sales of Records, with proceeds forwarded to the tracks' royalty pools. |
| [`player`](player) | [`miso_player`](player/miso_player) | A listener's on-chain root: one slim, non-transferable `Player` per address, which other packages extend. |
| [`lib`](lib) | [`credit`](lib/credit) | `Credit<Role>`: a party's credit on a work, a display name with one or more roles. |
| | [`genre`](lib/genre) | A canonical genre vocabulary as first-class on-chain objects. |
| | [`cover_art`](lib/cover_art) | The `CoverArt` value type: a still image plus an optional animation, each a Walrus reference. |
| | [`vault`](lib/vault) | Generic capability custody and temporary exact-return leases. |

[`music`](music/README.md) and [`party`](party/README.md) have their own landing pages.

## Economics

### Principles

- **Compositions and recordings earn.** Releases route revenue to them and earn nothing themselves.
- **Revenue enters at the work that was consumed.** A whole-release sale enters through the release. A stream or single-track sale pays the recording.
- **A derivative work pays its sources through a license the source grants.** Anyone may create the derivative. The license is what agrees its terms.
- **Payment never waits on authorization.** Authorization says what a source approved. It never blocks money owed to it.
- **The party granting a right stores it.** Each authorization is written by the work that grants it, and no one else can.
- **Shares are BPS.**

## Using a package

Depend on one package by its directory, pinned to an exact commit:

```toml
release_license = { git = "https://github.com/misofm/framework.git", subdir = "economics/release_license", rev = "<commit>" }
```

`subdir` is `<domain>/<package>`. Packages in this repository depend on each other by local path, for example `credit = { local = "../../lib/credit" }`. Dependencies outside it are pinned to full 40-character commit SHAs.

## Build and test

```sh
cd <domain>/<package>
sui move build
sui move test
```

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md) (FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version becomes Apache-2.0 two years after its release.
