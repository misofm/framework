// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module recording_revenue_share::recording_revenue_share;

use bps::bps::BPS;
use miso_music::{
    composition::{Composition, CompositionAdminCap},
    recording::{Recording, RecordingAdminCap}
};
use royalty_pool::{royalty_pool::{Self, RoyaltyPool}, royalty_pool_stake::{Self, RoyaltyPoolStake}};
use sui::{
    accumulator::AccumulatorRoot,
    balance::Balance,
    clock::Clock,
    coin_registry::Currency,
    derived_object,
    dynamic_field as df,
    event::emit
};

// === Errors ===

const EWrongTerms: u64 = 0;
const EWrongShares: u64 = 1;
const ENoStake: u64 = 2;
const ENoSupply: u64 = 3;
const EWrongComposition: u64 = 4;
const EWrongRate: u64 = 5;

// === Structs ===

public struct RecordingRevenueShare<phantom RecordingShare, phantom CompositionShare> has key {
    id: UID,
    recording_id: ID,
    composition_id: ID,
    stake: Option<RoyaltyPoolStake<RecordingShare>>,
}

public struct RecordingRevenueShareTerms<phantom CompositionShare> has key {
    id: UID,
    composition_id: ID,
    rate: BPS,
}

public struct RecordingRevenueShareKey() has copy, drop, store;

public struct RecordingRevenueShareTermsKey() has copy, drop, store;

public struct RevenueShareRecordingKey(ID) has copy, drop, store;

// === Events ===

public struct RecordingRevenueShareCreatedEvent has copy, drop {
    revenue_share_id: ID,
    recording_id: ID,
    composition_id: ID,
    rate_bps: u16,
    shares: u64,
    stake_id: Option<ID>,
}

public struct RecordingRevenueShareSweptEvent<phantom Currency> has copy, drop {
    recording_id: ID,
    composition_id: ID,
    stake_id: ID,
    value: u64,
}

public struct RecordingRevenueShareStakeWithdrawnEvent has copy, drop {
    recording_id: ID,
    composition_id: ID,
    stake_id: ID,
}

public struct RecordingRevenueShareTermsCreatedEvent has copy, drop {
    terms_id: ID,
    composition_id: ID,
    rate_bps: u16,
}

public struct RecordingRevenueShareTermsRateSetEvent has copy, drop {
    terms_id: ID,
    composition_id: ID,
    rate_bps: u16,
}

// === Method Aliases ===

public use fun recording_revenue_share_terms_rate as RecordingRevenueShareTerms.rate;
public use fun recording_revenue_share_terms_composition_id as
    RecordingRevenueShareTerms.composition_id;
public use fun recording_revenue_share_terms_has_recording as
    RecordingRevenueShareTerms.has_recording;
public use fun share_terms as RecordingRevenueShareTerms.share;

// === Public Functions ===

public fun share<RecordingShare, CompositionShare>(
    self: RecordingRevenueShare<RecordingShare, CompositionShare>,
) {
    transfer::share_object(self);
}

public fun register<RecordingShare, CompositionShare, Currency>(
    self: &mut RecordingRevenueShare<RecordingShare, CompositionShare>,
    recording_pool: &mut RoyaltyPool<RecordingShare, Currency>,
    _: &RoyaltyPool<CompositionShare, Currency>,
    root: &AccumulatorRoot,
    clock: &Clock,
) {
    assert!(self.stake.is_some(), ENoStake);
    recording_pool.register_stake(self.stake.borrow_mut(), root, clock)
}

