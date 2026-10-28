// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module recording_credits::credits_tests;

use credit::credit::{Self, Credit};
use miso_music::{recording::{Self, Recording, RecordingAdminCap}, test_helpers};
use miso_party::party::{Self, Party, PartyAdminCap};
use recording_credits::{
    recording_credits as credits,
    recording_party_role::{Self as rpr, RecordingPartyRole}
};
use std::{string::String, unit_test::{assert_eq, destroy}};
use sui::{bcs::to_bytes, event::{events_by_type, num_events}, test_scenario};

const ARTIST: address = @0xA1;
const MAX_CREDITS: u64 = 150;
const MAX_PRIMARY_ARTISTS: u64 = 20;
const MAX_FEATURED_ARTISTS: u64 = 50;

public struct TestShare() has drop;

fun mk_recording(ctx: &mut TxContext): (Recording<TestShare>, RecordingAdminCap<TestShare>) {
    recording::new_for_testing(test_helpers::fake_id(ctx), ctx)
}

fun vocalist(name: vector<u8>): Credit<RecordingPartyRole> {
    credit::new(name.to_string(), vector[rpr::new_vocalist_role(option::none())])
}

fun producer(name: vector<u8>): Credit<RecordingPartyRole> {
    credit::new(name.to_string(), vector[rpr::new_producer_role(option::none())])
}

fun instrumentalist(name: String, level: rpr::RecordingPartyRoleLevel): RecordingPartyRole {
    rpr::new_instrumentalist_role(name, option::some(level))
}

fun long_string(len: u64): String {
    let mut bytes = vector[];
    len.do!(|_| bytes.push_back(65));
    bytes.to_string()
}

fun other_long_string(len: u64): String {
    let mut bytes = vector[];
    len.do!(|_| bytes.push_back(66));
    bytes.to_string()
}

fun assert_added(
    event: &credits::RecordingCreditAddedEvent,
    recording_id: ID,
    party_id: ID,
    credit: &credit::Credit<RecordingPartyRole>,
) {
    let (
        event_object,
        event_party,
        event_name,
        event_roles,
    ) = credits::recording_credit_added_fields(event);
    assert_eq!(event_object, recording_id);
    assert_eq!(event_party, party_id);
    assert_eq!(event_name, *credit.display_name());
    assert_eq!(event_roles, *credit.roles());
}

#[test]
fun add_credit_attaches_and_reads_back() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    assert!(!credits::has_credits(&rec));
    let (p1, p1c) = party::new(ts.ctx());
    let alice = vocalist(b"Alice");
    credits::add_credit(&mut rec, &cap, &p1, alice);
    assert!(credits::has_credits(&rec));
    assert_eq!(credits::credits(&rec).length(), 1);
    assert_eq!(credits::credits(&rec)[&object::id(&p1)], alice);
    let (p2, p2c) = party::new(ts.ctx());
    credits::add_credit(
        &mut rec,
        &cap,
        &p2,
        producer(b"Bob"),
    );
    assert_eq!(credits::credits(&rec).length(), 2);
    destroy(rec);
    destroy(cap);
    destroy(p1);
    destroy(p1c);
    destroy(p2);
    destroy(p2c);
    ts.end();
}

#[test, expected_failure(abort_code = credits::EDuplicateParty)]
fun add_credit_rejects_duplicate_party() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    let (p, _pc) = party::new(ts.ctx());
    credits::add_credit(
        &mut rec,
        &cap,
        &p,
        vocalist(b"Alice"),
    );
    credits::add_credit(
        &mut rec,
        &cap,
        &p,
        producer(b"Alice"),
    );
    abort
}

#[test, expected_failure(abort_code = credits::EDuplicateParty)]
fun add_credit_rejects_identical_credit() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    let (p, _pc) = party::new(ts.ctx());
    let alice = vocalist(b"Alice");
    credits::add_credit(&mut rec, &cap, &p, alice);
    credits::add_credit(&mut rec, &cap, &p, alice);
    abort
}

#[test, expected_failure(abort_code = credits::EMaxRolesExceeded)]
fun add_credit_rejects_too_many_roles() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    let (p, _pc) = party::new(ts.ctx());
    let n = option::none();
    credits::add_credit(
        &mut rec,
        &cap,
        &p,
        credit::new(
            b"Alice".to_string(),
            vector[
                rpr::new_producer_role(n),
                rpr::new_vocalist_role(n),
                rpr::new_arranger_role(n),
                rpr::new_conductor_role(n),
                rpr::new_editor_role(n),
                rpr::new_mixing_engineer_role(n),
                rpr::new_mastering_engineer_role(n),
                rpr::new_recording_engineer_role(n),
                rpr::new_programmer_role(n),
                rpr::new_sound_designer_role(n),
                rpr::new_narrator_role(n),
            ],
        ),
    );
    abort
}

