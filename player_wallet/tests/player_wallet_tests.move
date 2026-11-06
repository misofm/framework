// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module player_wallet::player_wallet_tests;

use player::player::{Self, Player};
use player_wallet::player_wallet as wallet;
use std::unit_test::{assert_eq, destroy};
use sui::{
    accumulator::{Self, AccumulatorRoot},
    balance,
    coin::{Self, Coin},
    event,
    sui::SUI,
    test_scenario as ts,
    transfer::Receiving
};

const LISTENER: address = @0xA;
const OTHER: address = @0xB;
const SYSTEM: address = @0x0;

public struct RecordLike has key, store {
    id: UID,
    number: u32,
}

// === Fixtures ===

fun new_player(scenario: &mut ts::Scenario, owner: address): ID {
    let player = player::new(scenario.ctx());
    let player_id = object::id(&player);
    transfer::public_transfer(player, owner);
    player_id
}

fun send_coin<Currency>(scenario: &mut ts::Scenario, recipient: address, value: u64): ID {
    let coin = coin::mint_for_testing<Currency>(value, scenario.ctx());
    let coin_id = object::id(&coin);
    transfer::public_transfer(coin, recipient);
    coin_id
}

fun ticket<Item: key + store>(id: ID): Receiving<Item> {
    ts::receiving_ticket_by_id<Item>(id)
}

fun destroy_record(record: RecordLike) {
    let RecordLike { id, number: _ } = record;
    id.delete()
}

// === Object and coin receipt ===

#[test]
fun receives_the_exact_object_and_emits_payload() {
    let mut scenario = ts::begin(LISTENER);
    let player_id = new_player(&mut scenario, LISTENER);
    scenario.next_tx(OTHER);
    let record = RecordLike { id: object::new(scenario.ctx()), number: 42 };
    let record_id = object::id(&record);
    transfer::public_transfer(record, player_id.to_address());
    scenario.next_tx(LISTENER);
    let mut player = scenario.take_from_sender<Player>();
    let received = wallet::receive(&mut player, ticket<RecordLike>(record_id));
    assert_eq!(object::id(&received), record_id);
    assert_eq!(received.number, 42);
    let events = event::events_by_type<wallet::PlayerObjectReceivedEvent<RecordLike>>();
    assert_eq!(events.length(), 1);
    let (emitted_player, emitted_object) = wallet::player_object_received_fields_for_testing(
        &events[0],
    );
    assert_eq!(emitted_player, player_id);
    assert_eq!(emitted_object, record_id);
    destroy_record(received);
    scenario.return_to_sender(player);
    scenario.end();
}

#[test]
fun receives_a_coin_as_an_object() {
    let mut scenario = ts::begin(LISTENER);
    let player_id = new_player(&mut scenario, LISTENER);
    scenario.next_tx(OTHER);
    let coin_id = send_coin<SUI>(&mut scenario, player_id.to_address(), 77);
    scenario.next_tx(LISTENER);
    let mut player = scenario.take_from_sender<Player>();
    let coin = wallet::receive(&mut player, ticket<Coin<SUI>>(coin_id));
    assert_eq!(coin.value(), 77);
    assert_eq!(event::events_by_type<wallet::PlayerObjectReceivedEvent<Coin<SUI>>>().length(), 1);
    coin.burn_for_testing();
    scenario.return_to_sender(player);
    scenario.end();
}

#[test]
fun receives_and_merges_coins_with_event_payload() {
    let mut scenario = ts::begin(LISTENER);
    let player_id = new_player(&mut scenario, LISTENER);
    scenario.next_tx(OTHER);
    let first = send_coin<SUI>(&mut scenario, player_id.to_address(), 400);
    let second = send_coin<SUI>(&mut scenario, player_id.to_address(), 600);
    scenario.next_tx(LISTENER);
    let mut player = scenario.take_from_sender<Player>();
    let received = wallet::receive_balance<SUI>(
        &mut player,
        vector[ticket<Coin<SUI>>(first), ticket<Coin<SUI>>(second)],
    );
    assert_eq!(received.value(), 1_000);
    let events = event::events_by_type<wallet::PlayerCoinsReceivedEvent<SUI>>();
    assert_eq!(events.length(), 1);
    let (emitted_player, value, count) = wallet::player_coins_received_fields_for_testing(
        &events[0],
    );
    assert_eq!(emitted_player, player_id);
    assert_eq!(value, 1_000);
    assert_eq!(count, 2);
    assert_eq!(balance::destroy_for_testing(received), 1_000);
    scenario.return_to_sender(player);
    scenario.end();
}