public fun sweep<RecordingShare, CompositionShare, Currency>(
    self: &mut RecordingRevenueShare<RecordingShare, CompositionShare>,
    composition: &Composition<CompositionShare>,
    recording_pool: &mut RoyaltyPool<RecordingShare, Currency>,
    root: &AccumulatorRoot,
    clock: &Clock,
): u64 {
    assert!(object::id(composition) == self.composition_id, EWrongComposition);
    if (self.stake.is_none()) return 0;
    let stake = self.stake.borrow_mut();
    if (!stake.has_registration(object::id(recording_pool))) return 0;
    recording_pool.settle(root, clock);
    let royalty = recording_pool.claim_royalties(stake);
    let value = royalty.value();
    if (value == 0) {
        royalty.destroy_zero();
        return 0
    };
    royalty.send_funds(
        royalty_pool::derive_composition_pool_address<CompositionShare, Currency>(composition),
    );
    emit(RecordingRevenueShareSweptEvent<Currency> {
        recording_id: self.recording_id,
        composition_id: self.composition_id,
        stake_id: object::id(stake),
        value,
    });
    value
}

public fun share_terms<CompositionShare>(terms: RecordingRevenueShareTerms<CompositionShare>) {
    transfer::share_object(terms);
}

// === View Functions ===

public fun derive_address<RecordingShare>(recording: &Recording<RecordingShare>): address {
    derived_object::derive_address(object::id(recording), RecordingRevenueShareKey())
}

public fun recording_id<RecordingShare, CompositionShare>(
    self: &RecordingRevenueShare<RecordingShare, CompositionShare>,
): ID {
    self.recording_id
}

public fun composition_id<RecordingShare, CompositionShare>(
    self: &RecordingRevenueShare<RecordingShare, CompositionShare>,
): ID {
    self.composition_id
}

public fun stake<RecordingShare, CompositionShare>(
    self: &RecordingRevenueShare<RecordingShare, CompositionShare>,
): &Option<RoyaltyPoolStake<RecordingShare>> {
    &self.stake
}

public fun has_revenue_share<RecordingShare>(recording: &Recording<RecordingShare>): bool {
    derived_object::exists(recording.uid(), RecordingRevenueShareKey())
}

public fun derive_terms_address<CompositionShare>(
    composition: &Composition<CompositionShare>,
): address {
    derived_object::derive_address(object::id(composition), RecordingRevenueShareTermsKey())
}

public fun recording_revenue_share_terms_rate<CompositionShare>(
    terms: &RecordingRevenueShareTerms<CompositionShare>,
): BPS {
    terms.rate
}

public fun recording_revenue_share_terms_composition_id<CompositionShare>(
    terms: &RecordingRevenueShareTerms<CompositionShare>,
): ID {
    terms.composition_id
}

public fun has_terms<CompositionShare>(composition: &Composition<CompositionShare>): bool {
    derived_object::exists(composition.uid(), RecordingRevenueShareTermsKey())
}

public fun recording_revenue_share_terms_has_recording<CompositionShare>(
    terms: &RecordingRevenueShareTerms<CompositionShare>,
    recording_id: ID,
): bool {
    df::exists(&terms.id, RevenueShareRecordingKey(recording_id))
}

// === Admin Functions ===

public fun new<RecordingShare, CompositionShare>(
    terms: &mut RecordingRevenueShareTerms<CompositionShare>,
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    currency: &Currency<RecordingShare>,
    rate: BPS,
    shares: Balance<RecordingShare>,
    ctx: &mut TxContext,
): RecordingRevenueShare<RecordingShare, CompositionShare> {
    let revenue_share_uid = derived_object::claim(
        recording.uid_mut(cap),
        RecordingRevenueShareKey(),
    );
    let composition_id = recording.composition_id();
    assert!(terms.composition_id == composition_id, EWrongTerms);
    assert!(terms.rate == rate, EWrongRate);
    let supply = currency.total_supply().destroy_or!(abort ENoSupply);
    assert!(shares.value() == terms.rate.apply(supply), EWrongShares);
    let recording_id = object::id(recording);
    let shares_value = shares.value();
    let stake = if (shares_value > 0) {
        option::some(royalty_pool_stake::new(shares, ctx))
    } else {
        shares.destroy_zero();
        option::none()
    };
    let revenue_share = RecordingRevenueShare {
        id: revenue_share_uid,
        recording_id,
        composition_id,
        stake,
    };
    df::add(&mut terms.id, RevenueShareRecordingKey(recording_id), true);
    emit(RecordingRevenueShareCreatedEvent {
        revenue_share_id: object::id(&revenue_share),
        recording_id,
        composition_id,
        rate_bps: terms.rate.value(),
        shares: shares_value,
        stake_id: revenue_share.stake.map_ref!(|stake| object::id(stake)),
    });
    revenue_share
}

