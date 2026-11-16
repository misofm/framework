// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module player_storage::player_storage_tests;

use player::player::{Self, Player};
use player_storage::player_storage::{
    Self,
    ItemLockedEvent,
    ItemStoredEvent,
    ItemUnlockedEvent,
    ItemWithdrawnEvent
};
use std::{type_name, unit_test::{assert_eq, destroy}};
use sui::{dynamic_field as df, event, test_scenario as ts};

const LISTENER: address = @0xA1;

public struct Ticket has key, store {
    id: UID,
}

public struct Badge has key, store {
    id: UID,
}

public struct PlaytimeLock() has drop;

public struct StakingLock() has drop;

public struct Lock3() has drop;

public struct Lock4() has drop;

public struct Lock5() has drop;

public struct Lock6() has drop;

public struct Lock7() has drop;

public struct Lock8() has drop;

public struct Lock9() has drop;

fun new_ticket(ctx: &mut TxContext): Ticket {
    Ticket { id: object::new(ctx) }
}

fun player_with_ticket(ctx: &mut TxContext): (Player, ID) {
    let mut player = player::new_for_testing(ctx);
    let ticket = new_ticket(ctx);
    let ticket_id = object::id(&ticket);
    player_storage::store(&mut player, ticket);
    (player, ticket_id)
}

#[test]
fun store_borrow_and_withdraw() {
    let mut scenario = ts::begin(LISTENER);
    let (mut player, ticket_id) = player_with_ticket(scenario.ctx());
    let player_id = object::id(&player);
    let stored = event::events_by_type<ItemStoredEvent<Ticket>>();
    assert_eq!(stored.length(), 1);
    let (event_player_id, event_item_id) = player_storage::item_stored_fields_for_testing(&stored[0]);
    assert_eq!(event_player_id, player_id);
    assert_eq!(event_item_id, ticket_id);
    assert!(player_storage::has_item(&player, ticket_id));
    assert_eq!(object::id(player_storage::borrow<Ticket>(&player, ticket_id)), ticket_id);
    assert!(player_storage::locks<Ticket>(&player, ticket_id).is_empty());
    let ticket: Ticket = player_storage::withdraw(&mut player, ticket_id);
    assert_eq!(object::id(&ticket), ticket_id);
    assert!(!player_storage::has_item(&player, ticket_id));
    let withdrawn = event::events_by_type<ItemWithdrawnEvent<Ticket>>();
    assert_eq!(withdrawn.length(), 1);
    let (event_player_id, event_item_id) = player_storage::item_withdrawn_fields_for_testing(&withdrawn[0]);
    assert_eq!(event_player_id, player_id);
    assert_eq!(event_item_id, ticket_id);
    destroy(ticket);
    destroy(player);
    scenario.end();
}

#[test]
fun lock_and_unlock() {
    let mut scenario = ts::begin(LISTENER);
    let (mut player, ticket_id) = player_with_ticket(scenario.ctx());
    let player_id = object::id(&player);
    let playtime = player_storage::lock<Ticket, PlaytimeLock>(
        &mut player,
        ticket_id,
        PlaytimeLock(),
    );
    let staking = player_storage::lock<Ticket, StakingLock>(&mut player, ticket_id, StakingLock());
    let locks = player_storage::locks<Ticket>(&player, ticket_id);
    assert_eq!(locks.length(), 2);
    assert!(locks.contains(&type_name::with_defining_ids<PlaytimeLock>()));
    assert!(locks.contains(&type_name::with_defining_ids<StakingLock>()));
    let locked = event::events_by_type<ItemLockedEvent<Ticket, PlaytimeLock>>();
    assert_eq!(locked.length(), 1);
    let (event_player_id, event_item_id) = player_storage::item_locked_fields_for_testing(&locked[0]);
    assert_eq!(event_player_id, player_id);
    assert_eq!(event_item_id, ticket_id);
    player_storage::unlock(&mut player, ticket_id, playtime);
    let unlocked = event::events_by_type<ItemUnlockedEvent<Ticket, PlaytimeLock>>();
    assert_eq!(unlocked.length(), 1);
    let (event_player_id, event_item_id) = player_storage::item_unlocked_fields_for_testing(&unlocked[0]);
    assert_eq!(event_player_id, player_id);
    assert_eq!(event_item_id, ticket_id);
    let locks = player_storage::locks<Ticket>(&player, ticket_id);
    assert_eq!(locks.length(), 1);
    assert!(locks.contains(&type_name::with_defining_ids<StakingLock>()));
    player_storage::unlock(&mut player, ticket_id, staking);
    let ticket: Ticket = player_storage::withdraw(&mut player, ticket_id);
    destroy(ticket);
    destroy(player);
    scenario.end();
}

