// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module recording_credits::recording_credits;

use credit::credit::Credit;
use miso_music::recording::{Recording, RecordingAdminCap};
use miso_party::party::Party;
use recording_credits::recording_party_role::RecordingPartyRole;
use std::string::String;
use sui::{dynamic_field as df, event::emit, vec_map::{Self, VecMap}, vec_set::{Self, VecSet}};

// === Errors ===

const EMaxRolesExceeded: u64 = 0;
const EMaxCreditsExceeded: u64 = 1;
const EMaxPrimaryArtistsExceeded: u64 = 2;
const EMaxFeaturedArtistsExceeded: u64 = 3;
const EDuplicateParty: u64 = 4;
const EAlreadyPrimaryArtist: u64 = 5;
const EAlreadyFeaturedArtist: u64 = 6;
const ENoCredits: u64 = 7;
const EPartyNotFound: u64 = 8;
const ENotPrimaryArtist: u64 = 9;
const ENotFeaturedArtist: u64 = 10;

// === Constants ===

const MAX_ROLES_PER_CREDIT: u64 = 10;
const MAX_CREDITS: u64 = 150;
const MAX_PRIMARY_ARTISTS: u64 = 20;
const MAX_FEATURED_ARTISTS: u64 = 50;

// === Structs ===

public struct RecordingCredits has store {
    credits: VecMap<ID, Credit<RecordingPartyRole>>,
    primary_artist_ids: VecSet<ID>,
    featured_artist_ids: VecSet<ID>,
}

public struct RecordingCreditsKey() has copy, drop, store;

// === Events ===

public struct RecordingCreditAddedEvent has copy, drop {
    recording_id: ID,
    party_id: ID,
    display_name: String,
    roles: vector<RecordingPartyRole>,
}

public struct RecordingCreditRemovedEvent has copy, drop {
    recording_id: ID,
    party_id: ID,
}

public struct RecordingPrimaryArtistAddedEvent has copy, drop {
    recording_id: ID,
    party_id: ID,
}

public struct RecordingPrimaryArtistRemovedEvent has copy, drop {
    recording_id: ID,
    party_id: ID,
}

public struct RecordingFeaturedArtistAddedEvent has copy, drop {
    recording_id: ID,
    party_id: ID,
}

public struct RecordingFeaturedArtistRemovedEvent has copy, drop {
    recording_id: ID,
    party_id: ID,
}

// === View Functions ===

public fun has_credits<RecordingShare>(recording: &Recording<RecordingShare>): bool {
    df::exists(recording.uid(), RecordingCreditsKey())
}

public fun credits<RecordingShare>(
    recording: &Recording<RecordingShare>,
): &VecMap<ID, Credit<RecordingPartyRole>> {
    &borrow(recording.uid()).credits
}

public fun primary_artist_ids<RecordingShare>(recording: &Recording<RecordingShare>): &VecSet<ID> {
    &borrow(recording.uid()).primary_artist_ids
}

public fun featured_artist_ids<RecordingShare>(recording: &Recording<RecordingShare>): &VecSet<ID> {
    &borrow(recording.uid()).featured_artist_ids
}

public fun is_primary_artist<RecordingShare>(
    recording: &Recording<RecordingShare>,
    party_id: ID,
): bool {
    has_credits(recording) && borrow(recording.uid()).primary_artist_ids.contains(&party_id)
}

public fun is_featured_artist<RecordingShare>(
    recording: &Recording<RecordingShare>,
    party_id: ID,
): bool {
    has_credits(recording) && borrow(recording.uid()).featured_artist_ids.contains(&party_id)
}

// === Admin Functions ===

public fun add_credit<RecordingShare>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    party: &Party,
    credit: Credit<RecordingPartyRole>,
) {
    assert!(credit.roles().length() <= MAX_ROLES_PER_CREDIT, EMaxRolesExceeded);
    let recording_id = object::id(recording);
    let party_id = object::id(party);
    let display_name = *credit.display_name();
    let roles = *credit.roles();
    let uid = recording.uid_mut(cap);
    if (!df::exists(uid, RecordingCreditsKey())) {
        df::add(
            uid,
            RecordingCreditsKey(),
            RecordingCredits {
                credits: vec_map::empty(),
                primary_artist_ids: vec_set::empty(),
                featured_artist_ids: vec_set::empty(),
            },
        );
    };
    let record: &mut RecordingCredits = df::borrow_mut(uid, RecordingCreditsKey());
    assert!(record.credits.length() < MAX_CREDITS, EMaxCreditsExceeded);
    assert!(!record.credits.contains(&party_id), EDuplicateParty);
    record.credits.insert(party_id, credit);
    emit(RecordingCreditAddedEvent { recording_id, party_id, display_name, roles });
}