public fun withdraw<RecordingShare, CompositionShare>(
    self: &mut RecordingRevenueShare<RecordingShare, CompositionShare>,
    _: &CompositionAdminCap<CompositionShare>,
): RoyaltyPoolStake<RecordingShare> {
    assert!(self.stake.is_some(), ENoStake);
    let stake = self.stake.extract();
    emit(RecordingRevenueShareStakeWithdrawnEvent {
        recording_id: self.recording_id,
        composition_id: self.composition_id,
        stake_id: object::id(&stake),
    });
    stake
}

public fun new_terms<CompositionShare>(
    composition: &mut Composition<CompositionShare>,
    cap: &CompositionAdminCap<CompositionShare>,
    rate: BPS,
): RecordingRevenueShareTerms<CompositionShare> {
    let composition_id = object::id(composition);
    let terms = RecordingRevenueShareTerms<CompositionShare> {
        id: derived_object::claim(composition.uid_mut(cap), RecordingRevenueShareTermsKey()),
        composition_id,
        rate,
    };
    emit(RecordingRevenueShareTermsCreatedEvent {
        terms_id: object::id(&terms),
        composition_id,
        rate_bps: rate.value(),
    });
    terms
}

public fun set_rate<CompositionShare>(
    terms: &mut RecordingRevenueShareTerms<CompositionShare>,
    _: &CompositionAdminCap<CompositionShare>,
    rate: BPS,
) {
    if (terms.rate == rate) return;
    terms.rate = rate;
    emit(RecordingRevenueShareTermsRateSetEvent {
        terms_id: object::id(terms),
        composition_id: terms.composition_id,
        rate_bps: rate.value(),
    });
}

// === Test Functions ===

#[test_only]
public fun derive_address_for_testing(recording_id: ID): address {
    derived_object::derive_address(recording_id, RecordingRevenueShareKey())
}

#[test_only]
public fun recording_revenue_share_created_fields_for_testing(
    event: &RecordingRevenueShareCreatedEvent,
): (ID, ID, ID, u16, u64, Option<ID>) {
    (
        event.revenue_share_id,
        event.recording_id,
        event.composition_id,
        event.rate_bps,
        event.shares,
        event.stake_id,
    )
}

#[test_only]
public fun recording_revenue_share_swept_fields_for_testing<Currency>(
    event: &RecordingRevenueShareSweptEvent<Currency>,
): (ID, ID, ID, u64) {
    (event.recording_id, event.composition_id, event.stake_id, event.value)
}

#[test_only]
public fun recording_revenue_share_stake_withdrawn_fields_for_testing(
    event: &RecordingRevenueShareStakeWithdrawnEvent,
): (ID, ID, ID) {
    (event.recording_id, event.composition_id, event.stake_id)
}

#[test_only]
public fun derive_terms_address_for_testing(composition_id: ID): address {
    derived_object::derive_address(composition_id, RecordingRevenueShareTermsKey())
}

#[test_only]
public fun recording_revenue_share_terms_created_fields_for_testing(
    event: &RecordingRevenueShareTermsCreatedEvent,
): (ID, ID, u16) {
    (event.terms_id, event.composition_id, event.rate_bps)
}

#[test_only]
public fun recording_revenue_share_terms_rate_set_fields_for_testing(
    event: &RecordingRevenueShareTermsRateSetEvent,
): (ID, ID, u16) {
    (event.terms_id, event.composition_id, event.rate_bps)
}
