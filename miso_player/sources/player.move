// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module miso_player::player;

use sui::{derived_object, event::emit};

// === Structs ===

public struct Player has key {
    id: UID,
}

public struct PlayerRegistry has key {
    id: UID,
}

public struct PlayerKey(address) has copy, drop, store;

// === Events ===

public struct PlayerCreatedEvent has copy, drop {
    player_id: ID,
    owner: address,
}

// === Public Functions ===

fun init(ctx: &mut TxContext) {
    transfer::share_object(PlayerRegistry { id: object::new(ctx) });
}

public fun new(registry: &mut PlayerRegistry, ctx: &mut TxContext) {
    let owner = ctx.sender();
    let player = Player { id: derived_object::claim(&mut registry.id, PlayerKey(owner)) };
    emit(PlayerCreatedEvent { player_id: object::id(&player), owner });
    transfer::transfer(player, owner);
}

public fun uid_mut(self: &mut Player): &mut UID {
    &mut self.id
}

// === View Functions ===

public fun uid(self: &Player): &UID {
    &self.id
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
public fun player_created_fields_for_testing(event: &PlayerCreatedEvent): (ID, address) {
    (event.player_id, event.owner)
}