public fun remove_credit<RecordingShare>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    party_id: ID,
) {
    let recording_id = object::id(recording);
    let uid = recording.uid_mut(cap);
    let record = borrow_mut(uid);
    assert!(record.credits.contains(&party_id), EPartyNotFound);
    if (record.primary_artist_ids.contains(&party_id)) {
        record.primary_artist_ids.remove(&party_id);
        emit(RecordingPrimaryArtistRemovedEvent { recording_id, party_id });
    };
    if (record.featured_artist_ids.contains(&party_id)) {
        record.featured_artist_ids.remove(&party_id);
        emit(RecordingFeaturedArtistRemovedEvent { recording_id, party_id });
    };
    record.credits.remove(&party_id);
    if (record.credits.is_empty()) {
        let RecordingCredits { .. } = df::remove(uid, RecordingCreditsKey());
    };
    emit(RecordingCreditRemovedEvent { recording_id, party_id });
}

public fun add_primary_artist<RecordingShare>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    party_id: ID,
) {
    let recording_id = object::id(recording);
    let record = borrow_mut(recording.uid_mut(cap));
    assert!(record.primary_artist_ids.length() < MAX_PRIMARY_ARTISTS, EMaxPrimaryArtistsExceeded);
    assert!(record.credits.contains(&party_id), EPartyNotFound);
    assert!(!record.featured_artist_ids.contains(&party_id), EAlreadyFeaturedArtist);
    assert!(!record.primary_artist_ids.contains(&party_id), EAlreadyPrimaryArtist);
    record.primary_artist_ids.insert(party_id);
    emit(RecordingPrimaryArtistAddedEvent { recording_id, party_id });
}

public fun remove_primary_artist<RecordingShare>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    party_id: ID,
) {
    let recording_id = object::id(recording);
    let record = borrow_mut(recording.uid_mut(cap));
    assert!(record.credits.contains(&party_id), EPartyNotFound);
    assert!(record.primary_artist_ids.contains(&party_id), ENotPrimaryArtist);
    record.primary_artist_ids.remove(&party_id);
    emit(RecordingPrimaryArtistRemovedEvent { recording_id, party_id });
}

public fun add_featured_artist<RecordingShare>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    party_id: ID,
) {
    let recording_id = object::id(recording);
    let record = borrow_mut(recording.uid_mut(cap));
    assert!(
        record.featured_artist_ids.length() < MAX_FEATURED_ARTISTS,
        EMaxFeaturedArtistsExceeded,
    );
    assert!(record.credits.contains(&party_id), EPartyNotFound);
    assert!(!record.primary_artist_ids.contains(&party_id), EAlreadyPrimaryArtist);
    assert!(!record.featured_artist_ids.contains(&party_id), EAlreadyFeaturedArtist);
    record.featured_artist_ids.insert(party_id);
    emit(RecordingFeaturedArtistAddedEvent { recording_id, party_id });
}

public fun remove_featured_artist<RecordingShare>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    party_id: ID,
) {
    let recording_id = object::id(recording);
    let record = borrow_mut(recording.uid_mut(cap));
    assert!(record.credits.contains(&party_id), EPartyNotFound);
    assert!(record.featured_artist_ids.contains(&party_id), ENotFeaturedArtist);
    record.featured_artist_ids.remove(&party_id);
    emit(RecordingFeaturedArtistRemovedEvent { recording_id, party_id });
}

// === Private Functions ===

fun borrow(uid: &UID): &RecordingCredits {
    assert!(df::exists(uid, RecordingCreditsKey()), ENoCredits);
    df::borrow(uid, RecordingCreditsKey())
}

fun borrow_mut(uid: &mut UID): &mut RecordingCredits {
    assert!(df::exists(uid, RecordingCreditsKey()), ENoCredits);
    df::borrow_mut(uid, RecordingCreditsKey())
}

// === Test Functions ===

#[test_only]
public fun recording_credit_added_fields(
    event: &RecordingCreditAddedEvent,
): (ID, ID, String, vector<RecordingPartyRole>) {
    (event.recording_id, event.party_id, event.display_name, event.roles)
}

#[test_only]
public fun recording_credit_removed_fields(event: &RecordingCreditRemovedEvent): (ID, ID) {
    (event.recording_id, event.party_id)
}

#[test_only]
public fun recording_primary_artist_added_fields(
    event: &RecordingPrimaryArtistAddedEvent,
): (ID, ID) {
    (event.recording_id, event.party_id)
}

#[test_only]
public fun recording_primary_artist_removed_fields(
    event: &RecordingPrimaryArtistRemovedEvent,
): (ID, ID) {
    (event.recording_id, event.party_id)
}

#[test_only]
public fun recording_featured_artist_added_fields(
    event: &RecordingFeaturedArtistAddedEvent,
): (ID, ID) {
    (event.recording_id, event.party_id)
}

#[test_only]
public fun recording_featured_artist_removed_fields(
    event: &RecordingFeaturedArtistRemovedEvent,
): (ID, ID) {
    (event.recording_id, event.party_id)
}
