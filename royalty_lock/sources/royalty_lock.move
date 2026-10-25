// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module royalty_lock::royalty_lock;

// === Imports ===

use std::type_name;
use sui::accumulator::AccumulatorRoot;
use sui::balance::Balance;
use sui::clock::Clock;
use sui::event::emit;
use bps::bps::BPS;
use royalty_pool::pool::RoyaltyPool;
use royalty_pool::stake::Stake;

// === Errors ===

const EZeroRecipientShare: u64 = 0;
const EZeroAmount: u64 = 1;
const EZeroDuration: u64 = 2;
const ENoTerms: u64 = 3;
const ENotOwner: u64 = 4;
const ENotRecipient: u64 = 5;
const ENotUnlockable: u64 = 6;
const ENoAmount: u64 = 7;
const EWrongBuyout: u64 = 8;

// === Structs ===

public struct RoyaltyLock<phantom Share, phantom Currency> has key {
    id: UID,
    stake: Stake<Share>,
    owner: address,
    recipient: address,
    recipient_share: BPS,
    amount: Option<u64>,
    claimed: u64,
    ends_at_ms: Option<u64>,
}

public struct RoyaltyLockOwnerReceipt has key {
    id: UID,
    lock_id: ID,
}

public struct RoyaltyLockRecipientReceipt has key {
    id: UID,
    lock_id: ID,
}

public struct RoyaltyLockTerms has copy, drop, store {
    recipient_share: BPS,
    amount: Option<u64>,
    duration_ms: Option<u64>,
}

// === Events ===

public struct RoyaltyLockCreatedEvent<phantom Share, phantom Currency> has copy, drop {
    lock_id: ID,
    stake_id: ID,
    shares: u64,
    owner: address,
    recipient: address,
    recipient_share_bps: u16,
    amount: Option<u64>,
    ends_at_ms: Option<u64>,
}

public struct RoyaltyLockClaimedEvent<phantom PoolCurrency> has copy, drop {
    lock_id: ID,
    pool_id: ID,
    recipient_value: u64,
    owner_value: u64,
    claimed: u64,
}

public struct RoyaltyLockUnlockedEvent has copy, drop {
    lock_id: ID,
    stake_id: ID,
}

public struct RoyaltyLockBoughtOutEvent has copy, drop {
    lock_id: ID,
    stake_id: ID,
    value: u64,
}

public struct RoyaltyLockWaivedEvent has copy, drop {
    lock_id: ID,
    stake_id: ID,
}

public struct RoyaltyLockOwnerChangedEvent has copy, drop {
    lock_id: ID,
    owner: address,
}

public struct RoyaltyLockRecipientChangedEvent has copy, drop {
    lock_id: ID,
    recipient: address,
}

// === Method Aliases ===

public use fun owner_receipt_lock_id as RoyaltyLockOwnerReceipt.lock_id;
public use fun recipient_receipt_lock_id as RoyaltyLockRecipientReceipt.lock_id;
public use fun terms_recipient_share as RoyaltyLockTerms.recipient_share;
public use fun terms_amount as RoyaltyLockTerms.amount;
public use fun terms_duration_ms as RoyaltyLockTerms.duration_ms;

// === Public Functions ===

public fun new_terms(
    recipient_share: BPS,
    amount: Option<u64>,
    duration_ms: Option<u64>,
): RoyaltyLockTerms {
    assert!(!recipient_share.is_zero(), EZeroRecipientShare);
    assert!(amount.is_none_or!(|amount| *amount > 0), EZeroAmount);
    assert!(duration_ms.is_none_or!(|duration_ms| *duration_ms > 0), EZeroDuration);
    assert!(amount.is_some() || duration_ms.is_some(), ENoTerms);
    RoyaltyLockTerms { recipient_share, amount, duration_ms }
}

public fun new<Share, Currency>(
    stake: Stake<Share>,
    owner: address,
    recipient: address,
    terms: RoyaltyLockTerms,
    clock: &Clock,
    ctx: &mut TxContext,
): RoyaltyLock<Share, Currency> {
    let RoyaltyLockTerms { recipient_share, amount, duration_ms } = terms;
    let now = clock.timestamp_ms();
    let ends_at_ms = duration_ms.map!(|duration_ms| now + duration_ms);
    let id = object::new(ctx);
    emit(RoyaltyLockCreatedEvent<Share, Currency> {
        lock_id: id.to_inner(),
        stake_id: object::id(&stake),
        shares: stake.value(),
        owner,
        recipient,
        recipient_share_bps: recipient_share.value(),
        amount,
        ends_at_ms,
    });
    RoyaltyLock {
        id,
        stake,
        owner,
        recipient,
        recipient_share,
        amount,
        claimed: 0,
        ends_at_ms,
    }
}

