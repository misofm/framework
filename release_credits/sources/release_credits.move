// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module release_credits::release_credits;

use credit::credit::Credit;
use miso_music::release::{Release, ReleaseAdminCap};
use miso_party::party::Party;
use release_credits::release_party_role::ReleasePartyRole;
use std::string::String;
use sui::{dynamic_field as df, event::emit, vec_map::{Self, VecMap}};

// === Errors ===

const ETooManyCredits: u64 = 0;
const EPartyAlreadyCredited: u64 = 1;
const ENoCredits: u64 = 2;
const EPartyNotFound: u64 = 3;
const EInvalidCreditRoleCount: u64 = 4;

// === Constants ===

const CREDIT_ROLE_COUNT: u64 = 1;
const MAX_CREDITS: u64 = 50;

// === Structs ===

public struct ReleaseCredits has store {
    credits: VecMap<ID, Credit<ReleasePartyRole>>,
}

public struct ReleaseCreditsKey() has copy, drop, store;

// === Events ===

public struct ReleaseCreditAddedEvent has copy, drop {
    release_id: ID,
    party_id: ID,
    display_name: String,
    role: ReleasePartyRole,
}

public struct ReleaseCreditRemovedEvent has copy, drop {
    release_id: ID,
    party_id: ID,
}

// === View Functions ===

public fun has_credits(release: &Release): bool {
    df::exists(release.uid(), ReleaseCreditsKey())
}

public fun credits(release: &Release): &VecMap<ID, Credit<ReleasePartyRole>> {
    assert!(has_credits(release), ENoCredits);
    let record: &ReleaseCredits = df::borrow(release.uid(), ReleaseCreditsKey());
    &record.credits
}

// === Admin Functions ===

public fun add_credit(
    release: &mut Release,
    cap: &ReleaseAdminCap,
    party: &Party,
    credit: Credit<ReleasePartyRole>,
) {
    assert!(credit.roles().length() == CREDIT_ROLE_COUNT, EInvalidCreditRoleCount);
    let release_id = object::id(release);
    let party_id = object::id(party);
    let display_name = *credit.display_name();
    let role = credit.roles()[0];
    let uid = release.uid_mut(cap);
    if (!df::exists(uid, ReleaseCreditsKey())) {
        df::add(uid, ReleaseCreditsKey(), ReleaseCredits { credits: vec_map::empty() });
    };
    let record: &mut ReleaseCredits = df::borrow_mut(uid, ReleaseCreditsKey());
    assert!(record.credits.length() < MAX_CREDITS, ETooManyCredits);
    assert!(!record.credits.contains(&party_id), EPartyAlreadyCredited);
    record.credits.insert(party_id, credit);
    emit(ReleaseCreditAddedEvent { release_id, party_id, display_name, role });
}

public fun remove_credit(release: &mut Release, cap: &ReleaseAdminCap, party_id: ID) {
    let release_id = object::id(release);
    let uid = release.uid_mut(cap);
    assert!(df::exists(uid, ReleaseCreditsKey()), ENoCredits);
    let record: &mut ReleaseCredits = df::borrow_mut(uid, ReleaseCreditsKey());
    assert!(record.credits.contains(&party_id), EPartyNotFound);
    record.credits.remove(&party_id);
    if (record.credits.is_empty()) {
        let ReleaseCredits { credits } = df::remove(uid, ReleaseCreditsKey());
        credits.destroy_empty();
    };
    emit(ReleaseCreditRemovedEvent { release_id, party_id });
}

// === Test Functions ===

#[test_only]
public fun release_credit_added_fields_for_testing(
    event: &ReleaseCreditAddedEvent,
): (ID, ID, String, ReleasePartyRole) {
    (event.release_id, event.party_id, event.display_name, event.role)
}

#[test_only]
public fun release_credit_removed_fields_for_testing(event: &ReleaseCreditRemovedEvent): (ID, ID) {
    (event.release_id, event.party_id)
}