#[test]
fun primary_and_featured_round_trip() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    let (p1, p1c) = party::new(ts.ctx());
    let (p2, p2c) = party::new(ts.ctx());
    credits::add_credit(&mut rec, &cap, &p1, vocalist(b"Lead"));
    credits::add_credit(&mut rec, &cap, &p2, vocalist(b"Guest"));
    credits::add_primary_artist(&mut rec, &cap, object::id(&p1));
    credits::add_featured_artist(&mut rec, &cap, object::id(&p2));
    assert!(credits::is_primary_artist(&rec, object::id(&p1)));
    assert!(credits::is_featured_artist(&rec, object::id(&p2)));
    assert_eq!(credits::primary_artist_ids(&rec).length(), 1);
    assert_eq!(credits::featured_artist_ids(&rec).length(), 1);
    destroy(rec);
    destroy(cap);
    destroy(p1);
    destroy(p1c);
    destroy(p2);
    destroy(p2c);
    ts.end();
}

#[test, expected_failure(abort_code = credits::EPartyNotFound)]
fun primary_artist_must_be_credited() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    let (p, _pc) = party::new(ts.ctx());
    let (other, _otherc) = party::new(ts.ctx());
    credits::add_credit(&mut rec, &cap, &other, vocalist(b"Real"));
    credits::add_primary_artist(&mut rec, &cap, object::id(&p));
    abort
}

#[test, expected_failure(abort_code = credits::EAlreadyPrimaryArtist)]
fun featured_rejects_existing_primary() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    let (p, _pc) = party::new(ts.ctx());
    credits::add_credit(&mut rec, &cap, &p, vocalist(b"Alice"));
    credits::add_primary_artist(&mut rec, &cap, object::id(&p));
    credits::add_featured_artist(&mut rec, &cap, object::id(&p));
    abort
}

#[test]
fun remove_credit_cascades_to_primary_and_featured() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    let (p, _pc) = party::new(ts.ctx());
    let pid = object::id(&p);
    credits::add_credit(&mut rec, &cap, &p, vocalist(b"Alice"));
    credits::add_primary_artist(&mut rec, &cap, object::id(&p));
    assert!(credits::is_primary_artist(&rec, pid));
    credits::remove_credit(&mut rec, &cap, pid);
    assert!(!credits::is_primary_artist(&rec, pid));
    assert!(!credits::has_credits(&rec));
    let primary_removed = events_by_type<credits::RecordingPrimaryArtistRemovedEvent>();
    assert_eq!(primary_removed.length(), 1);
    let (_, event_party) = credits::recording_primary_artist_removed_fields(&primary_removed[0]);
    assert_eq!(event_party, pid);
    assert_eq!(events_by_type<credits::RecordingCreditRemovedEvent>().length(), 1);
    destroy(rec);
    destroy(cap);
    destroy(p);
    destroy(_pc);
    ts.end();
}

#[test]
fun add_credit_emits_the_full_credit() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    let (p, pc) = party::new(ts.ctx());
    let recording_id = object::id(&rec);
    let party_id = object::id(&p);
    let credit = credit::new(
        b"Alice Display".to_string(),
        vector[
            rpr::new_producer_role(option::none()),
            rpr::new_producer_role(option::some(rpr::new_primary_role_level())),
            rpr::new_instrumentalist_role(
                b"Piano".to_string(),
                option::some(rpr::new_lead_role_level()),
            ),
        ],
    );
    credits::add_credit(&mut rec, &cap, &p, credit);
    let events = events_by_type<credits::RecordingCreditAddedEvent>();
    assert_eq!(events.length(), 1);
    let (
        event_recording_id,
        event_party_id,
        event_name,
        event_roles,
    ) = credits::recording_credit_added_fields(&events[0]);
    assert_eq!(event_recording_id, recording_id);
    assert_eq!(event_party_id, party_id);
    assert_eq!(event_name, b"Alice Display".to_string());
    assert_eq!(event_roles, *credit.roles());
    assert_eq!(to_bytes(&events[0]).length(), 32 + 32 + 1 + 13 + 1 + 2 + 3 + 9);
    assert_eq!(credits::credits(&rec)[&object::id(&p)], credit);
    assert!(credits::has_credits(&rec));
    assert_eq!(credits::credits(&rec).length(), 1);
    assert!(!credits::is_primary_artist(&rec, object::id(&p)));
    assert!(!credits::is_featured_artist(&rec, object::id(&p)));
    assert_eq!(events_by_type<credits::RecordingCreditAddedEvent>().length(), 1);
    destroy(rec);
    destroy(cap);
    destroy(p);
    destroy(pc);
    ts.end();
}

