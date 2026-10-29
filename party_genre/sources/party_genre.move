// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module party_genre::party_genre;

use genre::genre::Genre;
use miso_party::party::{Party, PartyAdminCap};
use std::string::String;
use sui::event::emit;
use typed_set::typed_set as set;

// === Errors ===

const ENoGenres: u64 = 0;

// === Constants ===

const MAX_GENRES: u64 = 20;

// === Structs ===

public struct GenresKey() has copy, drop, store;

// === Events ===

public struct GenreAddedEvent has copy, drop {
    party_id: ID,
    genre_id: ID,
    genre_name: String,
}

public struct GenreRemovedEvent has copy, drop {
    party_id: ID,
    genre_id: ID,
}

public struct GenresClearedEvent has copy, drop {
    party_id: ID,
}

// === View Functions ===

public fun has_genres(party: &Party): bool {
    set::exists(party.uid(), GenresKey())
}

public fun has_genre(party: &Party, genre_id: ID): bool {
    set::contains(party.uid(), GenresKey(), &genre_id)
}

public fun genres(party: &Party): vector<ID> {
    assert!(has_genres(party), ENoGenres);
    set::keys(party.uid(), GenresKey())
}

// === Admin Functions ===

public fun add_genre(party: &mut Party, cap: &PartyAdminCap, genre: &Genre) {
    let party_id = object::id(party);
    let genre_id = object::id(genre);
    set::add(party.uid_mut(cap), GenresKey(), genre_id, MAX_GENRES);
    emit(GenreAddedEvent { party_id, genre_id, genre_name: *genre.name() });
}

public fun remove_genre(party: &mut Party, cap: &PartyAdminCap, genre_id: ID) {
    let party_id = object::id(party);
    set::remove(party.uid_mut(cap), GenresKey(), genre_id);
    emit(GenreRemovedEvent { party_id, genre_id });
}

public fun clear_genres(party: &mut Party, cap: &PartyAdminCap) {
    let party_id = object::id(party);
    let uid = party.uid_mut(cap);
    if (set::exists(uid, GenresKey())) {
        set::clear<GenresKey, ID>(uid, GenresKey());
        emit(GenresClearedEvent { party_id });
    }
}

// === Test Functions ===

#[test_only]
public fun added_event_fields(event: &GenreAddedEvent): (ID, ID, String) {
    (event.party_id, event.genre_id, event.genre_name)
}

#[test_only]
public fun removed_event_fields(event: &GenreRemovedEvent): (ID, ID) {
    (event.party_id, event.genre_id)
}

#[test_only]
public fun cleared_event_fields(event: &GenresClearedEvent): ID {
    event.party_id
}
