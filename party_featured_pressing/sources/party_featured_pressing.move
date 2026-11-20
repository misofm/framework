// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module party_featured_pressing::party_featured_pressing;

use miso_party::party::{Party, PartyAdminCap};
use record::pressing::Pressing;
use sui::{dynamic_field as df, event::emit};

// === Structs ===

public struct PartyFeaturedPressingKey() has copy, drop, store;

// === Events ===

public struct PartyFeaturedPressingSetEvent has copy, drop {
    party_id: ID,
    pressing_id: ID,
}

public struct PartyFeaturedPressingClearedEvent has copy, drop {
    party_id: ID,
}

// === View Functions ===

public fun featured_pressing(party: &Party): Option<ID> {
    if (!df::exists(party.uid(), PartyFeaturedPressingKey())) return option::none();
    option::some(*df::borrow(party.uid(), PartyFeaturedPressingKey()))
}

// === Admin Functions ===

public fun set_featured_pressing(party: &mut Party, cap: &PartyAdminCap, pressing: &Pressing) {
    let party_id = object::id(party);
    let pressing_id = object::id(pressing);
    let uid = party.uid_mut(cap);
    if (df::exists(uid, PartyFeaturedPressingKey())) {
        let previous: &mut ID = df::borrow_mut(uid, PartyFeaturedPressingKey());
        if (*previous == pressing_id) return;
        *previous = pressing_id;
    } else {
        df::add(uid, PartyFeaturedPressingKey(), pressing_id);
    };
    emit(PartyFeaturedPressingSetEvent { party_id, pressing_id });
}

public fun clear_featured_pressing(party: &mut Party, cap: &PartyAdminCap) {
    let party_id = object::id(party);
    let uid = party.uid_mut(cap);
    if (!df::exists(uid, PartyFeaturedPressingKey())) return;
    let _: ID = df::remove(uid, PartyFeaturedPressingKey());
    emit(PartyFeaturedPressingClearedEvent { party_id });
}

// === Test Functions ===

#[test_only]
public fun party_featured_pressing_set_fields_for_testing(
    event: &PartyFeaturedPressingSetEvent,
): (ID, ID) {
    (event.party_id, event.pressing_id)
}

#[test_only]
public fun party_featured_pressing_cleared_fields_for_testing(
    event: &PartyFeaturedPressingClearedEvent,
): ID {
    event.party_id
}