#[test]
fun remove_credit_emits_the_removed_party() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    let (p, pc) = party::new(ts.ctx());
    let recording_id = object::id(&rec);
    let party_id = object::id(&p);
    credits::add_credit(
        &mut rec,
        &cap,
        &p,
        credit::new(
            b"Remover Display".to_string(),
            vector[
                rpr::new_producer_role(
                    option::some(rpr::new_primary_role_level()),
                ),
            ],
        ),
    );
    credits::remove_credit(&mut rec, &cap, object::id(&p));
    let events = events_by_type<credits::RecordingCreditRemovedEvent>();
    assert_eq!(events.length(), 1);
    let (event_object, event_party) = credits::recording_credit_removed_fields(&events[0]);
    assert_eq!(event_object, recording_id);
    assert_eq!(event_party, party_id);
    assert_eq!(to_bytes(&events[0]).length(), 64);
    assert_eq!(events_by_type<credits::RecordingPrimaryArtistRemovedEvent>().length(), 0);
    assert_eq!(events_by_type<credits::RecordingFeaturedArtistRemovedEvent>().length(), 0);
    destroy(rec);
    destroy(cap);
    destroy(p);
    destroy(pc);
    ts.end();
}

#[test]
fun remove_credit_cascade_emits_artist_removals_before_the_credit_removal() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    let (p1, p1c) = party::new(ts.ctx());
    let (p2, p2c) = party::new(ts.ctx());
    let (p3, p3c) = party::new(ts.ctx());
    let recording_id = object::id(&rec);
    let p2_id = object::id(&p2);
    let p3_id = object::id(&p3);
    credits::add_credit(&mut rec, &cap, &p1, vocalist(b"Lead Display"));
    credits::add_credit(&mut rec, &cap, &p2, producer(b"Middle Display"));
    credits::add_credit(
        &mut rec,
        &cap,
        &p3,
        credit::new(
            b"Guest Display".to_string(),
            vector[
                rpr::new_vocalist_role(
                    option::some(rpr::new_featured_role_level()),
                ),
            ],
        ),
    );
    credits::add_primary_artist(&mut rec, &cap, object::id(&p1));
    credits::add_primary_artist(&mut rec, &cap, object::id(&p2));
    credits::add_featured_artist(&mut rec, &cap, object::id(&p3));
    let before = num_events();
    credits::remove_credit(&mut rec, &cap, object::id(&p2));
    assert_eq!(num_events() - before, 2);
    assert_eq!(credits::credits(&rec).get_idx(&object::id(&p1)), 0);
    assert_eq!(credits::credits(&rec).get_idx(&object::id(&p3)), 1);
    let before = num_events();
    credits::remove_credit(&mut rec, &cap, object::id(&p3));
    assert_eq!(num_events() - before, 2);
    assert!(credits::is_primary_artist(&rec, object::id(&p1)));
    assert!(!credits::is_primary_artist(&rec, object::id(&p2)));
    assert!(!credits::is_featured_artist(&rec, object::id(&p3)));
    assert_eq!(credits::primary_artist_ids(&rec).length(), 1);
    assert_eq!(credits::featured_artist_ids(&rec).length(), 0);
    let primary_removed = events_by_type<credits::RecordingPrimaryArtistRemovedEvent>();
    assert_eq!(primary_removed.length(), 1);
    let (event_object, event_party) = credits::recording_primary_artist_removed_fields(
        &primary_removed[0],
    );
    assert_eq!(event_object, recording_id);
    assert_eq!(event_party, p2_id);
    let featured_removed = events_by_type<credits::RecordingFeaturedArtistRemovedEvent>();
    assert_eq!(featured_removed.length(), 1);
    let (event_object, event_party) = credits::recording_featured_artist_removed_fields(
        &featured_removed[0],
    );
    assert_eq!(event_object, recording_id);
    assert_eq!(event_party, p3_id);
    let removed = events_by_type<credits::RecordingCreditRemovedEvent>();
    assert_eq!(removed.length(), 2);
    let (event_object, event_party) = credits::recording_credit_removed_fields(&removed[0]);
    assert_eq!(event_object, recording_id);
    assert_eq!(event_party, p2_id);
    let (event_object, event_party) = credits::recording_credit_removed_fields(&removed[1]);
    assert_eq!(event_object, recording_id);
    assert_eq!(event_party, p3_id);
    destroy(rec);
    destroy(cap);
    destroy(p1);
    destroy(p1c);
    destroy(p2);
    destroy(p2c);
    destroy(p3);
    destroy(p3c);
    ts.end();
}

