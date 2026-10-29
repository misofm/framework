// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module release_genre::release_genre;

use genre::genre::Genre;
use miso_music::release::{Release, ReleaseAdminCap};
use std::string::String;
use sui::event::emit;
use typed_set::typed_set as set;

// === Errors ===

const ENoGenres: u64 = 0;

// === Constants ===

const MAX_GENRES: u64 = 6;

// === Structs ===

public struct ReleaseGenreKey() has copy, drop, store;

// === Events ===

public struct ReleaseGenreAddedEvent has copy, drop {
    release_id: ID,
    genre_id: ID,
    genre_name: String,
}

public struct ReleaseGenreRemovedEvent has copy, drop {
    release_id: ID,
    genre_id: ID,
}

public struct ReleaseGenresClearedEvent has copy, drop {
    release_id: ID,
}

// === View Functions ===

public fun has_genres(release: &Release): bool {
    set::exists(release.uid(), ReleaseGenreKey())
}

public fun has_genre(release: &Release, genre_id: ID): bool {
    set::contains(release.uid(), ReleaseGenreKey(), &genre_id)
}

public fun genres(release: &Release): vector<ID> {
    assert!(has_genres(release), ENoGenres);
    set::keys(release.uid(), ReleaseGenreKey())
}

// === Admin Functions ===

public fun add_genre(release: &mut Release, cap: &ReleaseAdminCap, genre: &Genre) {
    let release_id = object::id(release);
    let genre_id = object::id(genre);
    set::add(release.uid_mut(cap), ReleaseGenreKey(), genre_id, MAX_GENRES);
    emit(ReleaseGenreAddedEvent { release_id, genre_id, genre_name: *genre.name() });
}

public fun remove_genre(release: &mut Release, cap: &ReleaseAdminCap, genre_id: ID) {
    let release_id = object::id(release);
    set::remove(release.uid_mut(cap), ReleaseGenreKey(), genre_id);
    emit(ReleaseGenreRemovedEvent { release_id, genre_id });
}

public fun clear_genres(release: &mut Release, cap: &ReleaseAdminCap) {
    let release_id = object::id(release);
    let uid = release.uid_mut(cap);
    if (set::exists(uid, ReleaseGenreKey())) {
        set::clear<ReleaseGenreKey, ID>(uid, ReleaseGenreKey());
        emit(ReleaseGenresClearedEvent { release_id });
    }
}

// === Test Functions ===

#[test_only]
public fun release_genre_added_fields(event: &ReleaseGenreAddedEvent): (ID, ID, String) {
    (event.release_id, event.genre_id, event.genre_name)
}

#[test_only]
public fun release_genre_removed_fields(event: &ReleaseGenreRemovedEvent): (ID, ID) {
    (event.release_id, event.genre_id)
}

#[test_only]
public fun release_genres_cleared_fields(event: &ReleaseGenresClearedEvent): ID {
    event.release_id
}
