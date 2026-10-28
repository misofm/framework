// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module recording_license::recording_license;

use bps::bps::BPS;
use miso_music::{
    composition::{Composition, CompositionAdminCap},
    recording::{Recording, RecordingAdminCap}
};
use royalty_pool::{pool::{Self, RoyaltyPool}, stake::{Self, Stake}};
use sui::{
    accumulator::AccumulatorRoot,
    balance::Balance,
    clock::Clock,
    coin_registry::Currency,
    derived_object,
    dynamic_field,
    event::emit
};

// === Errors ===

const EWrongPolicy: u64 = 0;
const EWrongCut: u64 = 1;
const ENoStake: u64 = 2;
const EUnknownSupply: u64 = 3;

// === Structs ===

public struct RecordingLicense<phantom RecordingShare, phantom CompositionShare> has key {
    id: UID,
    recording_id: ID,
    composition_id: ID,
    stake: Option<Stake<RecordingShare>>,
}

public struct RecordingLicensePolicy<phantom CompositionShare> has key {
    id: UID,
    composition_id: ID,
    rate: BPS,
}

public struct RecordingLicenseKey() has copy, drop, store;

public struct RecordingLicensePolicyKey() has copy, drop, store;

public struct LicensedRecordingKey(ID) has copy, drop, store;

// === Events ===

public struct RecordingLicensePolicyRateSetEvent has copy, drop {
    policy_id: ID,
    composition_id: ID,
    rate_bps: u16,
}

public struct RecordingLicenseIssuedEvent has copy, drop {
    license_id: ID,
    recording_id: ID,
    composition_id: ID,
    rate_bps: u16,
    cut: u64,
    stake_id: Option<ID>,
}

public struct RecordingLicenseRoyaltySweptEvent<phantom Currency> has copy, drop {
    recording_id: ID,
    composition_id: ID,
    value: u64,
}

public struct RecordingLicenseStakeWithdrawnEvent has copy, drop {
    recording_id: ID,
    composition_id: ID,
}

// === Method Aliases ===

public use fun recording_license_policy_rate as RecordingLicensePolicy.rate;
public use fun recording_license_policy_composition_id as RecordingLicensePolicy.composition_id;
public use fun recording_license_policy_has_license as RecordingLicensePolicy.has_license;
public use fun share_policy as RecordingLicensePolicy.share;

// === Public Functions ===

public fun share<RecordingShare, CompositionShare>(
    self: RecordingLicense<RecordingShare, CompositionShare>,
) {
    transfer::share_object(self);
}

public fun share_policy<CompositionShare>(policy: RecordingLicensePolicy<CompositionShare>) {
    transfer::share_object(policy);
}

public fun register<RecordingShare, CompositionShare, Currency>(
    self: &mut RecordingLicense<RecordingShare, CompositionShare>,
    recording_pool: &mut RoyaltyPool<RecordingShare, Currency>,
    _: &RoyaltyPool<CompositionShare, Currency>,
    root: &AccumulatorRoot,
    clock: &Clock,
) {
    if (self.stake.is_none()) return;
    let stake = self.stake.borrow_mut();
    if (stake.has_registration(object::id(recording_pool))) return;
    recording_pool.register_stake(stake, root, clock)
}

public fun sweep<RecordingShare, CompositionShare, Currency>(
    self: &mut RecordingLicense<RecordingShare, CompositionShare>,
    recording_pool: &mut RoyaltyPool<RecordingShare, Currency>,
    root: &AccumulatorRoot,
    clock: &Clock,
): u64 {
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
    royalty.send_funds(pool::derive_address<Currency>(self.composition_id));
    emit(RecordingLicenseRoyaltySweptEvent<Currency> {
        recording_id: self.recording_id,
        composition_id: self.composition_id,
        value,
    });
    value
}

// === View Functions ===

public fun derive_license_address(recording_id: ID): address {
    derived_object::derive_address(recording_id, RecordingLicenseKey())
}

public fun recording_id<RecordingShare, CompositionShare>(
    self: &RecordingLicense<RecordingShare, CompositionShare>,
): ID {
    self.recording_id
}

public fun composition_id<RecordingShare, CompositionShare>(
    self: &RecordingLicense<RecordingShare, CompositionShare>,
): ID {
    self.composition_id
}

public fun stake<RecordingShare, CompositionShare>(
    self: &RecordingLicense<RecordingShare, CompositionShare>,
): &Option<Stake<RecordingShare>> {
    &self.stake
}

public fun has_license<RecordingShare>(recording: &Recording<RecordingShare>): bool {
    derived_object::exists(recording.uid(), RecordingLicenseKey())
}

public fun derive_policy_address(composition_id: ID): address {
    derived_object::derive_address(composition_id, RecordingLicensePolicyKey())
}

