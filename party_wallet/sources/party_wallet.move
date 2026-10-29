// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module party_wallet::party_wallet;

use hikida::hikida;
use miso_party::party::{Party, PartyAdminCap};
use sui::{balance::Balance, coin::Coin, event::emit, transfer::Receiving};

// === Errors ===

const EEmptyCoins: u64 = 0;
const EZeroValue: u64 = 1;

// === Events ===

public struct PartyObjectReceivedEvent<phantom Item> has copy, drop {
    party_id: ID,
    object_id: ID,
}

public struct PartyCoinsReceivedEvent<phantom Currency> has copy, drop {
    party_id: ID,
    value: u64,
    coins: u64,
}

public struct PartyFundsRedeemedEvent<phantom Currency> has copy, drop {
    party_id: ID,
    value: u64,
}

// === View Functions ===

public fun inbox_address(party: &Party): address {
    object::id(party).to_address()
}

// === Admin Functions ===

public fun receive<Item: key + store>(
    party: &mut Party,
    cap: &PartyAdminCap,
    object_to_receive: Receiving<Item>,
): Item {
    let party_id = object::id(party);
    let received = transfer::public_receive(party.uid_mut(cap), object_to_receive);
    emit(PartyObjectReceivedEvent<Item> { party_id, object_id: object::id(&received) });
    received
}

public fun receive_balance<Currency>(
    party: &mut Party,
    cap: &PartyAdminCap,
    coins: vector<Receiving<Coin<Currency>>>,
): Balance<Currency> {
    assert!(!coins.is_empty(), EEmptyCoins);
    let party_id = object::id(party);
    let count = coins.length();
    let balance = hikida::receive_coins_as_balance(party.uid_mut(cap), coins);
    emit(PartyCoinsReceivedEvent<Currency> { party_id, value: balance.value(), coins: count });
    balance
}

public fun redeem_balance<Currency>(
    party: &mut Party,
    cap: &PartyAdminCap,
    value: u64,
): Balance<Currency> {
    let party_id = object::id(party);
    let uid = party.uid_mut(cap);
    assert!(value > 0, EZeroValue);
    let balance = hikida::redeem_balance<Currency>(uid, value);
    emit(PartyFundsRedeemedEvent<Currency> { party_id, value: balance.value() });
    balance
}

// === Test Functions ===

#[test_only]
public fun party_object_received_fields_for_testing<Item>(
    event: &PartyObjectReceivedEvent<Item>,
): (ID, ID) {
    (event.party_id, event.object_id)
}

#[test_only]
public fun party_coins_received_fields_for_testing<Currency>(
    event: &PartyCoinsReceivedEvent<Currency>,
): (ID, u64, u64) {
    (event.party_id, event.value, event.coins)
}

#[test_only]
public fun party_funds_redeemed_fields_for_testing<Currency>(
    event: &PartyFundsRedeemedEvent<Currency>,
): (ID, u64) {
    (event.party_id, event.value)
}
