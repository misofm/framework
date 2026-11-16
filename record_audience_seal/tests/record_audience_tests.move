// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module record_audience_seal::record_audience_tests;

use record_audience_seal::record_audience::{
    Self,
    RecordAudience,
    RecordAudienceAdminCap,
    RecordAudienceCreatedEvent,
    RecordAudienceRule,
    RecordAudienceRuleRemovedEvent,
    RecordAudienceRuleSetEvent
};
use std::unit_test::{assert_eq, destroy};
use sui::{address, event, test_scenario::{Self as ts, Scenario}};

const ADMIN: address = @0xA1;
const RELEASE: address = @0xE1;

public struct World {
    scenario: Scenario,
    cap: RecordAudienceAdminCap,
    audience_id: ID,
}

// === Helpers ===

fun release(): ID {
    object::id_from_address(RELEASE)
}

fun nth(i: u64): ID {
    object::id_from_address(address::from_u256(i as u256))
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

fun finish(world: World) {
    let World { scenario, cap, .. } = world;
    destroy(cap);
    scenario.end();
}

// === Creation ===

#[test]
fun new_shares_an_empty_audience_and_returns_its_cap() {
    let mut world = world();
    let created = event::events_by_type<RecordAudienceCreatedEvent>();
    assert_eq!(created.length(), 1);
    let (audience_id, admin_cap_id) =
        record_audience::record_audience_created_fields_for_testing(&created[0]);
    assert_eq!(audience_id, world.audience_id);
    assert_eq!(admin_cap_id, object::id(&world.cap));
    world.scenario.next_tx(ADMIN);
    let audience = world.scenario.take_shared_by_id<RecordAudience>(world.audience_id);
    assert_eq!(object::id(&audience), world.audience_id);
    assert_eq!(audience.rule_count(), 0);
    assert!(!audience.has_rule(release()));
    ts::return_shared(audience);
    finish(world);
}

// === Rules ===

#[test]
fun set_rule_stores_and_emits_the_rule() {
    let mut world = world();
    set(&mut world, release(), bounded_rule());
    let events = event::events_by_type<RecordAudienceRuleSetEvent>();
    assert_eq!(events.length(), 1);
    let (audience_id, release_id, rule) =
        record_audience::record_audience_rule_set_fields_for_testing(&events[0]);
    assert_eq!(audience_id, world.audience_id);
    assert_eq!(release_id, release());
    assert_eq!(rule, bounded_rule());
    world.scenario.next_tx(ADMIN);
    let audience = world.scenario.take_shared_by_id<RecordAudience>(world.audience_id);
    assert_eq!(audience.rule_count(), 1);
    let rule = audience.rule(release());
    assert_eq!(rule.edition_min(), option::some(2));
    assert_eq!(rule.edition_max(), option::some(3));
    assert_eq!(rule.number_min(), option::some(2));
    assert_eq!(rule.number_max(), option::some(4));
    ts::return_shared(audience);
    finish(world);
}

#[test]
fun set_rule_replaces_and_skips_equal_values() {
    let mut world = world();
    set(&mut world, release(), open_rule());
    set(&mut world, release(), open_rule());
    assert_eq!(event::events_by_type<RecordAudienceRuleSetEvent>().length(), 0);
    set(&mut world, release(), bounded_rule());
    assert_eq!(event::events_by_type<RecordAudienceRuleSetEvent>().length(), 1);
    world.scenario.next_tx(ADMIN);
    let audience = world.scenario.take_shared_by_id<RecordAudience>(world.audience_id);
    assert_eq!(audience.rule_count(), 1);
    assert_eq!(audience.rule(release()), bounded_rule());
    ts::return_shared(audience);
    finish(world);
}

#[test]
fun remove_rule_detaches_and_skips_absent_rules() {
    let mut world = world();
    set(&mut world, release(), open_rule());
    remove(&mut world, release());
    let events = event::events_by_type<RecordAudienceRuleRemovedEvent>();
    assert_eq!(events.length(), 1);
    let (audience_id, release_id) =
        record_audience::record_audience_rule_removed_fields_for_testing(&events[0]);
    assert_eq!(audience_id, world.audience_id);
    assert_eq!(release_id, release());
    remove(&mut world, release());
    assert_eq!(event::events_by_type<RecordAudienceRuleRemovedEvent>().length(), 0);
    world.scenario.next_tx(ADMIN);
    let audience = world.scenario.take_shared_by_id<RecordAudience>(world.audience_id);
    assert!(!audience.has_rule(release()));
    ts::return_shared(audience);
    finish(world);
}

#[test]
fun the_maximum_number_of_rules_is_accepted() {
    let mut world = world();
    world.scenario.next_tx(ADMIN);
    let mut audience = world.scenario.take_shared_by_id<RecordAudience>(world.audience_id);
    assert_eq!(record_audience::max_rules(), 1000);
    record_audience::max_rules().do!(|i| {
        audience.set_rule(&world.cap, nth(i), open_rule());
    });
    assert_eq!(audience.rule_count(), 1000);
    audience.set_rule(&world.cap, object::id_from_address(@0x0), bounded_rule());
    ts::return_shared(audience);
    finish(world);
}

#[test, expected_failure(abort_code = record_audience::ETooManyRules)]
fun a_rule_past_the_maximum_aborts() {
    let mut world = world();
    world.scenario.next_tx(ADMIN);
    let mut audience = world.scenario.take_shared_by_id<RecordAudience>(world.audience_id);
    (record_audience::max_rules() + 1).do!(|i| {
        audience.set_rule(&world.cap, nth(i), open_rule());
    });
    abort
}

#[test, expected_failure(abort_code = record_audience::EInvalidRange)]
fun an_inverted_edition_range_aborts() {
    record_audience::new_rule(option::some(3), option::some(2), option::none(), option::none());
}

#[test, expected_failure(abort_code = record_audience::EInvalidRange)]
fun an_inverted_number_range_aborts() {
    record_audience::new_rule(option::none(), option::none(), option::some(3), option::some(2));
}

#[test, expected_failure(abort_code = record_audience::ERuleNotFound)]
fun reading_a_missing_rule_aborts() {
    let mut world = world();
    world.scenario.next_tx(ADMIN);
    let audience = world.scenario.take_shared_by_id<RecordAudience>(world.audience_id);
    audience.rule(release());
    abort
}

#[test, expected_failure(abort_code = record_audience::EUnauthorized)]
fun another_audiences_cap_cannot_set_a_rule() {
    let mut world = world();
    let other_cap = record_audience::new(world.scenario.ctx());
    world.scenario.next_tx(ADMIN);
    let mut audience = world.scenario.take_shared_by_id<RecordAudience>(world.audience_id);
    audience.set_rule(&other_cap, release(), open_rule());
    abort
}

#[test, expected_failure(abort_code = record_audience::EUnauthorized)]
fun another_audiences_cap_cannot_remove_a_rule() {
    let mut world = world();
    set(&mut world, release(), open_rule());
    let other_cap = record_audience::new(world.scenario.ctx());
    world.scenario.next_tx(ADMIN);
    let mut audience = world.scenario.take_shared_by_id<RecordAudience>(world.audience_id);
    audience.remove_rule(&other_cap, release());
    abort
}
