// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module composition_title::composition_title_tests;

use composition_title::composition_title as ct;
use miso_music::composition::{Self, Composition, CompositionAdminCap};
use std::{string::String, unit_test::{assert_eq, destroy}};
use sui::{bcs::to_bytes, dynamic_field as df, event};

public struct TestShare() has drop;

fun mk_composition(ctx: &mut TxContext): (Composition<TestShare>, CompositionAdminCap<TestShare>) {
    composition::new_for_testing<TestShare>(ctx)
}

fun title_of_length(length: u64): String {
    vector::tabulate!(length, |_| 65u8).to_string()
}

#[test]
fun set_read_replace_clear_lifecycle() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = mk_composition(ctx);
    assert!(!ct::has_title(&comp));
    ct::set_title(&mut comp, &cap, b"Blue in Green".to_string());
    assert!(ct::has_title(&comp));
    assert_eq!(*ct::title(&comp), b"Blue in Green".to_string());
    ct::set_title(&mut comp, &cap, b"Blue In Green".to_string());
    assert_eq!(*ct::title(&comp), b"Blue In Green".to_string());
    ct::clear_title(&mut comp, &cap);
    assert!(!ct::has_title(&comp));
    ct::clear_title(&mut comp, &cap);
    assert!(!ct::has_title(&comp));
    ct::set_title(&mut comp, &cap, b"Flamenco Sketches".to_string());
    assert_eq!(*ct::title(&comp), b"Flamenco Sketches".to_string());
    destroy(comp);
    destroy(cap);
}

public struct UnrelatedKey() has copy, drop, store;

#[test]
fun unrelated_dynamic_field_survives_title_lifecycle() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = mk_composition(ctx);
    df::add(comp.uid_mut(&cap), UnrelatedKey(), 77u64);
    ct::set_title(&mut comp, &cap, b"Blue in Green".to_string());
    assert_eq!(*df::borrow(comp.uid(), UnrelatedKey()), 77u64);
    ct::clear_title(&mut comp, &cap);
    assert_eq!(*df::borrow(comp.uid(), UnrelatedKey()), 77u64);
    let _: u64 = df::remove(comp.uid_mut(&cap), UnrelatedKey());
    destroy(comp);
    destroy(cap);
}

#[test]
fun title_is_preserved_verbatim() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = mk_composition(ctx);
    let text = b"  sO whAt  (take 2) ".to_string();
    ct::set_title(&mut comp, &cap, text);
    assert_eq!(*ct::title(&comp), text);
    destroy(comp);
    destroy(cap);
}

#[test]
fun exactly_max_length_is_accepted() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = mk_composition(ctx);
    let text = title_of_length(300);
    ct::set_title(&mut comp, &cap, text);
    assert_eq!(ct::title(&comp).as_bytes().length(), 300);
    destroy(comp);
    destroy(cap);
}

#[test]
fun multibyte_text_is_bounded_by_bytes() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = mk_composition(ctx);
    let text = b"\xc3\xa9t\xc3\xa9 \xe2\x9c\xbf".to_string();
    assert_eq!(text.as_bytes().length(), 9);
    ct::set_title(&mut comp, &cap, text);
    assert_eq!(*ct::title(&comp), text);
    let ok = vector::tabulate!(100, |_| b"\xe2\x9c\xbf").flatten().to_string();
    assert_eq!(ok.as_bytes().length(), 300);
    ct::set_title(&mut comp, &cap, ok);
    assert_eq!(*ct::title(&comp), ok);
    destroy(comp);
    destroy(cap);
}

#[test, expected_failure(abort_code = ct::ETitleTooLong)]
fun multibyte_text_over_the_byte_bound_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = mk_composition(ctx);
    let over = vector::tabulate!(101, |_| b"\xe2\x9c\xbf").flatten().to_string();
    ct::set_title(&mut comp, &cap, over);
    destroy(comp);
    destroy(cap);
}

