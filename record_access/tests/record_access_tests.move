// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module record_access::record_access_tests;

use record::{pressing, record::{Self, Record}};
use record_access::record_access::{
    Self,
    RecordAccess,
    RecordAccessClaimedEvent,
    RecordAccessCreatedEvent
};
use std::unit_test::{assert_eq, destroy};
use sui::{bcs, clock, derived_object, event, test_scenario::{Self as ts, Scenario}};

const BUYER: address = @0xA1;
const COLLECTOR: address = @0xB2;
const RELEASE: address = @0xE1;
const OTHER_RELEASE: address = @0xE2;
const NONCE: u256 = 7;

public struct TestDistributor() has drop;

public struct Rule has drop {
    release: address,
    edition_min: Option<u16>,
    edition_max: Option<u16>,
    number_min: Option<u32>,
    number_max: Option<u32>,
    from_ms: Option<u64>,
    until_ms: Option<u64>,
}

// === Helpers ===

fun open_rule(): Rule {
    Rule {
        release: RELEASE,
        edition_min: option::none(),
        edition_max: option::none(),
        number_min: option::none(),
        number_max: option::none(),
        from_ms: option::none(),
        until_ms: option::none(),
    }
}

fun bounded_rule(): Rule {
    let mut rule = open_rule();
    rule.edition_min = option::some(2);
    rule.edition_max = option::some(3);
    rule.number_min = option::some(2);
    rule.number_max = option::some(4);
    rule.from_ms = option::some(100);
    rule.until_ms = option::some(200);
    rule
}

fun identity(rule: &Rule): vector<u8> {
    let mut id = bcs::to_bytes(&rule.release);
    id.append(bcs::to_bytes(&rule.edition_min));
    id.append(bcs::to_bytes(&rule.edition_max));
    id.append(bcs::to_bytes(&rule.number_min));
    id.append(bcs::to_bytes(&rule.number_max));
    id.append(bcs::to_bytes(&rule.from_ms));
    id.append(bcs::to_bytes(&rule.until_ms));
    let nonce = NONCE;
    id.append(bcs::to_bytes(&nonce));
    id
}

fun new_record(edition: u16, number: u32, ctx: &mut TxContext): Record {
    let (mut pressing, cap) = pressing::new_for_testing(
        object::id_from_address(RELEASE),
        edition,
        number,
        ctx,
    );
    pressing.authorize_distributor<TestDistributor>(&cap);
    let mut record = record::new(&mut pressing, TestDistributor());
    let mut n = 1;
    while (n < number) {
        record.destroy();
        record = record::new(&mut pressing, TestDistributor());
        n = n + 1;
    };
    destroy(pressing);
    destroy(cap);
    record
}

fun setup(edition: u16, number: u32): (Scenario, ID) {
    let mut scenario = ts::begin(BUYER);
    let record = new_record(edition, number, scenario.ctx());
    let record = record_access::new(record, scenario.ctx());
    let record_id = object::id(&record);
    transfer::public_transfer(record, BUYER);
    (scenario, record_id)
}

fun approve(scenario: &mut Scenario, sender: address, id: vector<u8>, now: u64) {
    scenario.next_tx(sender);
    let access = scenario.take_shared<RecordAccess>();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(now);
    record_access::seal_approve_for_testing(id, &access, &clock, scenario.ctx());
    clock.destroy_for_testing();
    ts::return_shared(access);
}

fun approve_rule(rule: &Rule, edition: u16, number: u32, now: u64) {
    let (mut scenario, _) = setup(edition, number);
    approve(&mut scenario, BUYER, identity(rule), now);
    scenario.end();
}

fun claim(scenario: &mut Scenario, sender: address, record_id: ID) {
    scenario.next_tx(sender);
    let mut access = scenario.take_shared<RecordAccess>();
    let record = scenario.take_from_sender_by_id<Record>(record_id);
    let record = record_access::claim(&mut access, record, scenario.ctx());
    scenario.return_to_sender(record);
    ts::return_shared(access);
}

// === Creation ===

#[test]
fun new_shares_a_derived_access_owned_by_the_creator() {
    let (mut scenario, record_id) = setup(2, 3);
    let events = event::events_by_type<RecordAccessCreatedEvent>();
    assert_eq!(events.length(), 1);
    let (access_id, event_record_id, owner) =
        record_access::record_access_created_fields_for_testing(&events[0]);
    assert_eq!(event_record_id, record_id);
    assert_eq!(owner, BUYER);
    assert_eq!(access_id.to_address(), record_access::derive_address(record_id));
    scenario.next_tx(BUYER);
    let access = scenario.take_shared<RecordAccess>();
    assert_eq!(object::id(&access), access_id);
    assert_eq!(access.release_id(), object::id_from_address(RELEASE));
    assert_eq!(access.edition(), 2);
    assert_eq!(access.number(), 3);
    assert_eq!(access.owner(), BUYER);
    ts::return_shared(access);
    scenario.end();
}

#[
    test,
    expected_failure(abort_code = derived_object::EObjectAlreadyExists, location = derived_object),
]
fun a_second_access_for_the_same_record_aborts() {
    let (mut scenario, record_id) = setup(1, 1);
    scenario.next_tx(BUYER);
    let record = scenario.take_from_sender_by_id<Record>(record_id);
    let record = record_access::new(record, scenario.ctx());
    destroy(record);
    scenario.end();
}

