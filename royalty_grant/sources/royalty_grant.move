// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module royalty_grant::royalty_grant;

use bps::bps::{Self, BPS};
use royalty_pool::{royalty_pool::RoyaltyPool, royalty_pool_stake::RoyaltyPoolStake};
use std::type_name::{Self, TypeName};
use sui::{
    accumulator::AccumulatorRoot,
    balance::Balance,
    clock::Clock,
    derived_object,
    event::emit,
    vec_map::{Self, VecMap}
};

// === Errors ===

const EZeroRecipientShare: u64 = 0;
const EZeroRepaymentValue: u64 = 1;
const EZeroDuration: u64 = 2;
const ENoTerms: u64 = 3;
const EStakeRegistered: u64 = 4;
const EUnauthorized: u64 = 5;
const ENotReclaimable: u64 = 6;
const ENoRepaymentValue: u64 = 7;
const EWrongBuyout: u64 = 8;
const EAlreadyReclaimable: u64 = 9;

// === Structs ===

public struct RoyaltyGrant<phantom Share, phantom Currency> has key {
    id: UID,
    stake: RoyaltyPoolStake<Share>,
    owner: address,
    recipient: address,
    recipient_share: BPS,
    repayment_value: Option<u64>,
    repaid_value: u64,
    remainders: VecMap<TypeName, u64>,
    ends_at_ms: Option<u64>,
}

public struct RoyaltyGrantOwnerCap has key, store {
    id: UID,
    grant_id: ID,
}

public struct RoyaltyGrantRecipientCap has key, store {
    id: UID,
    grant_id: ID,
}

public struct RoyaltyGrantTerms has copy, drop, store {
    recipient_share: BPS,
    repayment_value: Option<u64>,
    duration_ms: Option<u64>,
}

public struct RoyaltyGrantOwnerCapKey() has copy, drop, store;

public struct RoyaltyGrantRecipientCapKey() has copy, drop, store;

// === Events ===

public struct RoyaltyGrantCreatedEvent<phantom Share, phantom Currency> has copy, drop {
    grant_id: ID,
    stake_id: ID,
    pool_id: ID,
    shares: u64,
    owner: address,
    recipient: address,
    recipient_share_bps: u16,
    repayment_value: Option<u64>,
    ends_at_ms: Option<u64>,
}

public struct RoyaltyGrantSweptEvent<phantom PoolCurrency> has copy, drop {
    grant_id: ID,
    pool_id: ID,
    recipient: address,
    recipient_value: u64,
    owner: address,
    owner_value: u64,
    repaid_value: u64,
}

public struct RoyaltyGrantBoughtOutEvent has copy, drop {
    grant_id: ID,
    recipient: address,
    value: u64,
}

public struct RoyaltyGrantReclaimedEvent has copy, drop {
    grant_id: ID,
    stake_id: ID,
}

public struct RoyaltyGrantWaivedEvent has copy, drop {
    grant_id: ID,
    ends_at_ms: u64,
}

public struct RoyaltyGrantOwnerSetEvent has copy, drop {
    grant_id: ID,
    owner: address,
}

public struct RoyaltyGrantRecipientSetEvent has copy, drop {
    grant_id: ID,
    recipient: address,
}

// === Method Aliases ===

public use fun royalty_grant_owner_cap_grant_id as RoyaltyGrantOwnerCap.grant_id;
public use fun royalty_grant_recipient_cap_grant_id as RoyaltyGrantRecipientCap.grant_id;
public use fun royalty_grant_terms_recipient_share as RoyaltyGrantTerms.recipient_share;
public use fun royalty_grant_terms_repayment_value as RoyaltyGrantTerms.repayment_value;
public use fun royalty_grant_terms_duration_ms as RoyaltyGrantTerms.duration_ms;

// === Public Functions ===