#[test]
fun primary_artist_changes_emit_events() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    let (p1, p1c) = party::new(ts.ctx());
    let (p2, p2c) = party::new(ts.ctx());
    let id1 = object::id(&p1);
    let id2 = object::id(&p2);
    let recording_id = object::id(&rec);
    credits::add_credit(&mut rec, &cap, &p1, vocalist(b"Primary One Display"));
    credits::add_credit(&mut rec, &cap, &p2, producer(b"Primary Two Display"));
    credits::add_primary_artist(&mut rec, &cap, object::id(&p1));
    credits::add_primary_artist(&mut rec, &cap, object::id(&p2));
    let added = events_by_type<credits::RecordingPrimaryArtistAddedEvent>();
    assert_eq!(added.length(), 2);
    let (event_object, event_party) = credits::recording_primary_artist_added_fields(&added[0]);
    assert_eq!(event_object, recording_id);
    assert_eq!(event_party, id1);
    let (event_object, event_party) = credits::recording_primary_artist_added_fields(&added[1]);
    assert_eq!(event_object, recording_id);
    assert_eq!(event_party, id2);
    assert_eq!(to_bytes(&added[0]).length(), 64);
    credits::remove_primary_artist(&mut rec, &cap, id2);
    let removed = events_by_type<credits::RecordingPrimaryArtistRemovedEvent>();
    assert_eq!(removed.length(), 1);
    let (event_object, event_party) = credits::recording_primary_artist_removed_fields(&removed[0]);
    assert_eq!(event_object, recording_id);
    assert_eq!(event_party, id2);
    assert_eq!(to_bytes(&removed[0]).length(), 64);
    assert!(credits::is_primary_artist(&rec, id1));
    assert!(!credits::is_primary_artist(&rec, id2));
    destroy(rec);
    destroy(cap);
    destroy(p1);
    destroy(p1c);
    destroy(p2);
    destroy(p2c);
    ts.end();
}

#[test, expected_failure(abort_code = credits::EMaxCreditsExceeded)]
fun add_credit_rejects_past_max_credits() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    MAX_CREDITS.do!(|_| {
        let (p, pc) = party::new(ts.ctx());
        credits::add_credit(&mut rec, &cap, &p, vocalist(b"P"));
        destroy(p);
        destroy(pc);
    });
    assert_eq!(credits::credits(&rec).length(), MAX_CREDITS);
    let (p, _pc) = party::new(ts.ctx());
    credits::add_credit(&mut rec, &cap, &p, vocalist(b"Overflow"));
    abort
}

#[test, expected_failure(abort_code = credits::EMaxPrimaryArtistsExceeded)]
fun add_primary_artist_rejects_past_max_primary_artists() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    MAX_PRIMARY_ARTISTS.do!(|_| {
        let (p, pc) = party::new(ts.ctx());
        credits::add_credit(&mut rec, &cap, &p, vocalist(b"P"));
        credits::add_primary_artist(&mut rec, &cap, object::id(&p));
        destroy(p);
        destroy(pc);
    });
    assert_eq!(credits::primary_artist_ids(&rec).length(), MAX_PRIMARY_ARTISTS);
    let (p, _pc) = party::new(ts.ctx());
    credits::add_credit(&mut rec, &cap, &p, vocalist(b"Overflow"));
    credits::add_primary_artist(&mut rec, &cap, object::id(&p));
    abort
}

