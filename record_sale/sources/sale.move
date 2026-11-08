// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module record_sale::sale;

use miso_music::release::Release;
use record::{pressing::{Pressing, PressingAdminCap}, record::{Self, Record}};
use record_sale::witness::{Self, Witness};
use release_license::release_license::{Self, ReleaseLicense};
use sui::{balance::Balance, clock::Clock, dynamic_field as df, event::emit};

// === Errors ===

const EWrongRelease: u64 = 0;
const EWrongPayment: u64 = 1;
const ENoLicense: u64 = 2;
const ENotAuthorized: u64 = 3;
const ENoSale: u64 = 4;
const ESaleExists: u64 = 5;
const EWrongCurrency: u64 = 6;
const ENotStarted: u64 = 7;
const EStarted: u64 = 8;

// === Structs ===

/// A Pressing's sale: its price in `Currency` and when it starts. The currency is the type, so
/// there is one value per Pressing, at `RecordSaleKey()`, in exactly one currency.
public struct RecordSale<phantom Currency> has copy, drop, store {
    price: u64,
    starts_at_ms: u64,
}

public struct RecordSaleKey() has copy, drop, store;

// === Events ===

public struct SaleAuthorizedEvent<phantom Currency> has copy, drop {
    pressing_id: ID,
    price: u64,
    starts_at_ms: u64,
}

public struct SaleUpdatedEvent<phantom Currency> has copy, drop {
    pressing_id: ID,
    price: u64,
    starts_at_ms: u64,
}

public struct RecordSoldEvent<phantom Currency> has copy, drop {
    record_id: ID,
    pressing_id: ID,
    price: u64,
}

// === Public Functions ===

public fun purchase<Currency>(
    pressing: &mut Pressing,
    release: &Release,
    license: &ReleaseLicense,
    payment: Balance<Currency>,
    clock: &Clock,
): Record {
    assert!(object::id(release) == pressing.release_id(), EWrongRelease);
    assert!(license.is_authorized(), ENotAuthorized);
    let sale = *borrow_sale<Currency>(pressing);
    assert!(clock.timestamp_ms() >= sale.starts_at_ms, ENotStarted);
    assert!(payment.value() == sale.price, EWrongPayment);
    let record = record::new(pressing, witness::new());
    emit(RecordSoldEvent<Currency> {
        record_id: object::id(&record),
        pressing_id: object::id(pressing),
        price: sale.price,
    });
    release_license::forward(license, release, payment);
    record
}

// === View Functions ===

public fun has_sale(pressing: &Pressing): bool {
    df::exists(pressing.uid(), RecordSaleKey())
}

/// Whether the Pressing's sale is in `Currency`; false when it has none.
public fun is_currency<Currency>(pressing: &Pressing): bool {
    df::exists_with_type<RecordSaleKey, RecordSale<Currency>>(pressing.uid(), RecordSaleKey())
}

public fun price<Currency>(pressing: &Pressing): u64 {
    borrow_sale<Currency>(pressing).price
}

public fun starts_at_ms<Currency>(pressing: &Pressing): u64 {
    borrow_sale<Currency>(pressing).starts_at_ms
}

/// Whether the sale has started: from `starts_at_ms` on, its price and start are final.
public fun is_started<Currency>(pressing: &Pressing, clock: &Clock): bool {
    clock.timestamp_ms() >= borrow_sale<Currency>(pressing).starts_at_ms
}

// === Admin Functions ===

/// Authorizes record_sale on the Pressing and writes its sale: `price` in `Currency`, buyable
/// from `starts_at_ms` (any time, including the past: then at once). One sale per Pressing.
public fun authorize<Currency>(
    pressing: &mut Pressing,
    cap: &PressingAdminCap,
    release: &Release,
    price: u64,
    starts_at_ms: u64,
) {
    pressing.authorize_distributor<Witness>(cap);
    let pressing_release_id = pressing.release_id();
    let uid = pressing.uid_mut(cap);
    assert!(object::id(release) == pressing_release_id, EWrongRelease);
    assert!(release_license::has_license(release), ENoLicense);
    assert!(!df::exists(uid, RecordSaleKey()), ESaleExists);
    df::add(uid, RecordSaleKey(), RecordSale<Currency> { price, starts_at_ms });
    emit(SaleAuthorizedEvent<Currency> { pressing_id: uid.to_inner(), price, starts_at_ms });
}

/// Changes the price and start of a sale that has not started. Once it has, both are final
/// (`EStarted`). A start at or before now opens the sale at once. A no-op, with no event, when
/// nothing changes.
public fun update<Currency>(
    pressing: &mut Pressing,
    cap: &PressingAdminCap,
    price: u64,
    starts_at_ms: u64,
    clock: &Clock,
) {
    let uid = pressing.uid_mut(cap);
    let pressing_id = uid.to_inner();
    assert!(df::exists(uid, RecordSaleKey()), ENoSale);
    assert!(df::exists_with_type<RecordSaleKey, RecordSale<Currency>>(uid, RecordSaleKey()), EWrongCurrency);
    let sale: &mut RecordSale<Currency> = df::borrow_mut(uid, RecordSaleKey());
    assert!(clock.timestamp_ms() < sale.starts_at_ms, EStarted);
    if (sale.price == price && sale.starts_at_ms == starts_at_ms) return;
    sale.price = price;
    sale.starts_at_ms = starts_at_ms;
    emit(SaleUpdatedEvent<Currency> { pressing_id, price, starts_at_ms });
}

// === Private Functions ===

fun borrow_sale<Currency>(pressing: &Pressing): &RecordSale<Currency> {
    let uid = pressing.uid();
    assert!(df::exists(uid, RecordSaleKey()), ENoSale);
    assert!(df::exists_with_type<RecordSaleKey, RecordSale<Currency>>(uid, RecordSaleKey()), EWrongCurrency);
    df::borrow(uid, RecordSaleKey())
}

// === Test Functions ===

#[test_only]
public fun sale_authorized_fields_for_testing<Currency>(
    event: &SaleAuthorizedEvent<Currency>,
): (ID, u64, u64) {
    (event.pressing_id, event.price, event.starts_at_ms)
}

#[test_only]
public fun sale_updated_fields_for_testing<Currency>(
    event: &SaleUpdatedEvent<Currency>,
): (ID, u64, u64) {
    (event.pressing_id, event.price, event.starts_at_ms)
}

#[test_only]
public fun record_sold_fields_for_testing<Currency>(
    event: &RecordSoldEvent<Currency>,
): (ID, ID, u64) {
    (event.record_id, event.pressing_id, event.price)
}