// === Claims ===

#[test]
fun a_new_owner_claims_access() {
    let (mut scenario, record_id) = setup(1, 1);
    scenario.next_tx(BUYER);
    let record = scenario.take_from_sender_by_id<Record>(record_id);
    transfer::public_transfer(record, COLLECTOR);
    approve(&mut scenario, BUYER, identity(&open_rule()), 0);
    claim(&mut scenario, COLLECTOR, record_id);
    let events = event::events_by_type<RecordAccessClaimedEvent>();
    assert_eq!(events.length(), 1);
    let (access_id, event_record_id, owner) =
        record_access::record_access_claimed_fields_for_testing(&events[0]);
    assert_eq!(access_id.to_address(), record_access::derive_address(record_id));
    assert_eq!(event_record_id, record_id);
    assert_eq!(owner, COLLECTOR);
    approve(&mut scenario, COLLECTOR, identity(&open_rule()), 0);
    scenario.end();
}

#[test]
fun a_claim_by_the_current_owner_emits_nothing() {
    let (mut scenario, record_id) = setup(1, 1);
    claim(&mut scenario, BUYER, record_id);
    assert_eq!(event::events_by_type<RecordAccessClaimedEvent>().length(), 0);
    scenario.end();
}

#[test, expected_failure(abort_code = record_access::EWrongRecord)]
fun a_claim_with_another_record_aborts() {
    let (mut scenario, _) = setup(1, 1);
    scenario.next_tx(COLLECTOR);
    let mut access = scenario.take_shared<RecordAccess>();
    let mut other = new_record(1, 1, scenario.ctx());
    other = record_access::claim(&mut access, other, scenario.ctx());
    destroy(other);
    ts::return_shared(access);
    scenario.end();
}

#[test, expected_failure(abort_code = record_access::ENotOwner)]
fun the_previous_owner_is_refused_after_a_claim() {
    let (mut scenario, record_id) = setup(1, 1);
    scenario.next_tx(BUYER);
    let record = scenario.take_from_sender_by_id<Record>(record_id);
    transfer::public_transfer(record, COLLECTOR);
    claim(&mut scenario, COLLECTOR, record_id);
    approve(&mut scenario, BUYER, identity(&open_rule()), 0);
    scenario.end();
}

// === Rules ===

#[test]
fun an_open_rule_admits_any_record_of_the_release() {
    approve_rule(&open_rule(), 3, 5, 0);
}

#[test]
fun a_record_at_the_lower_bounds_is_admitted() {
    approve_rule(&bounded_rule(), 2, 2, 100);
}

#[test]
fun a_record_at_the_upper_bounds_is_admitted() {
    approve_rule(&bounded_rule(), 3, 4, 199);
}

#[test, expected_failure(abort_code = record_access::EWrongRelease)]
fun a_record_of_another_release_is_refused() {
    let mut rule = open_rule();
    rule.release = OTHER_RELEASE;
    approve_rule(&rule, 1, 1, 0);
}

#[test, expected_failure(abort_code = record_access::EEditionOutOfRange)]
fun an_edition_below_the_minimum_is_refused() {
    let mut rule = open_rule();
    rule.edition_min = option::some(2);
    approve_rule(&rule, 1, 1, 0);
}

#[test, expected_failure(abort_code = record_access::EEditionOutOfRange)]
fun an_edition_above_the_maximum_is_refused() {
    let mut rule = open_rule();
    rule.edition_max = option::some(1);
    approve_rule(&rule, 2, 1, 0);
}

#[test, expected_failure(abort_code = record_access::ENumberOutOfRange)]
fun a_number_below_the_minimum_is_refused() {
    let mut rule = open_rule();
    rule.number_min = option::some(2);
    approve_rule(&rule, 1, 1, 0);
}

#[test, expected_failure(abort_code = record_access::ENumberOutOfRange)]
fun a_number_above_the_maximum_is_refused() {
    let mut rule = open_rule();
    rule.number_max = option::some(1);
    approve_rule(&rule, 1, 2, 0);
}

#[test, expected_failure(abort_code = record_access::ENotYetOpen)]
fun a_request_before_the_window_is_refused() {
    let mut rule = open_rule();
    rule.from_ms = option::some(100);
    approve_rule(&rule, 1, 1, 99);
}

#[test, expected_failure(abort_code = record_access::EClosed)]
fun a_request_at_the_window_end_is_refused() {
    let mut rule = open_rule();
    rule.until_ms = option::some(100);
    approve_rule(&rule, 1, 1, 100);
}

#[test, expected_failure(abort_code = record_access::ETrailingBytes)]
fun an_identity_with_trailing_bytes_is_refused() {
    let (mut scenario, _) = setup(1, 1);
    let mut id = identity(&open_rule());
    id.push_back(0);
    approve(&mut scenario, BUYER, id, 0);
    scenario.end();
}

#[test, expected_failure(abort_code = bcs::EOutOfRange, location = bcs)]
fun a_truncated_identity_is_refused() {
    let (mut scenario, _) = setup(1, 1);
    let mut id = identity(&open_rule());
    id.pop_back();
    approve(&mut scenario, BUYER, id, 0);
    scenario.end();
}
