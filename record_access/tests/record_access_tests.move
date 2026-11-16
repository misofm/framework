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
use sui::{derived_object, event, test_scenario::{Self as ts, Scenario}};

const BUYER: address = @0xA1;
const COLLECTOR: address = @0xB2;
const RELEASE: address = @0xE1;

public struct TestDistributor() has drop;

// === Helpers ===

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

fun owner_of(scenario: &mut Scenario): address {
    scenario.next_tx(BUYER);
    let access = scenario.take_shared<RecordAccess>();
    let owner = access.owner();
    ts::return_shared(access);
    owner
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
    assert_eq!(owner_of(&mut scenario), BUYER);
    claim(&mut scenario, COLLECTOR, record_id);
    let events = event::events_by_type<RecordAccessClaimedEvent>();
    assert_eq!(events.length(), 1);
    let (access_id, event_record_id, owner) =
        record_access::record_access_claimed_fields_for_testing(&events[0]);
    assert_eq!(access_id.to_address(), record_access::derive_address(record_id));
    assert_eq!(event_record_id, record_id);
    assert_eq!(owner, COLLECTOR);
    assert_eq!(owner_of(&mut scenario), COLLECTOR);
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
