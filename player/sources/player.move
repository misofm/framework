// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module player::player;

use sui::{derived_object, event::emit};

// === Structs ===

public struct Player has key {
    id: UID,
    number: u64,
}

public struct PlayerRegistry has key {
    id: UID,
    count: u64,
}

public struct PlayerKey(address) has copy, drop, store;

// === Events ===

public struct PlayerCreatedEvent has copy, drop {
    player_id: ID,
    owner: address,
    number: u64,
}

// === Init Function ===

fun init(ctx: &mut TxContext) {
    transfer::share_object(PlayerRegistry { id: object::new(ctx), count: 0 });
}

// === Public Functions ===

public fun new(registry: &mut PlayerRegistry, ctx: &mut TxContext) {
    let owner = ctx.sender();
    registry.count = registry.count + 1;
    let number = registry.count;
    let player = Player { id: derived_object::claim(&mut registry.id, PlayerKey(owner)), number };
    emit(PlayerCreatedEvent { player_id: object::id(&player), owner, number });
    transfer::transfer(player, owner);
}

public fun uid_mut(self: &mut Player): &mut UID {
    &mut self.id
}

// === View Functions ===

public fun uid(self: &Player): &UID {
    &self.id
}

public fun number(self: &Player): u64 {
    self.number
}

public fun count(registry: &PlayerRegistry): u64 {
    registry.count
}

public fun derive_address(registry: &PlayerRegistry, owner: address): address {
    derived_object::derive_address(registry.id.to_inner(), PlayerKey(owner))
}

// === Test Functions ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx)
}

#[test_only]
public fun player_created_fields_for_testing(event: &PlayerCreatedEvent): (ID, address, u64) {
    (event.player_id, event.owner, event.number)
}
