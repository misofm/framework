// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module recording_genre::recording_genre;

use genre::genre::Genre;
use miso_music::recording::{Recording, RecordingAdminCap};
use sui::{dynamic_field as df, event::emit};

// === Errors ===

const EDuplicateGenre: u64 = 0;
const EMaxGenresExceeded: u64 = 1;
const ENoGenres: u64 = 2;
const EGenreNotFound: u64 = 3;

// === Constants ===

const MAX_GENRES: u64 = 6;

// === Structs ===

public struct RecordingGenreKey() has copy, drop, store;

// === Events ===

public struct RecordingGenreAddedEvent has copy, drop {
    recording_id: ID,
    genre_id: ID,
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
    df::exists(recording.uid(), RecordingGenreKey())
}

public fun genres<RecordingShare>(recording: &Recording<RecordingShare>): &vector<ID> {
    assert!(has_genres(recording), ENoGenres);
    df::borrow(recording.uid(), RecordingGenreKey())
}

// === Admin Functions ===

public fun add_genre<RecordingShare>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    genre: &Genre,
) {
    let recording_id = object::id(recording);
    let genre_id = object::id(genre);
    let uid = recording.uid_mut(cap);
    if (df::exists(uid, RecordingGenreKey())) {
        let genres: &mut vector<ID> = df::borrow_mut(uid, RecordingGenreKey());
        assert!(!genres.contains(&genre_id), EDuplicateGenre);
        assert!(genres.length() < MAX_GENRES, EMaxGenresExceeded);
        genres.push_back(genre_id);
    } else {
        df::add(uid, RecordingGenreKey(), vector[genre_id]);
    };
    emit(RecordingGenreAddedEvent { recording_id, genre_id });
}

public fun remove_genre<RecordingShare>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    genre_id: ID,
) {
    let recording_id = object::id(recording);
    let uid = recording.uid_mut(cap);
    assert!(df::exists(uid, RecordingGenreKey()), ENoGenres);
    let genres: &mut vector<ID> = df::borrow_mut(uid, RecordingGenreKey());
    let (found, index) = genres.index_of(&genre_id);
    assert!(found, EGenreNotFound);
    genres.remove(index);
    if (genres.is_empty()) {
        let _: vector<ID> = df::remove(uid, RecordingGenreKey());
    };
    emit(RecordingGenreRemovedEvent { recording_id, genre_id });
}

public fun clear_genres<RecordingShare>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
) {
    let recording_id = object::id(recording);
    let uid = recording.uid_mut(cap);
    if (df::exists(uid, RecordingGenreKey())) {
        let _: vector<ID> = df::remove(uid, RecordingGenreKey());
        emit(RecordingGenresClearedEvent { recording_id });
    }
}

// === Test Functions ===

#[test_only]
public fun recording_genre_added_fields(event: &RecordingGenreAddedEvent): (ID, ID) {
    (event.recording_id, event.genre_id)
}

#[test_only]
public fun recording_genre_removed_fields(event: &RecordingGenreRemovedEvent): (ID, ID) {
    (event.recording_id, event.genre_id)
}

#[test_only]
public fun recording_genres_cleared_fields(event: &RecordingGenresClearedEvent): ID {
    event.recording_id
}
