// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module party_cta::party_cta_tests;

use miso_party::party;
use party_cta::party_cta as cta;
use std::unit_test::{assert_eq, destroy};
use sui::{event, test_scenario as ts};

const OWNER: address = @0xA;

fun new_party(ctx: &mut TxContext): (party::Party, party::PartyAdminCap) {
    party::new(ctx)
}

#[test]
fun set_read_replace_clear() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let party_id = object::id(&p);
    assert!(!cta::has_ctas(&p));
    cta::set_ctas(
        &mut p,
        &cap,
        vector[
            cta::new(b"Tickets".to_string(), b"https://dice.fm/artist".to_string()),
            cta::new(b"Merch".to_string(), b"https://shop.example/artist".to_string()),
        ],
    );
    let set_events = event::events_by_type<cta::PartyCtasSetEvent>();
    assert_eq!(set_events.length(), 1);
    let (event_party_id, labels, urls) = cta::party_ctas_set_fields_for_testing(&set_events[0]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(labels, vector[b"Tickets".to_string(), b"Merch".to_string()]);
    assert_eq!(
        urls,
        vector[b"https://dice.fm/artist".to_string(), b"https://shop.example/artist".to_string()],
    );
    assert!(cta::has_ctas(&p));
    let list = cta::ctas(&p);
    assert_eq!(list.length(), 2);
    assert_eq!(list[0].label(), b"Tickets".to_string());
    assert_eq!(list[0].url(), b"https://dice.fm/artist".to_string());
    assert_eq!(list[1].label(), b"Merch".to_string());
    cta::set_ctas(
        &mut p,
        &cap,
        vector[cta::new(b"Newsletter".to_string(), b"https://substack.com/artist".to_string())],
    );
    let set_events = event::events_by_type<cta::PartyCtasSetEvent>();
    assert_eq!(set_events.length(), 2);
    let (event_party_id, labels, urls) = cta::party_ctas_set_fields_for_testing(&set_events[1]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(labels, vector[b"Newsletter".to_string()]);
    assert_eq!(urls, vector[b"https://substack.com/artist".to_string()]);
    assert_eq!(cta::ctas(&p).length(), 1);
    assert_eq!(cta::ctas(&p)[0].label(), b"Newsletter".to_string());
    cta::clear_ctas(&mut p, &cap);
    let cleared_events = event::events_by_type<cta::PartyCtasClearedEvent>();
    assert_eq!(cleared_events.length(), 1);
    assert_eq!(cta::party_ctas_cleared_fields_for_testing(&cleared_events[0]), party_id);
    assert!(!cta::has_ctas(&p));
    cta::clear_ctas(&mut p, &cap);
    assert_eq!(event::events_by_type<cta::PartyCtasClearedEvent>().length(), 1);
    destroy(p);
    destroy(cap);
}

#[test]
fun shared_party_cta_workflow() {
    let mut scenario = ts::begin(OWNER);
    let (p, cap) = new_party(scenario.ctx());
    p.share();
    transfer::public_transfer(cap, OWNER);
    scenario.next_tx(OWNER);
    let mut p = scenario.take_shared<party::Party>();
    let cap = scenario.take_from_sender<party::PartyAdminCap>();
    cta::set_ctas(
        &mut p,
        &cap,
        vector[cta::new(b"Tickets".to_string(), b"https://tickets.example".to_string())],
    );
    ts::return_shared(p);
    scenario.return_to_sender(cap);
    scenario.next_tx(@0xB);
    let p = scenario.take_shared<party::Party>();
    assert_eq!(cta::ctas(&p)[0].label(), b"Tickets".to_string());
    ts::return_shared(p);
    scenario.end();
}

#[test]
fun stored_empty_and_identical_replacement_preserve_event_semantics() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let party_id = object::id(&p);
    cta::set_ctas(&mut p, &cap, vector[]);
    assert!(cta::has_ctas(&p));
    let set_events = event::events_by_type<cta::PartyCtasSetEvent>();
    assert_eq!(set_events.length(), 1);
    let (event_party_id, labels, urls) = cta::party_ctas_set_fields_for_testing(&set_events[0]);
    assert_eq!(event_party_id, party_id);
    assert!(labels.is_empty());
    assert!(urls.is_empty());
    assert_eq!(std::bcs::to_bytes(&set_events[0]).length(), 34);
    cta::set_ctas(&mut p, &cap, vector[]);
    let set_events = event::events_by_type<cta::PartyCtasSetEvent>();
    assert_eq!(set_events.length(), 1);
    assert!(cta::has_ctas(&p));
    cta::clear_ctas(&mut p, &cap);
    assert!(!cta::has_ctas(&p));
    let cleared_events = event::events_by_type<cta::PartyCtasClearedEvent>();
    assert_eq!(cleared_events.length(), 1);
    assert_eq!(cta::party_ctas_cleared_fields_for_testing(&cleared_events[0]), party_id);
    cta::clear_ctas(&mut p, &cap);
    assert_eq!(event::events_by_type<cta::PartyCtasClearedEvent>().length(), 1);
    destroy(p);
    destroy(cap);
}

