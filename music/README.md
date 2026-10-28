# Music Protocol Extensions

Data-model extensions for
[`misofm/music-protocol`](https://github.com/misofm/music-protocol) (`miso_music`) on Sui.

Miso keeps `Composition`, `Recording`, and `Release` focused on constitutive
protocol state. An extension adds optional typed data as a dynamic field on one
of those objects. Writes require the object's matching admin capability through
its cap-gated `uid_mut`; reads are permissionless.

Extensions do not custody capabilities, automate administrative authority, or
route economic value. Related packages:

| Location | Responsibility |
|----------|----------------|
| [`misofm/music-protocol`](https://github.com/misofm/music-protocol) | Core music objects and the canonical `ReleaseRegistry` namespace. |
| [`../economics/royalty_pool`](../economics/royalty_pool) | Each work's canonical royalty pools. |
| [`../economics/recording_license`](../economics/recording_license) | A composition's standing license to record it. |
| [`../party/party_wallet`](../party/party_wallet) | Custody-agnostic, return-oriented Party workflows. |
| [`../lib/vault`](../lib/vault) | Generic capability custody and temporary exact-return leases. |

This directory is the `music` domain of
[`misofm/framework`](../README.md). Each subdirectory is an independently
versioned and published Move package. Applications should depend only on the
extensions they use.

## Packages

### Metadata extensions

First-party, platform-neutral metadata extensions.

| Package | Target | Purpose |
|---------|--------|---------|
| [`composition_credits`](./composition_credits) | Composition | Songwriting and publishing attribution keyed by Party ID. |
| [`composition_lyrics`](./composition_lyrics) | Composition | Zstd-compressed lyrics keyed by ISO 639-1 language code. |
| [`composition_title`](./composition_title) | Composition | The composition's preferred title. |
| [`recording_advisory`](./recording_advisory) | Recording | Explicit, not-explicit, or cleaned advisory classification. |
| [`recording_credits`](./recording_credits) | Recording | Performance and production credits with primary and featured artist designations. |
| [`recording_genre`](./recording_genre) | Recording | Ordered genre classification of the master, primary first. |
| [`recording_language`](./recording_language) | Recording | Ordered ISO 639-1 language metadata; an empty list explicitly denotes instrumental content. |
| [`recording_master`](./recording_master) | Recording | Verified audio masters, one per distinct audio and verifier, written once. |
| [`recording_version`](./recording_version) | Recording | Name of this particular take, such as Live or Radio Edit. |
| [`release_cover_art`](./release_cover_art) | Release | Release-level cover art with optional per-track overrides. |
| [`release_credits`](./release_credits) | Release | Primary and featured top-line artist billing keyed by Party ID. |
| [`release_description`](./release_description) | Release | Bounded free-text editorial description. |
| [`release_genre`](./release_genre) | Release | Ordered release-level genre classification, primary first. |
| [`release_kind`](./release_kind) | Release | Bounded free-text release classification such as Album, EP, or Mixtape. |
| [`release_title`](./release_title) | Release | The release's preferred title. |

Each package covers one concern and stores its value under its own key, named
for what it stores (`RecordingGenreKey()`, `ReleaseCoverArtKey()`), so changing
one attribute's schema never forces a data migration of another. Keys take
parameters only where a package stores several values: `CompositionLyricsKey`
by language and `RecordingMasterKey` by verifier and PCM digest. Titles live
here because `miso_music` stores none.

### Libraries

Shared building blocks for the extensions. They attach nothing themselves.

| Package | Used by | Purpose |
|---------|---------|---------|
| [`release_track_data`](./release_track_data) | `release_cover_art` | `ReleaseTrackData<Data>`: one value per track of a release, aligned to its tracklist by construction. |
| [`release_track_iterator`](./release_track_iterator) | none yet | `ReleaseTrackIterator<Witness>`: a witness-gated hot potato that walks a release's tracklist, one typed call per track. |

The extensions also use the shared [`credit`](../lib/credit),
[`genre`](../lib/genre), and [`cover_art`](../lib/cover_art) libraries in
`lib/`. Packages in this repository depend on each other by local path.

## Usage

Reference an extension by its `music/<package>` subdirectory and an exact commit:

```toml
[dependencies]
release_genre = { git = "https://github.com/misofm/framework.git", subdir = "music/release_genre", rev = "<40-character-commit>" }
```

Each package's `Move.toml` pins its protocol and other external dependencies
to exact commits. The current sources target `miso_music` commit
`f404d771be28db15e79bedb5bd09a5d1f63ee727`: Composition and Recording are
generic over their share coin type, and their admin capabilities authorize by
that type; a Release admin capability authorizes by the release's ID.
Composition and Recording extension events carry no share type arguments;
consumers identify the subject through the event's object ID.

Existing `Published.toml` files are retained as records of the currently
deployed, prior package generation, including the protocol extension packages'
deployment records from before they moved from
`misonetwork/protocol-extensions`. Some historical Mainnet records include an
`upgrade-capability`; that is provenance, not authorization to upgrade. Every
package in this repository is released by publishing a fresh package identity
and immediately making it immutable. After a successful publication, the admin
CLI replaces only that network's `Published.toml` block with the new immutable
generation. Clients migrate explicitly to the new package identity; these
packages are never upgraded in place.

When an admin capability is held in a Vault, applications should use the
matching custody-agnostic Action. A caller may borrow the capability from the
Vault, call that Action, and return the capability within one programmable
transaction block.

## Development

Run build and test commands from an individual package directory:

```sh
cd music/release_genre
sui move build
sui move test --coverage
```

The test suites include production-shaped `sui::test_scenario` flows for shared
protocol objects and focused invariant and authorization tests.

## License

[Functional Source License 1.1, ALv2 Future License](../LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.

## Event payload policy

See [EVENT_PAYLOADS.md](EVENT_PAYLOADS.md) for the payload rule and
consumer integration notes; each package README lists its events.