public fun new<Share, Currency>(
    pool: &mut RoyaltyPool<Share, Currency>,
    mut stake: RoyaltyPoolStake<Share>,
    owner: address,
    recipient: address,
    terms: RoyaltyGrantTerms,
    root: &AccumulatorRoot,
    clock: &Clock,
    ctx: &mut TxContext,
): (RoyaltyGrant<Share, Currency>, RoyaltyGrantOwnerCap) {
    assert!(stake.pool_ids().is_empty(), EStakeRegistered);
    pool.register_stake(&mut stake, root, clock);
    let RoyaltyGrantTerms { recipient_share, repayment_value, duration_ms } = terms;
    let now = clock.timestamp_ms();
    let ends_at_ms = duration_ms.map!(|duration_ms| now.saturating_add(duration_ms));
    let mut id = object::new(ctx);
    let grant_id = id.to_inner();
    let owner_cap = RoyaltyGrantOwnerCap {
        id: derived_object::claim(&mut id, RoyaltyGrantOwnerCapKey()),
        grant_id,
    };
    let recipient_cap = RoyaltyGrantRecipientCap {
        id: derived_object::claim(&mut id, RoyaltyGrantRecipientCapKey()),
        grant_id,
    };
    emit(RoyaltyGrantCreatedEvent<Share, Currency> {
        grant_id,
        stake_id: object::id(&stake),
        pool_id: object::id(pool),
        shares: stake.value(),
        owner,
        recipient,
        recipient_share_bps: recipient_share.value(),
        repayment_value,
        ends_at_ms,
    });
    transfer::public_transfer(recipient_cap, recipient);
    let grant = RoyaltyGrant {
        id,
        stake,
        owner,
        recipient,
        recipient_share,
        repayment_value,
        repaid_value: 0,
        remainders: vec_map::empty(),
        ends_at_ms,
    };
    (grant, owner_cap)
}

public fun share<Share, Currency>(self: RoyaltyGrant<Share, Currency>) {
    transfer::share_object(self);
}

public fun register<Share, Currency, PoolCurrency>(
    self: &mut RoyaltyGrant<Share, Currency>,
    pool: &mut RoyaltyPool<Share, PoolCurrency>,
    root: &AccumulatorRoot,
    clock: &Clock,
) {
    pool.register_stake(&mut self.stake, root, clock);
}

public fun sweep<Share, Currency, PoolCurrency>(
    self: &mut RoyaltyGrant<Share, Currency>,
    pool: &mut RoyaltyPool<Share, PoolCurrency>,
    root: &AccumulatorRoot,
    clock: &Clock,
): u64 {
    let grant_id = object::id(self);
    let pool_id = object::id(pool);
    if (!self.stake.has_registration(pool_id)) return 0;
    pool.settle(root, clock);
    let mut royalties = pool.claim_royalties(&mut self.stake);
    let value = royalties.value();
    if (value == 0) {
        royalties.destroy_zero();
        return 0
    };
    let now = clock.timestamp_ms();
    let currency = type_name::with_defining_ids<PoolCurrency>();
    let recipient_value = if (self.ends_at_ms.is_some_and!(|ends_at_ms| now >= *ends_at_ms)) 0
    else if (self.repayment_value.is_none()) self.accrue(currency, value)
    else if (currency == type_name::with_defining_ids<Currency>()) {
        let remaining_value = *self.repayment_value.borrow() - self.repaid_value;
        let recipient_value = self.accrue(currency, value).min(remaining_value);
        self.repaid_value = self.repaid_value + recipient_value;
        recipient_value
    } else 0;
    let owner_value = value - recipient_value;
    if (recipient_value > 0) royalties.split(recipient_value).send_funds(self.recipient);
    if (owner_value > 0) royalties.send_funds(self.owner) else royalties.destroy_zero();
    emit(RoyaltyGrantSweptEvent<PoolCurrency> {
        grant_id,
        pool_id,
        recipient: self.recipient,
        recipient_value,
        owner: self.owner,
        owner_value,
        repaid_value: self.repaid_value,
    });
    value
}

public fun buyout<Share, Currency>(
    self: &mut RoyaltyGrant<Share, Currency>,
    payment: Balance<Currency>,
) {
    let value = payment.value();
    assert!(value == self.remaining_value().destroy_or!(abort ENoRepaymentValue), EWrongBuyout);
    if (value > 0) payment.send_funds(self.recipient) else payment.destroy_zero();
    self.repaid_value = *self.repayment_value.borrow();
    emit(RoyaltyGrantBoughtOutEvent {
        grant_id: object::id(self),
        recipient: self.recipient,
        value,
    });
}

public fun destroy_recipient_cap(cap: RoyaltyGrantRecipientCap) {
    let RoyaltyGrantRecipientCap { id, grant_id: _ } = cap;
    id.delete();
}

