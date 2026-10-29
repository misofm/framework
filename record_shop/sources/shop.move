// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module record_shop::shop;

use miso_music::release::Release;
use record::{pressing::{Pressing, PressingAdminCap}, record::Record};
use record_shop::witness;
use release_license::release_license::{Self, ReleaseLicense};
use sui::{balance::Balance, clock::Clock, dynamic_field as df, event::emit};

// === Errors ===

const EWrongRelease: u64 = 0;
const EWrongPayment: u64 = 1;
const ENoLicense: u64 = 2;
const ENotAuthorized: u64 = 3;
const ENoPricing: u64 = 4;

// === Structs ===

public struct PricingKey<phantom Currency>() has copy, drop, store;

// === Enums ===

public enum Pricing has copy, drop, store {
    Fixed(u64),
    Floor(u64),
}

// === Events ===

public struct PricingSetEvent<phantom Currency> has copy, drop {
    pressing_id: ID,
    pricing: Pricing,
}

public struct PricingRemovedEvent<phantom Currency> has copy, drop {
    pressing_id: ID,
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
    clock: &Clock,
): Record {
    assert!(object::id(release) == pressing.release_id(), EWrongRelease);
    assert!(license.is_authorized(), ENotAuthorized);
    let paid_value = payment.value();
    match (pricing<Currency>(pressing)) {
        Pricing::Fixed(value) => assert!(paid_value == *value, EWrongPayment),
        Pricing::Floor(value) => assert!(paid_value >= *value, EWrongPayment),
    };
    let record = pressing.press<witness::Witness, Currency>(witness::new(), paid_value, clock);
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

public fun set_pricing<Currency>(
    pressing: &mut Pressing,
    cap: &PressingAdminCap,
    release: &Release,
    pricing: Pricing,
) {
    assert!(object::id(release) == pressing.release_id(), EWrongRelease);
    assert!(release_license::has_license(release), ENoLicense);
    let uid = pressing.uid_mut(cap);
    if (df::exists(uid, PricingKey<Currency>())) {
        let current: &mut Pricing = df::borrow_mut(uid, PricingKey<Currency>());
        if (*current == pricing) return;
        *current = pricing;
    } else df::add(uid, PricingKey<Currency>(), pricing);
    emit(PricingSetEvent<Currency> { pressing_id: uid.to_inner(), pricing });
}

public fun remove_pricing<Currency>(pressing: &mut Pressing, cap: &PressingAdminCap) {
    let uid = pressing.uid_mut(cap);
    assert!(df::exists(uid, PricingKey<Currency>()), ENoPricing);
    let _: Pricing = df::remove(uid, PricingKey<Currency>());
    emit(PricingRemovedEvent<Currency> { pressing_id: uid.to_inner() });
}

// === Test Functions ===

#[test_only]
public fun set_event_fields<Currency>(event: &PricingSetEvent<Currency>): (ID, Pricing) {
    (event.pressing_id, event.pricing)
}

#[test_only]
public fun removed_event_fields<Currency>(event: &PricingRemovedEvent<Currency>): ID {
    event.pressing_id
}
