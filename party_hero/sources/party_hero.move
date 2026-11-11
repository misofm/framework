// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module party_hero::party_hero;

use miso_party::party::{Party, PartyAdminCap};
use sui::{dynamic_field as df, event::emit};

// === Errors ===

const ENoHero: u64 = 0;

// === Structs ===

public struct PartyHeroKey() has copy, drop, store;

// === Events ===

public struct PartyHeroSetEvent has copy, drop {
    party_id: ID,
    blob_id: u256,
}

public struct PartyHeroClearedEvent has copy, drop {
    party_id: ID,
}

// === View Functions ===

public fun has_hero(party: &Party): bool {
    df::exists(party.uid(), PartyHeroKey())
}

public fun hero(party: &Party): u256 {
    assert!(has_hero(party), ENoHero);
    *df::borrow(party.uid(), PartyHeroKey())
}

// === Admin Functions ===

public fun set_hero(party: &mut Party, cap: &PartyAdminCap, blob_id: u256) {
    let party_id = object::id(party);
    let uid = party.uid_mut(cap);
    if (df::exists(uid, PartyHeroKey())) {
        let previous: &mut u256 = df::borrow_mut(uid, PartyHeroKey());
        if (*previous == blob_id) return;
        *previous = blob_id;
    } else {
        df::add(uid, PartyHeroKey(), blob_id);
    };
    emit(PartyHeroSetEvent { party_id, blob_id });
}

public fun clear_hero(party: &mut Party, cap: &PartyAdminCap) {
    let party_id = object::id(party);
    let uid = party.uid_mut(cap);
    if (!df::exists(uid, PartyHeroKey())) return;
    let _: u256 = df::remove(uid, PartyHeroKey());
    emit(PartyHeroClearedEvent { party_id });
}

// === Test Functions ===

#[test_only]
public fun party_hero_set_fields_for_testing(event: &PartyHeroSetEvent): (ID, u256) {
    (event.party_id, event.blob_id)
}

#[test_only]
public fun party_hero_cleared_fields_for_testing(event: &PartyHeroClearedEvent): ID {
    event.party_id
}