public fun new_terms(
    recipient_share: BPS,
    repayment_value: Option<u64>,
    duration_ms: Option<u64>,
): RoyaltyGrantTerms {
    assert!(!recipient_share.is_zero(), EZeroRecipientShare);
    assert!(
        repayment_value.is_none_or!(|repayment_value| *repayment_value > 0),
        EZeroRepaymentValue,
    );
    assert!(duration_ms.is_none_or!(|duration_ms| *duration_ms > 0), EZeroDuration);
    assert!(repayment_value.is_some() || duration_ms.is_some(), ENoTerms);
    RoyaltyGrantTerms { recipient_share, repayment_value, duration_ms }
}

// === View Functions ===

public fun stake<Share, Currency>(self: &RoyaltyGrant<Share, Currency>): &RoyaltyPoolStake<Share> {
    &self.stake
}

public fun owner<Share, Currency>(self: &RoyaltyGrant<Share, Currency>): address {
    self.owner
}

public fun recipient<Share, Currency>(self: &RoyaltyGrant<Share, Currency>): address {
    self.recipient
}

public fun recipient_share<Share, Currency>(self: &RoyaltyGrant<Share, Currency>): BPS {
    self.recipient_share
}

public fun repayment_value<Share, Currency>(self: &RoyaltyGrant<Share, Currency>): Option<u64> {
    self.repayment_value
}

public fun repaid_value<Share, Currency>(self: &RoyaltyGrant<Share, Currency>): u64 {
    self.repaid_value
}

public fun remaining_value<Share, Currency>(self: &RoyaltyGrant<Share, Currency>): Option<u64> {
    self.repayment_value.map_ref!(|repayment_value| *repayment_value - self.repaid_value)
}

public fun ends_at_ms<Share, Currency>(self: &RoyaltyGrant<Share, Currency>): Option<u64> {
    self.ends_at_ms
}

public fun is_reclaimable<Share, Currency>(
    self: &RoyaltyGrant<Share, Currency>,
    clock: &Clock,
): bool {
    self.repayment_value.is_some_and!(|repayment_value| self.repaid_value == *repayment_value)
        || self.ends_at_ms.is_some_and!(|ends_at_ms| clock.timestamp_ms() >= *ends_at_ms)
}

public fun derive_owner_cap_address<Share, Currency>(
    self: &RoyaltyGrant<Share, Currency>,
): address {
    derived_object::derive_address(object::id(self), RoyaltyGrantOwnerCapKey())
}

public fun derive_recipient_cap_address<Share, Currency>(
    self: &RoyaltyGrant<Share, Currency>,
): address {
    derived_object::derive_address(object::id(self), RoyaltyGrantRecipientCapKey())
}

public fun royalty_grant_owner_cap_grant_id(cap: &RoyaltyGrantOwnerCap): ID {
    cap.grant_id
}

public fun royalty_grant_recipient_cap_grant_id(cap: &RoyaltyGrantRecipientCap): ID {
    cap.grant_id
}

public fun royalty_grant_terms_recipient_share(terms: &RoyaltyGrantTerms): BPS {
    terms.recipient_share
}

public fun royalty_grant_terms_repayment_value(terms: &RoyaltyGrantTerms): Option<u64> {
    terms.repayment_value
}

public fun royalty_grant_terms_duration_ms(terms: &RoyaltyGrantTerms): Option<u64> {
    terms.duration_ms
}

// === Admin Functions ===

public fun reclaim<Share, Currency>(
    self: RoyaltyGrant<Share, Currency>,
    cap: RoyaltyGrantOwnerCap,
    clock: &Clock,
): RoyaltyPoolStake<Share> {
    let grant_id = object::id(&self);
    assert!(cap.grant_id == grant_id, EUnauthorized);
    assert!(self.is_reclaimable(clock), ENotReclaimable);
    let RoyaltyGrant { id, stake, .. } = self;
    let RoyaltyGrantOwnerCap { id: cap_id, grant_id: _ } = cap;
    emit(RoyaltyGrantReclaimedEvent { grant_id, stake_id: object::id(&stake) });
    cap_id.delete();
    id.delete();
    stake
}