#[test, expected_failure(abort_code = credits::EMaxFeaturedArtistsExceeded)]
fun add_featured_artist_rejects_past_max_featured_artists() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    MAX_FEATURED_ARTISTS.do!(|_| {
        let (p, pc) = party::new(ts.ctx());
        credits::add_credit(&mut rec, &cap, &p, vocalist(b"P"));
        credits::add_featured_artist(&mut rec, &cap, object::id(&p));
        destroy(p);
        destroy(pc);
    });
    assert_eq!(credits::featured_artist_ids(&rec).length(), MAX_FEATURED_ARTISTS);
    let (p, _pc) = party::new(ts.ctx());
    credits::add_credit(&mut rec, &cap, &p, vocalist(b"Overflow"));
    credits::add_featured_artist(&mut rec, &cap, object::id(&p));
    abort
}

#[test, expected_failure(abort_code = credits::ENoCredits)]
fun add_primary_artist_rejects_when_no_credits_record() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    let (p, _pc) = party::new(ts.ctx());
    credits::add_primary_artist(&mut rec, &cap, object::id(&p));
    abort
}

#[test, expected_failure(abort_code = credits::ENoCredits)]
fun credits_view_aborts_when_no_credits_record() {
    let mut ts = test_scenario::begin(ARTIST);
    let (rec, _cap) = mk_recording(ts.ctx());
    let _ = credits::credits(&rec);
    abort
}

#[test]
fun is_primary_and_featured_artist_are_false_before_any_credit() {
    let mut ts = test_scenario::begin(ARTIST);
    let (rec, cap) = mk_recording(ts.ctx());
    let (p, pc) = party::new(ts.ctx());
    assert!(!credits::has_credits(&rec));
    assert!(!credits::is_primary_artist(&rec, object::id(&p)));
    assert!(!credits::is_featured_artist(&rec, object::id(&p)));
    destroy(rec);
    destroy(cap);
    destroy(p);
    destroy(pc);
    ts.end();
}

#[test, expected_failure(abort_code = credits::EAlreadyFeaturedArtist)]
fun add_primary_artist_rejects_existing_featured() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    let (p, _pc) = party::new(ts.ctx());
    credits::add_credit(&mut rec, &cap, &p, vocalist(b"Alice"));
    credits::add_featured_artist(&mut rec, &cap, object::id(&p));
    credits::add_primary_artist(&mut rec, &cap, object::id(&p));
    abort
}

#[test, expected_failure(abort_code = credits::EAlreadyPrimaryArtist)]
fun add_primary_artist_rejects_duplicate_designation() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    let (p, _pc) = party::new(ts.ctx());
    credits::add_credit(&mut rec, &cap, &p, vocalist(b"Alice"));
    credits::add_primary_artist(&mut rec, &cap, object::id(&p));
    credits::add_primary_artist(&mut rec, &cap, object::id(&p));
    abort
}

#[test, expected_failure(abort_code = credits::EPartyNotFound)]
fun add_featured_artist_rejects_uncredited_party() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    let (p, _pc) = party::new(ts.ctx());
    let (other, _oc) = party::new(ts.ctx());
    credits::add_credit(&mut rec, &cap, &other, vocalist(b"Real"));
    credits::add_featured_artist(&mut rec, &cap, object::id(&p));
    abort
}

#[test, expected_failure(abort_code = credits::EAlreadyFeaturedArtist)]
fun add_featured_artist_rejects_duplicate_designation() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    let (p, _pc) = party::new(ts.ctx());
    credits::add_credit(&mut rec, &cap, &p, vocalist(b"Alice"));
    credits::add_featured_artist(&mut rec, &cap, object::id(&p));
    credits::add_featured_artist(&mut rec, &cap, object::id(&p));
    abort
}

#[test, expected_failure(abort_code = credits::ENotPrimaryArtist)]
fun remove_primary_artist_rejects_when_not_primary() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    let (p, _pc) = party::new(ts.ctx());
    credits::add_credit(&mut rec, &cap, &p, vocalist(b"Alice"));
    credits::remove_primary_artist(&mut rec, &cap, object::id(&p));
    abort
}

#[test, expected_failure(abort_code = credits::ENotFeaturedArtist)]
fun remove_featured_artist_rejects_when_not_featured() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    let (p, _pc) = party::new(ts.ctx());
    credits::add_credit(&mut rec, &cap, &p, vocalist(b"Alice"));
    credits::remove_featured_artist(&mut rec, &cap, object::id(&p));
    abort
}

