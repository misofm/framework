// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module party_genre::party_genre;

use genre::genre::Genre;
use miso_party::party::{Party, PartyAdminCap};
use std::string::String;
use sui::{dynamic_field, event::emit};

// === Errors ===

const EGenreAlreadyAdded: u64 = 0;
const EGenreNotFound: u64 = 1;

// === Structs ===

public struct PartyGenreKey(ID) has copy, drop, store;

// === Events ===

public struct PartyGenreAddedEvent has copy, drop {
    party_id: ID,
    genre_id: ID,
    genre_name: String,
}

public struct PartyGenreRemovedEvent has copy, drop {
    party_id: ID,
    genre_id: ID,
}

// === View Functions ===

public fun has_genre(party: &Party, genre_id: ID): bool {
    dynamic_field::exists(party.uid(), PartyGenreKey(genre_id))
}

// === Admin Functions ===

public fun add_genre(party: &mut Party, cap: &PartyAdminCap, genre: &Genre) {
    let party_id = object::id(party);
    let genre_id = object::id(genre);
    let uid = party.uid_mut(cap);
    assert!(!dynamic_field::exists(uid, PartyGenreKey(genre_id)), EGenreAlreadyAdded);
    dynamic_field::add(uid, PartyGenreKey(genre_id), true);
    emit(PartyGenreAddedEvent { party_id, genre_id, genre_name: *genre.name() });
}

public fun remove_genre(party: &mut Party, cap: &PartyAdminCap, genre_id: ID) {
    let party_id = object::id(party);
    let uid = party.uid_mut(cap);
    assert!(dynamic_field::exists(uid, PartyGenreKey(genre_id)), EGenreNotFound);
    dynamic_field::remove<PartyGenreKey, bool>(uid, PartyGenreKey(genre_id));
    emit(PartyGenreRemovedEvent { party_id, genre_id });
}

// === Test Functions ===

#[test_only]
public fun added_event_fields(event: &PartyGenreAddedEvent): (ID, ID, String) {
    (event.party_id, event.genre_id, event.genre_name)
}

#[test_only]
public fun removed_event_fields(event: &PartyGenreRemovedEvent): (ID, ID) {
    (event.party_id, event.genre_id)
}