public fun recording_license_policy_rate<CompositionShare>(
    policy: &RecordingLicensePolicy<CompositionShare>,
): BPS {
    policy.rate
}

public fun recording_license_policy_composition_id<CompositionShare>(
    policy: &RecordingLicensePolicy<CompositionShare>,
): ID {
    policy.composition_id
}

public fun has_policy<CompositionShare>(composition: &Composition<CompositionShare>): bool {
    derived_object::exists(composition.uid(), RecordingLicensePolicyKey())
}

public fun recording_license_policy_has_license<CompositionShare>(
    policy: &RecordingLicensePolicy<CompositionShare>,
    recording_id: ID,
): bool {
    dynamic_field::exists(&policy.id, LicensedRecordingKey(recording_id))
}

// === Admin Functions ===

public fun new_policy<CompositionShare>(
    composition: &mut Composition<CompositionShare>,
    cap: &CompositionAdminCap<CompositionShare>,
    rate: BPS,
): RecordingLicensePolicy<CompositionShare> {
    let composition_id = object::id(composition);
    let policy = RecordingLicensePolicy<CompositionShare> {
        id: derived_object::claim(composition.uid_mut(cap), RecordingLicensePolicyKey()),
        composition_id,
        rate,
    };
    emit(RecordingLicensePolicyRateSetEvent {
        policy_id: object::id(&policy),
        composition_id,
        rate_bps: rate.value(),
    });
    policy
}

public fun issue<RecordingShare, CompositionShare>(
    policy: &mut RecordingLicensePolicy<CompositionShare>,
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    currency: &Currency<RecordingShare>,
    cut: Balance<RecordingShare>,
    ctx: &mut TxContext,
): RecordingLicense<RecordingShare, CompositionShare> {
    let composition_id = recording.composition_id();
    assert!(policy.composition_id == composition_id, EWrongPolicy);
    let supply = currency.total_supply().destroy_or!(abort EUnknownSupply);
    assert!(cut.value() == policy.rate.apply(supply), EWrongCut);
    let recording_id = object::id(recording);
    let cut_value = cut.value();
    let stake = if (cut_value > 0) {
        option::some(stake::new(cut, ctx))
    } else {
        cut.destroy_zero();
        option::none()
    };
    let license = RecordingLicense {
        id: derived_object::claim(recording.uid_mut(cap), RecordingLicenseKey()),
        recording_id,
        composition_id,
        stake,
    };
    dynamic_field::add(&mut policy.id, LicensedRecordingKey(recording_id), true);
    emit(RecordingLicenseIssuedEvent {
        license_id: object::id(&license),
        recording_id,
        composition_id,
        rate_bps: policy.rate.value(),
        cut: cut_value,
        stake_id: license.stake.map_ref!(|stake| object::id(stake)),
    });
    license
}

public fun set_rate<CompositionShare>(
    policy: &mut RecordingLicensePolicy<CompositionShare>,
    _: &CompositionAdminCap<CompositionShare>,
    rate: BPS,
) {
    if (policy.rate == rate) return;
    policy.rate = rate;
    emit(RecordingLicensePolicyRateSetEvent {
        policy_id: object::id(policy),
        composition_id: policy.composition_id,
        rate_bps: rate.value(),
    });
}

public fun withdraw<RecordingShare, CompositionShare>(
    self: &mut RecordingLicense<RecordingShare, CompositionShare>,
    _: &CompositionAdminCap<CompositionShare>,
): Stake<RecordingShare> {
    assert!(self.stake.is_some(), ENoStake);
    emit(RecordingLicenseStakeWithdrawnEvent {
        recording_id: self.recording_id,
        composition_id: self.composition_id,
    });
    self.stake.extract()
}

// === Test Functions ===

#[test_only]
public fun issued_event_fields(
    event: &RecordingLicenseIssuedEvent,
): (ID, ID, ID, u16, u64, Option<ID>) {
    (
        event.license_id,
        event.recording_id,
        event.composition_id,
        event.rate_bps,
        event.cut,
        event.stake_id,
    )
}

#[test_only]
public fun rate_set_event_fields(event: &RecordingLicensePolicyRateSetEvent): (ID, ID, u16) {
    (event.policy_id, event.composition_id, event.rate_bps)
}

#[test_only]
public fun withdrawn_event_fields(event: &RecordingLicenseStakeWithdrawnEvent): (ID, ID) {
    (event.recording_id, event.composition_id)
}

#[test_only]
public fun swept_event_fields<Currency>(
    event: &RecordingLicenseRoyaltySweptEvent<Currency>,
): (ID, ID, u64) {
    (event.recording_id, event.composition_id, event.value)
}
