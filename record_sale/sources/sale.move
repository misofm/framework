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
const ENoPricing: u64 = 4;
const EPricingExists: u64 = 5;

// === Structs ===

public struct PricingKey<phantom Currency>() has copy, drop, store;

// === Enums ===

public enum Pricing has copy, drop, store {
    Fixed(u64),
    Floor(u64),
}

// === Events ===

public struct SaleAuthorizedEvent<phantom Currency> has copy, drop {
    pressing_id: ID,
    pricing: Pricing,
}

public struct RecordSoldEvent<phantom Currency> has copy, drop {
    record_id: ID,
    pressing_id: ID,
    value: u64,
}

// === Public Functions ===

public fun fixed(value: u64): Pricing {
    Pricing::Fixed(value)
}

public fun floor(value: u64): Pricing {
    Pricing::Floor(value)
}

public fun purchase<Currency>(
    pressing: &mut Pressing,
    release: &Release,
    license: &ReleaseLicense,
    payment: Balance<Currency>,
): Record {
    assert!(object::id(release) == pressing.release_id(), EWrongRelease);
    assert!(license.is_authorized(), ENotAuthorized);
    let paid_value = payment.value();
    match (pricing<Currency>(pressing)) {
        Pricing::Fixed(value) => assert!(paid_value == *value, EWrongPayment),
        Pricing::Floor(value) => assert!(paid_value >= *value, EWrongPayment),
    };
    let record = record::new(pressing, witness::new());
    emit(RecordSoldEvent<Currency> {
        record_id: object::id(&record),
        pressing_id: object::id(pressing),
        value: paid_value,
    });
    release_license::forward(license, release, payment);
    record
}

// === View Functions ===

public fun has_pricing<Currency>(pressing: &Pressing): bool {
    df::exists(pressing.uid(), PricingKey<Currency>())
}

public fun pricing<Currency>(pressing: &Pressing): &Pricing {
    assert!(has_pricing<Currency>(pressing), ENoPricing);
    df::borrow(pressing.uid(), PricingKey<Currency>())
}

public fun value(self: &Pricing): u64 {
    match (self) {
        Pricing::Fixed(value) | Pricing::Floor(value) => *value,
    }
}

public fun is_fixed(self: &Pricing): bool {
    match (self) {
        Pricing::Fixed(_) => true,
        Pricing::Floor(_) => false,
    }
}

// === Admin Functions ===

public fun authorize<Currency>(
    pressing: &mut Pressing,
    cap: &PressingAdminCap,
    release: &Release,
    pricing: Pricing,
) {
    pressing.authorize_distributor<Witness>(cap);
    let pressing_release_id = pressing.release_id();
    let uid = pressing.uid_mut(cap);
    assert!(object::id(release) == pressing_release_id, EWrongRelease);
    assert!(release_license::has_license(release), ENoLicense);
    assert!(!df::exists(uid, PricingKey<Currency>()), EPricingExists);
    df::add(uid, PricingKey<Currency>(), pricing);
    emit(SaleAuthorizedEvent<Currency> { pressing_id: uid.to_inner(), pricing });
}

// === Test Functions ===

#[test_only]
public fun sale_authorized_fields_for_testing<Currency>(
    event: &SaleAuthorizedEvent<Currency>,
): (ID, Pricing) {
    (event.pressing_id, event.pricing)
}

#[test_only]
public fun record_sold_fields_for_testing<Currency>(
    event: &RecordSoldEvent<Currency>,
): (ID, ID, u64) {
    (event.record_id, event.pressing_id, event.value)
}
