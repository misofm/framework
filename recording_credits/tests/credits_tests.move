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
use sui::{bcs::to_bytes, event::events_by_type, test_scenario};

const ARTIST: address = @0xA1;
const MAX_CREDITS: u64 = 150;

public struct TestShare() has drop;

fun new_recording(ctx: &mut TxContext): (Recording<TestShare>, RecordingAdminCap<TestShare>) {
    recording::new_for_testing(test_helpers::fake_id(ctx), ctx)
}

fun vocalist(name: vector<u8>): Credit<RecordingPartyRole> {
    credit::new(name.to_string(), vector[rpr::new_vocalist_role(option::none())])
}

fun producer(name: vector<u8>): Credit<RecordingPartyRole> {
    credit::new(name.to_string(), vector[rpr::new_producer_role(option::none())])
}

fun artist(name: vector<u8>, role: RecordingPartyRole): Credit<RecordingPartyRole> {
    credit::new(name.to_string(), vector[role])
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
    ) = credits::recording_credit_added_fields_for_testing(event);
    assert_eq!(event_object, recording_id);
    assert_eq!(event_party, party_id);
    assert_eq!(event_name, *credit.display_name());
    assert_eq!(event_roles, *credit.roles());
}

#[test]
fun add_credit_attaches_and_reads_back() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = new_recording(ts.ctx());
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

#[test, expected_failure(abort_code = credits::EPartyAlreadyCredited)]
fun add_credit_rejects_duplicate_party() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = new_recording(ts.ctx());
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

#[test, expected_failure(abort_code = credits::EPartyAlreadyCredited)]
fun add_credit_rejects_identical_credit() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = new_recording(ts.ctx());
    let (p, _pc) = party::new(ts.ctx());
    let alice = vocalist(b"Alice");
    credits::add_credit(&mut rec, &cap, &p, alice);
    credits::add_credit(&mut rec, &cap, &p, alice);
    abort
}

#[test, expected_failure(abort_code = credits::EPrimaryAndFeatured)]
fun add_credit_rejects_primary_and_featured() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = new_recording(ts.ctx());
    let (p, _pc) = party::new(ts.ctx());
    credits::add_credit(
        &mut rec,
        &cap,
        &p,
        credit::new(
            b"Alice".to_string(),
            vector[rpr::new_primary_role(), rpr::new_featured_role()],
        ),
    );
    abort
}

#[test, expected_failure(abort_code = credits::ETooManyRoles)]
fun add_credit_rejects_too_many_roles() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = new_recording(ts.ctx());
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
    let (mut rec, cap) = new_recording(ts.ctx());
    let (p1, p1c) = party::new(ts.ctx());
    let (p2, p2c) = party::new(ts.ctx());
    let (p3, p3c) = party::new(ts.ctx());
    credits::add_credit(&mut rec, &cap, &p1, artist(b"Lead", rpr::new_primary_role()));
    credits::add_credit(&mut rec, &cap, &p2, artist(b"Guest", rpr::new_featured_role()));
    credits::add_credit(&mut rec, &cap, &p3, vocalist(b"Backing"));
    assert!(credits::is_primary_artist(&rec, object::id(&p1)));
    assert!(!credits::is_featured_artist(&rec, object::id(&p1)));
    assert!(credits::is_featured_artist(&rec, object::id(&p2)));
    assert!(!credits::is_primary_artist(&rec, object::id(&p2)));
    assert!(!credits::is_primary_artist(&rec, object::id(&p3)));
    assert!(!credits::is_featured_artist(&rec, object::id(&p3)));
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
fun artist_roles_combine_with_other_roles_in_one_credit() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = new_recording(ts.ctx());
    let (p, pc) = party::new(ts.ctx());
    credits::add_credit(
        &mut rec,
        &cap,
        &p,
        credit::new(
            b"Both".to_string(),
            vector[rpr::new_primary_role(), rpr::new_vocalist_role(option::none())],
        ),
    );
    assert!(credits::is_primary_artist(&rec, object::id(&p)));
    assert!(!credits::is_featured_artist(&rec, object::id(&p)));
    destroy(rec);
    destroy(cap);
    destroy(p);
    destroy(pc);
    ts.end();
}

#[test]
fun artist_views_are_false_for_uncredited_party() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = new_recording(ts.ctx());
    let (p, pc) = party::new(ts.ctx());
    let (other, oc) = party::new(ts.ctx());
    credits::add_credit(&mut rec, &cap, &p, artist(b"Lead", rpr::new_primary_role()));
    assert!(!credits::is_primary_artist(&rec, object::id(&other)));
    assert!(!credits::is_featured_artist(&rec, object::id(&other)));
    destroy(rec);
    destroy(cap);
    destroy(p);
    destroy(pc);
    destroy(other);
    destroy(oc);
    ts.end();
}