public fun share<Share, Currency>(self: RoyaltyLock<Share, Currency>, ctx: &mut TxContext) {
    let lock_id = self.id.to_inner();
    transfer::transfer(RoyaltyLockOwnerReceipt { id: object::new(ctx), lock_id }, self.owner);
    transfer::transfer(
        RoyaltyLockRecipientReceipt { id: object::new(ctx), lock_id },
        self.recipient,
    );
    transfer::share_object(self);
}

public fun claim<Share, Currency, PoolCurrency>(
    self: &mut RoyaltyLock<Share, Currency>,
    pool: &mut RoyaltyPool<Share, PoolCurrency>,
    root: &AccumulatorRoot,
    clock: &Clock,
) {
    pool.settle(root, clock);
    if (!self.stake.has_registration(object::id(pool))) return;
    let mut royalties = pool.claim_royalties(&mut self.stake);
    let value = royalties.value();
    if (value == 0) return royalties.destroy_zero();
    let now = clock.timestamp_ms();
    let mut recipient_value = if (self.ends_at_ms.is_none_or!(|ends_at_ms| now < *ends_at_ms)) {
        self.recipient_share.apply(value)
    } else 0;
    if (self.amount.is_some()) {
        if (
            type_name::with_defining_ids<PoolCurrency>() == type_name::with_defining_ids<Currency>()
        ) {
            recipient_value = recipient_value.min(*self.amount.borrow() - self.claimed);
            self.claimed = self.claimed + recipient_value;
        } else recipient_value = 0;
    };
    let owner_value = value - recipient_value;
    if (recipient_value > 0) royalties.split(recipient_value).send_funds(self.recipient);
    if (owner_value > 0) royalties.send_funds(self.owner) else royalties.destroy_zero();
    emit(RoyaltyLockClaimedEvent<PoolCurrency> {
        lock_id: self.id.to_inner(),
        pool_id: object::id(pool),
        recipient_value,
        owner_value,
        claimed: self.claimed,
    });
}

public fun unlock<Share, Currency>(self: RoyaltyLock<Share, Currency>, clock: &Clock) {
    assert!(self.is_unlockable(clock), ENotUnlockable);
    let (lock_id, stake_id) = return_stake(self);
    emit(RoyaltyLockUnlockedEvent { lock_id, stake_id });
}

public fun buyout<Share, Currency>(self: RoyaltyLock<Share, Currency>, payment: Balance<Currency>) {
    assert!(self.amount.is_some(), ENoAmount);
    let value = payment.value();
    assert!(value == *self.amount.borrow() - self.claimed, EWrongBuyout);
    if (value > 0) payment.send_funds(self.recipient) else payment.destroy_zero();
    let (lock_id, stake_id) = return_stake(self);
    emit(RoyaltyLockBoughtOutEvent { lock_id, stake_id, value });
}

public fun waive<Share, Currency>(self: RoyaltyLock<Share, Currency>, ctx: &mut TxContext) {
    assert!(ctx.sender() == self.recipient, ENotRecipient);
    let (lock_id, stake_id) = return_stake(self);
    emit(RoyaltyLockWaivedEvent { lock_id, stake_id });
}

public fun register<Share, Currency, PoolCurrency>(
    self: &mut RoyaltyLock<Share, Currency>,
    pool: &mut RoyaltyPool<Share, PoolCurrency>,
    root: &AccumulatorRoot,
    clock: &Clock,
) {
    pool.register_stake(&mut self.stake, root, clock);
}

public fun set_owner<Share, Currency>(
    self: &mut RoyaltyLock<Share, Currency>,
    owner: address,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == self.owner, ENotOwner);
    self.owner = owner;
    let lock_id = self.id.to_inner();
    transfer::transfer(RoyaltyLockOwnerReceipt { id: object::new(ctx), lock_id }, owner);
    emit(RoyaltyLockOwnerChangedEvent { lock_id, owner });
}

public fun set_recipient<Share, Currency>(
    self: &mut RoyaltyLock<Share, Currency>,
    recipient: address,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == self.recipient, ENotRecipient);
    self.recipient = recipient;
    let lock_id = self.id.to_inner();
    transfer::transfer(RoyaltyLockRecipientReceipt { id: object::new(ctx), lock_id }, recipient);
    emit(RoyaltyLockRecipientChangedEvent { lock_id, recipient });
}

