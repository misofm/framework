// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module composition_credits::credits_tests;

use composition_credits::{
    composition_credits as credits,
    composition_party_role::{Self as cpr, CompositionPartyRole}
};
use credit::credit::{Self, Credit};
use miso_music::{composition::{Self, Composition, CompositionAdminCap}, test_helpers};
use miso_party::party::{Self, Party, PartyAdminCap};
use std::{string::String, unit_test::{assert_eq, destroy}};
use sui::{bcs::to_bytes, event::events_by_type, test_scenario};

const ARTIST: address = @0xA1;
const MAX_CREDITS: u64 = 50;

public struct TestShare() has drop;

fun new_composition(ctx: &mut TxContext): (Composition<TestShare>, CompositionAdminCap<TestShare>) {
    composition::new_for_testing<TestShare>(ctx)
}

fun composer(name: vector<u8>): Credit<CompositionPartyRole> {
    credit::new(name.to_string(), vector[cpr::new_composer_role()])
}

fun long_string(len: u64): String {
    let mut bytes = vector[];
    len.do!(|_| bytes.push_back(65));
    bytes.to_string()
}

fun fill_to_capacity(
    comp: &mut Composition<TestShare>,
    cap: &CompositionAdminCap<TestShare>,
    ctx: &mut TxContext,
): (Party, PartyAdminCap) {
    let (first, first_cap) = party::new(ctx);
    credits::add_credit(comp, cap, &first, composer(b"P"));
    (MAX_CREDITS - 1).do!(|_| {
        let (p, pc) = party::new(ctx);
        credits::add_credit(comp, cap, &p, composer(b"P"));
        destroy(p);
        destroy(pc);
    });
    assert_eq!(credits::credits(comp).length(), MAX_CREDITS);
    (first, first_cap)
}

#[test]
fun add_credit_attaches_and_reads_back() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut comp, cap) = new_composition(ts.ctx());
    assert!(!credits::has_credits(&comp));
    let (p1, p1c) = party::new(ts.ctx());
    let alice = composer(b"Alice");
    credits::add_credit(&mut comp, &cap, &p1, alice);
    assert!(credits::has_credits(&comp));
    assert_eq!(credits::credits(&comp).length(), 1);
    assert_eq!(credits::credits(&comp)[&object::id(&p1)], alice);
    let added = events_by_type<credits::CompositionCreditAddedEvent>();
    assert_eq!(added.length(), 1);
    let (
        _,
        first_party,
        first_name,
        first_roles,
    ) = credits::composition_credit_added_fields_for_testing(
        &added[0],
    );
    assert_eq!(first_party, object::id(&p1));
    assert_eq!(first_name, b"Alice".to_string());
    assert_eq!(first_roles, vector[cpr::new_composer_role()]);
    let (p2, p2c) = party::new(ts.ctx());
    let bob = credit::new(b"Bob".to_string(), vector[cpr::new_lyricist_role()]);
    credits::add_credit(&mut comp, &cap, &p2, bob);
    assert_eq!(credits::credits(&comp).length(), 2);
    let added = events_by_type<credits::CompositionCreditAddedEvent>();
    assert_eq!(added.length(), 2);
    let (
        _,
        second_party,
        second_name,
        second_roles,
    ) = credits::composition_credit_added_fields_for_testing(
        &added[1],
    );
    assert_eq!(second_party, object::id(&p2));
    assert_eq!(second_name, b"Bob".to_string());
    assert_eq!(second_roles, vector[cpr::new_lyricist_role()]);
    destroy(comp);
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
    let (mut comp, cap) = new_composition(ts.ctx());
    let (p, _pc) = party::new(ts.ctx());
    credits::add_credit(&mut comp, &cap, &p, composer(b"Alice"));
    credits::add_credit(
        &mut comp,
        &cap,
        &p,
        credit::new(b"Alice".to_string(), vector[cpr::new_lyricist_role()]),
    );
    abort
}

