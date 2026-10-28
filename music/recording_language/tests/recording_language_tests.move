// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module recording_language::recording_language_tests;

use language_code::language_code::{Self, LanguageCode};
use miso_music::recording::{Self, Recording, RecordingAdminCap};
use recording_language::recording_language::{
    Self as rl,
    RecordingLanguagesSetEvent,
    RecordingLanguagesClearedEvent,
};
use std::{string::String, unit_test::{assert_eq, destroy}};
use sui::{bcs::to_bytes, event::events_by_type};

const TEN_CODES: vector<vector<u8>> = vector[
    b"en",
    b"fr",
    b"es",
    b"de",
    b"it",
    b"ja",
    b"ko",
    b"pt",
    b"ru",
    b"zh",
];

public struct TestShare() has drop;

fun new_rec(ctx: &mut TxContext): (Recording<TestShare>, RecordingAdminCap<TestShare>) {
    recording::new_for_testing(object::id_from_address(@0xC0FFEE), ctx)
}

fun lang(code: vector<u8>): LanguageCode {
    language_code::new(code.to_string())
}

fun langs(codes: vector<vector<u8>>): vector<LanguageCode> {
    codes.map!(|code| lang(code))
}

fun strings(codes: vector<vector<u8>>): vector<String> {
    codes.map!(|code| code.to_string())
}

fun stored_codes(rec: &Recording<TestShare>): vector<String> {
    rl::languages(rec).map_ref!(|language| language.code())
}

#[test]
fun set_read_replace_clear_lifecycle() {
    let ctx = &mut tx_context::dummy();
    let (mut rec, cap) = new_rec(ctx);
    let rec_id = object::id(&rec);
    assert!(!rl::has_languages(&rec));
    rl::set_languages(&mut rec, &cap, langs(vector[b"en", b"fr"]));
    assert!(rl::has_languages(&rec));
    assert_eq!(stored_codes(&rec), strings(vector[b"en", b"fr"]));
    let set_events = events_by_type<RecordingLanguagesSetEvent>();
    assert_eq!(set_events.length(), 1);
    let (event_rec_id, languages) = rl::recording_languages_set_fields(&set_events[0]);
    assert_eq!(event_rec_id, rec_id);
    assert_eq!(languages, strings(vector[b"en", b"fr"]));
    rl::set_languages(&mut rec, &cap, langs(vector[b"fr", b"en"]));
    assert_eq!(stored_codes(&rec), strings(vector[b"fr", b"en"]));
    let set_events = events_by_type<RecordingLanguagesSetEvent>();
    assert_eq!(set_events.length(), 2);
    let (_, languages) = rl::recording_languages_set_fields(&set_events[1]);
    assert_eq!(languages, strings(vector[b"fr", b"en"]));
    rl::clear_languages(&mut rec, &cap);
    assert!(!rl::has_languages(&rec));
    let cleared = events_by_type<RecordingLanguagesClearedEvent>();
    assert_eq!(cleared.length(), 1);
    assert_eq!(rl::recording_languages_cleared_fields(&cleared[0]), rec_id);
    rl::set_languages(&mut rec, &cap, langs(vector[b"ja"]));
    assert_eq!(stored_codes(&rec), strings(vector[b"ja"]));
    assert_eq!(events_by_type<RecordingLanguagesSetEvent>().length(), 3);
    destroy(rec);
    destroy(cap);
}

#[test]
fun equal_set_neither_writes_nor_emits() {
    let ctx = &mut tx_context::dummy();
    let (mut rec, cap) = new_rec(ctx);
    rl::set_languages(&mut rec, &cap, langs(vector[b"en", b"fr"]));
    rl::set_languages(&mut rec, &cap, langs(vector[b"en", b"fr"]));
    assert_eq!(stored_codes(&rec), strings(vector[b"en", b"fr"]));
    assert_eq!(events_by_type<RecordingLanguagesSetEvent>().length(), 1);
    rl::set_languages(&mut rec, &cap, vector[]);
    rl::set_languages(&mut rec, &cap, vector[]);
    assert_eq!(events_by_type<RecordingLanguagesSetEvent>().length(), 2);
    destroy(rec);
    destroy(cap);
}

#[test]
fun clear_when_absent_is_silent() {
    let ctx = &mut tx_context::dummy();
    let (mut rec, cap) = new_rec(ctx);
    rl::clear_languages(&mut rec, &cap);
    assert!(!rl::has_languages(&rec));
    assert_eq!(events_by_type<RecordingLanguagesClearedEvent>().length(), 0);
    rl::set_languages(&mut rec, &cap, langs(vector[b"en"]));
    rl::clear_languages(&mut rec, &cap);
    rl::clear_languages(&mut rec, &cap);
    assert_eq!(events_by_type<RecordingLanguagesClearedEvent>().length(), 1);
    destroy(rec);
    destroy(cap);
}

