# Architecture

## State and identity

The Record Shop's only state is a `Pricing` dynamic field on each Pressing, one
per currency, at `PricingKey<Currency>()`:

- `Pricing::Fixed(u64)` or `Pricing::Floor(u64)`, where a price of 0 is free or
  pay what you want.

Holding a pricing is what puts the Pressing on sale in that currency. A pricing is
written once and never changes or goes away: `add_pricing` aborts `EPricingExists`
for a currency that already has one, and there is no clear or pause. There is no
listing object, enabled flag or stored Pressing ID: the pricing lives on the
Pressing it prices. The Release is not stored; `add_pricing` and `purchase` check
it against the Pressing's `release_id`.

`add_pricing` also requires the Release to have a `release_license` license
(`ENoLicense`). `purchase` takes that license and requires it to be `Authorized`
(`ENotAuthorized`), so a release sells only while every track's recording has
authorized it. Once `Authorized`, a license stays `Authorized` and its splits are
fixed, so licensing can't stop a sellable release from selling. Sales end only
when the Pressing sells out or its admin removes the Record Shop as a distributor
with `revoke_distributor`.

A purchase reads the pricing from the Pressing it already mutates, so a sale takes
no shared input besides the Pressing, the Release and its license, the last two
read-only. Every press mutates the
Pressing because it owns the edition-local sequence and supply cap.

## Events

Events are currency-typed and carry the full value, so an indexer can track
every Pressing's pricing from events alone, without reading the dynamic field:

| Event | Fields | Bytes |
|---|---|---|
| `PricingAddedEvent<Currency>` | `pressing_id`, `pricing` (the `Pricing` enum value) | 41 |
| `RecordPurchasedEvent<Currency>` | `record_id`, `pressing_id`, `value` | 72 |

A sale changes no Record Shop state. It emits
`RecordPurchasedEvent<Currency>` with the amount paid as `value`; `record::new`
emits `RecordCreatedEvent<witness::Witness>` for the new Record, carrying the
Release and edition, and `release_license::forward` emits
`ReleaseRevenueForwardedEvent<Currency>` when the payment pays the tracks. The
event types name the distributor and currency.

## Authority

`PressingAdminCap` is the only pricing capability: `add_pricing` goes through the
Pressing's cap-gated `uid_mut`. The split that
divides proceeds is set once by the `ReleaseAdminCap` through `release_license`,
and each track's `RecordingAdminCap` authorizes the Release there.

The Record Shop does not hold press authority as an object. A Pressing instead
authorizes the type `record_shop::witness::Witness`. `purchase` creates the
drop-only package witness after all sale checks and passes it directly to
`record::new`.

## Purchase ordering

`purchase` performs these checks and effects atomically:

1. require the Pressing's Release and an `Authorized` license;
2. read the Pressing's `Currency` pricing, aborting if there is none;
3. validate exact Fixed payment or minimum Floor payment;
4. press the next Record through the authorized witness and emit
   `RecordPurchasedEvent<Currency>` with the amount paid;
5. forward the entire Balance with `release_license::forward`, which sends each
   track's royalty pool address its basis-point share of the payment, rounded
   down, and the remainder to the license's address;
6. return the Record for PTB composition.

Move transaction atomicity rolls back the sequence increment, Record derivation,
payment forwarding, and events if any later command aborts.

## Immutability

The package is intended to be made immutable when published. Future Record Shop
designs ship as separate packages with explicit migration paths, so pricings do
not carry package-upgrade versions. Its `UpgradeCap` must be consumed before any
Pressing authorizes the package Witness.

## Edition supply

All currencies and distributors share the Pressing lifetime issuance ceiling.
The Pressing's `max_supply` is always positive; there is no optional cap or zero
sentinel. The Pressing enforces exhaustion atomically before payment is sent.
Whether a Pressing is priced is independent of sold-out status. Sequential
edition creation is enforced by Record using the previous derived claim on the
Release.
