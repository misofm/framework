// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module royalty_advance_term::term;

// === Imports ===

use sui::accumulator::AccumulatorRoot;
use sui::balance::Balance;
use sui::clock::Clock;
use royalty_pool::pool::RoyaltyPool;
use royalty_pool::stake::Stake;
use royalty_advance::advance::{Self, RoyaltyAdvance};

// === Errors ===

const EZeroDuration: u64 = 0;
const EOfferExpired: u64 = 1;
const ENotProvider: u64 = 2;
const ETermNotEnded: u64 = 3;

// === Structs ===

public struct Term has store {
    duration_ms: u64,
    ends_at_ms: u64,
    offer_expires_at_ms: u64,
}

public struct TermPolicy() has drop;

// === Public Functions ===

public fun offer<Share, Currency>(
    payment: Balance<Currency>,
    provider: address,
    beneficiary: address,
    shares: u64,
    duration_ms: u64,
    offer_expires_at_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(duration_ms > 0, EZeroDuration);
    assert!(offer_expires_at_ms > clock.timestamp_ms(), EOfferExpired);
    advance::new<Share, Currency, TermPolicy, Term>(
        TermPolicy(),
        payment,
        Term { duration_ms, ends_at_ms: 0, offer_expires_at_ms },
        provider,
        beneficiary,
        shares,
        ctx,
    );
}

public fun accept<Share, Currency>(
    advance: &mut RoyaltyAdvance<Share, Currency, TermPolicy>,
    stake: Stake<Share>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let now = clock.timestamp_ms();
    let term = advance::config_mut<Share, Currency, TermPolicy, Term>(advance, TermPolicy());
    assert!(now < term.offer_expires_at_ms, EOfferExpired);
    term.ends_at_ms = now + term.duration_ms;
    advance.accept(TermPolicy(), stake, ctx);
}

public fun cancel<Share, Currency>(
    advance: RoyaltyAdvance<Share, Currency, TermPolicy>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(
        ctx.sender() == advance.provider()
            || clock.timestamp_ms() >= term(&advance).offer_expires_at_ms,
        ENotProvider,
    );
    let Term { .. } = advance.cancel(TermPolicy());
}

public fun claim<Share, Currency, PoolCurrency>(
    advance: &mut RoyaltyAdvance<Share, Currency, TermPolicy>,
    pool: &mut RoyaltyPool<Share, PoolCurrency>,
    root: &AccumulatorRoot,
    clock: &Clock,
) {
    pool.settle(root, clock);
    let pending = pool.pending_royalties(advance.stake());
    if (pending == 0) return;
    let provider_value = if (clock.timestamp_ms() < term(advance).ends_at_ms) pending else 0;
    advance.claim(TermPolicy(), pool, provider_value);
}

public fun release<Share, Currency>(
    advance: RoyaltyAdvance<Share, Currency, TermPolicy>,
    clock: &Clock,
) {
    assert!(clock.timestamp_ms() >= term(&advance).ends_at_ms, ETermNotEnded);
    let Term { .. } = advance.release(TermPolicy());
}

// === View Functions ===

public fun duration_ms<Share, Currency>(
    advance: &RoyaltyAdvance<Share, Currency, TermPolicy>,
): u64 {
    term(advance).duration_ms
}

public fun ends_at_ms<Share, Currency>(advance: &RoyaltyAdvance<Share, Currency, TermPolicy>): u64 {
    term(advance).ends_at_ms
}

public fun offer_expires_at_ms<Share, Currency>(
    advance: &RoyaltyAdvance<Share, Currency, TermPolicy>,
): u64 {
    term(advance).offer_expires_at_ms
}

// === Private Functions ===

fun term<Share, Currency>(advance: &RoyaltyAdvance<Share, Currency, TermPolicy>): &Term {
    advance.config()
}