#[test]
fun remove_credit_clears_artist_roles() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = new_recording(ts.ctx());
    let (p, pc) = party::new(ts.ctx());
    let pid = object::id(&p);
    credits::add_credit(&mut rec, &cap, &p, artist(b"Alice", rpr::new_primary_role()));
    assert!(credits::is_primary_artist(&rec, pid));
    credits::remove_credit(&mut rec, &cap, pid);
    assert!(!credits::is_primary_artist(&rec, pid));
    assert!(!credits::has_credits(&rec));
    assert_eq!(events_by_type<credits::RecordingCreditRemovedEvent>().length(), 1);
    destroy(rec);
    destroy(cap);
    destroy(p);
    destroy(pc);
    ts.end();
}

#[test]
fun add_credit_emits_the_full_credit() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = new_recording(ts.ctx());
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
    ) = credits::recording_credit_added_fields_for_testing(&events[0]);
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
    let (mut rec, cap) = new_recording(ts.ctx());
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
    let (event_object, event_party) = credits::recording_credit_removed_fields_for_testing(
        &events[0],
    );
    assert_eq!(event_object, recording_id);
    assert_eq!(event_party, party_id);
    assert_eq!(to_bytes(&events[0]).length(), 64);
    destroy(rec);
    destroy(cap);
    destroy(p);
    destroy(pc);
    ts.end();
}

#[test, expected_failure(abort_code = credits::ETooManyCredits)]
fun add_credit_rejects_past_max_credits() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = new_recording(ts.ctx());
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

#[test, expected_failure(abort_code = credits::ENoCredits)]
fun credits_view_aborts_when_no_credits_record() {
    let mut ts = test_scenario::begin(ARTIST);
    let (rec, _cap) = new_recording(ts.ctx());
    let _ = credits::credits(&rec);
    abort
}

#[test]
fun is_primary_and_featured_artist_are_false_before_any_credit() {
    let mut ts = test_scenario::begin(ARTIST);
    let (rec, cap) = new_recording(ts.ctx());
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

#[test, expected_failure(abort_code = credits::EPartyNotFound)]
fun remove_credit_rejects_double_removal() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = new_recording(ts.ctx());
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
    let (mut rec, cap) = new_recording(ts.ctx());
    let (p, _pc) = party::new(ts.ctx());
    let pid = object::id(&p);
    credits::add_credit(&mut rec, &cap, &p, vocalist(b"Alice"));
    credits::remove_credit(&mut rec, &cap, pid);
    assert!(!credits::has_credits(&rec));
    credits::remove_credit(&mut rec, &cap, pid);
    abort
}

#[test]
fun credits_are_scoped_to_their_own_recording() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec_a, cap_a) = new_recording(ts.ctx());
    let (rec_b, cap_b) = new_recording(ts.ctx());
    let (p, pc) = party::new(ts.ctx());
    credits::add_credit(&mut rec_a, &cap_a, &p, artist(b"Alice", rpr::new_primary_role()));
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
fun remove_and_readd_preserves_order() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = new_recording(ts.ctx());
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
    let (event_object, event_party) = credits::recording_credit_removed_fields_for_testing(
        &removed[0],
    );
    assert_eq!(event_object, recording_id);
    assert_eq!(event_party, id1);
    let (event_object, event_party) = credits::recording_credit_removed_fields_for_testing(
        &removed[1],
    );
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
    let (mut rec, cap) = new_recording(ts.ctx());
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
    let (_, _, name, roles) = credits::recording_credit_added_fields_for_testing(&added[0]);
    assert_eq!(name, long_string(200));
    assert_eq!(roles, *credits::credits(&rec)[&pid].roles());
    assert_eq!(to_bytes(&added[0]).length(), 32 + 32 + 2 + 200 + 1 + 10 * 104);
    credits::remove_credit(&mut rec, &cap, pid);
    let removed = events_by_type<credits::RecordingCreditRemovedEvent>();
    assert_eq!(to_bytes(&removed[0]).length(), 64);
    destroy(rec);
    destroy(cap);
    destroy(p);
    destroy(pc);
    ts.end();
}

#[test, expected_failure(abort_code = credits::ETooManyCredits)]
fun add_credit_duplicate_at_capacity_reports_capacity() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rec, cap) = new_recording(ts.ctx());
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
