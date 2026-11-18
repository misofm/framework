# audio

`Audio<AudioVerifier, Format, Layout>` is attested audio: a format, a channel
layout and the Walrus blob that holds the file. Only code holding an
`AudioVerifier` witness can create one, so the type names who vouched for
it. `Audio` is a plain value with no UID that the owner stores, typically as a
recording's master in [`recording_master`](../recording_master). It is
format-agnostic: `Format` and `Layout` come from their own packages, such as
[`audio_format_pcm`](../audio_format_pcm) and
[`audio_channel_layout`](../audio_channel_layout), and this package depends on
neither.

## What it stores

Nothing itself: `Audio` is a `store + drop` value, without `copy` and without
`key`.

```move
public struct Audio<
    phantom AudioVerifier,
    Format: store + drop,
    Layout: store + drop,
> has store, drop {
    format: Format,
    layout: Layout,
    data: ori::data::WalrusBlob,
}
```

- `data` is the file: a Walrus blob ID plus its
  `ori::confidentiality::Confidentiality`. An encrypted master is
  `Encrypted { sealed_dek }`, the Seal-encrypted data key of the blob.
- The fields never change once created. There is no registry, no object ID and
  no freeze. The same facts may exist in many `Audio` values.
- `Audio` has no `copy`, so whoever holds one holds the only instance created
  by that call. It can be dropped.

## API

### Constructors

| Function | Returns | Aborts |
|---|---|---|
| `new<AudioVerifier: drop, Format: store + drop, Layout: store + drop>(witness, format, layout, data)` | `Audio<AudioVerifier, Format, Layout>` | none |

### Views

| Function | Returns |
|---|---|
| `format(audio)` | `&Format` |
| `layout(audio)` | `&Layout` |
| `data(audio)` | `&ori::data::WalrusBlob` |

## Events

None. `new` changes no on-chain state. Verifiers emit what they attest, for
example `audio_verifier::AudioVerifiedEvent`, and stores emit what they hold,
for example `recording_master::RecordingMasterAddedEvent`.

## Errors

None. `new` checks nothing: the verifier checks the facts before it calls `new`.

## Dependencies

- [`ori`](https://github.com/unconfirmedlabs/ori) (`move` subdirectory) at
  `a3a134ae69a4861030a05ae22f21e67a7b91faf9`: `WalrusBlob` and
  `Confidentiality`.

## Integrator notes

- **Pin the verifier types you trust.** Accept
  `Audio<audio_verifier::audio_verifier::AudioVerifier, Pcm, ChannelLayout>`.
  Never treat a generic `Audio<V, _, _>` as trusted: anyone can publish a
  witness and vouch for anything.
- **An `Audio` attests the audio, not who owns it.** A verifier's signed
  facts can be replayed by anyone to build another identical `Audio`. Rights
  and access come from where it is stored. For masters, decryption is gated by
  [`recording_master_seal`](../recording_master_seal), whose identity names the
  recording.
- **The blob is not checked on chain.** Nothing proves it is still stored on
  Walrus. Its lifetime is the owner's concern.

## Build and test

```sh
sui move build --lint --warnings-are-errors
sui move build --lint --warnings-are-errors --build-env mainnet
sui move test --coverage --lint --warnings-are-errors
sui move coverage summary
```

## Generations

This is the second generation of `audio`. The first, a frozen
`Audio<AudioVerifier>` object derived from a shared `AudioRegistry`, stays
published and immutable on mainnet:

- mainnet `0x5dafcccd44bc253b50bf35b23086e0495264956662fd96fb87b8068eef8eeaeb`,
  registry `0x9bb7d829ecbbff28376caceb99e68e2ba4ff5db47aef4ed797edc77fdc0fc52f`
- testnet `0x2c612a84ed3c6f19faeb50cadd801ffd266d6726defcdf8d95899ffbbce6138d`,
  registry `0x100683a91c8be9238928dbf322373ec0503aaed18c6ecd058345d1c9f2be5d51`

`Published.toml` records the current generation per network. Until mainnet is
republished, its mainnet block still names the first generation.

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
