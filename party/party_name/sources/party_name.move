// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module party_name::party_name;

use miso_party::party::{Party, PartyAdminCap};
use std::string::String;
use sui::{dynamic_field as df, event::emit};

// === Errors ===

const EEmptyName: u64 = 0;
const ENoName: u64 = 1;

// === Structs ===

public struct NameKey() has copy, drop, store;

// === Events ===

public struct PartyNameSetEvent has copy, drop {
    party_id: ID,
    name: String,
}

public struct PartyNameClearedEvent has copy, drop {
    party_id: ID,
}

// === View Functions ===

public fun has_name(party: &Party): bool {
    df::exists(party.uid(), NameKey())
}

public fun name(party: &Party): String {
    assert!(has_name(party), ENoName);
    *df::borrow(party.uid(), NameKey())
}

// === Admin Functions ===

public fun set_name(party: &mut Party, cap: &PartyAdminCap, name: String) {
    assert!(!name.is_empty(), EEmptyName);
    let party_id = object::id(party);
    let uid = party.uid_mut(cap);
    if (df::exists(uid, NameKey())) {
        let previous: &mut String = df::borrow_mut(uid, NameKey());
        if (*previous == name) return;
        *previous = name;
    } else {
        df::add(uid, NameKey(), name);
    };
    emit(PartyNameSetEvent { party_id, name });
}

public fun clear_name(party: &mut Party, cap: &PartyAdminCap) {
    let party_id = object::id(party);
    let uid = party.uid_mut(cap);
    if (!df::exists(uid, NameKey())) return;
    let _: String = df::remove(uid, NameKey());
    emit(PartyNameClearedEvent { party_id });
}

// === Test Functions ===

#[test_only]
public fun set_event_fields(event: &PartyNameSetEvent): (ID, String) {
    (event.party_id, event.name)
}

#[test_only]
public fun cleared_event_fields(event: &PartyNameClearedEvent): ID {
    event.party_id
}
