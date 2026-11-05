# record_sale

`record_sale` is the first-party fixed-price sales package for Miso Records on
Sui. The Pressing's admin authorizes the sale with its price in one call; its
only state is that price and its currency, stored on the Pressing. There is no
global sale, Distributor or listing object.

```text
Release
└── PressingKey(edition) → Pressing
    ├── RecordKey(number) → Record
    └── PriceKey() → Price { currency, value }   (dynamic field)
```

A Pressing is on sale while record_sale is an authorized distributor and the
Pressing holds a `Price` under `PriceKey()`. A Pressing has one price in one
currency, forever.
Sales consume the Pressing's mandatory, immutable supply cap, shared with every
other distributor. Destruction does not
replenish this lifetime cap. Editions are `u16` values created sequentially from
1 by the Record package.

## Sale flow

The release administrator licenses the Release with its splits through
[`release_license`](../release_license), and every track's recording admin
authorizes it there. The release administrator also
creates a Pressing, authorizes the sale at its price, and shares it:

```move
let license = release_license::release_license::new(&mut release, &release_cap, splits);
license.share();
record_sale::sale::authorize<SUI>(
    &mut pressing,
    &pressing_cap,
    &release,
    1_000_000_000,
);
pressing.share();
```

Buyers pass the mutable Pressing, its Release, the Release's `ReleaseLicense`,
and a `Balance<Currency>`. `purchase` returns the Record; the PTB must transfer or otherwise
consume it.

```move
let record = record_sale::sale::purchase(&mut pressing, &release, &license, payment);
transfer::public_transfer(record, recipient);
```

- `purchase` accepts exactly the price, aborting `EWrongPayment` (1) otherwise.
  A price of 0 is free, paid with a zero `Balance`; a free sale emits a
  `RecordSoldEvent` with a price of 0 and forwards nothing.
- **Tips are separate.** Pay what you want is a price (often 0) plus a tip the
  client sends in the same PTB with `release_license::forward`, which pays the
  same pools by the same splits:

  ```move
  let record = record_sale::sale::purchase(&mut pressing, &release, &license, price_payment);
  release_license::release_license::forward(&license, &release, tip);
  ```

  The tip appears only in `ReleaseRevenueForwardedEvent`; nothing on-chain
  depends on it.
- **A price is final.** `authorize` sets it once, in one currency, and there is
  no way to change or remove it or add another currency. Authorizing again aborts
  in `record` (`EDistributorAlreadyAuthorized`), or with `EPriceExists` (5)
  after a revoke, in any currency. A different price or currency is a different
  pressing or edition.
- **There is no pause.** The Pressing's admin can only remove record_sale as a
  distributor with `revoke_distributor`. Authorizing it again through
  `record` restores the sale at its original price.
- Paying in another currency aborts with `EWrongCurrency` (6), and a Pressing
  with no price aborts with `ENoPrice` (4).
- **A release sells only while it is fully licensed.** `purchase` aborts
  `ENotAuthorized` (3) unless the license `is_authorized`: every track's
  recording has authorized the Release. Once `Authorized`, a license can't be
  revoked, so licensing can't stop a release that is on sale.
- `authorize` requires the Pressing's `PressingAdminCap`, checked before any
  other check. It also takes the
  Pressing's Release, aborting with `EWrongRelease` for another Release and
  `ENoLicense` (2) when the Release has no `release_license` license. A sale can
  be authorized before every recording has authorized the Release. `has_price` reports
  whether a price is set; `price` and `currency` return it, aborting `ENoPrice`
  when there is none.
- The returned Record stores no sale data. The currency type and price are in
  the sale's `RecordSoldEvent<Currency>`; the buyer is that event's
  transaction sender.

All proceeds go straight to the royalty pools of the Release's tracks through
`release_license::forward`: each track's pool address receives its share of the
Release's basis-point splits, rounded down, and the rounding remainder goes to the
license's address, where anyone can forward it later. Recording holders can claim
their share after the next settle; the composition's cut reaches its own pool when
anyone calls `recording_revenue_share::sweep`, and the composition's holders claim it
after that pool settles. A `Release` other than the Pressing's aborts with
`EWrongRelease`, and a license for another Release aborts in `release_license`.

## Errors

| Code | Name | Raised by |
|---|---|---|
| 0 | `EWrongRelease` | `purchase`, `authorize`: the Release is not the Pressing's |
| 1 | `EWrongPayment` | `purchase`: the payment is not exactly the price |
| 2 | `ENoLicense` | `authorize`: the Release has no `release_license` license |
| 3 | `ENotAuthorized` | `purchase`: the license is not `Authorized` |
| 4 | `ENoPrice` | `purchase`, `price`, `currency`: the Pressing has no price |
| 5 | `EPriceExists` | `authorize`: a revoked sale keeps its price, so authorizing it again, in any currency, aborts |
| 6 | `EWrongCurrency` | `purchase`: the payment is not in the price's currency |

A foreign `PressingAdminCap`, a second `authorize`, a revoked sale and a sold-out
Pressing abort in `record` (`EUnauthorized`, `EDistributorAlreadyAuthorized`,
`EDistributorNotAuthorized`, `EMaxSupplyReached`); a license for another Release aborts in `release_license`.

## Witness authority

The authorized identity is exactly:

```text
record_sale::witness::Witness
```

`Witness` has only `drop`; its constructor is `public(package)`. Production code
constructs and immediately consumes it only inside `sale::purchase`. The privacy
fixtures prove that an external package can neither pack `Witness()` nor call
`witness::new()`.

## Publication

The package must be made immutable before any Pressing authorizes its Witness.
Publish the package, consume its `UpgradeCap` with `package::make_immutable`, verify
that the capability is gone, and only then authorize
`record_sale::witness::Witness`.

## Events

| Event | Fields |
|---|---|
| `SaleAuthorizedEvent<Currency>` | `pressing_id`, `price` |
| `RecordSoldEvent<Currency>` | `record_id`, `pressing_id`, `price` |

`SaleAuthorizedEvent<Currency>` (40 BCS bytes) carries the price, so indexers
track prices from events alone. A sale emits `RecordSoldEvent<Currency>` (72 BCS
bytes) with the price; `record`'s `RecordCreatedEvent<record_sale::witness::Witness>`
announces the Record, and `release_license`'s
`ReleaseRevenueForwardedEvent<Currency>` the forwarded payment, when it pays the
tracks.

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