#[test, expected_failure(abort_code = player_storage::ELocked)]
fun withdraw_while_locked_aborts() {
    let mut scenario = ts::begin(LISTENER);
    let (mut player, ticket_id) = player_with_ticket(scenario.ctx());
    let lock = player_storage::lock<Ticket, PlaytimeLock>(&mut player, ticket_id, PlaytimeLock());
    let ticket: Ticket = player_storage::withdraw(&mut player, ticket_id);
    destroy(ticket);
    destroy(lock);
    destroy(player);
    scenario.end();
}

#[test, expected_failure(abort_code = player_storage::EAlreadyLocked)]
fun second_lock_by_the_same_locker_aborts() {
    let mut scenario = ts::begin(LISTENER);
    let (mut player, ticket_id) = player_with_ticket(scenario.ctx());
    let first = player_storage::lock<Ticket, PlaytimeLock>(&mut player, ticket_id, PlaytimeLock());
    let second = player_storage::lock<Ticket, PlaytimeLock>(&mut player, ticket_id, PlaytimeLock());
    destroy(first);
    destroy(second);
    destroy(player);
    scenario.end();
}

#[test, expected_failure(abort_code = player_storage::ETooManyLocks)]
fun lock_past_the_maximum_aborts() {
    let mut scenario = ts::begin(LISTENER);
    let (mut player, ticket_id) = player_with_ticket(scenario.ctx());
    assert_eq!(player_storage::max_locks(), 8);
    let l1 = player_storage::lock<Ticket, PlaytimeLock>(&mut player, ticket_id, PlaytimeLock());
    let l2 = player_storage::lock<Ticket, StakingLock>(&mut player, ticket_id, StakingLock());
    let l3 = player_storage::lock<Ticket, Lock3>(&mut player, ticket_id, Lock3());
    let l4 = player_storage::lock<Ticket, Lock4>(&mut player, ticket_id, Lock4());
    let l5 = player_storage::lock<Ticket, Lock5>(&mut player, ticket_id, Lock5());
    let l6 = player_storage::lock<Ticket, Lock6>(&mut player, ticket_id, Lock6());
    let l7 = player_storage::lock<Ticket, Lock7>(&mut player, ticket_id, Lock7());
    let l8 = player_storage::lock<Ticket, Lock8>(&mut player, ticket_id, Lock8());
    let l9 = player_storage::lock<Ticket, Lock9>(&mut player, ticket_id, Lock9());
    destroy(l1);
    destroy(l2);
    destroy(l3);
    destroy(l4);
    destroy(l5);
    destroy(l6);
    destroy(l7);
    destroy(l8);
    destroy(l9);
    destroy(player);
    scenario.end();
}

#[test, expected_failure(abort_code = df::EFieldTypeMismatch, location = df)]
fun borrow_as_another_type_aborts() {
    let mut scenario = ts::begin(LISTENER);
    let (player, ticket_id) = player_with_ticket(scenario.ctx());
    let _badge: &Badge = player_storage::borrow(&player, ticket_id);
    destroy(player);
    scenario.end();
}

#[test, expected_failure(abort_code = df::EFieldDoesNotExist, location = df)]
fun withdraw_of_an_absent_item_aborts() {
    let mut scenario = ts::begin(LISTENER);
    let mut player = player::new_for_testing(scenario.ctx());
    let ticket: Ticket = player_storage::withdraw(&mut player, object::id_from_address(@0x1));
    destroy(ticket);
    destroy(player);
    scenario.end();
}