#[test]
fun storage_preserves_order_duplicates_and_multibyte_values() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let party_id = object::id(&p);
    let first_label = vector[0xC3u8, 0xA9u8].to_string();
    let first_url = vector[
        0x68u8,
        0x74u8,
        0x74u8,
        0x70u8,
        0x73u8,
        0x3Au8,
        0x2Fu8,
        0x2Fu8,
        0xE2u8,
        0x98u8,
        0x83u8,
    ].to_string();
    let duplicate_label = first_label;
    let duplicate_url = first_url;
    cta::set_ctas(
        &mut p,
        &cap,
        vector[
            cta::new(first_label, first_url),
            cta::new(duplicate_label, duplicate_url),
            cta::new(b"Last".to_string(), b"https://last.example".to_string()),
        ],
    );
    let set_events = event::events_by_type<cta::PartyCtasSetEvent>();
    assert_eq!(set_events.length(), 1);
    let (event_party_id, labels, urls) = cta::party_ctas_set_fields_for_testing(&set_events[0]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(labels, vector[first_label, duplicate_label, b"Last".to_string()]);
    assert_eq!(urls, vector[first_url, duplicate_url, b"https://last.example".to_string()]);
    let list = cta::ctas(&p);
    assert_eq!(list.length(), 3);
    assert_eq!(list[0].label(), vector[0xC3u8, 0xA9u8].to_string());
    assert_eq!(list[1].label(), vector[0xC3u8, 0xA9u8].to_string());
    assert_eq!(list[2].url(), b"https://last.example".to_string());
    destroy(p);
    destroy(cap);
}

fun max_ctas(): vector<cta::Cta> {
    vector::tabulate!(
        20,
        |_| cta::new(
            vector::tabulate!(60, |_| 0x61u8).to_string(),
            vector::tabulate!(2000, |_| 0x62u8).to_string(),
        ),
    )
}

#[test]
fun maximum_content_is_emitted_in_full() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let party_id = object::id(&p);
    cta::set_ctas(&mut p, &cap, max_ctas());
    let set_events = event::events_by_type<cta::PartyCtasSetEvent>();
    assert_eq!(set_events.length(), 1);
    let (event_party_id, labels, urls) = cta::party_ctas_set_fields_for_testing(&set_events[0]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(labels, vector::tabulate!(20, |_| vector::tabulate!(60, |_| 0x61u8).to_string()));
    assert_eq!(urls, vector::tabulate!(20, |_| vector::tabulate!(2000, |_| 0x62u8).to_string()));
    assert_eq!(std::bcs::to_bytes(&set_events[0]).length(), 41294);
    cta::set_ctas(&mut p, &cap, max_ctas());
    let set_events = event::events_by_type<cta::PartyCtasSetEvent>();
    assert_eq!(set_events.length(), 1);
    cta::clear_ctas(&mut p, &cap);
    let cleared_events = event::events_by_type<cta::PartyCtasClearedEvent>();
    assert_eq!(cleared_events.length(), 1);
    assert_eq!(cta::party_ctas_cleared_fields_for_testing(&cleared_events[0]), party_id);
    assert_eq!(std::bcs::to_bytes(&cleared_events[0]).length(), 32);
    destroy(p);
    destroy(cap);
}

#[test]
fun equal_cta_list_is_silent_but_component_change_emits() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    cta::set_ctas(
        &mut p,
        &cap,
        vector[cta::new(b"Listen".to_string(), b"https://one.example".to_string())],
    );
    cta::set_ctas(
        &mut p,
        &cap,
        vector[cta::new(b"Listen".to_string(), b"https://one.example".to_string())],
    );
    assert_eq!(event::events_by_type<cta::PartyCtasSetEvent>().length(), 1);
    cta::set_ctas(
        &mut p,
        &cap,
        vector[cta::new(b"Listen".to_string(), b"https://two.example".to_string())],
    );
    let set_events = event::events_by_type<cta::PartyCtasSetEvent>();
    assert_eq!(set_events.length(), 2);
    let (_, labels, urls) = cta::party_ctas_set_fields_for_testing(&set_events[1]);
    assert_eq!(labels, vector[b"Listen".to_string()]);
    assert_eq!(urls, vector[b"https://two.example".to_string()]);
    assert_eq!(cta::ctas(&p)[0].url(), b"https://two.example".to_string());
    destroy(p);
    destroy(cap);
}

