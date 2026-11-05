// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module record_sale::sale;

use miso_music::release::Release;
use record::{pressing::{Pressing, PressingAdminCap}, record::{Self, Record}};
use record_sale::witness::{Self, Witness};
use release_license::release_license::{Self, ReleaseLicense};
use sui::{balance::Balance, dynamic_field as df, event::emit};

// === Errors ===

const EWrongRelease: u64 = 0;
const EWrongPayment: u64 = 1;
const ENoLicense: u64 = 2;
const ENotAuthorized: u64 = 3;
const ENoPrice: u64 = 4;
const EPriceExists: u64 = 5;

// === Structs ===

public struct PriceKey<phantom Currency>() has copy, drop, store;

// === Events ===

public struct SaleAuthorizedEvent<phantom Currency> has copy, drop {
    pressing_id: ID,
    price: u64,
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
): Record {
    assert!(object::id(release) == pressing.release_id(), EWrongRelease);
    assert!(license.is_authorized(), ENotAuthorized);
    let price = price<Currency>(pressing);
    assert!(payment.value() == price, EWrongPayment);
    let record = record::new(pressing, witness::new());
    emit(RecordSoldEvent<Currency> {
        record_id: object::id(&record),
        pressing_id: object::id(pressing),
        price,
    });
    release_license::forward(license, release, payment);
    record
}

// === View Functions ===

public fun has_price<Currency>(pressing: &Pressing): bool {
    df::exists(pressing.uid(), PriceKey<Currency>())
}

public fun price<Currency>(pressing: &Pressing): u64 {
    assert!(has_price<Currency>(pressing), ENoPrice);
    *df::borrow(pressing.uid(), PriceKey<Currency>())
}

// === Admin Functions ===

public fun authorize<Currency>(
    pressing: &mut Pressing,
    cap: &PressingAdminCap,
    release: &Release,
    price: u64,
) {
    pressing.authorize_distributor<Witness>(cap);
    let pressing_release_id = pressing.release_id();
    let uid = pressing.uid_mut(cap);
    assert!(object::id(release) == pressing_release_id, EWrongRelease);
    assert!(release_license::has_license(release), ENoLicense);
    assert!(!df::exists(uid, PriceKey<Currency>()), EPriceExists);
    df::add(uid, PriceKey<Currency>(), price);
    emit(SaleAuthorizedEvent<Currency> { pressing_id: uid.to_inner(), price });
}

// === Test Functions ===

#[test_only]
public fun sale_authorized_fields_for_testing<Currency>(
    event: &SaleAuthorizedEvent<Currency>,
): (ID, u64) {
    (event.pressing_id, event.price)
}

#[test_only]
public fun record_sold_fields_for_testing<Currency>(
    event: &RecordSoldEvent<Currency>,
): (ID, ID, u64) {
    (event.record_id, event.pressing_id, event.price)
}
