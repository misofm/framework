// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

/// A composition's standing license to record it and distribute the recording.
///
/// The composition admin publishes a `RecordingLicensePolicy` with a rate. Any
/// recording admin may then take a `RecordingLicense` for a recording of that
/// composition, without the composition admin's involvement. Shares are each
/// work's canonical coin, so the license mints nothing: the recording admin
/// pays the composition's cut, `rate` of the recording's supply, in the
/// recording's coin, and the policy holds it as a registered stake that the
/// composition owns. The rate is the composition's whole share of the
/// recording's sales and streams; sync, broadcast and live performance are
/// separate.
module recording_license::recording_license;

// === Imports ===

use sui::accumulator::AccumulatorRoot;
use sui::balance::Balance;
use sui::clock::Clock;
use sui::derived_object::{Self, claim};
use sui::dynamic_object_field as dof;
use sui::event::emit;
use bps::bps::{Self, BPS};
use musicos::composition::{Composition, CompositionAdminCap};
use musicos::recording::{Recording, RecordingAdminCap};
use royalty_pool::pool::{Self, RoyaltyPool};
use royalty_pool::stake::{Self, Stake};

// === Errors ===

/// The policy is not derived from this composition.
const EWrongPolicy: u64 = 0;
/// The rate exceeds `MAX_RATE_BPS`.
const ERateTooHigh: u64 = 1;
/// The license belongs to another recording.
const EWrongLicense: u64 = 2;
/// The policy's rate differs from the rate the recording admin agreed to.
const ERateMismatch: u64 = 3;
/// The cut is not the policy's rate of the recording's share supply.
const EWrongCut: u64 = 4;

// === Constants ===

/// Upper bound on a rate: a quarter of a recording's shares.
const MAX_RATE_BPS: u16 = 2_500;
/// Recording share supply in base units, fixed by musicos.
const SUPPLY: u64 = 100_000_000_000_000;

// === Structs ===

/// Derivation key for both the policy (under a composition) and the license
/// (under a recording).
public struct ExtensionKey() has copy, drop, store;

/// A composition's standing terms for recording it. Permanent. Parent of the
/// composition's pools. Holds the composition's recording stakes as dynamic
/// object fields keyed by recording ID.
public struct RecordingLicensePolicy has key {
    id: UID,
    composition_id: ID,
    /// Rate for new licenses. Existing licenses keep the rate they took.
    rate: BPS,
}

/// A recording's license. Permanent. Parent of the recording's pools.
public struct RecordingLicense has key {
    id: UID,
    recording_id: ID,
}

// === Events ===

/// Emitted when a policy is created and whenever its rate changes.
public struct RecordingLicensePolicyRateSetEvent has copy, drop {
    composition_id: ID,
    rate_bps: u16,
}

public struct RecordingLicenseIssuedEvent has copy, drop {
    recording_id: ID,
    composition_id: ID,
    rate_bps: u16,
}

public struct RecordingStakeWithdrawnEvent has copy, drop {
    composition_id: ID,
    recording_id: ID,
}

public struct RecordingRoyaltySweptEvent<phantom Currency> has copy, drop {
    composition_id: ID,
    recording_id: ID,
    value: u64,
}

// === Public Functions ===

/// Creates and shares the composition's policy.
public fun new<CompositionShare>(
    composition: &mut Composition<CompositionShare>,
    cap: &CompositionAdminCap<CompositionShare>,
    rate_bps: u16,
) {
    assert!(rate_bps <= MAX_RATE_BPS, ERateTooHigh);
    let composition_id = object::id(composition);
    let policy = RecordingLicensePolicy {
        id: claim(composition.uid_mut(cap), ExtensionKey()),
        composition_id,
        rate: bps::new(rate_bps),
    };
    transfer::share_object(policy);
    emit(RecordingLicensePolicyRateSetEvent { composition_id, rate_bps });
}

/// Sets the rate for future licenses. No-op if unchanged.
public fun set_rate<CompositionShare>(
    self: &mut RecordingLicensePolicy,
    composition: &Composition<CompositionShare>,
    cap: &CompositionAdminCap<CompositionShare>,
    rate_bps: u16,
) {
    assert!(rate_bps <= MAX_RATE_BPS, ERateTooHigh);
    self.authorize(composition, cap);
    if (self.rate.value() == rate_bps) return;
    self.rate = bps::new(rate_bps);
    emit(RecordingLicensePolicyRateSetEvent { composition_id: self.composition_id, rate_bps });
}

/// Creates a composition pool for `Currency`, where swept royalties arrive.
/// Returned unshared: shared empty, the first tiny staker would collect
/// everything waiting at its address. Register the composition's own stakes,
/// then `pool::share` it.
public fun new_composition_pool<CompositionShare, Currency>(
    self: &mut RecordingLicensePolicy,
    composition: &Composition<CompositionShare>,
    cap: &CompositionAdminCap<CompositionShare>,
): RoyaltyPool<CompositionShare, Currency> {
    self.authorize(composition, cap);
    pool::new<CompositionShare, Currency>(&mut self.id)
}

/// Takes a recording stake out of the policy. The recording stays licensed.
public fun withdraw<CompositionShare, RecordingShare>(
    self: &mut RecordingLicensePolicy,
    composition: &Composition<CompositionShare>,
    cap: &CompositionAdminCap<CompositionShare>,
    recording_id: ID,
): Stake<RecordingShare> {
    self.authorize(composition, cap);
    let stake = dof::remove(&mut self.id, recording_id);
    emit(RecordingStakeWithdrawnEvent { composition_id: self.composition_id, recording_id });
    stake
}

