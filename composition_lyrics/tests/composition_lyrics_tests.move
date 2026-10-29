// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module composition_lyrics::composition_lyrics_tests;

use composition_lyrics::composition_lyrics as cl;
use language_code::language_code as lc;
use miso_music::composition::{Self, Composition, CompositionAdminCap};
use std::unit_test::{assert_eq, destroy};
use sui::{bcs, event, test_scenario};

public struct TestShare() has drop;

fun new_composition(ctx: &mut TxContext): (Composition<TestShare>, CompositionAdminCap<TestShare>) {
    composition::new_for_testing<TestShare>(ctx)
}

fun assert_set_event(
    event: &cl::CompositionLyricsSetEvent,
    composition_id: ID,
    language: vector<u8>,
    lyrics: vector<u8>,
) {
    let (event_id, event_language, event_lyrics) = cl::composition_lyrics_set_fields_for_testing(
        event,
    );
    assert_eq!(event_id, composition_id);
    assert_eq!(event_language, language.to_string());
    assert_eq!(event_lyrics, lyrics);
    let mut bytes = bcs::new(bcs::to_bytes(event));
    assert_eq!(bytes.peel_address().to_id(), composition_id);
    assert_eq!(bytes.peel_vec_u8(), language);
    assert_eq!(bytes.peel_vec_u8(), lyrics);
    assert!(bytes.into_remainder_bytes().is_empty());
}

fun assert_cleared_event(
    event: &cl::CompositionLyricsClearedEvent,
    composition_id: ID,
    language: vector<u8>,
) {
    let (event_id, event_language) = cl::composition_lyrics_cleared_fields_for_testing(event);
    assert_eq!(event_id, composition_id);
    assert_eq!(event_language, language.to_string());
    let mut bytes = bcs::new(bcs::to_bytes(event));
    assert_eq!(bytes.peel_address().to_id(), composition_id);
    assert_eq!(bytes.peel_vec_u8(), language);
    assert!(bytes.into_remainder_bytes().is_empty());
    assert_eq!(bcs::to_bytes(event).length(), 35);
}

#[test]
fun languages_are_independent_and_events_replay_transitions() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = new_composition(ctx);
    let en = lc::new(b"en".to_string());
    let ja = lc::new(b"ja".to_string());
    let id = object::id(&comp);
    assert!(!cl::has_lyrics(&comp, en));
    cl::clear_lyrics(&mut comp, &cap, en);
    assert!(event::events_by_type<cl::CompositionLyricsClearedEvent>().is_empty());
    let first = vector[0u8, 255, 128];
    cl::set_lyrics(&mut comp, &cap, en, first);
    cl::set_lyrics(&mut comp, &cap, ja, vector[42]);
    cl::set_lyrics(&mut comp, &cap, en, vector[7]);
    cl::set_lyrics(&mut comp, &cap, en, vector[7]);
    assert_eq!(*cl::lyrics(&comp, en), vector[7]);
    assert_eq!(*cl::lyrics(&comp, ja), vector[42]);
    let sets = event::events_by_type<cl::CompositionLyricsSetEvent>();
    assert_eq!(sets.length(), 3);
    assert_set_event(&sets[0], id, b"en", first);
    assert_set_event(&sets[1], id, b"ja", vector[42]);
    assert_set_event(&sets[2], id, b"en", vector[7]);
    assert_eq!(bcs::to_bytes(&sets[2]).length(), 32 + 3 + 1 + 1);
    cl::clear_lyrics(&mut comp, &cap, en);
    cl::clear_lyrics(&mut comp, &cap, en);
    assert!(!cl::has_lyrics(&comp, en));
    assert_eq!(*cl::lyrics(&comp, ja), vector[42]);
    let clears = event::events_by_type<cl::CompositionLyricsClearedEvent>();
    assert_eq!(clears.length(), 1);
    assert_cleared_event(&clears[0], id, b"en");
    cl::set_lyrics(&mut comp, &cap, en, first);
    let sets = event::events_by_type<cl::CompositionLyricsSetEvent>();
    assert_eq!(sets.length(), 4);
    assert_set_event(&sets[3], id, b"en", first);
    cl::clear_lyrics(&mut comp, &cap, en);
    cl::clear_lyrics(&mut comp, &cap, ja);
    destroy(comp);
    destroy(cap);
}