#[test]
fun constructors_and_views_emit_no_events() {
    let before_set = event::events_by_type<cta::PartyCtasSetEvent>().length();
    let before_clear = event::events_by_type<cta::PartyCtasClearedEvent>().length();
    let value = cta::new(b"Label".to_string(), b"https://example.com".to_string());
    assert_eq!(value.label(), b"Label".to_string());
    assert_eq!(value.url(), b"https://example.com".to_string());
    let ctx = &mut tx_context::dummy();
    let (p, cap) = new_party(ctx);
    assert!(!cta::has_ctas(&p));
    assert_eq!(event::events_by_type<cta::PartyCtasSetEvent>().length(), before_set);
    assert_eq!(event::events_by_type<cta::PartyCtasClearedEvent>().length(), before_clear);
    destroy(p);
    destroy(cap);
}

#[test, expected_failure(abort_code = cta::EEmptyLabel)]
fun rejects_empty_label() {
    let _ = cta::new(b"".to_string(), b"https://x.com".to_string());
    abort
}

#[test, expected_failure(abort_code = cta::EEmptyUrl)]
fun rejects_empty_url() {
    let _ = cta::new(b"Listen".to_string(), b"".to_string());
    abort
}

#[test, expected_failure(abort_code = cta::ELabelTooLong)]
fun rejects_overlong_label() {
    let label = vector::tabulate!(61, |_| 97u8).to_string();
    let _ = cta::new(label, b"https://x.com".to_string());
    abort
}

#[test, expected_failure(abort_code = cta::EUrlTooLong)]
fun rejects_overlong_url() {
    let url = vector::tabulate!(2001, |_| 97u8).to_string();
    let _ = cta::new(b"Listen".to_string(), url);
    abort
}

#[test, expected_failure(abort_code = cta::ETooManyCtas)]
fun rejects_over_max() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let mut list = vector[];
    21u64.do!(|_| list.push_back(cta::new(b"L".to_string(), b"https://x.com".to_string())));
    cta::set_ctas(&mut p, &cap, list);
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun set_ctas_with_wrong_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, _cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    cta::set_ctas(
        &mut p,
        &other_cap,
        vector[cta::new(b"Tickets".to_string(), b"https://dice.fm/artist".to_string())],
    );
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun set_ctas_replace_with_wrong_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    cta::set_ctas(
        &mut p,
        &cap,
        vector[cta::new(b"Initial".to_string(), b"https://initial.example".to_string())],
    );
    cta::set_ctas(
        &mut p,
        &other_cap,
        vector[cta::new(b"Replacement".to_string(), b"https://replacement.example".to_string())],
    );
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun set_ctas_equal_with_wrong_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    cta::set_ctas(
        &mut p,
        &cap,
        vector[cta::new(b"Initial".to_string(), b"https://initial.example".to_string())],
    );
    cta::set_ctas(
        &mut p,
        &other_cap,
        vector[cta::new(b"Initial".to_string(), b"https://initial.example".to_string())],
    );
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun clear_ctas_with_wrong_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    cta::set_ctas(
        &mut p,
        &cap,
        vector[cta::new(b"Initial".to_string(), b"https://initial.example".to_string())],
    );
    cta::clear_ctas(&mut p, &other_cap);
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun clear_absent_ctas_with_wrong_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, _cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    cta::clear_ctas(&mut p, &other_cap);
    abort
}

#[test, expected_failure(abort_code = cta::ETooManyCtas)]
fun over_max_precedes_wrong_cap_authorization() {
    let ctx = &mut tx_context::dummy();
    let (mut p, _cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    let mut list = vector[];
    21u64.do!(
        |_| list.push_back(
            cta::new(
                b"L".to_string(),
                b"https://x.com".to_string(),
            ),
        ),
    );
    cta::set_ctas(&mut p, &other_cap, list);
    abort
}

#[test, expected_failure(abort_code = cta::ENoCtas)]
fun reading_ctas_without_ctas_aborts() {
    let ctx = &mut tx_context::dummy();
    let (p, cap) = new_party(ctx);
    cta::ctas(&p);
    destroy(p);
    destroy(cap);
}
