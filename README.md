# Miso Framework

Miso's economic model for music on Sui: where a work's revenue lands, how a derivative work pays the works it is built from, and who may access a work. It sits between the neutral protocol primitives ([`music-protocol`](https://github.com/misofm/music-protocol), [`party-protocol`](https://github.com/misofm/party-protocol), [`share`](https://github.com/misofm/share)) and the applications built on them.

## Packages

Each directory is a separate Move package with its own manifest, published and versioned on its own.

| Package | What it does |
|---|---|
| [`royalty_pool`](royalty_pool) | One pool per work per currency. Holders stake the work's share coin and claim their pro-rata cut of everything paid in. |
| [`recording_license`](recording_license) | A composition's standing license to record it. The recording pays the composition's rate as a stake in its own pool. |
| [`release_license`](release_license) | A recording's license for a release. The release sets a split, recordings authorize it by hash, and revenue is forwarded to each track's pool. |
| [`royalty_advance`](royalty_advance) | A provider pays a rights holder up front for a stake locked in a shared advance. The provider takes a share of the stake's royalties until an amount is repaid or a term ends, then the stake goes back. |

## Principles

- **Compositions and recordings earn.** Releases route revenue to them and earn nothing themselves.
- **Revenue enters at the work that was consumed.** A whole-release sale enters through the release. A stream or single-track sale pays the recording.
- **A derivative work pays its sources through a license the source grants.** Anyone may create the derivative. The license is what agrees its terms.
- **Payment never waits on authorization.** Authorization says what a source approved. It never blocks money owed to it.
- **The party granting a right stores it.** Each authorization is written by the work that grants it, and no one else can.
- **Shares are BPS.**

## Using a package

Depend on one package by its directory, pinned to an exact commit:

```toml
release_license = { git = "https://github.com/misofm/framework.git", subdir = "release_license", rev = "<commit>" }
```

Packages in this repository depend on each other by local path.

## Build and test

```sh
cd <package>
sui move build
sui move test
```

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md) (FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version becomes Apache-2.0 two years after its release.
