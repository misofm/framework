// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module composition_credits::composition_credits;

use composition_credits::composition_party_role::CompositionPartyRole;
use credit::credit::Credit;
use miso_music::composition::{Composition, CompositionAdminCap};
use miso_party::party::Party;
use std::string::String;
use sui::{dynamic_field as df, event::emit, vec_map::{Self, VecMap}};

// === Errors ===

const ETooManyCredits: u64 = 0;
const EPartyAlreadyCredited: u64 = 1;
const ENoCredits: u64 = 2;
const EPartyNotFound: u64 = 3;

// === Constants ===

const MAX_CREDITS: u64 = 50;

// === Structs ===

public struct CompositionCredits has store {
    credits: VecMap<ID, Credit<CompositionPartyRole>>,
}

public struct CompositionCreditsKey() has copy, drop, store;

// === Events ===

public struct CompositionCreditAddedEvent has copy, drop {
    composition_id: ID,
    party_id: ID,
    display_name: String,
    roles: vector<CompositionPartyRole>,
}

public struct CompositionCreditRemovedEvent has copy, drop {
    composition_id: ID,
    party_id: ID,
}

// === View Functions ===

public fun has_credits<CompositionShare>(composition: &Composition<CompositionShare>): bool {
    df::exists(composition.uid(), CompositionCreditsKey())
}

public fun credits<CompositionShare>(
    composition: &Composition<CompositionShare>,
): &VecMap<ID, Credit<CompositionPartyRole>> {
    assert!(df::exists(composition.uid(), CompositionCreditsKey()), ENoCredits);
    let record: &CompositionCredits = df::borrow(composition.uid(), CompositionCreditsKey());
    &record.credits
}

// === Admin Functions ===

public fun add_credit<CompositionShare>(
    composition: &mut Composition<CompositionShare>,
    cap: &CompositionAdminCap<CompositionShare>,
    party: &Party,
    credit: Credit<CompositionPartyRole>,
) {
    let composition_id = object::id(composition);
    let party_id = object::id(party);
    let display_name = *credit.display_name();
    let roles = *credit.roles();
    let uid = composition.uid_mut(cap);
    if (!df::exists(uid, CompositionCreditsKey())) {
        df::add(uid, CompositionCreditsKey(), CompositionCredits { credits: vec_map::empty() });
    };
    let record: &mut CompositionCredits = df::borrow_mut(uid, CompositionCreditsKey());
    assert!(record.credits.length() < MAX_CREDITS, ETooManyCredits);
    assert!(!record.credits.contains(&party_id), EPartyAlreadyCredited);
    record.credits.insert(party_id, credit);
    emit(CompositionCreditAddedEvent { composition_id, party_id, display_name, roles });
}

public fun remove_credit<CompositionShare>(
    composition: &mut Composition<CompositionShare>,
    cap: &CompositionAdminCap<CompositionShare>,
    party_id: ID,
) {
    let composition_id = object::id(composition);
    let uid = composition.uid_mut(cap);
    assert!(df::exists(uid, CompositionCreditsKey()), ENoCredits);
    let record: &mut CompositionCredits = df::borrow_mut(uid, CompositionCreditsKey());
    assert!(record.credits.contains(&party_id), EPartyNotFound);
    record.credits.remove(&party_id);
    if (record.credits.is_empty()) {
        let CompositionCredits { credits } = df::remove(uid, CompositionCreditsKey());
        credits.destroy_empty();
    };
    emit(CompositionCreditRemovedEvent { composition_id, party_id });
}

// === Test Functions ===

#[test_only]
public fun composition_credit_added_fields_for_testing(
    event: &CompositionCreditAddedEvent,
): (ID, ID, String, vector<CompositionPartyRole>) {
    (event.composition_id, event.party_id, event.display_name, event.roles)
}

#[test_only]
public fun composition_credit_removed_fields_for_testing(
    event: &CompositionCreditRemovedEvent,
): (ID, ID) {
    (event.composition_id, event.party_id)
}