#[test]
fun equal_set_is_a_silent_no_op() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = new_composition(ctx);
    let en = lc::new(b"en".to_string());
    let id = object::id(&comp);
    cl::set_lyrics(&mut comp, &cap, en, vector[1, 2, 3]);
    let events_after_first = event::num_events();
    cl::set_lyrics(&mut comp, &cap, en, vector[1, 2, 3]);
    assert_eq!(event::num_events(), events_after_first);
    assert_eq!(*cl::lyrics(&comp, en), vector[1, 2, 3]);
    let sets = event::events_by_type<cl::CompositionLyricsSetEvent>();
    assert_eq!(sets.length(), 1);
    assert_set_event(&sets[0], id, b"en", vector[1, 2, 3]);
    destroy(comp);
    destroy(cap);
}

#[test]
fun views_and_absent_clear_are_silent() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = new_composition(ctx);
    let en = lc::new(b"en".to_string());
    let events_before = event::num_events();
    assert!(!cl::has_lyrics(&comp, en));
    cl::clear_lyrics(&mut comp, &cap, en);
    assert_eq!(event::num_events(), events_before);
    cl::set_lyrics(&mut comp, &cap, en, vector[1]);
    let events_after_set = event::num_events();
    assert!(cl::has_lyrics(&comp, en));
    assert_eq!(*cl::lyrics(&comp, en), vector[1]);
    assert_eq!(event::num_events(), events_after_set);
    destroy(comp);
    destroy(cap);
}

#[test, expected_failure(abort_code = cl::EEmptyLyrics)]
fun empty_payload_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = new_composition(ctx);
    cl::set_lyrics(&mut comp, &cap, lc::new(b"en".to_string()), vector[]);
    abort
}

#[test]
fun max_lyrics_length_is_32_kib() {
    assert_eq!(cl::max_lyrics_length(), 32768);
}

#[test]
fun maximum_payload_can_be_added_replaced_and_cleared() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = new_composition(ctx);
    let en = lc::new(b"en".to_string());
    let id = object::id(&comp);
    assert_eq!(cl::max_lyrics_length(), 32768);
    let data = vector::tabulate!(32768, |_| 255u8);
    let other = vector::tabulate!(32768, |_| 0u8);
    cl::set_lyrics(&mut comp, &cap, en, data);
    cl::set_lyrics(&mut comp, &cap, en, data);
    assert_eq!(*cl::lyrics(&comp, en), data);
    cl::set_lyrics(&mut comp, &cap, en, other);
    assert_eq!(*cl::lyrics(&comp, en), other);
    let sets = event::events_by_type<cl::CompositionLyricsSetEvent>();
    assert_eq!(sets.length(), 2);
    assert_set_event(&sets[0], id, b"en", data);
    assert_set_event(&sets[1], id, b"en", other);
    assert_eq!(bcs::to_bytes(&sets[1]).length(), 32 + 3 + 3 + 32768);
    cl::clear_lyrics(&mut comp, &cap, en);
    let clears = event::events_by_type<cl::CompositionLyricsClearedEvent>();
    assert_cleared_event(&clears[0], id, b"en");
    destroy(comp);
    destroy(cap);
}

#[test, expected_failure(abort_code = cl::ELyricsTooLong)]
fun oversized_payload_aborts_on_add() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = new_composition(ctx);
    let lyrics = vector::tabulate!(cl::max_lyrics_length() + 1, |_| 0u8);
    cl::set_lyrics(&mut comp, &cap, lc::new(b"en".to_string()), lyrics);
    abort
}

#[test, expected_failure(abort_code = cl::ELyricsTooLong)]
fun oversized_payload_aborts_on_replace() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = new_composition(ctx);
    cl::set_lyrics(&mut comp, &cap, lc::new(b"en".to_string()), vector[1]);
    let lyrics = vector::tabulate!(cl::max_lyrics_length() + 1, |_| 0u8);
    cl::set_lyrics(&mut comp, &cap, lc::new(b"en".to_string()), lyrics);
    abort
}

