# Architecture

## State and identity

record_sale's only state is one `Price { currency, value }` dynamic field on
each Pressing it sells, at `PriceKey()`. A Pressing has one price in one
currency; the key is not currency-typed, so a second currency can't be added.
A price of 0 is free. There is no floor or
pay-what-you-want mode: a tip is a separate `release_license::forward` in the
buyer's PTB.

`authorize` authorizes record_sale's witness on the Pressing and writes the
price in the same call. A price is written once and never changes or goes
away: authorizing again aborts, and there is no clear or pause. There is no
listing object, enabled flag or stored Pressing ID: the price lives on the
Pressing it prices. The Release is not stored; `authorize` and `purchase` check
it against the Pressing's `release_id`.

`authorize` also requires the Release to have a `release_license` license
(`ENoLicense`). `purchase` takes that license and requires it to be `Authorized`
(`ENotAuthorized`), so a release sells only while every track's recording has
authorized it. Once `Authorized`, a license stays `Authorized` and its splits are
fixed, so licensing can't stop a sellable release from selling. Sales end only
when the Pressing sells out or its admin removes record_sale as a distributor
with `revoke_distributor`.

A purchase reads the price from the Pressing it already mutates, so a sale takes
no shared input besides the Pressing, the Release and its license, the last two
read-only. Every press mutates the
Pressing because it owns the edition-local sequence and supply cap.

## Events

Events are currency-typed and carry the full value, so an indexer can track
every Pressing's price from events alone, without reading the dynamic field:

| Event | Fields | Bytes |
|---|---|---|
| `SaleAuthorizedEvent<Currency>` | `pressing_id`, `price` | 40 |
| `RecordSoldEvent<Currency>` | `record_id`, `pressing_id`, `price` | 72 |

A sale changes no record_sale state. It emits
`RecordSoldEvent<Currency>` with the price; `record::new`
emits `RecordCreatedEvent<witness::Witness>` for the new Record, carrying the
Release and edition, and `release_license::forward` emits
`ReleaseRevenueForwardedEvent<Currency>` when the payment pays the tracks. The
event types name the distributor and currency.

## Authority

`PressingAdminCap` is the only price capability: `authorize` goes through the
Pressing's cap-gated `authorize_distributor` and `uid_mut`. The split that
divides proceeds is set once by the `ReleaseAdminCap` through `release_license`,
and each track's `RecordingAdminCap` authorizes the Release there.

record_sale does not hold press authority as an object. A Pressing instead
authorizes the type `record_sale::witness::Witness`. `purchase` creates the
drop-only package witness after all sale checks and passes it directly to
`record::new`.

## Purchase ordering

`purchase` performs these checks and effects atomically:

1. require the Pressing's Release and an `Authorized` license;
2. read the Pressing's price, aborting if there is none;
3. require the payment to be in the price's currency and equal its value;
4. press the next Record through the authorized witness and emit
   `RecordSoldEvent<Currency>` with the price;
5. forward the entire Balance with `release_license::forward`, which sends each
   track's royalty pool address its basis-point share of the payment, rounded
   down, and the remainder to the license's address;
6. return the Record for PTB composition.

Move transaction atomicity rolls back the sequence increment, Record derivation,
payment forwarding, and events if any later command aborts.

## Immutability

The package is intended to be made immutable when published. Future sale
designs ship as separate packages with explicit migration paths, so prices do
not carry package-upgrade versions. Its `UpgradeCap` must be consumed before any
Pressing authorizes the package Witness.

## Edition supply

All distributors share the Pressing lifetime issuance ceiling.
The Pressing's `max_supply` is always positive; there is no optional cap or zero
sentinel. The Pressing enforces exhaustion atomically before payment is sent.
Whether a Pressing is priced is independent of sold-out status. Sequential
edition creation is enforced by Record using the previous derived claim on the
Release.