#[test, expected_failure(abort_code = credits::EPartyAlreadyCredited)]
fun add_credit_rejects_identical_credit() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut comp, cap) = new_composition(ts.ctx());
    let (p, _pc) = party::new(ts.ctx());
    let alice = composer(b"Alice");
    credits::add_credit(&mut comp, &cap, &p, alice);
    credits::add_credit(&mut comp, &cap, &p, alice);
    abort
}

#[test]
fun remove_credit_round_trip() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut comp, cap) = new_composition(ts.ctx());
    let (p1, p1c) = party::new(ts.ctx());
    let (p2, p2c) = party::new(ts.ctx());
    let (p3, p3c) = party::new(ts.ctx());
    credits::add_credit(&mut comp, &cap, &p1, composer(b"Alice"));
    credits::add_credit(&mut comp, &cap, &p2, composer(b"Bob"));
    credits::add_credit(&mut comp, &cap, &p3, composer(b"Cara"));
    assert_eq!(credits::credits(&comp).length(), 3);
    credits::remove_credit(&mut comp, &cap, object::id(&p2));
    assert_eq!(credits::credits(&comp).length(), 2);
    assert_eq!(credits::credits(&comp).get_idx(&object::id(&p1)), 0);
    assert_eq!(credits::credits(&comp).get_idx(&object::id(&p3)), 1);
    let removed = events_by_type<credits::CompositionCreditRemovedEvent>();
    assert_eq!(removed.length(), 1);
    let (_, event_party) = credits::composition_credit_removed_fields_for_testing(&removed[0]);
    assert_eq!(event_party, object::id(&p2));
    credits::remove_credit(&mut comp, &cap, object::id(&p1));
    assert!(credits::has_credits(&comp));
    credits::remove_credit(&mut comp, &cap, object::id(&p3));
    assert!(!credits::has_credits(&comp));
    let removed = events_by_type<credits::CompositionCreditRemovedEvent>();
    assert_eq!(removed.length(), 3);
    let (_, event_party) = credits::composition_credit_removed_fields_for_testing(&removed[1]);
    assert_eq!(event_party, object::id(&p1));
    let (_, event_party) = credits::composition_credit_removed_fields_for_testing(&removed[2]);
    assert_eq!(event_party, object::id(&p3));
    let bob_again = credit::new(b"Bob Again".to_string(), vector[cpr::new_translator_role()]);
    credits::add_credit(&mut comp, &cap, &p2, bob_again);
    assert!(credits::has_credits(&comp));
    assert_eq!(credits::credits(&comp).length(), 1);
    assert_eq!(credits::credits(&comp).get_idx(&object::id(&p2)), 0);
    let added = events_by_type<credits::CompositionCreditAddedEvent>();
    assert_eq!(added.length(), 4);
    let (
        _,
        event_party,
        event_name,
        event_roles,
    ) = credits::composition_credit_added_fields_for_testing(
        &added[3],
    );
    assert_eq!(event_party, object::id(&p2));
    assert_eq!(event_name, b"Bob Again".to_string());
    assert_eq!(event_roles, vector[cpr::new_translator_role()]);
    destroy(comp);
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
fun add_credit_emits_full_record() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = new_composition(ctx);
    let (p, pc) = party::new(ctx);
    let composition_id = object::id(&comp);
    let party_id = object::id(&p);
    let roles = vector[
        cpr::new_adapter_role(),
        cpr::new_arranger_role(),
        cpr::new_composer_role(),
        cpr::new_lyricist_role(),
        cpr::new_songwriter_role(),
        cpr::new_translator_role(),
    ];
    credits::add_credit(&mut comp, &cap, &p, credit::new(long_string(200), roles));
    let events = events_by_type<credits::CompositionCreditAddedEvent>();
    assert_eq!(events.length(), 1);
    let (
        event_composition_id,
        event_party_id,
        event_name,
        event_roles,
    ) = credits::composition_credit_added_fields_for_testing(&events[0]);
    assert_eq!(event_composition_id, composition_id);
    assert_eq!(event_party_id, party_id);
    assert_eq!(event_name, long_string(200));
    assert_eq!(event_roles, roles);
    assert_eq!(to_bytes(&events[0]).length(), 32 + 32 + 2 + 200 + 1 + 6);
    let (mut other_comp, other_cap) = new_composition(ctx);
    let (other_party, other_party_cap) = party::new(ctx);
    credits::add_credit(&mut other_comp, &other_cap, &other_party, composer(b"Other"));
    let events = events_by_type<credits::CompositionCreditAddedEvent>();
    assert_eq!(events.length(), 2);
    let (event_composition_id, _, _, _) = credits::composition_credit_added_fields_for_testing(
        &events[1],
    );
    assert_eq!(event_composition_id, object::id(&other_comp));
    destroy(comp);
    destroy(cap);
    destroy(p);
    destroy(pc);
    destroy(other_comp);
    destroy(other_cap);
    destroy(other_party);
    destroy(other_party_cap);
}