#[test, expected_failure(abort_code = cl::ENoLyrics)]
fun missing_language_aborts_even_when_another_exists() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = new_composition(ctx);
    cl::set_lyrics(&mut comp, &cap, lc::new(b"en".to_string()), vector[1]);
    cl::lyrics(&comp, lc::new(b"ja".to_string()));
    abort
}

#[test, expected_failure(abort_code = cl::ENoLyrics)]
fun cleared_language_aborts_on_read() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = new_composition(ctx);
    cl::set_lyrics(&mut comp, &cap, lc::new(b"en".to_string()), vector[1]);
    cl::clear_lyrics(&mut comp, &cap, lc::new(b"en".to_string()));
    cl::lyrics(&comp, lc::new(b"en".to_string()));
    abort
}

#[test]
fun published_composition_supports_edits_and_permissionless_reads() {
    let mut ts = test_scenario::begin(@0xA);
    let (comp, cap) = new_composition(ts.ctx());
    comp.share();
    transfer::public_transfer(cap, @0xA);
    ts.next_tx(@0xA);
    let mut comp = ts.take_shared<Composition<TestShare>>();
    let cap = ts.take_from_sender<CompositionAdminCap<TestShare>>();
    cl::set_lyrics(&mut comp, &cap, lc::new(b"en".to_string()), vector[1]);
    cl::set_lyrics(&mut comp, &cap, lc::new(b"ja".to_string()), vector[2]);
    ts.return_to_sender(cap);
    test_scenario::return_shared(comp);
    ts.next_tx(@0xB);
    let comp = ts.take_shared<Composition<TestShare>>();
    assert_eq!(*cl::lyrics(&comp, lc::new(b"en".to_string())), vector[1]);
    assert_eq!(*cl::lyrics(&comp, lc::new(b"ja".to_string())), vector[2]);
    test_scenario::return_shared(comp);
    ts.next_tx(@0xA);
    let mut comp = ts.take_shared<Composition<TestShare>>();
    let cap = ts.take_from_sender<CompositionAdminCap<TestShare>>();
    cl::set_lyrics(&mut comp, &cap, lc::new(b"en".to_string()), vector[3]);
    cl::clear_lyrics(&mut comp, &cap, lc::new(b"ja".to_string()));
    ts.return_to_sender(cap);
    test_scenario::return_shared(comp);
    ts.next_tx(@0xB);
    let comp = ts.take_shared<Composition<TestShare>>();
    assert_eq!(*cl::lyrics(&comp, lc::new(b"en".to_string())), vector[3]);
    assert!(!cl::has_lyrics(&comp, lc::new(b"ja".to_string())));
    test_scenario::return_shared(comp);
    ts.end();
}

#[test]
fun compositions_have_separate_lyrics_and_identified_events() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = new_composition(ctx);
    let (mut other, other_cap) = new_composition(ctx);
    let en = lc::new(b"en".to_string());
    cl::set_lyrics(&mut comp, &cap, en, vector[1]);
    cl::set_lyrics(&mut other, &other_cap, en, vector[2]);
    let events = event::events_by_type<cl::CompositionLyricsSetEvent>();
    assert_eq!(events.length(), 2);
    let (first_id, _, first_lyrics) = cl::composition_lyrics_set_fields_for_testing(&events[0]);
    assert_eq!(first_id, object::id(&comp));
    assert_eq!(first_lyrics, vector[1]);
    let (second_id, _, second_lyrics) = cl::composition_lyrics_set_fields_for_testing(&events[1]);
    assert_eq!(second_id, object::id(&other));
    assert_eq!(second_lyrics, vector[2]);
    cl::clear_lyrics(&mut comp, &cap, en);
    assert_eq!(*cl::lyrics(&other, en), vector[2]);
    destroy(comp);
    destroy(cap);
    destroy(other);
    destroy(other_cap);
}