#[test]
fun titles_are_per_composition() {
    let ctx = &mut tx_context::dummy();
    let (mut a, a_cap) = mk_composition(ctx);
    let (mut b, b_cap) = mk_composition(ctx);
    let a_id = object::id(&a);
    let b_id = object::id(&b);
    ct::set_title(&mut a, &a_cap, b"First".to_string());
    assert!(ct::has_title(&a));
    assert!(!ct::has_title(&b));
    ct::set_title(&mut b, &b_cap, b"Second".to_string());
    ct::clear_title(&mut a, &a_cap);
    assert!(!ct::has_title(&a));
    assert_eq!(*ct::title(&b), b"Second".to_string());
    let sets = event::events_by_type<ct::CompositionTitleSetEvent>();
    assert_eq!(sets.length(), 2);
    let (id, title) = ct::composition_title_set_fields(&sets[0]);
    assert_eq!(id, a_id);
    assert_eq!(title, b"First".to_string());
    let (id, title) = ct::composition_title_set_fields(&sets[1]);
    assert_eq!(id, b_id);
    assert_eq!(title, b"Second".to_string());
    let clears = event::events_by_type<ct::CompositionTitleClearedEvent>();
    assert_eq!(clears.length(), 1);
    assert_eq!(ct::composition_title_cleared_fields(&clears[0]), a_id);
    destroy(a);
    destroy(a_cap);
    destroy(b);
    destroy(b_cap);
}

#[test]
fun compositions_have_separate_state_and_identified_events() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = mk_composition(ctx);
    let (mut other, other_cap) = mk_composition(ctx);
    let comp_id = object::id(&comp);
    let other_id = object::id(&other);
    ct::set_title(&mut comp, &cap, b"Ours".to_string());
    ct::set_title(&mut other, &other_cap, b"Theirs".to_string());
    let sets = event::events_by_type<ct::CompositionTitleSetEvent>();
    assert_eq!(sets.length(), 2);
    let (first_id, _) = ct::composition_title_set_fields(&sets[0]);
    assert_eq!(first_id, comp_id);
    let (second_id, _) = ct::composition_title_set_fields(&sets[1]);
    assert_eq!(second_id, other_id);
    ct::clear_title(&mut comp, &cap);
    assert_eq!(*ct::title(&other), b"Theirs".to_string());
    destroy(comp);
    destroy(cap);
    destroy(other);
    destroy(other_cap);
}

#[test]
fun set_emits_each_transition() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = mk_composition(ctx);
    let comp_id = object::id(&comp);
    ct::set_title(&mut comp, &cap, b"First draft".to_string());
    ct::set_title(&mut comp, &cap, b"Second draft".to_string());
    ct::set_title(&mut comp, &cap, b"Second draft".to_string());
    let events = event::events_by_type<ct::CompositionTitleSetEvent>();
    assert_eq!(events.length(), 2);
    assert_eq!(event::num_events(), 2);
    let (id, first) = ct::composition_title_set_fields(&events[0]);
    assert_eq!(id, comp_id);
    assert_eq!(first, b"First draft".to_string());
    let (id, second) = ct::composition_title_set_fields(&events[1]);
    assert_eq!(id, comp_id);
    assert_eq!(second, b"Second draft".to_string());
    assert_eq!(*ct::title(&comp), b"Second draft".to_string());
    destroy(comp);
    destroy(cap);
}

#[test]
fun first_set_is_never_a_no_op() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = mk_composition(ctx);
    ct::set_title(&mut comp, &cap, b"So What".to_string());
    ct::set_title(&mut comp, &cap, b"So What".to_string());
    assert_eq!(event::events_by_type<ct::CompositionTitleSetEvent>().length(), 1);
    ct::clear_title(&mut comp, &cap);
    ct::set_title(&mut comp, &cap, b"So What".to_string());
    assert_eq!(event::events_by_type<ct::CompositionTitleSetEvent>().length(), 2);
    destroy(comp);
    destroy(cap);
}

#[test]
fun clear_emits_only_when_something_was_removed() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = mk_composition(ctx);
    let comp_id = object::id(&comp);
    ct::clear_title(&mut comp, &cap);
    assert_eq!(event::num_events(), 0);
    ct::set_title(&mut comp, &cap, b"Working title".to_string());
    ct::clear_title(&mut comp, &cap);
    ct::clear_title(&mut comp, &cap);
    let events = event::events_by_type<ct::CompositionTitleClearedEvent>();
    assert_eq!(events.length(), 1);
    assert_eq!(ct::composition_title_cleared_fields(&events[0]), comp_id);
    assert_eq!(event::num_events(), 2);
    destroy(comp);
    destroy(cap);
}

