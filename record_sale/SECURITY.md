# Security

## Invariants

- External packages cannot construct `record_sale::witness::Witness` by
  packing it or by calling its package-visible constructor.
- A purchase cannot press a Record unless the bound Pressing currently authorizes that exact
  witness type.
- A price applies only to the Pressing that stores it, and `purchase` requires
  the Pressing's own Release.
- A Pressing holds at most one record_sale price, in one currency, written with
  the authorization, and it never changes, goes away or gains a second currency.
- Authorizing a sale requires the Pressing's `PressingAdminCap`.
- `purchase` rejects underpayment, overpayment and any other currency. A tip is a separate
  `release_license::forward` the client adds; this package never takes more
  than the price.
- All payment is forwarded to the Release's tracks' royalty pools, with the
  rounding remainder sent to the license's address; no proceeds remain in a
  Pressing or record_sale-owned object.
- Record lineage, numbering, Distributor type, and maximum supply are enforced
  by `record`. Currency and price are not stored on the Record; record_sale's
  `RecordSoldEvent<Currency>` reports them from the consumed
  `Balance<Currency>`.

- Every Pressing has a positive immutable lifetime supply ceiling shared across
  distributors. Burns and distributor changes cannot replenish it.
- Editions start at 1 and require the previous edition claim on the same Release;
  this does not require sellout or prevent additional editions.

## Trust boundaries

The holder of a `PressingAdminCap` can authorize record_sale once, with its price and currency,
and can authorize or revoke Distributor types on the Pressing. It cannot reprice or pause
a sale; the only way to end record_sale sales early is to revoke its witness. Secure capability
custody is therefore required. Revocation immediately stops new record_sale presses,
but does not affect Records already sold.

`PressingAdminCap` and `ReleaseAdminCap` must remain address-owned or wrapped in
trusted custody. Never share or freeze either capability: doing so makes its
reference publicly available and therefore makes its authority public.

The package must be made immutable before its Witness is authorized. Retaining its
`UpgradeCap` would allow later code to construct the same authorized Witness while
bypassing the price and payment checks.

A tip forwarded beside a purchase is non-refundable at the contract layer.
Frontends should make its amount explicit.

A free (price 0) sale lets any address
take Records up to `max_supply` for the cost of gas and storage. This package has
no per-buyer limit; gate claims with a separate Distributor if that matters.

Proceeds are forwarded to the tracks' royalty pool addresses with
`release_license::forward`, which divides them by the license's basis-point splits
and writes no shared object. The published package links one exact version of
`release_license`, so a later upgrade cannot redirect this package's proceeds. The
splits can be replaced only while the license is `Authorizing` with no
authorizations, and `authorize` requires a license. A sale requires the license to be `Authorized`, so nothing is sold while
any track's recording has not authorized the Release. Once `Authorized`, the
license can't be revoked and its splits can't change, so buyers and the release
administrator can rely on it.
Funds sent to a pool address wait there until the pool exists and has registered
stakes; the small rounding remainder goes to the license's address, where anyone's
`release_license::redeem_and_forward` forwards it later.

A Record stores neither its buyer nor its recipient; the event's transaction sender
is the buyer. The caller must consume the returned Record in the same PTB, normally
with `transfer::public_transfer`; this permits gifts and composition. Purchase
provenance is in the sale's `RecordSoldEvent<Currency>` and `record`'s
`RecordCreatedEvent`, neither of which claims a final owner.

## Verification

`make verify` runs success and abort-path unit tests plus two external compile-fail
fixtures. The end-to-end scenario covers Release → capped Pressing → Witness
authorization → Pressing price → buyer payment → returned Record →
buyer ownership → proceeds forwarded to the tracks' royalty pools.

Report suspected vulnerabilities privately through this repository's GitHub
Security Advisory workflow before public disclosure.