#[test]
fun remove_credit_emits_the_removed_party() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = new_composition(ctx);
    let (p, pc) = party::new(ctx);
    let composition_id = object::id(&comp);
    let party_id = object::id(&p);
    credits::add_credit(&mut comp, &cap, &p, composer(b"Alice"));
    credits::remove_credit(&mut comp, &cap, party_id);
    let events = events_by_type<credits::CompositionCreditRemovedEvent>();
    assert_eq!(events.length(), 1);
    let (
        event_composition_id,
        event_party_id,
    ) = credits::composition_credit_removed_fields_for_testing(
        &events[0],
    );
    assert_eq!(event_composition_id, composition_id);
    assert_eq!(event_party_id, party_id);
    assert_eq!(to_bytes(&events[0]).length(), 64);
    destroy(comp);
    destroy(cap);
    destroy(p);
    destroy(pc);
}

#[test]
fun add_credit_against_published_and_shared_composition() {
    let mut ts = test_scenario::begin(ARTIST);
    let (comp, cap) = new_composition(ts.ctx());
    comp.publish(&cap);
    ts.next_tx(ARTIST);
    let mut comp = ts.take_shared<Composition<TestShare>>();
    let (p, pc) = party::new(ts.ctx());
    credits::add_credit(&mut comp, &cap, &p, composer(b"Alice"));
    assert_eq!(credits::credits(&comp).length(), 1);
    test_scenario::return_shared(comp);
    destroy(cap);
    destroy(p);
    destroy(pc);
    ts.end();
}

#[test, expected_failure(abort_code = credits::ETooManyCredits)]
fun add_credit_rejects_when_max_credits_reached() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = new_composition(ctx);
    let (_first, _first_cap) = fill_to_capacity(&mut comp, &cap, ctx);
    let (p, _pc) = party::new(ctx);
    credits::add_credit(&mut comp, &cap, &p, composer(b"Extra"));
    abort
}

#[test, expected_failure(abort_code = credits::ETooManyCredits)]
fun add_credit_duplicate_at_capacity_reports_capacity() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = new_composition(ctx);
    let (first, _first_cap) = fill_to_capacity(&mut comp, &cap, ctx);
    credits::add_credit(&mut comp, &cap, &first, composer(b"P again"));
    abort
}

#[test, expected_failure(abort_code = credits::ENoCredits)]
fun credits_view_aborts_when_none_attached() {
    let ctx = &mut tx_context::dummy();
    let (comp, _cap) = new_composition(ctx);
    credits::credits(&comp);
    abort
}

#[test, expected_failure(abort_code = credits::ENoCredits)]
fun remove_credit_aborts_when_none_attached() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = new_composition(ctx);
    credits::remove_credit(&mut comp, &cap, test_helpers::fake_id(ctx));
    abort
}

#[test, expected_failure(abort_code = credits::EPartyNotFound)]
fun remove_credit_rejects_uncredited_party() {
    let ctx = &mut tx_context::dummy();
    let (mut comp, cap) = new_composition(ctx);
    let (p, _pc) = party::new(ctx);
    credits::add_credit(&mut comp, &cap, &p, composer(b"Alice"));
    credits::remove_credit(&mut comp, &cap, test_helpers::fake_id(ctx));
    abort
}
