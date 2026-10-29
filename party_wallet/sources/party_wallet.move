// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module party_wallet::party_wallet;

use hikida::hikida;
use miso_party::party::{Party, PartyAdminCap};
use sui::{balance::Balance, coin::Coin, event::emit, transfer::Receiving};

// === Errors ===

const ENothingToReceive: u64 = 0;
const ENoValueToRedeem: u64 = 1;

// === Events ===

public struct PartyObjectReceivedEvent<phantom Item> has copy, drop {
    party_id: ID,
    object_id: ID,
}

public struct PartyCoinsReceivedEvent<phantom Currency> has copy, drop {
    party_id: ID,
    amount: u64,
    coins: u64,
}

public struct PartyFundsRedeemedEvent<phantom Currency> has copy, drop {
    party_id: ID,
    amount: u64,
}

// === View Functions ===

public fun inbox_address(party: &Party): address {
    object::id(party).to_address()
}

// === Admin Functions ===

public fun receive<Item: key + store>(
    party: &mut Party,
    admin_cap: &PartyAdminCap,
    object_to_receive: Receiving<Item>,
): Item {
    let party_id = object::id(party);
    let received = transfer::public_receive(party.uid_mut(admin_cap), object_to_receive);
    emit(PartyObjectReceivedEvent<Item> { party_id, object_id: object::id(&received) });
    received
}

public fun receive_balance<Currency>(
    party: &mut Party,
    admin_cap: &PartyAdminCap,
    coins: vector<Receiving<Coin<Currency>>>,
): Balance<Currency> {
    assert!(!coins.is_empty(), ENothingToReceive);
    let party_id = object::id(party);
    let count = coins.length();
    let balance = hikida::receive_coins_as_balance(party.uid_mut(admin_cap), coins);
    emit(PartyCoinsReceivedEvent<Currency> { party_id, amount: balance.value(), coins: count });
    balance
}

public fun redeem_balance<Currency>(
    party: &mut Party,
    admin_cap: &PartyAdminCap,
    value: u64,
): Balance<Currency> {
    let party_id = object::id(party);
    let uid = party.uid_mut(admin_cap);
    assert!(value > 0, ENoValueToRedeem);
    let balance = hikida::redeem_balance<Currency>(uid, value);
    emit(PartyFundsRedeemedEvent<Currency> { party_id, amount: balance.value() });
    balance
}

// === Test Functions ===

#[test_only]
public fun object_received_event_fields<Item>(event: &PartyObjectReceivedEvent<Item>): (ID, ID) {
    (event.party_id, event.object_id)
}

#[test_only]
public fun coins_received_event_fields<Currency>(
    event: &PartyCoinsReceivedEvent<Currency>,
): (ID, u64, u64) {
    (event.party_id, event.amount, event.coins)
}

#[test_only]
public fun funds_redeemed_event_fields<Currency>(
    event: &PartyFundsRedeemedEvent<Currency>,
): (ID, u64) {
    (event.party_id, event.amount)
}