#[test, expected_failure(abort_code = credits::EPartyNotFound)]
fun remove_credit_rejects_double_removal() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    let (p, _pc) = party::new(ts.ctx());
    let (other, _oc) = party::new(ts.ctx());
    let pid = object::id(&p);
    credits::add_credit(&mut rec, &cap, &p, vocalist(b"Alice"));
    credits::add_credit(&mut rec, &cap, &other, vocalist(b"Bob"));
    credits::remove_credit(&mut rec, &cap, pid);
    credits::remove_credit(&mut rec, &cap, pid);
    abort
}

#[test, expected_failure(abort_code = credits::ENoCredits)]
fun remove_last_credit_detaches_the_record() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    let (p, _pc) = party::new(ts.ctx());
    let pid = object::id(&p);
    credits::add_credit(&mut rec, &cap, &p, vocalist(b"Alice"));
    credits::remove_credit(&mut rec, &cap, pid);
    assert!(!credits::has_credits(&rec));
    credits::remove_credit(&mut rec, &cap, pid);
    abort
}

#[test, expected_failure(abort_code = credits::EPartyNotFound)]
fun remove_primary_artist_rejects_uncredited_party() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    let (p, _pc) = party::new(ts.ctx());
    credits::add_credit(&mut rec, &cap, &p, vocalist(b"Alice"));
    credits::remove_primary_artist(&mut rec, &cap, test_helpers::fake_id(ts.ctx()));
    abort
}

#[test, expected_failure(abort_code = credits::EPartyNotFound)]
fun remove_featured_artist_rejects_uncredited_party() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    let (p, _pc) = party::new(ts.ctx());
    credits::add_credit(&mut rec, &cap, &p, vocalist(b"Alice"));
    credits::remove_featured_artist(&mut rec, &cap, test_helpers::fake_id(ts.ctx()));
    abort
}

#[test, expected_failure(abort_code = credits::ENoCredits)]
fun remove_primary_artist_rejects_when_no_credits_record() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    credits::remove_primary_artist(&mut rec, &cap, test_helpers::fake_id(ts.ctx()));
    abort
}

#[test, expected_failure(abort_code = credits::ENoCredits)]
fun remove_featured_artist_rejects_when_no_credits_record() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    credits::remove_featured_artist(&mut rec, &cap, test_helpers::fake_id(ts.ctx()));
    abort
}

#[test]
fun credits_are_scoped_to_their_own_recording() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec_a, cap_a) = mk_recording(ts.ctx());
    let (rec_b, cap_b) = mk_recording(ts.ctx());
    let (p, pc) = party::new(ts.ctx());
    credits::add_credit(&mut rec_a, &cap_a, &p, vocalist(b"Alice"));
    credits::add_primary_artist(&mut rec_a, &cap_a, object::id(&p));
    assert!(credits::has_credits(&rec_a));
    assert!(credits::is_primary_artist(&rec_a, object::id(&p)));
    assert!(!credits::has_credits(&rec_b));
    assert!(!credits::is_primary_artist(&rec_b, object::id(&p)));
    destroy(rec_a);
    destroy(cap_a);
    destroy(rec_b);
    destroy(cap_b);
    destroy(p);
    destroy(pc);
    ts.end();
}

#[test]
fun featured_artist_changes_emit_events() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    let (p1, p1c) = party::new(ts.ctx());
    let (p2, p2c) = party::new(ts.ctx());
    let id1 = object::id(&p1);
    let id2 = object::id(&p2);
    let recording_id = object::id(&rec);
    credits::add_credit(&mut rec, &cap, &p1, vocalist(b"Featured One Display"));
    credits::add_credit(&mut rec, &cap, &p2, producer(b"Featured Two Display"));
    credits::add_featured_artist(&mut rec, &cap, object::id(&p1));
    credits::add_featured_artist(&mut rec, &cap, object::id(&p2));
    let added = events_by_type<credits::RecordingFeaturedArtistAddedEvent>();
    assert_eq!(added.length(), 2);
    let (event_object, event_party) = credits::recording_featured_artist_added_fields(&added[0]);
    assert_eq!(event_object, recording_id);
    assert_eq!(event_party, id1);
    let (event_object, event_party) = credits::recording_featured_artist_added_fields(&added[1]);
    assert_eq!(event_object, recording_id);
    assert_eq!(event_party, id2);
    assert_eq!(to_bytes(&added[0]).length(), 64);
    credits::remove_featured_artist(&mut rec, &cap, id2);
    let removed = events_by_type<credits::RecordingFeaturedArtistRemovedEvent>();
    assert_eq!(removed.length(), 1);
    let (event_object, event_party) = credits::recording_featured_artist_removed_fields(
        &removed[0],
    );
    assert_eq!(event_object, recording_id);
    assert_eq!(event_party, id2);
    assert_eq!(to_bytes(&removed[0]).length(), 64);
    assert!(credits::is_featured_artist(&rec, id1));
    assert!(!credits::is_featured_artist(&rec, id2));
    destroy(rec);
    destroy(cap);
    destroy(p1);
    destroy(p1c);
    destroy(p2);
    destroy(p2c);
    ts.end();
}

