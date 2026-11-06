// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module player::player_tests;

use player::player::{Self, Player, PlayerCreatedEvent};
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

fun create_player(scenario: &mut Scenario, owner: address): ID {
    scenario.next_tx(owner);
    let player = player::new(scenario.ctx());
    let player_id = object::id(&player);
    transfer::public_transfer(player, owner);
    player_id
}

fun setup(): Scenario {
    ts::begin(LISTENER)
}

// === Creation ===

#[test]
fun new_returns_a_player_and_emits_its_id() {
    let mut scenario = setup();
    let player_id = create_player(&mut scenario, LISTENER);
    let events = event::events_by_type<PlayerCreatedEvent>();
    assert_eq!(events.length(), 1);
    assert_eq!(player::player_created_fields_for_testing(&events[0]), player_id);
    scenario.next_tx(LISTENER);
    let player = scenario.take_from_sender<Player>();
    assert_eq!(object::id(&player), player_id);
    assert_eq!(player.uid().to_inner(), player_id);
    scenario.return_to_sender(player);
    scenario.end();
}

#[test]
fun an_address_can_hold_several_players() {
    let mut scenario = setup();
    create_player(&mut scenario, LISTENER);
    create_player(&mut scenario, LISTENER);
    scenario.next_tx(LISTENER);
    assert_eq!(scenario.ids_for_sender<Player>().length(), 2);
    scenario.end();
}

// === Transfer ===

#[test]
fun a_player_and_its_holdings_move_to_a_new_owner() {
    let mut scenario = setup();
    let player_id = create_player(&mut scenario, LISTENER);
    scenario.next_tx(LISTENER);
    let gift = coin::mint_for_testing<SUI>(7, scenario.ctx());
    let gift_id = object::id(&gift);
    transfer::public_transfer(gift, player_id.to_address());
    scenario.next_tx(LISTENER);
    let player = scenario.take_from_sender<Player>();
    transfer::public_transfer(player, OTHER_LISTENER);
    scenario.next_tx(OTHER_LISTENER);
    let mut player = scenario.take_from_sender<Player>();
    assert_eq!(object::id(&player), player_id);
    let ticket = ts::receiving_ticket_by_id<Coin<SUI>>(gift_id);
    let received = transfer::public_receive(player.uid_mut(), ticket);
    assert_eq!(received.value(), 7);
    transfer::public_transfer(received, OTHER_LISTENER);
    scenario.return_to_sender(player);
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
