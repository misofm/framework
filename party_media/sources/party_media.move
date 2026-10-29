// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module party_media::party_media;

use miso_party::party::{Party, PartyAdminCap};
use sui::{dynamic_field as df, event::emit};

// === Errors ===

const EZeroQuilt: u64 = 0;
const ENoMedia: u64 = 1;

// === Structs ===

public struct Media has drop, store {
    quilt: u256,
}

public struct PartyMediaKey() has copy, drop, store;

// === Events ===

public struct PartyMediaSetEvent has copy, drop {
    party_id: ID,
    quilt: u256,
}

public struct PartyMediaClearedEvent has copy, drop {
    party_id: ID,
}

// === View Functions ===

public fun has_media(party: &Party): bool {
    df::exists(party.uid(), PartyMediaKey())
}

public fun quilt(party: &Party): u256 {
    assert!(has_media(party), ENoMedia);
    df::borrow<PartyMediaKey, Media>(party.uid(), PartyMediaKey()).quilt
}

// === Admin Functions ===

public fun set_media(party: &mut Party, cap: &PartyAdminCap, quilt: u256) {
    assert!(quilt != 0, EZeroQuilt);
    let party_id = object::id(party);
    let uid = party.uid_mut(cap);
    if (df::exists(uid, PartyMediaKey())) {
        let media: &mut Media = df::borrow_mut(uid, PartyMediaKey());
        if (media.quilt == quilt) return;
        media.quilt = quilt;
    } else {
        df::add(uid, PartyMediaKey(), Media { quilt });
    };
    emit(PartyMediaSetEvent { party_id, quilt });
}

public fun clear_media(party: &mut Party, cap: &PartyAdminCap) {
    let party_id = object::id(party);
    let uid = party.uid_mut(cap);
    if (df::exists(uid, PartyMediaKey())) {
        let Media { quilt: _ } = df::remove(uid, PartyMediaKey());
        emit(PartyMediaClearedEvent { party_id });
    }
}

// === Test Functions ===

#[test_only]
public fun party_media_set_fields_for_testing(event: &PartyMediaSetEvent): (ID, u256) {
    (event.party_id, event.quilt)
}

#[test_only]
public fun party_media_cleared_fields_for_testing(event: &PartyMediaClearedEvent): ID {
    event.party_id
}
