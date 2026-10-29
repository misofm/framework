// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module recording_genre::recording_genre;

use genre::genre::Genre;
use miso_music::recording::{Recording, RecordingAdminCap};
use std::string::String;
use sui::{dynamic_field as df, event::emit};

// === Errors ===

const EGenreAlreadyAdded: u64 = 0;
const EGenreNotFound: u64 = 1;

// === Structs ===

public struct RecordingGenreKey(ID) has copy, drop, store;

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

// === View Functions ===

public fun has_genre<RecordingShare>(recording: &Recording<RecordingShare>, genre_id: ID): bool {
    df::exists(recording.uid(), RecordingGenreKey(genre_id))
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
    assert!(!df::exists(uid, RecordingGenreKey(genre_id)), EGenreAlreadyAdded);
    df::add(uid, RecordingGenreKey(genre_id), true);
    emit(RecordingGenreAddedEvent { recording_id, genre_id, genre_name: *genre.name() });
}

public fun remove_genre<RecordingShare>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    genre_id: ID,
) {
    let recording_id = object::id(recording);
    let uid = recording.uid_mut(cap);
    assert!(df::exists(uid, RecordingGenreKey(genre_id)), EGenreNotFound);
    df::remove<RecordingGenreKey, bool>(uid, RecordingGenreKey(genre_id));
    emit(RecordingGenreRemovedEvent { recording_id, genre_id });
}

// === Test Functions ===

#[test_only]
public fun recording_genre_added_fields_for_testing(
    event: &RecordingGenreAddedEvent,
): (ID, ID, String) {
    (event.recording_id, event.genre_id, event.genre_name)
}

#[test_only]
public fun recording_genre_removed_fields_for_testing(
    event: &RecordingGenreRemovedEvent,
): (ID, ID) {
    (event.recording_id, event.genre_id)
}
