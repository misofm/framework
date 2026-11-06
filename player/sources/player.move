// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module player::player;

use sui::event::emit;

// === Structs ===

public struct Player has key, store {
    id: UID,
    number: u64,
}

public struct PlayerRegistry has key {
    id: UID,
    count: u64,
}

// === Events ===

public struct PlayerCreatedEvent has copy, drop {
    player_id: ID,
    number: u64,
}

// === Init Function ===

fun init(ctx: &mut TxContext) {
    transfer::share_object(PlayerRegistry { id: object::new(ctx), count: 0 });
}

// === Public Functions ===

public fun new(registry: &mut PlayerRegistry, ctx: &mut TxContext): Player {
    registry.count = registry.count + 1;
    let number = registry.count;
    let player = Player { id: object::new(ctx), number };
    emit(PlayerCreatedEvent { player_id: object::id(&player), number });
    player
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

// === Test Functions ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx)
}

#[test_only]
public fun player_created_fields_for_testing(event: &PlayerCreatedEvent): (ID, u64) {
    (event.player_id, event.number)
}
