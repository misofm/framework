// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module party_tags::party_tags_tests;

use miso_party::party;
use party_tags::party_tags as tags;
use std::unit_test::{assert_eq, destroy};
use sui::{bcs, event, test_scenario as ts};

const OWNER: address = @0xA;

fun new_party(ctx: &mut TxContext): (party::Party, party::PartyAdminCap) {
    party::new(ctx)
}

fun bytes_of_len(len: u64, seed: u8): vector<u8> {
    let mut bytes = vector[];
    if (len > 0) {
        bytes.push_back(seed);
        (len - 1).do!(|_| bytes.push_back(65));
    };
    bytes
}

#[test]
fun add_remove_and_query() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    assert!(!tags::has_tags(&p));
    tags::add_tag(&mut p, &cap, b"ambient".to_string());
    tags::add_tag(&mut p, &cap, b"deconstructed club".to_string());
    assert!(tags::has_tags(&p));
    assert!(tags::has_tag(&p, b"ambient".to_string()));
    assert!(!tags::has_tag(&p, b"techno".to_string()));
    assert_eq!(tags::tags(&p).length(), 2);
    tags::remove_tag(&mut p, &cap, b"ambient".to_string());
    assert!(!tags::has_tag(&p, b"ambient".to_string()));
    assert_eq!(tags::tags(&p).length(), 1);
    tags::remove_tag(&mut p, &cap, b"deconstructed club".to_string());
    assert!(!tags::has_tags(&p));
    tags::add_tag(&mut p, &cap, b"leftfield pop".to_string());
    tags::clear_tags(&mut p, &cap);
    assert!(!tags::has_tags(&p));
    tags::clear_tags(&mut p, &cap);
    destroy(p);
    destroy(cap);
}

#[test]
fun shared_party_tags_workflow() {
    let mut scenario = ts::begin(OWNER);
    let (p, cap) = new_party(scenario.ctx());
    party::share(p, &cap);
    transfer::public_transfer(cap, OWNER);
    scenario.next_tx(OWNER);
    let mut p = scenario.take_shared<party::Party>();
    let cap = scenario.take_from_sender<party::PartyAdminCap>();
    tags::add_tag(&mut p, &cap, b"ambient".to_string());
    ts::return_shared(p);
    scenario.return_to_sender(cap);
    scenario.next_tx(@0xB);
    let p = scenario.take_shared<party::Party>();
    assert!(tags::has_tag(&p, b"ambient".to_string()));
    ts::return_shared(p);
    scenario.end();
}

#[test, expected_failure(abort_code = tags::EEmptyTag)]
fun rejects_empty() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    tags::add_tag(&mut p, &cap, b"".to_string());
    abort
}

#[test, expected_failure(abort_code = tags::ETagTooLong)]
fun rejects_overlong_tag() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let tag = vector::tabulate!(51, |_| 97u8).to_string();
    tags::add_tag(&mut p, &cap, tag);
    abort
}

#[test, expected_failure(abort_code = typed_set::typed_set::EDuplicateItem)]
fun rejects_duplicate() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    tags::add_tag(&mut p, &cap, b"ambient".to_string());
    tags::add_tag(&mut p, &cap, b"ambient".to_string());
    abort
}

#[test, expected_failure(abort_code = typed_set::typed_set::EItemNotPresent)]
fun remove_absent_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    tags::add_tag(&mut p, &cap, b"ambient".to_string());
    tags::remove_tag(&mut p, &cap, b"techno".to_string());
    abort
}

#[test, expected_failure(abort_code = typed_set::typed_set::EMaxItemsExceeded)]
fun rejects_over_max() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    31u64.do!(|i| {
        let tag = std::string::utf8(vector[b"t"[0], ((65 + i) as u8)]);
        tags::add_tag(&mut p, &cap, tag);
    });
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun add_tag_with_wrong_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, _cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    tags::add_tag(&mut p, &other_cap, b"ambient".to_string());
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun add_tag_with_wrong_cap_on_full_set_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    30u64.do!(|i| {
        let tag = std::string::utf8(vector[b"t"[0], ((65 + i) as u8)]);
        tags::add_tag(&mut p, &cap, tag);
    });
    tags::add_tag(&mut p, &other_cap, b"ambient".to_string());
    abort
}

