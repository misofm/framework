// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module player_wallet::player_wallet;

use hikida::hikida;
use player::player::Player;
use sui::{balance::Balance, coin::Coin, event::emit, transfer::Receiving};

// === Errors ===

const EEmptyCoins: u64 = 0;
const EZeroValue: u64 = 1;

// === Events ===

public struct PlayerObjectReceivedEvent<phantom Item> has copy, drop {
    player_id: ID,
    object_id: ID,
}

public struct PlayerCoinsReceivedEvent<phantom Currency> has copy, drop {
    player_id: ID,
    value: u64,
    coins: u64,
}

public struct PlayerFundsRedeemedEvent<phantom Currency> has copy, drop {
    player_id: ID,
    value: u64,
}

// === Public Functions ===

public fun receive<Item: key + store>(
    player: &mut Player,
    object_to_receive: Receiving<Item>,
): Item {
    let player_id = object::id(player);
    let received = transfer::public_receive(player.uid_mut(), object_to_receive);
    emit(PlayerObjectReceivedEvent<Item> { player_id, object_id: object::id(&received) });
    received
}

public fun receive_balance<Currency>(
    player: &mut Player,
    coins: vector<Receiving<Coin<Currency>>>,
): Balance<Currency> {
    assert!(!coins.is_empty(), EEmptyCoins);
    let player_id = object::id(player);
    let count = coins.length();
    let balance = hikida::receive_coins_as_balance(player.uid_mut(), coins);
    emit(PlayerCoinsReceivedEvent<Currency> { player_id, value: balance.value(), coins: count });
    balance
}

public fun redeem_balance<Currency>(player: &mut Player, value: u64): Balance<Currency> {
    assert!(value > 0, EZeroValue);
    let player_id = object::id(player);
    let balance = hikida::redeem_balance<Currency>(player.uid_mut(), value);
    emit(PlayerFundsRedeemedEvent<Currency> { player_id, value: balance.value() });
    balance
}

// === View Functions ===

public fun inbox_address(player: &Player): address {
    object::id(player).to_address()
}

// === Test Functions ===

#[test_only]
public fun player_object_received_fields_for_testing<Item>(
    event: &PlayerObjectReceivedEvent<Item>,
): (ID, ID) {
    (event.player_id, event.object_id)
}

#[test_only]
public fun player_coins_received_fields_for_testing<Currency>(
    event: &PlayerCoinsReceivedEvent<Currency>,
): (ID, u64, u64) {
    (event.player_id, event.value, event.coins)
}

#[test_only]
public fun player_funds_redeemed_fields_for_testing<Currency>(
    event: &PlayerFundsRedeemedEvent<Currency>,
): (ID, u64) {
    (event.player_id, event.value)
}
