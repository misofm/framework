// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module party_avatar::party_avatar;

use miso_party::party::{Party, PartyAdminCap};
use sui::{dynamic_field as df, event::emit};

// === Errors ===

const ENoAvatar: u64 = 0;

// === Structs ===

public struct PartyAvatarKey() has copy, drop, store;

// === Events ===

public struct PartyAvatarSetEvent has copy, drop {
    party_id: ID,
    blob_id: u256,
}

public struct PartyAvatarClearedEvent has copy, drop {
    party_id: ID,
}

// === View Functions ===

public fun has_avatar(party: &Party): bool {
    df::exists(party.uid(), PartyAvatarKey())
}

public fun avatar(party: &Party): u256 {
    assert!(has_avatar(party), ENoAvatar);
    *df::borrow(party.uid(), PartyAvatarKey())
}

// === Admin Functions ===

public fun set_avatar(party: &mut Party, cap: &PartyAdminCap, blob_id: u256) {
    let party_id = object::id(party);
    let uid = party.uid_mut(cap);
    if (df::exists(uid, PartyAvatarKey())) {
        let previous: &mut u256 = df::borrow_mut(uid, PartyAvatarKey());
        if (*previous == blob_id) return;
        *previous = blob_id;
    } else {
        df::add(uid, PartyAvatarKey(), blob_id);
    };
    emit(PartyAvatarSetEvent { party_id, blob_id });
}

public fun clear_avatar(party: &mut Party, cap: &PartyAdminCap) {
    let party_id = object::id(party);
    let uid = party.uid_mut(cap);
    if (!df::exists(uid, PartyAvatarKey())) return;
    let _: u256 = df::remove(uid, PartyAvatarKey());
    emit(PartyAvatarClearedEvent { party_id });
}

// === Test Functions ===

#[test_only]
public fun party_avatar_set_fields_for_testing(event: &PartyAvatarSetEvent): (ID, u256) {
    (event.party_id, event.blob_id)
}

#[test_only]
public fun party_avatar_cleared_fields_for_testing(event: &PartyAvatarClearedEvent): ID {
    event.party_id
}