#[test]
fun remove_and_readd_preserves_order() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    let (p1, p1c) = party::new(ts.ctx());
    let (p2, p2c) = party::new(ts.ctx());
    let (p3, p3c) = party::new(ts.ctx());
    let (p4, p4c) = party::new(ts.ctx());
    let id1 = object::id(&p1);
    let id2 = object::id(&p2);
    let id3 = object::id(&p3);
    let id4 = object::id(&p4);
    let recording_id = object::id(&rec);
    let one = vocalist(b"One");
    let one_again = vocalist(b"OneAgain");
    let two = producer(b"Two");
    let two_again = producer(b"TwoAgain");
    let three = vocalist(b"Three");
    let four = producer(b"Four");
    credits::add_credit(&mut rec, &cap, &p1, one);
    credits::remove_credit(&mut rec, &cap, id1);
    assert!(!credits::has_credits(&rec));
    credits::add_credit(&mut rec, &cap, &p1, one_again);
    credits::add_credit(&mut rec, &cap, &p2, two);
    credits::add_credit(&mut rec, &cap, &p3, three);
    credits::add_credit(&mut rec, &cap, &p4, four);
    assert_eq!(credits::credits(&rec).get_idx(&id1), 0);
    assert_eq!(credits::credits(&rec).get_idx(&id2), 1);
    assert_eq!(credits::credits(&rec).get_idx(&id3), 2);
    assert_eq!(credits::credits(&rec).get_idx(&id4), 3);
    credits::remove_credit(&mut rec, &cap, id2);
    assert_eq!(credits::credits(&rec).get_idx(&id1), 0);
    assert_eq!(credits::credits(&rec).get_idx(&id3), 1);
    assert_eq!(credits::credits(&rec).get_idx(&id4), 2);
    credits::add_credit(&mut rec, &cap, &p2, two_again);
    assert_eq!(credits::credits(&rec).get_idx(&id1), 0);
    assert_eq!(credits::credits(&rec).get_idx(&id3), 1);
    assert_eq!(credits::credits(&rec).get_idx(&id4), 2);
    assert_eq!(credits::credits(&rec).get_idx(&id2), 3);
    assert_eq!(credits::credits(&rec)[&id1], one_again);
    assert_eq!(credits::credits(&rec)[&id2], two_again);
    assert_eq!(credits::credits(&rec)[&id3], three);
    assert_eq!(credits::credits(&rec)[&id4], four);
    let added = events_by_type<credits::RecordingCreditAddedEvent>();
    assert_eq!(added.length(), 6);
    assert_added(&added[0], recording_id, id1, &one);
    assert_added(&added[1], recording_id, id1, &one_again);
    assert_added(&added[2], recording_id, id2, &two);
    assert_added(&added[3], recording_id, id3, &three);
    assert_added(&added[4], recording_id, id4, &four);
    assert_added(&added[5], recording_id, id2, &two_again);
    let removed = events_by_type<credits::RecordingCreditRemovedEvent>();
    assert_eq!(removed.length(), 2);
    let (event_object, event_party) = credits::recording_credit_removed_fields(&removed[0]);
    assert_eq!(event_object, recording_id);
    assert_eq!(event_party, id1);
    let (event_object, event_party) = credits::recording_credit_removed_fields(&removed[1]);
    assert_eq!(event_object, recording_id);
    assert_eq!(event_party, id2);
    destroy(rec);
    destroy(cap);
    destroy(p1);
    destroy(p1c);
    destroy(p2);
    destroy(p2c);
    destroy(p3);
    destroy(p3c);
    destroy(p4);
    destroy(p4c);
    ts.end();
}

