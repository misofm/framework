// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module record_audience_seal::seal_tests;

use record_access::record_access;
use record_audience_seal::{
    record_audience::{Self, RecordAudience, RecordAudienceAdminCap, RecordAudienceRule},
    seal
};
use std::unit_test::destroy;
use sui::{bcs, test_scenario::{Self as ts, Scenario}};

const ADMIN: address = @0xA1;
const HOLDER: address = @0xB2;
const STRANGER: address = @0xC3;
const RELEASE: address = @0xE1;
const OTHER_RELEASE: address = @0xE2;
const NONCE: u256 = 7;

public struct World {
    scenario: Scenario,
    cap: RecordAudienceAdminCap,
    audience_id: ID,
}

// === Helpers ===

fun release(): ID {
    object::id_from_address(RELEASE)
}

fun open_rule(): RecordAudienceRule {
    record_audience::new_rule(option::none(), option::none(), option::none(), option::none())
}

fun bounded_rule(): RecordAudienceRule {
    record_audience::new_rule(
        option::some(2),
        option::some(3),
        option::some(2),
        option::some(4),
    )
}

fun world(): World {
    let mut scenario = ts::begin(ADMIN);
    let cap = record_audience::new(scenario.ctx());
    let audience_id = cap.admin_cap_audience_id();
    World { scenario, cap, audience_id }
}

fun set(world: &mut World, release_id: ID, rule: RecordAudienceRule) {
    world.scenario.next_tx(ADMIN);
    let mut audience = world.scenario.take_shared_by_id<RecordAudience>(world.audience_id);
    audience.set_rule(&world.cap, release_id, rule);
    ts::return_shared(audience);
}

fun remove(world: &mut World, release_id: ID) {
    world.scenario.next_tx(ADMIN);
    let mut audience = world.scenario.take_shared_by_id<RecordAudience>(world.audience_id);
    audience.remove_rule(&world.cap, release_id);
    ts::return_shared(audience);
}

fun identity(audience_id: ID): vector<u8> {
    let mut id = bcs::to_bytes(&audience_id.to_address());
    let nonce = NONCE;
    id.append(bcs::to_bytes(&nonce));
    id
}

fun approve_id(world: &mut World, id: vector<u8>, sender: address, edition: u16, number: u32) {
    world.scenario.next_tx(sender);
    let audience = world.scenario.take_shared_by_id<RecordAudience>(world.audience_id);
    let ctx = world.scenario.ctx();
    let access = record_access::new_for_testing(release(), edition, number, HOLDER, ctx);
    seal::seal_approve_for_testing(id, &audience, &access, ctx);
    destroy(access);
    ts::return_shared(audience);
}

fun approve(world: &mut World, edition: u16, number: u32) {
    let id = identity(world.audience_id);
    approve_id(world, id, HOLDER, edition, number);
}

fun finish(world: World) {
    let World { scenario, cap, .. } = world;
    destroy(cap);
    scenario.end();
}

// === Seal policy ===

#[test]
fun an_open_rule_admits_any_holder_of_the_release() {
    let mut world = world();
    set(&mut world, release(), open_rule());
    approve(&mut world, 9, 99);
    finish(world);
}

#[test]
fun a_holder_at_the_bounds_is_admitted() {
    let mut world = world();
    set(&mut world, release(), bounded_rule());
    approve(&mut world, 2, 2);
    approve(&mut world, 3, 4);
    finish(world);
}

#[test, expected_failure(abort_code = seal::ENoMatchingRule)]
fun a_holder_of_an_unlisted_release_is_refused() {
    let mut world = world();
    set(&mut world, object::id_from_address(OTHER_RELEASE), open_rule());
    approve(&mut world, 1, 1);
    abort
}

#[test, expected_failure(abort_code = seal::ENoMatchingRule)]
fun a_holder_after_the_rule_is_removed_is_refused() {
    let mut world = world();
    set(&mut world, release(), open_rule());
    remove(&mut world, release());
    approve(&mut world, 1, 1);
    abort
}

#[test, expected_failure(abort_code = seal::ENoMatchingRule)]
fun an_edition_below_the_range_is_refused() {
    let mut world = world();
    set(&mut world, release(), bounded_rule());
    approve(&mut world, 1, 3);
    abort
}

#[test, expected_failure(abort_code = seal::ENoMatchingRule)]
fun an_edition_above_the_range_is_refused() {
    let mut world = world();
    set(&mut world, release(), bounded_rule());
    approve(&mut world, 4, 3);
    abort
}

#[test, expected_failure(abort_code = seal::ENoMatchingRule)]
fun a_number_below_the_range_is_refused() {
    let mut world = world();
    set(&mut world, release(), bounded_rule());
    approve(&mut world, 2, 1);
    abort
}

#[test, expected_failure(abort_code = seal::ENoMatchingRule)]
fun a_number_above_the_range_is_refused() {
    let mut world = world();
    set(&mut world, release(), bounded_rule());
    approve(&mut world, 2, 5);
    abort
}

#[test, expected_failure(abort_code = seal::ENotOwner)]
fun a_caller_other_than_the_owner_is_refused() {
    let mut world = world();
    set(&mut world, release(), open_rule());
    let id = identity(world.audience_id);
    approve_id(&mut world, id, STRANGER, 1, 1);
    abort
}

#[test, expected_failure(abort_code = seal::EWrongAudience)]
fun an_identity_for_another_audience_is_refused() {
    let mut world = world();
    set(&mut world, release(), open_rule());
    let id = identity(object::id_from_address(@0xBAD));
    approve_id(&mut world, id, HOLDER, 1, 1);
    abort
}

#[test, expected_failure(abort_code = seal::EWrongAudience)]
fun an_identity_with_trailing_bytes_is_refused() {
    let mut world = world();
    set(&mut world, release(), open_rule());
    let mut id = identity(world.audience_id);
    id.push_back(0);
    approve_id(&mut world, id, HOLDER, 1, 1);
    abort
}

#[test, expected_failure(abort_code = bcs::EOutOfRange, location = bcs)]
fun a_truncated_identity_is_refused() {
    let mut world = world();
    set(&mut world, release(), open_rule());
    let mut id = identity(world.audience_id);
    id.pop_back();
    approve_id(&mut world, id, HOLDER, 1, 1);
    abort
}

#[test]
fun half_open_bounds_are_accepted() {
    let mut world = world();
    let rule = record_audience::new_rule(
        option::some(2),
        option::none(),
        option::some(3),
        option::none(),
    );
    set(&mut world, release(), rule);
    approve(&mut world, 9, 99);
    finish(world);
}
