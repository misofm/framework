// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module recording_credits::recording_credits;

use credit::credit::Credit;
use miso_music::recording::{Recording, RecordingAdminCap};
use miso_party::party::Party;
use recording_credits::recording_party_role::{
    RecordingPartyRole,
    new_featured_role,
    new_primary_role,
};
use std::string::String;
use sui::{dynamic_field as df, event::emit, vec_map::{Self, VecMap}};

// === Errors ===

const ETooManyRoles: u64 = 0;
const ETooManyCredits: u64 = 1;
const EPartyAlreadyCredited: u64 = 2;
const ENoCredits: u64 = 3;
const EPartyNotFound: u64 = 4;
const EPrimaryAndFeatured: u64 = 5;

// === Constants ===

const MAX_ROLES_PER_CREDIT: u64 = 10;
const MAX_CREDITS: u64 = 150;

// === Structs ===

public struct RecordingCredits has store {
    credits: VecMap<ID, Credit<RecordingPartyRole>>,
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

// === View Functions ===

public fun has_credits<RecordingShare>(recording: &Recording<RecordingShare>): bool {
    df::exists(recording.uid(), RecordingCreditsKey())
}

public fun credits<RecordingShare>(
    recording: &Recording<RecordingShare>,
): &VecMap<ID, Credit<RecordingPartyRole>> {
    &borrow(recording.uid()).credits
}

public fun is_primary_artist<RecordingShare>(
    recording: &Recording<RecordingShare>,
    party_id: ID,
): bool {
    has_role(recording, party_id, new_primary_role())
}

public fun is_featured_artist<RecordingShare>(
    recording: &Recording<RecordingShare>,
    party_id: ID,
): bool {
    has_role(recording, party_id, new_featured_role())
}

// === Admin Functions ===

public fun add_credit<RecordingShare>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    party: &Party,
    credit: Credit<RecordingPartyRole>,
) {
    assert!(credit.roles().length() <= MAX_ROLES_PER_CREDIT, ETooManyRoles);
    assert!(
        !(
            credit.roles().contains(&new_primary_role()) && credit.roles().contains(&new_featured_role()),
        ),
        EPrimaryAndFeatured,
    );
    let recording_id = object::id(recording);
    let party_id = object::id(party);
    let display_name = *credit.display_name();
    let roles = *credit.roles();
    let uid = recording.uid_mut(cap);
    if (!df::exists(uid, RecordingCreditsKey())) {
        df::add(uid, RecordingCreditsKey(), RecordingCredits { credits: vec_map::empty() });
    };
    let record: &mut RecordingCredits = df::borrow_mut(uid, RecordingCreditsKey());
    assert!(record.credits.length() < MAX_CREDITS, ETooManyCredits);
    assert!(!record.credits.contains(&party_id), EPartyAlreadyCredited);
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
    assert!(df::exists(uid, RecordingCreditsKey()), ENoCredits);
    let record: &mut RecordingCredits = df::borrow_mut(uid, RecordingCreditsKey());
    assert!(record.credits.contains(&party_id), EPartyNotFound);
    record.credits.remove(&party_id);
    if (record.credits.is_empty()) {
        let RecordingCredits { credits } = df::remove(uid, RecordingCreditsKey());
        credits.destroy_empty();
    };
    emit(RecordingCreditRemovedEvent { recording_id, party_id });
}

// === Private Functions ===

fun borrow(uid: &UID): &RecordingCredits {
    assert!(df::exists(uid, RecordingCreditsKey()), ENoCredits);
    df::borrow(uid, RecordingCreditsKey())
}

fun has_role<RecordingShare>(
    recording: &Recording<RecordingShare>,
    party_id: ID,
    role: RecordingPartyRole,
): bool {
    has_credits(recording) &&
        borrow(recording.uid()).credits.try_get(&party_id).is_some_and!(|credit| credit.roles().contains(&role))
}

// === Test Functions ===

#[test_only]
public fun recording_credit_added_fields_for_testing(
    event: &RecordingCreditAddedEvent,
): (ID, ID, String, vector<RecordingPartyRole>) {
    (event.recording_id, event.party_id, event.display_name, event.roles)
}

#[test_only]
public fun recording_credit_removed_fields_for_testing(
    event: &RecordingCreditRemovedEvent,
): (ID, ID) {
    (event.recording_id, event.party_id)
}