public fun waive<Share, Currency>(
    self: &mut RoyaltyGrant<Share, Currency>,
    cap: &RoyaltyGrantRecipientCap,
    clock: &Clock,
) {
    let grant_id = object::id(self);
    assert!(cap.grant_id == grant_id, EUnauthorized);
    assert!(!self.is_reclaimable(clock), EAlreadyReclaimable);
    let ends_at_ms = clock.timestamp_ms();
    self.ends_at_ms = option::some(ends_at_ms);
    emit(RoyaltyGrantWaivedEvent { grant_id, ends_at_ms });
}

public fun set_owner<Share, Currency>(
    self: &mut RoyaltyGrant<Share, Currency>,
    cap: &RoyaltyGrantOwnerCap,
    owner: address,
) {
    let grant_id = object::id(self);
    assert!(cap.grant_id == grant_id, EUnauthorized);
    if (self.owner == owner) return;
    self.owner = owner;
    emit(RoyaltyGrantOwnerSetEvent { grant_id, owner });
}

public fun set_recipient<Share, Currency>(
    self: &mut RoyaltyGrant<Share, Currency>,
    cap: &RoyaltyGrantRecipientCap,
    recipient: address,
) {
    let grant_id = object::id(self);
    assert!(cap.grant_id == grant_id, EUnauthorized);
    if (self.recipient == recipient) return;
    self.recipient = recipient;
    emit(RoyaltyGrantRecipientSetEvent { grant_id, recipient });
}

// === Private Functions ===

fun accrue<Share, Currency>(
    self: &mut RoyaltyGrant<Share, Currency>,
    currency: TypeName,
    value: u64,
): u64 {
    if (!self.remainders.contains(&currency)) self.remainders.insert(currency, 0);
    let remainder = self.remainders.get_mut(&currency);
    let denominator = bps::max().value() as u128;
    let numerator = (value as u128) * (self.recipient_share.value() as u128) + (*remainder as u128);
    *remainder = (numerator % denominator) as u64;
    (numerator / denominator) as u64
}

// === Test Functions ===

#[test_only]
public fun derive_owner_cap_address_for_testing(grant_id: ID): address {
    derived_object::derive_address(grant_id, RoyaltyGrantOwnerCapKey())
}

#[test_only]
public fun derive_recipient_cap_address_for_testing(grant_id: ID): address {
    derived_object::derive_address(grant_id, RoyaltyGrantRecipientCapKey())
}

#[test_only]
public fun royalty_grant_created_fields_for_testing<Share, Currency>(
    event: &RoyaltyGrantCreatedEvent<Share, Currency>,
): (ID, ID, ID, u64, address, address, u16, Option<u64>, Option<u64>) {
    (
        event.grant_id,
        event.stake_id,
        event.pool_id,
        event.shares,
        event.owner,
        event.recipient,
        event.recipient_share_bps,
        event.repayment_value,
        event.ends_at_ms,
    )
}

#[test_only]
public fun royalty_grant_swept_fields_for_testing<PoolCurrency>(
    event: &RoyaltyGrantSweptEvent<PoolCurrency>,
): (ID, ID, address, u64, address, u64, u64) {
    (
        event.grant_id,
        event.pool_id,
        event.recipient,
        event.recipient_value,
        event.owner,
        event.owner_value,
        event.repaid_value,
    )
}

#[test_only]
public fun royalty_grant_bought_out_fields_for_testing(
    event: &RoyaltyGrantBoughtOutEvent,
): (ID, address, u64) {
    (event.grant_id, event.recipient, event.value)
}

#[test_only]
public fun royalty_grant_reclaimed_fields_for_testing(
    event: &RoyaltyGrantReclaimedEvent,
): (ID, ID) {
    (event.grant_id, event.stake_id)
}

#[test_only]
public fun royalty_grant_waived_fields_for_testing(event: &RoyaltyGrantWaivedEvent): (ID, u64) {
    (event.grant_id, event.ends_at_ms)
}

#[test_only]
public fun royalty_grant_owner_set_fields_for_testing(
    event: &RoyaltyGrantOwnerSetEvent,
): (ID, address) {
    (event.grant_id, event.owner)
}

#[test_only]
public fun royalty_grant_recipient_set_fields_for_testing(
    event: &RoyaltyGrantRecipientSetEvent,
): (ID, address) {
    (event.grant_id, event.recipient)
}