/// Licenses the recording at `rate_bps`, which must equal the policy's current
/// rate, so a concurrent rate change aborts the transaction. `cut` must be
/// exactly that rate of the recording's supply. Creates the recording's first
/// pool and keeps a nonzero cut as a stake registered in it, owned by the
/// composition. The pool is unshared: register the recording's own stakes,
/// then `pool::share` it in the same transaction, so no revenue reaches it
/// before they are registered. Aborts if the recording is already licensed.
public fun issue<RecordingShare, Currency>(
    self: &mut RecordingLicensePolicy,
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    cut: Balance<RecordingShare>,
    rate_bps: u16,
    root: &AccumulatorRoot,
    clock: &Clock,
    ctx: &mut TxContext,
): RoyaltyPool<RecordingShare, Currency> {
    let composition_id = recording.composition_id();
    assert!(object::id_address(self) == derive_address(composition_id), EWrongPolicy);
    assert!(self.rate.value() == rate_bps, ERateMismatch);
    assert!(cut.value() == self.rate.apply(SUPPLY), EWrongCut);

    let recording_id = object::id(recording);
    let mut license = RecordingLicense {
        id: claim(recording.uid_mut(cap), ExtensionKey()),
        recording_id,
    };
    let mut pool = pool::new<RecordingShare, Currency>(&mut license.id);

    if (cut.value() > 0) {
        let mut stake = stake::new(cut, ctx);
        pool.register_stake(&mut stake, root, clock);
        dof::add(&mut self.id, recording_id, stake);
    } else {
        cut.destroy_zero();
    };

    transfer::share_object(license);
    emit(RecordingLicenseIssuedEvent { recording_id, composition_id, rate_bps });
    pool
}

/// Creates another recording pool, registering the composition's stake if the
/// policy still holds it. Returned unshared, as with `issue`.
public fun new_recording_pool<RecordingShare, Currency>(
    self: &mut RecordingLicensePolicy,
    license: &mut RecordingLicense,
    recording: &Recording<RecordingShare>,
    _: &RecordingAdminCap<RecordingShare>,
    root: &AccumulatorRoot,
    clock: &Clock,
): RoyaltyPool<RecordingShare, Currency> {
    let recording_id = object::id(recording);
    assert!(license.recording_id == recording_id, EWrongLicense);
    assert!(object::id_address(self) == derive_address(recording.composition_id()), EWrongPolicy);

    let mut pool = pool::new<RecordingShare, Currency>(&mut license.id);
    if (dof::exists(&self.id, recording_id)) {
        let stake: &mut Stake<RecordingShare> = dof::borrow_mut(&mut self.id, recording_id);
        pool.register_stake(stake, root, clock);
    };
    pool
}

/// Claims a held stake's royalties from its recording pool and sends them to
/// the composition pool's address, where `pool::settle` folds them in. Does
/// not settle the recording pool: call `pool::settle` on it first in the same
/// PTB to include its latest funds. Permissionless. Returns the value sent; 0
/// if the stake was withdrawn.
public fun sweep<RecordingShare, Currency>(
    self: &mut RecordingLicensePolicy,
    recording_id: ID,
    recording_pool: &mut RoyaltyPool<RecordingShare, Currency>,
): u64 {
    if (!dof::exists(&self.id, recording_id)) return 0;
    let reward = recording_pool.claim_rewards(dof::borrow_mut(&mut self.id, recording_id));
    let value = reward.value();
    if (value == 0) {
        reward.destroy_zero();
        return 0
    };
    reward.send_funds(pool::derive_address<Currency>(object::id(self)));
    emit(RecordingRoyaltySweptEvent<Currency> {
        composition_id: self.composition_id,
        recording_id,
        value,
    });
    value
}

// === View Functions ===

/// The policy address for a composition ID, or the license address for a
/// recording ID. Computes an address, not evidence the object exists. The
/// policy and license parent the work's pools: revenue for a recording goes to
/// `pool::derive_address<Currency>(license_id)`, where it waits until the pool
/// exists and has registered stakes.
public fun derive_address(parent_id: ID): address {
    derived_object::derive_address(parent_id, ExtensionKey())
}

public fun rate(self: &RecordingLicensePolicy): BPS { self.rate }

public fun composition_id(self: &RecordingLicensePolicy): ID { self.composition_id }

public fun recording_id(self: &RecordingLicense): ID { self.recording_id }

public fun is_licensed<RecordingShare>(recording: &Recording<RecordingShare>): bool {
    derived_object::exists(recording.uid(), ExtensionKey())
}

// === Private Functions ===

/// The cap's share type authorizes; the policy must belong to this composition.
fun authorize<CompositionShare>(
    self: &RecordingLicensePolicy,
    composition: &Composition<CompositionShare>,
    _: &CompositionAdminCap<CompositionShare>,
) {
    assert!(self.composition_id == object::id(composition), EWrongPolicy);
}

// === Test Functions ===

#[test_only]
public fun holds_recording_stake_for_testing(self: &RecordingLicensePolicy, recording_id: ID): bool {
    dof::exists(&self.id, recording_id)
}

#[test_only]
public fun issued_event_fields(e: &RecordingLicenseIssuedEvent): (ID, ID, u16) {
    (e.recording_id, e.composition_id, e.rate_bps)
}

#[test_only]
public fun rate_set_event_fields(e: &RecordingLicensePolicyRateSetEvent): (ID, u16) {
    (e.composition_id, e.rate_bps)
}

#[test_only]
public fun swept_event_fields<Currency>(e: &RecordingRoyaltySweptEvent<Currency>): (ID, ID, u64) {
    (e.composition_id, e.recording_id, e.value)
}