#[test]
fun event_bcs_sizes_match_declared_maxima() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    let (p, pc) = party::new(ts.ctx());
    let max_credit = credit::new(
        long_string(200),
        vector[
            instrumentalist(long_string(100), rpr::new_additional_role_level()),
            instrumentalist(long_string(100), rpr::new_assistant_role_level()),
            instrumentalist(long_string(100), rpr::new_associate_role_level()),
            instrumentalist(long_string(100), rpr::new_backing_role_level()),
            instrumentalist(long_string(100), rpr::new_executive_role_level()),
            instrumentalist(long_string(100), rpr::new_featured_role_level()),
            instrumentalist(long_string(100), rpr::new_lead_role_level()),
            instrumentalist(long_string(100), rpr::new_primary_role_level()),
            instrumentalist(long_string(100), rpr::new_principal_role_level()),
            instrumentalist(other_long_string(100), rpr::new_principal_role_level()),
        ],
    );
    let pid = object::id(&p);
    credits::add_credit(&mut rec, &cap, &p, max_credit);
    let added = events_by_type<credits::RecordingCreditAddedEvent>();
    let (_, _, name, roles) = credits::recording_credit_added_fields(&added[0]);
    assert_eq!(name, long_string(200));
    assert_eq!(roles, *credits::credits(&rec)[&pid].roles());
    assert_eq!(to_bytes(&added[0]).length(), 32 + 32 + 2 + 200 + 1 + 10 * 104);
    credits::add_primary_artist(&mut rec, &cap, object::id(&p));
    let primary_added = events_by_type<credits::RecordingPrimaryArtistAddedEvent>();
    assert_eq!(to_bytes(&primary_added[0]).length(), 64);
    credits::remove_primary_artist(&mut rec, &cap, pid);
    let primary_removed = events_by_type<credits::RecordingPrimaryArtistRemovedEvent>();
    assert_eq!(to_bytes(&primary_removed[0]).length(), 64);
    credits::add_featured_artist(&mut rec, &cap, object::id(&p));
    let featured_added = events_by_type<credits::RecordingFeaturedArtistAddedEvent>();
    assert_eq!(to_bytes(&featured_added[0]).length(), 64);
    credits::remove_featured_artist(&mut rec, &cap, pid);
    let featured_removed = events_by_type<credits::RecordingFeaturedArtistRemovedEvent>();
    assert_eq!(to_bytes(&featured_removed[0]).length(), 64);
    credits::remove_credit(&mut rec, &cap, pid);
    let removed = events_by_type<credits::RecordingCreditRemovedEvent>();
    assert_eq!(to_bytes(&removed[0]).length(), 64);
    destroy(rec);
    destroy(cap);
    destroy(p);
    destroy(pc);
    ts.end();
}

#[test, expected_failure(abort_code = credits::EMaxCreditsExceeded)]
fun add_credit_duplicate_at_capacity_reports_capacity() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    let (first, _first_cap) = party::new(ts.ctx());
    credits::add_credit(&mut rec, &cap, &first, vocalist(b"First"));
    (MAX_CREDITS - 1).do!(|_| {
        let (p, pc) = party::new(ts.ctx());
        credits::add_credit(&mut rec, &cap, &p, vocalist(b"P"));
        destroy(p);
        destroy(pc);
    });
    credits::add_credit(&mut rec, &cap, &first, vocalist(b"First again"));
    abort
}

#[test, expected_failure(abort_code = credits::EMaxPrimaryArtistsExceeded)]
fun add_primary_artist_full_set_and_uncredited_party_reports_capacity() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    MAX_PRIMARY_ARTISTS.do!(|_| {
        let (p, pc) = party::new(ts.ctx());
        credits::add_credit(&mut rec, &cap, &p, vocalist(b"P"));
        credits::add_primary_artist(&mut rec, &cap, object::id(&p));
        destroy(p);
        destroy(pc);
    });
    credits::add_primary_artist(&mut rec, &cap, test_helpers::fake_id(ts.ctx()));
    abort
}

#[test, expected_failure(abort_code = credits::EMaxFeaturedArtistsExceeded)]
fun add_featured_artist_full_set_and_uncredited_party_reports_capacity() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = mk_recording(ts.ctx());
    MAX_FEATURED_ARTISTS.do!(|_| {
        let (p, pc) = party::new(ts.ctx());
        credits::add_credit(&mut rec, &cap, &p, vocalist(b"P"));
        credits::add_featured_artist(&mut rec, &cap, object::id(&p));
        destroy(p);
        destroy(pc);
    });
    credits::add_featured_artist(&mut rec, &cap, test_helpers::fake_id(ts.ctx()));
    abort
}
