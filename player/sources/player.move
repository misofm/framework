// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module player::player;

use sui::event::emit;

// === Structs ===

public struct Player has key, store {
    id: UID,
}

// === Events ===

public struct PlayerCreatedEvent has copy, drop {
    player_id: ID,
}

// === Public Functions ===

public fun new(ctx: &mut TxContext): Player {
    let player = Player { id: object::new(ctx) };
    emit(PlayerCreatedEvent { player_id: object::id(&player) });
    player
}

public fun uid_mut(self: &mut Player): &mut UID {
    &mut self.id
}

// === View Functions ===

public fun uid(self: &Player): &UID {
    &self.id
}

// === Test Functions ===

#[test_only]
public fun player_created_fields_for_testing(event: &PlayerCreatedEvent): ID {
    event.player_id
}
