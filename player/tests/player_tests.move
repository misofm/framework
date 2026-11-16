// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module player::player_tests;

use player::player::{Self, Player, PlayerCreatedEvent, PlayerRegistry};
use std::unit_test::assert_eq;
use sui::{
    balance,
    coin::{Self, Coin},
    derived_object,
    dynamic_field as df,
    event,
    sui::SUI,
    test_scenario::{Self as ts, Scenario}
};

const LISTENER: address = @0xA1;
const OTHER_LISTENER: address = @0xB2;

public struct TestKey() has copy, drop, store;

// === Helpers ===

fun setup(): Scenario {
    let mut scenario = ts::begin(LISTENER);
    player::init_for_testing(scenario.ctx());
    scenario
}

fun create_player(scenario: &mut Scenario, owner: address): ID {
    scenario.next_tx(owner);
    let mut registry = scenario.take_shared<PlayerRegistry>();
    let player = player::new(&mut registry, scenario.ctx());
    let player_id = object::id(&player);
    player.keep();
    ts::return_shared(registry);
    player_id
}

// === Creation ===

#[test]
fun new_derives_the_owners_player_and_emits_it() {
    let mut scenario = setup();
    let player_id = create_player(&mut scenario, LISTENER);
    let events = event::events_by_type<PlayerCreatedEvent>();
    assert_eq!(events.length(), 1);
    let (event_player_id, event_owner) = player::player_created_fields_for_testing(&events[0]);
    assert_eq!(event_player_id, player_id);
    assert_eq!(event_owner, LISTENER);
    scenario.next_tx(LISTENER);
    let registry = scenario.take_shared<PlayerRegistry>();
    assert_eq!(player::derive_address(&registry, LISTENER), player_id.to_address());
    ts::return_shared(registry);
    let player = scenario.take_from_sender<Player>();
    assert_eq!(object::id(&player), player_id);
    assert_eq!(player.uid().to_inner(), player_id);
    assert_eq!(player.owner(), LISTENER);
    scenario.return_to_sender(player);
    scenario.end();
}

#[test]
fun each_address_gets_its_own_player() {
    let mut scenario = setup();
    let first = create_player(&mut scenario, LISTENER);
    let second = create_player(&mut scenario, OTHER_LISTENER);
    assert!(first != second);
    scenario.next_tx(OTHER_LISTENER);
    let player = scenario.take_from_sender<Player>();
    assert_eq!(object::id(&player), second);
    assert_eq!(player.owner(), OTHER_LISTENER);
    scenario.return_to_sender(player);
    scenario.end();
}

#[
    test,
    expected_failure(abort_code = derived_object::EObjectAlreadyExists, location = derived_object),
]
fun a_second_player_for_the_same_address_aborts() {
    let mut scenario = setup();
    create_player(&mut scenario, LISTENER);
    create_player(&mut scenario, LISTENER);
    scenario.end();
}

// === Holdings ===

#[test]
fun objects_sent_to_player_come_out_through_uid_mut() {
    let mut scenario = setup();
    let player_id = create_player(&mut scenario, LISTENER);
    scenario.next_tx(OTHER_LISTENER);
    let gift = coin::mint_for_testing<SUI>(42, scenario.ctx());
    let gift_id = object::id(&gift);
    transfer::public_transfer(gift, player_id.to_address());
    scenario.next_tx(LISTENER);
    let mut player = scenario.take_from_sender<Player>();
    let ticket = ts::receiving_ticket_by_id<Coin<SUI>>(gift_id);
    let received = transfer::public_receive(player.uid_mut(), ticket);
    assert_eq!(object::id(&received), gift_id);
    assert_eq!(received.value(), 42);
    transfer::public_transfer(received, LISTENER);
    scenario.return_to_sender(player);
    scenario.end();
}

#[test]
fun funds_sent_to_player_come_out_through_uid_mut() {
    let mut scenario = setup();
    create_player(&mut scenario, LISTENER);
    scenario.next_tx(LISTENER);
    let mut player = scenario.take_from_sender<Player>();
    let funds = balance::redeem_funds(
        balance::withdraw_funds_from_object<SUI>(player.uid_mut(), 0),
    );
    assert_eq!(funds.value(), 0);
    funds.destroy_zero();
    scenario.return_to_sender(player);
    scenario.end();
}

// === Extensions ===

#[test]
fun extensions_attach_through_uid_mut() {
    let mut scenario = setup();
    create_player(&mut scenario, LISTENER);
    scenario.next_tx(LISTENER);
    let mut player = scenario.take_from_sender<Player>();
    df::add(player.uid_mut(), TestKey(), b"value");
    assert_eq!(*df::borrow<TestKey, vector<u8>>(player.uid(), TestKey()), b"value");
    let child = derived_object::claim(player.uid_mut(), TestKey());
    assert_eq!(child.to_address(), derived_object::derive_address(object::id(&player), TestKey()));
    child.delete();
    scenario.return_to_sender(player);
    scenario.end();
}
