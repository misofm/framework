// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module release_genre::release_genre;

use genre::genre::Genre;
use miso_music::release::{Release, ReleaseAdminCap};
use std::string::String;
use sui::{dynamic_field, event::emit};

// === Errors ===

const EGenreAlreadyAdded: u64 = 0;
const EGenreNotFound: u64 = 1;

// === Structs ===

public struct ReleaseGenreKey(ID) has copy, drop, store;

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

// === View Functions ===

public fun has_genre(release: &Release, genre_id: ID): bool {
    dynamic_field::exists(release.uid(), ReleaseGenreKey(genre_id))
}

// === Admin Functions ===

public fun add_genre(release: &mut Release, cap: &ReleaseAdminCap, genre: &Genre) {
    let release_id = object::id(release);
    let genre_id = object::id(genre);
    let uid = release.uid_mut(cap);
    assert!(!dynamic_field::exists(uid, ReleaseGenreKey(genre_id)), EGenreAlreadyAdded);
    dynamic_field::add(uid, ReleaseGenreKey(genre_id), true);
    emit(ReleaseGenreAddedEvent { release_id, genre_id, genre_name: *genre.name() });
}

public fun remove_genre(release: &mut Release, cap: &ReleaseAdminCap, genre_id: ID) {
    let release_id = object::id(release);
    let uid = release.uid_mut(cap);
    assert!(dynamic_field::exists(uid, ReleaseGenreKey(genre_id)), EGenreNotFound);
    dynamic_field::remove<ReleaseGenreKey, bool>(uid, ReleaseGenreKey(genre_id));
    emit(ReleaseGenreRemovedEvent { release_id, genre_id });
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
