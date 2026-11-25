# audio_channel_layout

The `ChannelLayout` value type: the speaker position of each channel, in
channel order. It is the `Layout` of an [`audio::Audio`](../audio). It is its
own package so that `audio` stays layout-agnostic: an object-based or
ambisonic layout would be another layout package. The codes are the WAVE
channel-mask bit positions, the convention FLAC's
`WAVEFORMATEXTENSIBLE_CHANNEL_MASK` uses.

## What it stores

Nothing: `ChannelLayout` is a `copy + drop + store` value.

```move
public struct ChannelLayout(vector<u8>) has copy, drop, store;
```

- One code per channel, in channel order, 1 to 255 channels.
- Each code is a speaker position from 0 to 17, or 255 for a channel with no
  assigned position.
- A position appears at most once. 255 may repeat.

| Code | Position | Code | Position |
|---|---|---|---|
| 0 | front left (FL) | 9 | side left (SL) |
| 1 | front right (FR) | 10 | side right (SR) |
| 2 | front center (FC) | 11 | top center (TC) |
| 3 | low frequency (LFE) | 12 | top front left (TFL) |
| 4 | back left (BL) | 13 | top front center (TFC) |
| 5 | back right (BR) | 14 | top front right (TFR) |
| 6 | front left of center (FLC) | 15 | top back left (TBL) |
| 7 | front right of center (FRC) | 16 | top back center (TBC) |
| 8 | back center (BC) | 17 | top back right (TBR) |
| | | 255 | unassigned |

## API

### Constructors

| Function | Returns | Aborts |
|---|---|---|
| `new(speakers: vector<u8>)` | `ChannelLayout` | `EInvalidLength` (0), `EInvalidSpeaker` (1), `EDuplicateSpeaker` (2) |

### Views

| Function | Returns |
|---|---|
| `speakers(layout)` | `&vector<u8>`, one code per channel |

## Events

None: a value type changes no state.

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EInvalidLength` | No codes, or more than 255 |
| 1 | `EInvalidSpeaker` | A code from 18 to 254 |
| 2 | `EDuplicateSpeaker` | A position other than 255 appears twice |

## Dependencies

None beyond the Sui framework.

## Integrator notes

- **The layout does not know the channel count.** Whoever pairs it with a
  format checks that they agree. `audio_verifier` requires
  `speakers().length() == pcm.channels()`.
- **FLAC's default orders,** used when a file has no channel mask: 1 channel
  `[2]`, 2 `[0, 1]`, 3 `[0, 1, 2]`, 4 `[0, 1, 4, 5]`, 5 `[0, 1, 2, 4, 5]`,
  6 `[0, 1, 2, 3, 4, 5]`, 7 `[0, 1, 2, 3, 8, 9, 10]`, 8
  `[0, 1, 2, 3, 4, 5, 9, 10]`. A 5.1 file with side surrounds carries the mask
  `0x60F`, which gives `[0, 1, 2, 3, 9, 10]`.
- **Mapping a WAVE channel mask:** take the set bits from lowest to highest
  and assign them to channels in order. Channels left over after the mask runs
  out are 255.
- **Position codes are not channel indexes.** `[1, 0]` means the first channel
  plays front right.

## Build and test

```sh
sui move build --lint --warnings-are-errors
sui move build --lint --warnings-are-errors --build-env mainnet
sui move test --coverage --lint --warnings-are-errors
sui move coverage summary
```

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