public fun destroy_owner_receipt(receipt: RoyaltyLockOwnerReceipt) {
    let RoyaltyLockOwnerReceipt { id, lock_id: _ } = receipt;
    id.delete();
}

public fun destroy_recipient_receipt(receipt: RoyaltyLockRecipientReceipt) {
    let RoyaltyLockRecipientReceipt { id, lock_id: _ } = receipt;
    id.delete();
}

// === View Functions ===

public fun stake<Share, Currency>(self: &RoyaltyLock<Share, Currency>): &Stake<Share> {
    &self.stake
}

public fun owner<Share, Currency>(self: &RoyaltyLock<Share, Currency>): address {
    self.owner
}

public fun recipient<Share, Currency>(self: &RoyaltyLock<Share, Currency>): address {
    self.recipient
}

public fun recipient_share<Share, Currency>(self: &RoyaltyLock<Share, Currency>): BPS {
    self.recipient_share
}

public fun amount<Share, Currency>(self: &RoyaltyLock<Share, Currency>): Option<u64> {
    self.amount
}

public fun claimed<Share, Currency>(self: &RoyaltyLock<Share, Currency>): u64 {
    self.claimed
}

public fun remaining<Share, Currency>(self: &RoyaltyLock<Share, Currency>): Option<u64> {
    self.amount.map_ref!(|amount| *amount - self.claimed)
}

public fun ends_at_ms<Share, Currency>(self: &RoyaltyLock<Share, Currency>): Option<u64> {
    self.ends_at_ms
}

public fun is_unlockable<Share, Currency>(
    self: &RoyaltyLock<Share, Currency>,
    clock: &Clock,
): bool {
    self.amount.is_some_and!(|amount| self.claimed == *amount)
        || self.ends_at_ms.is_some_and!(|ends_at_ms| clock.timestamp_ms() >= *ends_at_ms)
}

public fun owner_receipt_lock_id(receipt: &RoyaltyLockOwnerReceipt): ID {
    receipt.lock_id
}

public fun recipient_receipt_lock_id(receipt: &RoyaltyLockRecipientReceipt): ID {
    receipt.lock_id
}

public fun terms_recipient_share(terms: &RoyaltyLockTerms): BPS {
    terms.recipient_share
}

public fun terms_amount(terms: &RoyaltyLockTerms): Option<u64> {
    terms.amount
}

public fun terms_duration_ms(terms: &RoyaltyLockTerms): Option<u64> {
    terms.duration_ms
}

// === Private Functions ===

fun return_stake<Share, Currency>(self: RoyaltyLock<Share, Currency>): (ID, ID) {
    let RoyaltyLock { id, stake, owner, .. } = self;
    let lock_id = id.to_inner();
    let stake_id = object::id(&stake);
    transfer::public_transfer(stake, owner);
    id.delete();
    (lock_id, stake_id)
}

// === Test Functions ===

#[test_only]
public fun created_event_fields<Share, Currency>(
    event: &RoyaltyLockCreatedEvent<Share, Currency>,
): (ID, ID, u64, address, address, u16, Option<u64>, Option<u64>) {
    (
        event.lock_id,
        event.stake_id,
        event.shares,
        event.owner,
        event.recipient,
        event.recipient_share_bps,
        event.amount,
        event.ends_at_ms,
    )
}

#[test_only]
public fun claimed_event_fields<PoolCurrency>(
    event: &RoyaltyLockClaimedEvent<PoolCurrency>,
): (ID, ID, u64, u64, u64) {
    (event.lock_id, event.pool_id, event.recipient_value, event.owner_value, event.claimed)
}

#[test_only]
public fun unlocked_event_fields(event: &RoyaltyLockUnlockedEvent): (ID, ID) {
    (event.lock_id, event.stake_id)
}

#[test_only]
public fun bought_out_event_fields(event: &RoyaltyLockBoughtOutEvent): (ID, ID, u64) {
    (event.lock_id, event.stake_id, event.value)
}

#[test_only]
public fun waived_event_fields(event: &RoyaltyLockWaivedEvent): (ID, ID) {
    (event.lock_id, event.stake_id)
}

#[test_only]
public fun owner_changed_event_fields(event: &RoyaltyLockOwnerChangedEvent): (ID, address) {
    (event.lock_id, event.owner)
}

#[test_only]
public fun recipient_changed_event_fields(
    event: &RoyaltyLockRecipientChangedEvent,
): (ID, address) {
    (event.lock_id, event.recipient)
}
