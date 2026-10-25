// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module royalty_advance_recoup::recoup;

// === Imports ===

use std::type_name;
use sui::accumulator::AccumulatorRoot;
use sui::balance::Balance;
use sui::clock::Clock;
use sui::event::emit;
use royalty_pool::pool::RoyaltyPool;
use royalty_pool::stake::Stake;
use royalty_advance::advance::{Self, RoyaltyAdvance};

// === Errors ===

const EZeroAmount: u64 = 0;
const EOfferExpired: u64 = 1;
const ENotProvider: u64 = 2;
const ENotRecouped: u64 = 3;
const EWrongBuyout: u64 = 4;

// === Structs ===

public struct Recoup has store {
    amount: u64,
    claimed: u64,
    offer_expires_at_ms: u64,
}

public struct RecoupPolicy() has drop;

// === Events ===

public struct RecoupBoughtOutEvent has copy, drop {
    advance_id: ID,
    value: u64,
}

// === Public Functions ===

public fun offer<Share, Currency>(
    payment: Balance<Currency>,
    provider: address,
    beneficiary: address,
    shares: u64,
    amount: u64,
    offer_expires_at_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(amount > 0, EZeroAmount);
    assert!(offer_expires_at_ms > clock.timestamp_ms(), EOfferExpired);
    advance::new<Share, Currency, RecoupPolicy, Recoup>(
        RecoupPolicy(),
        payment,
        Recoup { amount, claimed: 0, offer_expires_at_ms },
        provider,
        beneficiary,
        shares,
        ctx,
    );
}

public fun accept<Share, Currency>(
    advance: &mut RoyaltyAdvance<Share, Currency, RecoupPolicy>,
    stake: Stake<Share>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(clock.timestamp_ms() < recoup(advance).offer_expires_at_ms, EOfferExpired);
    advance.accept(RecoupPolicy(), stake, ctx);
}

public fun cancel<Share, Currency>(
    advance: RoyaltyAdvance<Share, Currency, RecoupPolicy>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(
        ctx.sender() == advance.provider()
            || clock.timestamp_ms() >= recoup(&advance).offer_expires_at_ms,
        ENotProvider,
    );
    let Recoup { .. } = advance.cancel(RecoupPolicy());
}

public fun claim<Share, Currency, PoolCurrency>(
    advance: &mut RoyaltyAdvance<Share, Currency, RecoupPolicy>,
    pool: &mut RoyaltyPool<Share, PoolCurrency>,
    root: &AccumulatorRoot,
    clock: &Clock,
) {
    pool.settle(root, clock);
    let pending = pool.pending_royalties(advance.stake());
    if (pending == 0) return;
    let mut provider_value = 0;
    if (type_name::with_defining_ids<PoolCurrency>() == type_name::with_defining_ids<Currency>()) {
        let recoup = advance::config_mut<Share, Currency, RecoupPolicy, Recoup>(
            advance,
            RecoupPolicy(),
        );
        provider_value = pending.min(recoup.amount - recoup.claimed);
        recoup.claimed = recoup.claimed + provider_value;
    };
    advance.claim(RecoupPolicy(), pool, provider_value);
}

public fun release<Share, Currency>(advance: RoyaltyAdvance<Share, Currency, RecoupPolicy>) {
    assert!(remaining(&advance) == 0, ENotRecouped);
    let Recoup { .. } = advance.release(RecoupPolicy());
}

public fun buyout<Share, Currency>(
    advance: RoyaltyAdvance<Share, Currency, RecoupPolicy>,
    payment: Balance<Currency>,
) {
    let value = payment.value();
    assert!(value == remaining(&advance), EWrongBuyout);
    if (value > 0) payment.send_funds(advance.provider()) else payment.destroy_zero();
    emit(RecoupBoughtOutEvent { advance_id: object::id(&advance), value });
    let Recoup { .. } = advance.release(RecoupPolicy());
}

public fun waive<Share, Currency>(
    advance: RoyaltyAdvance<Share, Currency, RecoupPolicy>,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == advance.provider(), ENotProvider);
    let Recoup { .. } = advance.release(RecoupPolicy());
}

// === View Functions ===

public fun amount<Share, Currency>(advance: &RoyaltyAdvance<Share, Currency, RecoupPolicy>): u64 {
    recoup(advance).amount
}

public fun claimed<Share, Currency>(advance: &RoyaltyAdvance<Share, Currency, RecoupPolicy>): u64 {
    recoup(advance).claimed
}

public fun remaining<Share, Currency>(
    advance: &RoyaltyAdvance<Share, Currency, RecoupPolicy>,
): u64 {
    let recoup = recoup(advance);
    recoup.amount - recoup.claimed
}

public fun offer_expires_at_ms<Share, Currency>(
    advance: &RoyaltyAdvance<Share, Currency, RecoupPolicy>,
): u64 {
    recoup(advance).offer_expires_at_ms
}

// === Private Functions ===

fun recoup<Share, Currency>(advance: &RoyaltyAdvance<Share, Currency, RecoupPolicy>): &Recoup {
    advance.config()
}

// === Test Functions ===

#[test_only]
public fun bought_out_event_fields(event: &RecoupBoughtOutEvent): (ID, u64) {
    (event.advance_id, event.value)
}