#[test]
fun order_is_preserved() {
    let ctx = &mut tx_context::dummy();
    let (mut rec, cap) = new_rec(ctx);
    rl::set_languages(&mut rec, &cap, langs(vector[b"ja", b"en", b"ko"]));
    let got = rl::languages(&rec);
    assert_eq!(got[0].code(), b"ja".to_string());
    assert_eq!(got[1].code(), b"en".to_string());
    assert_eq!(got[2].code(), b"ko".to_string());
    destroy(rec);
    destroy(cap);
}

#[test]
fun reordered_languages_count_as_a_change() {
    let ctx = &mut tx_context::dummy();
    let (mut rec, cap) = new_rec(ctx);
    rl::set_languages(&mut rec, &cap, langs(vector[b"en", b"fr", b"ja"]));
    rl::set_languages(&mut rec, &cap, langs(vector[b"ja", b"en", b"fr"]));
    assert_eq!(stored_codes(&rec), strings(vector[b"ja", b"en", b"fr"]));
    let set_events = events_by_type<RecordingLanguagesSetEvent>();
    assert_eq!(set_events.length(), 2);
    let (_, languages) = rl::recording_languages_set_fields(&set_events[1]);
    assert_eq!(languages, strings(vector[b"ja", b"en", b"fr"]));
    destroy(rec);
    destroy(cap);
}

#[test]
fun instrumental_is_distinct_from_absent_and_from_sung() {
    let ctx = &mut tx_context::dummy();
    let (mut rec, cap) = new_rec(ctx);
    let rec_id = object::id(&rec);
    assert!(!rl::has_languages(&rec));
    rl::set_languages(&mut rec, &cap, vector[]);
    assert!(rl::has_languages(&rec));
    assert!(rl::languages(&rec).is_empty());
    let set_events = events_by_type<RecordingLanguagesSetEvent>();
    assert_eq!(set_events.length(), 1);
    let (event_rec_id, languages) = rl::recording_languages_set_fields(&set_events[0]);
    assert_eq!(event_rec_id, rec_id);
    assert!(languages.is_empty());
    assert_eq!(to_bytes(&set_events[0]).length(), 33);
    rl::set_languages(&mut rec, &cap, langs(vector[b"en"]));
    assert_eq!(stored_codes(&rec), strings(vector[b"en"]));
    assert_eq!(events_by_type<RecordingLanguagesSetEvent>().length(), 2);
    rl::set_languages(&mut rec, &cap, vector[]);
    assert!(rl::languages(&rec).is_empty());
    assert_eq!(events_by_type<RecordingLanguagesSetEvent>().length(), 3);
    rl::clear_languages(&mut rec, &cap);
    assert!(!rl::has_languages(&rec));
    let cleared = events_by_type<RecordingLanguagesClearedEvent>();
    assert_eq!(cleared.length(), 1);
    assert_eq!(rl::recording_languages_cleared_fields(&cleared[0]), rec_id);
    assert_eq!(to_bytes(&cleared[0]).length(), 32);
    destroy(rec);
    destroy(cap);
}

#[test]
fun set_event_carries_the_recording_and_the_new_value() {
    let ctx = &mut tx_context::dummy();
    let (mut rec, cap) = new_rec(ctx);
    let rec_id = object::id(&rec);
    rl::set_languages(&mut rec, &cap, langs(vector[b"en", b"fr"]));
    let events = events_by_type<RecordingLanguagesSetEvent>();
    assert_eq!(events.length(), 1);
    let (event_rec_id, languages) = rl::recording_languages_set_fields(&events[0]);
    assert_eq!(event_rec_id, rec_id);
    assert_eq!(languages, strings(vector[b"en", b"fr"]));
    assert_eq!(to_bytes(&events[0]).length(), 32 + 1 + 3 * 2);
    destroy(rec);
    destroy(cap);
}

