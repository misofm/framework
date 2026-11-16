// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module player::player;

use sui::{derived_object, event::emit};

// === Structs ===

public struct PlayerRegistry has key {
    id: UID,
}

public struct Player has key {
    id: UID,
    owner: address,
}

public struct PlayerKey(address) has copy, drop, store;

// === Events ===

public struct PlayerCreatedEvent has copy, drop {
    player_id: ID,
    owner: address,
}

// === Init Function ===

fun init(ctx: &mut TxContext) {
    transfer::share_object(PlayerRegistry { id: object::new(ctx) });
}

// === Public Functions ===

public fun new(registry: &mut PlayerRegistry, ctx: &mut TxContext): Player {
    let owner = ctx.sender();
    let player = Player { id: derived_object::claim(&mut registry.id, PlayerKey(owner)), owner };
    emit(PlayerCreatedEvent { player_id: object::id(&player), owner });
    player
}

public fun keep(self: Player) {
    let owner = self.owner;
    transfer::transfer(self, owner);
}

public fun uid_mut(self: &mut Player): &mut UID {
    &mut self.id
}

// === View Functions ===

public fun uid(self: &Player): &UID {
    &self.id
}

public fun owner(self: &Player): address {
    self.owner
}

public fun derive_address(registry: &PlayerRegistry, owner: address): address {
    derived_object::derive_address(object::id(registry), PlayerKey(owner))
}

// === Test Functions ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx)
}

#[test_only]
public fun new_for_testing(ctx: &mut TxContext): Player {
    Player { id: object::new(ctx), owner: ctx.sender() }
}

#[test_only]
public fun player_created_fields_for_testing(event: &PlayerCreatedEvent): (ID, address) {
    (event.player_id, event.owner)
}