#[test]
fun mutation_events_carry_tags_and_final_reclaim_without_clear_event() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let party_id = object::id(&p);
    tags::add_tag(&mut p, &cap, b"ambient".to_string());
    tags::add_tag(&mut p, &cap, b"deconstructed club".to_string());
    tags::remove_tag(&mut p, &cap, b"ambient".to_string());
    tags::remove_tag(&mut p, &cap, b"deconstructed club".to_string());
    let added = event::events_by_type<tags::TagAddedEvent>();
    assert_eq!(added.length(), 2);
    let (event_party_id, tag) = tags::added_event_fields(&added[0]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(tag, b"ambient".to_string());
    let (event_party_id, tag) = tags::added_event_fields(&added[1]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(tag, b"deconstructed club".to_string());
    let removed = event::events_by_type<tags::TagRemovedEvent>();
    assert_eq!(removed.length(), 2);
    let (event_party_id, tag) = tags::removed_event_fields(&removed[0]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(tag, b"ambient".to_string());
    let (event_party_id, tag) = tags::removed_event_fields(&removed[1]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(tag, b"deconstructed club".to_string());
    assert!(!tags::has_tags(&p));
    assert_eq!(event::events_by_type<tags::TagsClearedEvent>().length(), 0);
    destroy(p);
    destroy(cap);
}

#[test]
fun clear_event_reports_party_and_absent_repeat_is_silent() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let party_id = object::id(&p);
    tags::add_tag(&mut p, &cap, b"Ambient".to_string());
    tags::add_tag(&mut p, &cap, b" ambient ".to_string());
    tags::add_tag(&mut p, &cap, std::string::utf8(vector[99, 97, 102, 0xc3, 0xa9]));
    tags::clear_tags(&mut p, &cap);
    tags::clear_tags(&mut p, &cap);
    let cleared = event::events_by_type<tags::TagsClearedEvent>();
    assert_eq!(cleared.length(), 1);
    assert_eq!(tags::cleared_event_fields(&cleared[0]), party_id);
    assert!(!tags::has_tags(&p));
    destroy(p);
    destroy(cap);
}

#[test]
fun thirty_max_length_tags_have_expected_event_bcs_sizes() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let mut expected_tags = vector[];
    30u64.do!(|i| {
        let bytes = bytes_of_len(50, (65 + i) as u8);
        expected_tags.push_back(bytes);
        tags::add_tag(&mut p, &cap, bytes.to_string());
    });
    let added = event::events_by_type<tags::TagAddedEvent>();
    assert_eq!(added.length(), 30);
    30u64.do!(|i| {
        assert_eq!(bcs::to_bytes(&added[i]).length(), 83);
        let (_, tag) = tags::added_event_fields(&added[i]);
        assert_eq!(tag, expected_tags[i].to_string());
    });
    tags::clear_tags(&mut p, &cap);
    let cleared = event::events_by_type<tags::TagsClearedEvent>();
    assert_eq!(cleared.length(), 1);
    assert_eq!(bcs::to_bytes(&cleared[0]).length(), 32);
    destroy(p);
    destroy(cap);
}

#[test]
fun views_are_silent_and_preserve_exact_utf8_whitespace_and_case() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let before = event::num_events();
    let utf8_tag = std::string::utf8(vector[99, 97, 102, 0xc3, 0xa9]);
    tags::add_tag(&mut p, &cap, b"Ambient".to_string());
    tags::add_tag(&mut p, &cap, b" ambient ".to_string());
    tags::add_tag(&mut p, &cap, utf8_tag);
    assert_eq!(event::num_events(), before + 3);
    let stored = tags::tags(&p);
    let cafe = vector[99, 97, 102, 0xc3, 0xa9].to_string();
    assert_eq!(stored, vector[b"Ambient".to_string(), b" ambient ".to_string(), cafe]);
    assert!(tags::has_tag(&p, b"Ambient".to_string()));
    assert!(tags::has_tag(&p, b" ambient ".to_string()));
    assert!(tags::has_tag(&p, std::string::utf8(vector[99, 97, 102, 0xc3, 0xa9])));
    assert!(!tags::has_tag(&p, b"ambient".to_string()));
    assert_eq!(event::num_events(), before + 3);
    destroy(p);
    destroy(cap);
}

