# record_shop

`record_shop` is the first-party fixed/floor-price sales package for Miso
Records on Sui. Its only state is a `Pricing` stored on each Pressing per
currency. There is no global Record Shop, Distributor or listing object.

```text
Release
└── PressingKey(edition) → Pressing
    ├── RecordKey(number) → Record
    └── PricingKey<Currency>() → Pricing   (dynamic field)
```

A Pressing is on sale in `Currency` while it holds a `Pricing` under
`PricingKey<Currency>()`. Each currency has its own pricing, and all of them
consume the same mandatory, immutable Pressing supply cap. Destruction does not
replenish this lifetime cap. Editions are `u16` values created sequentially from
1 by the Record package.

## Sale flow

The release administrator licenses the Release with its splits through
[`release_license`](../release_license), and every track's recording admin
authorizes it there. The release administrator also
creates a Pressing, authorizes the exact witness type, prices it in one or more
currencies, and shares it:

```move
let license = release_license::release_license::new(&mut release, &release_cap, splits);
license.share();
pressing.authorize_distributor<record_shop::witness::Witness>(&pressing_cap);
record_shop::shop::set_pricing<SUI>(
    &mut pressing,
    &pressing_cap,
    &release,
    record_shop::shop::fixed(1_000_000_000),
);
pressing.share();
```

Buyers pass the mutable Pressing, its Release, the Release's `ReleaseLicense`,
a `Balance<Currency>` and the `Clock`. `purchase` returns the Record; the PTB must transfer or otherwise
consume it.

```move
let record = record_shop::shop::purchase(&mut pressing, &release, &license, payment, &clock);
transfer::public_transfer(record, recipient);
```

- `fixed(value)` accepts exactly `value`; `fixed(0)` is free, paid with a zero
  `Balance`.
- `floor(value)` accepts at least `value` and forwards the entire payment;
  `floor(0)` is pay what you want.
- A free Record stores the pricing's currency and a price of 0. A zero payment
  forwards nothing.
- The payment amount is fixed when the buyer signs, so a repricing can't
  charge more: a Fixed price that no longer matches, or a Floor above the
  payment, aborts with `EWrongPayment`.
- A currency the Pressing is not on sale in aborts with `ENoPricing` (4).
- **A release sells only while it is fully licensed.** `purchase` aborts
  `ENotAuthorized` (3) unless the license `is_authorized`: every track's
  recording has authorized the Release. Once `Authorized`, a license can't be
  revoked, so a release that is on sale stays sellable.
- `set_pricing` (add or reprice) and `clear_pricing` (stop selling; silent when
  nothing is set) require the Pressing's `PressingAdminCap`, checked before any
  other check. `set_pricing` also takes the
  Pressing's Release, aborting with `EWrongRelease` for another Release and
  `ENoLicense` (2) when the Release has no `release_license` license. Pricing can
  be set before every recording has authorized. `has_pricing<Currency>` reports
  whether a pricing is set, and `pricing<Currency>` returns `&Pricing`, aborting
  `ENoPricing` when there is none.
- The returned Record stores the concrete currency type, actual amount paid and
  purchase time as immutable provenance. It does not store the buyer; indexers
  read it as the sale event's transaction sender.

All proceeds go straight to the royalty pools of the Release's tracks through
`release_license::forward`: each track's pool address receives its share of the
Release's basis-point splits, rounded down, and the rounding remainder goes to the
license's address, where anyone can forward it later. Recording holders can claim
their share after the next settle; the composition's cut reaches its own pool when
anyone calls `recording_license::sweep`, and the composition's holders claim it
after that pool settles. A `Release` other than the Pressing's aborts with
`EWrongRelease`, and a license for another Release aborts in `release_license`.

## Witness authority

The authorized identity is exactly:

```text
record_shop::witness::Witness
```

`Witness` has only `drop`; its constructor is `public(package)`. Production code
constructs and immediately consumes it only inside `shop::purchase`. The privacy
fixtures prove that an external package can neither pack `Witness()` nor call
`witness::new()`.

## Publication

The package must be made immutable before any Pressing authorizes its Witness.
Publish the package, consume its `UpgradeCap` with `package::make_immutable`, verify
that the capability is gone, and only then authorize
`record_shop::witness::Witness`.

## Events

| Event | Fields |
|---|---|
| `PricingSetEvent<Currency>` | `pressing_id`, `pricing` |
| `PricingClearedEvent<Currency>` | `pressing_id` |

`pricing` is the full `Pricing` enum value (41 BCS bytes with the ID), so
indexers track pricing from events alone. No-op updates and clears of absent pricing emit nothing. A sale
emits no Record Shop event: `record`'s
`RecordPurchasedEvent<record_shop::witness::Witness, Currency>` announces the
Record, and `release_license`'s `ReleaseRevenueForwardedEvent<Currency>` the
forwarded payment, when it pays the tracks.

## Verify

Requires Sui CLI 1.82.1 or a compatible toolchain:

```bash
make verify
```

This runs the Move tests, including the complete ownership and proceeds flow,
then confirms both external witness-construction probes fail for the expected
privacy diagnostics.

See [architecture](docs/ARCHITECTURE.md) and [security](SECURITY.md) for the
invariants and trust boundaries.

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