#[test, expected_failure]
fun receive_rejects_a_ticket_for_another_address() {
    let mut scenario = ts::begin(LISTENER);
    new_player(&mut scenario, LISTENER);
    scenario.next_tx(LISTENER);
    let coin_id = send_coin<SUI>(&mut scenario, OTHER, 10);
    scenario.next_tx(LISTENER);
    let mut player = scenario.take_from_sender<Player>();
    let coin = wallet::receive(&mut player, ticket<Coin<SUI>>(coin_id));
    coin.burn_for_testing();
    scenario.return_to_sender(player);
    scenario.end();
}

#[test, expected_failure(abort_code = wallet::EEmptyCoins)]
fun receive_balance_rejects_empty_input() {
    let ctx = &mut tx_context::dummy();
    let mut player = player::new(ctx);
    let balance = wallet::receive_balance<SUI>(&mut player, vector[]);
    balance::destroy_for_testing(balance);
    abort
}

#[test]
fun a_new_holder_receives_what_was_sent_to_the_player() {
    let mut scenario = ts::begin(LISTENER);
    let player_id = new_player(&mut scenario, LISTENER);
    scenario.next_tx(OTHER);
    let coin_id = send_coin<SUI>(&mut scenario, player_id.to_address(), 5);
    scenario.next_tx(LISTENER);
    let player = scenario.take_from_sender<Player>();
    transfer::public_transfer(player, OTHER);
    scenario.next_tx(OTHER);
    let mut player = scenario.take_from_sender<Player>();
    let coin = wallet::receive(&mut player, ticket<Coin<SUI>>(coin_id));
    assert_eq!(coin.value(), 5);
    coin.burn_for_testing();
    scenario.return_to_sender(player);
    scenario.end();
}

// === Accumulator redemption ===

#[test]
fun redeems_funds_and_emits_payload() {
    let mut scenario = ts::begin(LISTENER);
    let player_id = new_player(&mut scenario, LISTENER);
    scenario.next_tx(OTHER);
    balance::create_for_testing<SUI>(750).send_funds(player_id.to_address());
    scenario.next_tx(LISTENER);
    let mut player = scenario.take_from_sender<Player>();
    let redeemed = wallet::redeem_balance<SUI>(&mut player, 750);
    assert_eq!(redeemed.value(), 750);
    let events = event::events_by_type<wallet::PlayerFundsRedeemedEvent<SUI>>();
    assert_eq!(events.length(), 1);
    let (emitted_player, value) = wallet::player_funds_redeemed_fields_for_testing(&events[0]);
    assert_eq!(emitted_player, player_id);
    assert_eq!(value, 750);
    assert_eq!(balance::destroy_for_testing(redeemed), 750);
    scenario.return_to_sender(player);
    scenario.end();
}

#[test]
fun partial_redemptions_cover_every_locally_reachable_funded_path() {
    let mut scenario = ts::begin(LISTENER);
    let player_id = new_player(&mut scenario, LISTENER);
    scenario.next_tx(OTHER);
    balance::create_for_testing<SUI>(1_000).send_funds(player_id.to_address());
    scenario.next_tx(LISTENER);
    let mut player = scenario.take_from_sender<Player>();
    let first = wallet::redeem_balance<SUI>(&mut player, 400);
    assert_eq!(balance::destroy_for_testing(first), 400);
    scenario.return_to_sender(player);
    scenario.next_tx(LISTENER);
    let mut player = scenario.take_from_sender<Player>();
    let remainder = wallet::redeem_balance<SUI>(&mut player, 600);
    assert_eq!(balance::destroy_for_testing(remainder), 600);
    scenario.return_to_sender(player);
    scenario.end();
}

#[test, expected_failure(abort_code = wallet::EZeroValue)]
fun zero_redemption_aborts() {
    let ctx = &mut tx_context::dummy();
    let mut player = player::new(ctx);
    let redeemed = wallet::redeem_balance<SUI>(&mut player, 0);
    balance::destroy_for_testing(redeemed);
    abort
}

#[test]
fun funded_accumulator_snapshot_documents_zero_vm_result() {
    let mut scenario = ts::begin(SYSTEM);
    accumulator::create_for_testing(scenario.ctx());
    let player_id = new_player(&mut scenario, LISTENER);
    scenario.next_tx(OTHER);
    balance::create_for_testing<SUI>(123).send_funds(player_id.to_address());
    scenario.next_tx(LISTENER);
    let player = scenario.take_from_sender<Player>();
    let root = scenario.take_shared<AccumulatorRoot>();
    let settled = balance::settled_funds_value<SUI>(&root, wallet::inbox_address(&player));
    assert_eq!(settled, 0);
    ts::return_shared(root);
    scenario.return_to_sender(player);
    scenario.end();
}

// === Views ===

#[test]
fun inbox_address_is_the_player_id_as_an_address() {
    let ctx = &mut tx_context::dummy();
    let player = player::new(ctx);
    assert_eq!(wallet::inbox_address(&player), object::id(&player).to_address());
    destroy(player);
}
