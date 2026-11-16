// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module player_storage::player_storage;

use player::player::Player;
use std::type_name::{Self, TypeName};
use sui::{
    borrow::{Self, Borrow, Referent},
    dynamic_field as df,
    event::emit,
    vec_set::{Self, VecSet}
};

// === Errors ===

const ELocked: u64 = 0;
const EAlreadyLocked: u64 = 1;
const ETooManyLocks: u64 = 2;

// === Constants ===

const MAX_LOCKS: u64 = 8;

// === Structs ===

public struct StorageSlot<Item: key + store> has store {
    item: Referent<Item>,
    locks: VecSet<TypeName>,
}

public struct Lock<phantom Item, phantom Locker>() has store;

public struct SlotKey(ID) has copy, drop, store;

// === Events ===

public struct ItemStoredEvent<phantom Item> has copy, drop {
    player_id: ID,
    item_id: ID,
}

public struct ItemWithdrawnEvent<phantom Item> has copy, drop {
    player_id: ID,
    item_id: ID,
}

public struct ItemLockedEvent<phantom Item, phantom Locker> has copy, drop {
    player_id: ID,
    item_id: ID,
}

public struct ItemUnlockedEvent<phantom Item, phantom Locker> has copy, drop {
    player_id: ID,
    item_id: ID,
}

// === Public Functions ===

public fun store<Item: key + store>(player: &mut Player, item: Item, ctx: &mut TxContext) {
    let item_id = object::id(&item);
    let player_id = object::id(player);
    let slot = StorageSlot { item: borrow::new(item, ctx), locks: vec_set::empty() };
    df::add(player.uid_mut(), SlotKey(item_id), slot);
    emit(ItemStoredEvent<Item> { player_id, item_id });
}

public fun withdraw<Item: key + store>(player: &mut Player, item_id: ID): Item {
    let player_id = object::id(player);
    let StorageSlot<Item> { item, locks } = df::remove(player.uid_mut(), SlotKey(item_id));
    assert!(locks.is_empty(), ELocked);
    emit(ItemWithdrawnEvent<Item> { player_id, item_id });
    item.destroy()
}

public fun borrow<Item: key + store>(player: &mut Player, item_id: ID): (Item, Borrow) {
    let slot: &mut StorageSlot<Item> = df::borrow_mut(player.uid_mut(), SlotKey(item_id));
    slot.item.borrow()
}

public fun put_back<Item: key + store>(player: &mut Player, item: Item, borrow: Borrow) {
    let key = SlotKey(object::id(&item));
    let slot: &mut StorageSlot<Item> = df::borrow_mut(player.uid_mut(), key);
    slot.item.put_back(item, borrow)
}

public fun lock<Item: key + store, Locker: drop>(
    player: &mut Player,
    item_id: ID,
    _: Locker,
): Lock<Item, Locker> {
    let player_id = object::id(player);
    let slot: &mut StorageSlot<Item> = df::borrow_mut(player.uid_mut(), SlotKey(item_id));
    let locker = type_name::with_defining_ids<Locker>();
    assert!(!slot.locks.contains(&locker), EAlreadyLocked);
    assert!(slot.locks.length() < MAX_LOCKS, ETooManyLocks);
    slot.locks.insert(locker);
    emit(ItemLockedEvent<Item, Locker> { player_id, item_id });
    Lock()
}

public fun unlock<Item: key + store, Locker>(
    player: &mut Player,
    item_id: ID,
    lock: Lock<Item, Locker>,
) {
    let Lock() = lock;
    let player_id = object::id(player);
    let slot: &mut StorageSlot<Item> = df::borrow_mut(player.uid_mut(), SlotKey(item_id));
    slot.locks.remove(&type_name::with_defining_ids<Locker>());
    emit(ItemUnlockedEvent<Item, Locker> { player_id, item_id });
}

// === View Functions ===

public fun has_item(player: &Player, item_id: ID): bool {
    df::exists(player.uid(), SlotKey(item_id))
}

public fun locks<Item: key + store>(player: &Player, item_id: ID): &VecSet<TypeName> {
    let slot: &StorageSlot<Item> = df::borrow(player.uid(), SlotKey(item_id));
    &slot.locks
}

public fun max_locks(): u64 {
    MAX_LOCKS
}

// === Test Functions ===

#[test_only]
public fun item_stored_fields_for_testing<Item>(event: &ItemStoredEvent<Item>): (ID, ID) {
    (event.player_id, event.item_id)
}

#[test_only]
public fun item_withdrawn_fields_for_testing<Item>(event: &ItemWithdrawnEvent<Item>): (ID, ID) {
    (event.player_id, event.item_id)
}

#[test_only]
public fun item_locked_fields_for_testing<Item, Locker>(
    event: &ItemLockedEvent<Item, Locker>,
): (ID, ID) {
    (event.player_id, event.item_id)
}

#[test_only]
public fun item_unlocked_fields_for_testing<Item, Locker>(
    event: &ItemUnlockedEvent<Item, Locker>,
): (ID, ID) {
    (event.player_id, event.item_id)
}
