// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module player_record_access::player_record_access_tests;

use player::player::{Self, Player};
use player_storage::player_storage;
use record::{pressing, record};
use player_record_access::player_record_access;
use std::unit_test::destroy;
use sui::{bcs, clock::{Self, Clock}, dynamic_field as df, test_scenario as ts};

const LISTENER: address = @0xA1;
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

fun identity(rule: &Rule): vector<u8> {
    let mut id = bcs::to_bytes(&rule.release);
    id.append(bcs::to_bytes(&rule.edition_min));
    id.append(bcs::to_bytes(&rule.edition_max));
    id.append(bcs::to_bytes(&rule.number_min));
    id.append(bcs::to_bytes(&rule.number_max));
    id.append(bcs::to_bytes(&rule.from_ms));
    id.append(bcs::to_bytes(&rule.until_ms));
    id.append(bcs::to_bytes(&NONCE));
    id
}

fun player_with_record(edition: u16, number: u32, ctx: &mut TxContext): (Player, ID) {
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
    let record_id = object::id(&record);
    let mut player = player::new(ctx);
    player_storage::store(&mut player, record);
    destroy(pressing);
    destroy(cap);
    (player, record_id)
}

fun approve(rule: &Rule, edition: u16, number: u32, now: u64) {
    approve_id(identity(rule), edition, number, now)
}

fun approve_id(id: vector<u8>, edition: u16, number: u32, now: u64) {
    let mut scenario = ts::begin(LISTENER);
    let (player, record_id) = player_with_record(edition, number, scenario.ctx());
    let clock = clock_at(now, scenario.ctx());
    player_record_access::seal_approve_for_testing(id, &player, record_id, &clock);
    destroy(player);
    clock.destroy_for_testing();
    scenario.end();
}

fun clock_at(now: u64, ctx: &mut TxContext): Clock {
    let mut clock = clock::create_for_testing(ctx);
    clock.set_for_testing(now);
    clock
}

#[test]
fun an_open_rule_admits_any_record_of_the_release() {
    approve(&open_rule(), 3, 5, 0);
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

#[test]
fun a_record_at_the_lower_bounds_is_admitted() {
    approve(&bounded_rule(), 2, 2, 100);
}

#[test]
fun a_record_at_the_upper_bounds_is_admitted() {
    approve(&bounded_rule(), 3, 4, 199);
}

#[test, expected_failure(abort_code = player_record_access::EWrongRelease)]
fun a_record_of_another_release_is_refused() {
    let mut rule = open_rule();
    rule.release = OTHER_RELEASE;
    approve(&rule, 1, 1, 0);
}

#[test, expected_failure(abort_code = player_record_access::EEditionOutOfRange)]
fun an_edition_below_the_minimum_is_refused() {
    let mut rule = open_rule();
    rule.edition_min = option::some(2);
    approve(&rule, 1, 1, 0);
}

#[test, expected_failure(abort_code = player_record_access::EEditionOutOfRange)]
fun an_edition_above_the_maximum_is_refused() {
    let mut rule = open_rule();
    rule.edition_max = option::some(1);
    approve(&rule, 2, 1, 0);
}

#[test, expected_failure(abort_code = player_record_access::ENumberOutOfRange)]
fun a_number_below_the_minimum_is_refused() {
    let mut rule = open_rule();
    rule.number_min = option::some(2);
    approve(&rule, 1, 1, 0);
}

#[test, expected_failure(abort_code = player_record_access::ENumberOutOfRange)]
fun a_number_above_the_maximum_is_refused() {
    let mut rule = open_rule();
    rule.number_max = option::some(1);
    approve(&rule, 1, 2, 0);
}

#[test, expected_failure(abort_code = player_record_access::ENotYetOpen)]
fun a_request_before_the_window_is_refused() {
    let mut rule = open_rule();
    rule.from_ms = option::some(100);
    approve(&rule, 1, 1, 99);
}

#[test, expected_failure(abort_code = player_record_access::EClosed)]
fun a_request_at_the_window_end_is_refused() {
    let mut rule = open_rule();
    rule.until_ms = option::some(100);
    approve(&rule, 1, 1, 100);
}

#[test, expected_failure(abort_code = player_record_access::ETrailingBytes)]
fun an_identity_with_trailing_bytes_is_refused() {
    let mut id = identity(&open_rule());
    id.push_back(0);
    approve_id(id, 1, 1, 0);
}

#[test, expected_failure(abort_code = bcs::EOutOfRange, location = bcs)]
fun a_truncated_identity_is_refused() {
    let mut id = identity(&open_rule());
    id.pop_back();
    approve_id(id, 1, 1, 0);
}

#[test, expected_failure(abort_code = df::EFieldDoesNotExist, location = df)]
fun a_record_not_in_the_player_is_refused() {
    let mut scenario = ts::begin(LISTENER);
    let (player, _) = player_with_record(1, 1, scenario.ctx());
    let clock = clock_at(0, scenario.ctx());
    player_record_access::seal_approve_for_testing(
        identity(&open_rule()),
        &player,
        object::id_from_address(@0x1),
        &clock,
    );
    destroy(player);
    clock.destroy_for_testing();
    scenario.end();
}
