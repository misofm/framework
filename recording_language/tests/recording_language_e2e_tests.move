// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module recording_language::recording_language_e2e_tests;

use language_code::language_code::{Self, LanguageCode};
use miso_music::{composition, recording::{Self, Recording, RecordingAdminCap}};
use recording_language::recording_language::{
    Self as rl,
    RecordingLanguagesSetEvent,
    RecordingLanguagesClearedEvent,
};
use std::unit_test::{assert_eq, destroy};
use sui::{bcs::to_bytes, event::events_by_type, test_scenario::{Self as ts, Scenario}};

const ADMIN: address = @0xAD;
const STRANGER: address = @0x51;

public struct TestShare() has drop;

fun language(code: vector<u8>): LanguageCode {
    language_code::new(code.to_string())
}

fun publish_recording(ts: &mut Scenario): (ID, RecordingAdminCap<TestShare>) {
    let (comp, comp_cap) = composition::new_for_testing<TestShare>(ts.ctx());
    let (rec, cap) = recording::new_for_testing<TestShare>(object::id(&comp), ts.ctx());
    comp.share();
    destroy(comp_cap);
    let rec_id = object::id(&rec);
    rec.share();
    (rec_id, cap)
}

#[test]
fun admin_sets_languages_on_a_published_shared_recording_and_a_stranger_reads_it() {
    let mut ts = ts::begin(ADMIN);
    let (rec_id, rec_cap) = publish_recording(&mut ts);
    ts.next_tx(ADMIN);
    let mut rec = ts.take_shared<Recording<TestShare>>();
    assert!(!rl::has_languages(&rec));
    rl::set_languages(&mut rec, &rec_cap, vector[language(b"en"), language(b"fr")]);
    let events = events_by_type<RecordingLanguagesSetEvent>();
    assert_eq!(events.length(), 1);
    let (event_id, languages) = rl::recording_languages_set_fields_for_testing(&events[0]);
    assert_eq!(event_id, rec_id);
    assert_eq!(languages, vector[b"en".to_string(), b"fr".to_string()]);
    assert_eq!(to_bytes(&events[0]).length(), 39);
    ts::return_shared(rec);
    ts.next_tx(STRANGER);
    let rec = ts.take_shared<Recording<TestShare>>();
    assert!(rl::has_languages(&rec));
    let got = rl::languages(&rec);
    assert_eq!(got.length(), 2);
    assert_eq!(got[0].code(), b"en".to_string());
    assert_eq!(got[1].code(), b"fr".to_string());
    ts::return_shared(rec);
    ts.next_tx(ADMIN);
    let mut rec = ts.take_shared<Recording<TestShare>>();
    rl::set_languages(&mut rec, &rec_cap, vector[language(b"en"), language(b"fr")]);
    assert_eq!(events_by_type<RecordingLanguagesSetEvent>().length(), 0);
    rl::set_languages(&mut rec, &rec_cap, vector[]);
    assert!(rl::has_languages(&rec));
    assert!(rl::languages(&rec).is_empty());
    let events = events_by_type<RecordingLanguagesSetEvent>();
    assert_eq!(events.length(), 1);
    let (_, languages) = rl::recording_languages_set_fields_for_testing(&events[0]);
    assert!(languages.is_empty());
    assert_eq!(to_bytes(&events[0]).length(), 33);
    rl::clear_languages(&mut rec, &rec_cap);
    assert!(!rl::has_languages(&rec));
    let cleared = events_by_type<RecordingLanguagesClearedEvent>();
    assert_eq!(cleared.length(), 1);
    assert_eq!(rl::recording_languages_cleared_fields_for_testing(&cleared[0]), rec_id);
    assert_eq!(to_bytes(&cleared[0]).length(), 32);
    ts::return_shared(rec);
    ts.next_tx(STRANGER);
    let rec = ts.take_shared<Recording<TestShare>>();
    assert!(!rl::has_languages(&rec));
    ts::return_shared(rec);
    destroy(rec_cap);
    ts.end();
}

#[test, expected_failure(abort_code = rl::ENoLanguages)]
fun reading_after_clear_aborts_for_any_reader() {
    let mut ts = ts::begin(ADMIN);
    let (_, rec_cap) = publish_recording(&mut ts);
    ts.next_tx(ADMIN);
    let mut rec = ts.take_shared<Recording<TestShare>>();
    rl::set_languages(&mut rec, &rec_cap, vector[language(b"en")]);
    rl::clear_languages(&mut rec, &rec_cap);
    ts::return_shared(rec);
    ts.next_tx(STRANGER);
    let rec = ts.take_shared<Recording<TestShare>>();
    let _ = rl::languages(&rec);
    ts::return_shared(rec);
    destroy(rec_cap);
    ts.end();
}

#[test, expected_failure(abort_code = rl::ELanguageAlreadyAdded)]
fun duplicate_language_aborts_against_a_shared_recording() {
    let mut ts = ts::begin(ADMIN);
    let (_, rec_cap) = publish_recording(&mut ts);
    ts.next_tx(ADMIN);
    let mut rec = ts.take_shared<Recording<TestShare>>();
    rl::set_languages(&mut rec, &rec_cap, vector[language(b"en"), language(b"en")]);
    ts::return_shared(rec);
    destroy(rec_cap);
    ts.end();
}