#[test]
fun exactly_max_languages_is_accepted() {
    let ctx = &mut tx_context::dummy();
    let (mut rec, cap) = new_rec(ctx);
    rl::set_languages(&mut rec, &cap, langs(TEN_CODES));
    assert_eq!(rl::languages(&rec).length(), 10);
    assert_eq!(stored_codes(&rec), strings(TEN_CODES));
    let events = events_by_type<RecordingLanguagesSetEvent>();
    assert_eq!(events.length(), 1);
    let (_, languages) = rl::recording_languages_set_fields(&events[0]);
    assert_eq!(languages, strings(TEN_CODES));
    assert_eq!(to_bytes(&events[0]).length(), 32 + 1 + 3 * 10);
    destroy(rec);
    destroy(cap);
}

#[test]
fun views_are_silent() {
    let ctx = &mut tx_context::dummy();
    let (mut rec, cap) = new_rec(ctx);
    assert!(!rl::has_languages(&rec));
    rl::set_languages(&mut rec, &cap, langs(vector[b"en"]));
    let _ = rl::has_languages(&rec);
    let _ = rl::languages(&rec);
    assert_eq!(events_by_type<RecordingLanguagesSetEvent>().length(), 1);
    assert_eq!(events_by_type<RecordingLanguagesClearedEvent>().length(), 0);
    destroy(rec);
    destroy(cap);
}

#[test]
fun languages_are_per_recording() {
    let ctx = &mut tx_context::dummy();
    let (mut a, a_cap) = new_rec(ctx);
    let (mut b, b_cap) = new_rec(ctx);
    rl::set_languages(&mut a, &a_cap, langs(vector[b"en"]));
    assert!(!rl::has_languages(&b));
    assert_eq!(events_by_type<RecordingLanguagesSetEvent>().length(), 1);
    rl::set_languages(&mut b, &b_cap, langs(vector[b"fr"]));
    assert_eq!(rl::languages(&a)[0].code(), b"en".to_string());
    assert_eq!(rl::languages(&b)[0].code(), b"fr".to_string());
    assert_eq!(events_by_type<RecordingLanguagesSetEvent>().length(), 2);
    rl::clear_languages(&mut a, &a_cap);
    assert!(rl::has_languages(&b));
    assert_eq!(events_by_type<RecordingLanguagesClearedEvent>().length(), 1);
    destroy(a);
    destroy(a_cap);
    destroy(b);
    destroy(b_cap);
}

#[test, expected_failure(abort_code = rl::ENoLanguages)]
fun languages_aborts_when_absent() {
    let ctx = &mut tx_context::dummy();
    let (rec, cap) = new_rec(ctx);
    let _ = rl::languages(&rec);
    destroy(rec);
    destroy(cap);
}

#[test, expected_failure(abort_code = rl::ENoLanguages)]
fun languages_aborts_after_clear() {
    let ctx = &mut tx_context::dummy();
    let (mut rec, cap) = new_rec(ctx);
    rl::set_languages(&mut rec, &cap, vector[]);
    rl::clear_languages(&mut rec, &cap);
    let _ = rl::languages(&rec);
    destroy(rec);
    destroy(cap);
}

#[test, expected_failure(abort_code = rl::EDuplicateLanguage)]
fun duplicate_language_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut rec, cap) = new_rec(ctx);
    rl::set_languages(&mut rec, &cap, langs(vector[b"en", b"fr", b"en"]));
    destroy(rec);
    destroy(cap);
}

#[test, expected_failure(abort_code = rl::EMaxLanguagesExceeded)]
fun more_than_max_languages_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut rec, cap) = new_rec(ctx);
    let mut codes = TEN_CODES;
    codes.push_back(b"ar");
    rl::set_languages(&mut rec, &cap, langs(codes));
    destroy(rec);
    destroy(cap);
}

#[test, expected_failure(abort_code = rl::EMaxLanguagesExceeded)]
fun count_is_checked_before_duplicates() {
    let ctx = &mut tx_context::dummy();
    let (mut rec, cap) = new_rec(ctx);
    let mut codes = TEN_CODES;
    codes.push_back(b"en");
    rl::set_languages(&mut rec, &cap, langs(codes));
    destroy(rec);
    destroy(cap);
}

#[test, expected_failure(abort_code = rl::EDuplicateLanguage)]
fun invalid_replacement_aborts_without_touching_the_stored_value() {
    let ctx = &mut tx_context::dummy();
    let (mut rec, cap) = new_rec(ctx);
    rl::set_languages(&mut rec, &cap, langs(vector[b"en"]));
    rl::set_languages(&mut rec, &cap, langs(vector[b"fr", b"fr"]));
    destroy(rec);
    destroy(cap);
}

#[test, expected_failure(abort_code = language_code::EInvalidLanguageCode)]
fun invalid_code_is_rejected_by_the_primitive() {
    let _ = lang(b"zzz");
}