#[test]
fun views_are_silent() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = mk_composition(ctx);
    assert!(!ct::has_title(&comp));
    assert_eq!(event::num_events(), 0);
    ct::set_title(&mut comp, &cap, b"No event from reading".to_string());
    assert!(ct::has_title(&comp));
    assert_eq!(*ct::title(&comp), b"No event from reading".to_string());
    assert_eq!(event::num_events(), 1);
    destroy(comp);
    destroy(cap);
}

#[test]
fun payloads_have_exact_bcs_sizes() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = mk_composition(ctx);
    ct::set_title(&mut comp, &cap, b"So What".to_string());
    let sets = event::events_by_type<ct::CompositionTitleSetEvent>();
    assert_eq!(to_bytes(&sets[0]).length(), 32 + 1 + 7);
    let max = title_of_length(300);
    ct::set_title(&mut comp, &cap, max);
    let mut different = b"B".to_string();
    different.append(title_of_length(299));
    ct::set_title(&mut comp, &cap, different);
    let sets = event::events_by_type<ct::CompositionTitleSetEvent>();
    assert_eq!(sets.length(), 3);
    let (_, title) = ct::composition_title_set_fields(&sets[1]);
    assert_eq!(title, max);
    let (_, title) = ct::composition_title_set_fields(&sets[2]);
    assert_eq!(title, different);
    assert_eq!(to_bytes(&sets[1]).length(), 334);
    assert_eq!(to_bytes(&sets[2]).length(), 334);
    ct::clear_title(&mut comp, &cap);
    let clears = event::events_by_type<ct::CompositionTitleClearedEvent>();
    assert_eq!(clears.length(), 1);
    assert_eq!(to_bytes(&clears[0]).length(), 32);
    destroy(comp);
    destroy(cap);
}

#[test]
fun events_preserve_whitespace_case_and_utf8() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = mk_composition(ctx);
    let first = b"  MiXeD  spacing  ".to_string();
    let second = b"\xc3\xa9t\xc3\xa9 \xe2\x9c\xbf".to_string();
    ct::set_title(&mut comp, &cap, first);
    ct::set_title(&mut comp, &cap, second);
    let sets = event::events_by_type<ct::CompositionTitleSetEvent>();
    let (_, after_first) = ct::composition_title_set_fields(&sets[0]);
    let (_, after_second) = ct::composition_title_set_fields(&sets[1]);
    assert_eq!(*after_first.as_bytes(), b"  MiXeD  spacing  ");
    assert_eq!(*after_second.as_bytes(), *second.as_bytes());
    destroy(comp);
    destroy(cap);
}

#[test, expected_failure(abort_code = ct::ENoTitle)]
fun title_aborts_when_unset() {
    let ctx = &mut tx_context::dummy();
    let (comp, cap) = mk_composition(ctx);
    let _ = ct::title(&comp);
    destroy(comp);
    destroy(cap);
}

#[test, expected_failure(abort_code = ct::ENoTitle)]
fun cleared_title_aborts_on_read() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = mk_composition(ctx);
    ct::set_title(&mut comp, &cap, b"Gone soon".to_string());
    ct::clear_title(&mut comp, &cap);
    let _ = ct::title(&comp);
    destroy(comp);
    destroy(cap);
}

#[test, expected_failure(abort_code = ct::EEmptyTitle)]
fun empty_title_aborts_on_add() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = mk_composition(ctx);
    ct::set_title(&mut comp, &cap, b"".to_string());
    destroy(comp);
    destroy(cap);
}

#[test, expected_failure(abort_code = ct::EEmptyTitle)]
fun empty_title_aborts_on_replace() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = mk_composition(ctx);
    ct::set_title(&mut comp, &cap, b"Short".to_string());
    ct::set_title(&mut comp, &cap, b"".to_string());
    destroy(comp);
    destroy(cap);
}

#[test, expected_failure(abort_code = ct::ETitleTooLong)]
fun over_max_length_aborts_on_add() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = mk_composition(ctx);
    ct::set_title(&mut comp, &cap, title_of_length(301));
    destroy(comp);
    destroy(cap);
}

#[test, expected_failure(abort_code = ct::ETitleTooLong)]
fun over_max_length_aborts_on_replace() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = mk_composition(ctx);
    ct::set_title(&mut comp, &cap, b"Short".to_string());
    ct::set_title(&mut comp, &cap, title_of_length(301));
    destroy(comp);
    destroy(cap);
}