#[test]
fun transferred_cap_can_add_tag() {
    let mut scenario = ts::begin(OWNER);
    let (p, cap) = new_party(scenario.ctx());
    let party_id = object::id(&p);
    party::share(p, &cap);
    transfer::public_transfer(cap, OWNER);
    scenario.next_tx(OWNER);
    let mut p = scenario.take_shared<party::Party>();
    let cap = scenario.take_from_sender<party::PartyAdminCap>();
    tags::add_tag(&mut p, &cap, b"transferred".to_string());
    let added = event::events_by_type<tags::TagAddedEvent>();
    assert_eq!(added.length(), 1);
    let (event_party_id, tag) = tags::added_event_fields(&added[0]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(tag, b"transferred".to_string());
    ts::return_shared(p);
    scenario.return_to_sender(cap);
    scenario.end();
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun remove_with_wrong_cap_and_present_tag_aborts_as_unauthorized() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    tags::add_tag(&mut p, &cap, b"ambient".to_string());
    tags::remove_tag(&mut p, &other_cap, b"ambient".to_string());
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun remove_with_wrong_cap_and_missing_tag_aborts_as_unauthorized() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    tags::add_tag(&mut p, &cap, b"ambient".to_string());
    tags::remove_tag(&mut p, &other_cap, b"techno".to_string());
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun remove_with_wrong_cap_and_missing_field_aborts_as_unauthorized() {
    let ctx = &mut tx_context::dummy();
    let (mut p, _cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    tags::remove_tag(&mut p, &other_cap, b"ambient".to_string());
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun clear_with_wrong_cap_and_present_set_aborts_as_unauthorized() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    tags::add_tag(&mut p, &cap, b"ambient".to_string());
    tags::clear_tags(&mut p, &other_cap);
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun clear_with_wrong_cap_and_absent_set_aborts_as_unauthorized() {
    let ctx = &mut tx_context::dummy();
    let (mut p, _cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    tags::clear_tags(&mut p, &other_cap);
    abort
}

#[test, expected_failure(abort_code = tags::EEmptyTag)]
fun empty_tag_with_wrong_cap_aborts_as_empty() {
    let ctx = &mut tx_context::dummy();
    let (mut p, _cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    tags::add_tag(&mut p, &other_cap, b"".to_string());
    abort
}

#[test, expected_failure(abort_code = tags::ETagTooLong)]
fun overlong_tag_with_wrong_cap_aborts_as_too_long() {
    let ctx = &mut tx_context::dummy();
    let (mut p, _cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    tags::add_tag(&mut p, &other_cap, bytes_of_len(51, 65).to_string());
    abort
}

#[test, expected_failure(abort_code = typed_set::typed_set::EDuplicateItem)]
fun authorized_duplicate_on_full_set_aborts_as_duplicate() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    30u64.do!(|i| tags::add_tag(&mut p, &cap, bytes_of_len(1, (65 + i) as u8).to_string()));
    tags::add_tag(&mut p, &cap, b"A".to_string());
    abort
}

#[test, expected_failure(abort_code = typed_set::typed_set::EItemNotPresent)]
fun remove_from_missing_field_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    tags::remove_tag(&mut p, &cap, b"ambient".to_string());
    abort
}

#[test, expected_failure(abort_code = tags::ENoTags)]
fun reading_tags_without_tags_aborts() {
    let ctx = &mut tx_context::dummy();
    let (p, cap) = new_party(ctx);
    tags::tags(&p);
    destroy(p);
    destroy(cap);
}
