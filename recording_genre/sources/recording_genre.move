// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module recording_genre::recording_genre;

use genre::genre::Genre;
use miso_music::recording::{Recording, RecordingAdminCap};
use std::string::String;
use sui::event::emit;
use typed_set::typed_set as set;

// === Errors ===

const ENoGenres: u64 = 0;

// === Constants ===

const MAX_GENRES: u64 = 6;

// === Structs ===

public struct RecordingGenreKey() has copy, drop, store;

// === Events ===

public struct RecordingGenreAddedEvent has copy, drop {
    recording_id: ID,
    genre_id: ID,
    genre_name: String,
}

public struct RecordingGenreRemovedEvent has copy, drop {
    recording_id: ID,
    genre_id: ID,
}

public struct RecordingGenresClearedEvent has copy, drop {
    recording_id: ID,
}

// === View Functions ===

public fun has_genres<RecordingShare>(recording: &Recording<RecordingShare>): bool {
    set::exists(recording.uid(), RecordingGenreKey())
}

public fun has_genre<RecordingShare>(recording: &Recording<RecordingShare>, genre_id: ID): bool {
    set::contains(recording.uid(), RecordingGenreKey(), &genre_id)
}

public fun genres<RecordingShare>(recording: &Recording<RecordingShare>): vector<ID> {
    assert!(has_genres(recording), ENoGenres);
    set::keys(recording.uid(), RecordingGenreKey())
}

// === Admin Functions ===

public fun add_genre<RecordingShare>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    genre: &Genre,
) {
    let recording_id = object::id(recording);
    let genre_id = object::id(genre);
    set::add(recording.uid_mut(cap), RecordingGenreKey(), genre_id, MAX_GENRES);
    emit(RecordingGenreAddedEvent { recording_id, genre_id, genre_name: *genre.name() });
}

public fun remove_genre<RecordingShare>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    genre_id: ID,
) {
    let recording_id = object::id(recording);
    set::remove(recording.uid_mut(cap), RecordingGenreKey(), genre_id);
    emit(RecordingGenreRemovedEvent { recording_id, genre_id });
}

public fun clear_genres<RecordingShare>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
) {
    let recording_id = object::id(recording);
    let uid = recording.uid_mut(cap);
    if (set::exists(uid, RecordingGenreKey())) {
        set::clear<RecordingGenreKey, ID>(uid, RecordingGenreKey());
        emit(RecordingGenresClearedEvent { recording_id });
    }
}

// === Test Functions ===

#[test_only]
public fun recording_genre_added_fields(event: &RecordingGenreAddedEvent): (ID, ID, String) {
    (event.recording_id, event.genre_id, event.genre_name)
}

#[test_only]
public fun recording_genre_removed_fields(event: &RecordingGenreRemovedEvent): (ID, ID) {
    (event.recording_id, event.genre_id)
}

#[test_only]
public fun recording_genres_cleared_fields(event: &RecordingGenresClearedEvent): ID {
    event.recording_id
}
