// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

/// A composition's standing license to record it and distribute the recording.
///
/// The composition admin publishes a `RecordingLicensePolicy` with a rate. Any
/// recording admin may then take a `RecordingLicense` for a recording of that
/// composition, without the composition admin's involvement. Shares are each
/// work's canonical coin, so the license mints nothing: the recording admin
/// pays the composition's cut, `rate` of the recording's supply, in the
/// recording's coin, and the license holds it as a stake that the composition
/// owns. Anyone can `register` that stake in the recording's canonical pools,
/// so it earns from every revenue stream that pays them, and `sweep` its
/// royalties to the composition's canonical pool. Sync, broadcast and live
/// performance are separate.
module recording_license::recording_license;

// === Imports ===

use sui::accumulator::AccumulatorRoot;
use sui::balance::Balance;
use sui::clock::Clock;
use sui::derived_object::{Self, claim};
use sui::event::emit;
use bps::bps::{Self, BPS};
use musicos::composition::{Composition, CompositionAdminCap};
use musicos::recording::{Recording, RecordingAdminCap};
use royalty_pool::pool::{Self, RoyaltyPool};
use royalty_pool::stake::{Self, Stake};

// === Errors ===

/// The policy is not the recording's composition's.
const EWrongPolicy: u64 = 0;
/// The rate exceeds `MAX_RATE_BPS`.
const ERateTooHigh: u64 = 1;
/// The cut is not the policy's current rate of the recording's share supply.
const EWrongCut: u64 = 2;
/// The license holds no stake.
const ENoStake: u64 = 3;

// === Constants ===

/// Upper bound on a rate: a quarter of a recording's shares.
const MAX_RATE_BPS: u16 = 2_500;
/// Recording share supply in base units, fixed by musicos.
const SUPPLY: u64 = 100_000_000_000_000;

// === Structs ===

/// A composition's standing terms for recording it. Permanent.
public struct RecordingLicensePolicy<phantom CompositionShare> has key {
    id: UID,
    composition_id: ID,
    /// Rate for new licenses. Existing licenses keep the rate they took.
    rate: BPS,
}

/// A recording's license, holding the composition's stake in the recording.
/// Permanent. The stake is `none` for a zero rate or once withdrawn.
public struct RecordingLicense<phantom RecordingShare, phantom CompositionShare> has key {
    id: UID,
    recording_id: ID,
    composition_id: ID,
    stake: Option<Stake<RecordingShare>>,
}

/// Derivation key for both the policy (under a composition) and the license
/// (under a recording).
public struct ExtensionKey() has copy, drop, store;

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

public struct RecordingRoyaltySweptEvent<phantom Currency> has copy, drop {
    recording_id: ID,
    composition_id: ID,
    value: u64,
}

public struct RecordingStakeWithdrawnEvent has copy, drop {
    recording_id: ID,
    composition_id: ID,
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
    let policy = RecordingLicensePolicy<CompositionShare> {
        id: claim(composition.uid_mut(cap), ExtensionKey()),
        composition_id,
        rate: bps::new(rate_bps),
    };
    transfer::share_object(policy);
    emit(RecordingLicensePolicyRateSetEvent { composition_id, rate_bps });
}

/// Sets the rate for future licenses. No-op if unchanged. The cap's type
/// identifies the composition: musicos allows one per share type.
public fun set_rate<CompositionShare>(
    self: &mut RecordingLicensePolicy<CompositionShare>,
    _: &CompositionAdminCap<CompositionShare>,
    rate_bps: u16,
) {
    assert!(rate_bps <= MAX_RATE_BPS, ERateTooHigh);
    if (self.rate.value() == rate_bps) return;
    self.rate = bps::new(rate_bps);
    emit(RecordingLicensePolicyRateSetEvent { composition_id: self.composition_id, rate_bps });
}

/// Licenses the recording at the policy's current rate. `cut` must be exactly
/// that rate of the recording's supply, so it commits to the rate, and becomes the
/// composition's stake. Returns the license unshared: `register` it, then `share`
/// it. Aborts if already licensed.
public fun issue<RecordingShare, CompositionShare>(
    self: &RecordingLicensePolicy<CompositionShare>,
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    cut: Balance<RecordingShare>,
    ctx: &mut TxContext,
): RecordingLicense<RecordingShare, CompositionShare> {
    let composition_id = recording.composition_id();
    assert!(self.composition_id == composition_id, EWrongPolicy);
    assert!(cut.value() == self.rate.apply(SUPPLY), EWrongCut);

    let recording_id = object::id(recording);
    let stake = if (cut.value() > 0) option::some(stake::new(cut, ctx))
    else {
        cut.destroy_zero();
        option::none()
    };
    let rate_bps = self.rate.value();
    emit(RecordingLicenseIssuedEvent { recording_id, composition_id, rate_bps });
    RecordingLicense {
        id: claim(recording.uid_mut(cap), ExtensionKey()),
        recording_id,
        composition_id,
        stake,
    }
}

/// Shares the license so anyone can register and sweep its stake.
public fun share<RecordingShare, CompositionShare>(
    self: RecordingLicense<RecordingShare, CompositionShare>,
) {
    transfer::share_object(self);
}

/// Registers the composition's stake in the recording's canonical `Currency`
/// pool. The type binds the pool: only the recording can create a pool of its
/// coin, once per currency. Permissionless. No-op without a stake or if
/// already registered.
public fun register<RecordingShare, CompositionShare, Currency>(
    self: &mut RecordingLicense<RecordingShare, CompositionShare>,
    pool: &mut RoyaltyPool<RecordingShare, Currency>,
    root: &AccumulatorRoot,
    clock: &Clock,
) {
    if (self.stake.is_none()) return;
    let stake = self.stake.borrow_mut();
    if (stake.has_registration(object::id(pool))) return;
    pool.register_stake(stake, root, clock)
}

/// Claims the stake's royalties and sends them to the composition's canonical
/// pool address. Does not settle: `pool::settle` the recording pool first.
/// Permissionless. Returns the value sent; 0 without a stake or registration.
public fun sweep<RecordingShare, CompositionShare, Currency>(
    self: &mut RecordingLicense<RecordingShare, CompositionShare>,
    recording_pool: &mut RoyaltyPool<RecordingShare, Currency>,
): u64 {
    if (self.stake.is_none()) return 0;
    let stake = self.stake.borrow_mut();
    if (!stake.has_registration(object::id(recording_pool))) return 0;
    let royalty = recording_pool.claim_royalties(stake);
    let value = royalty.value();
    if (value == 0) {
        royalty.destroy_zero();
        return 0
    };
    royalty.send_funds(pool::derive_address<Currency>(self.composition_id));
    emit(RecordingRoyaltySweptEvent<Currency> {
        recording_id: self.recording_id,
        composition_id: self.composition_id,
        value,
    });
    value
}

/// Takes the composition's stake out, with its registrations and unclaimed
/// royalties, e.g. to migrate it to a new pool type. The recording stays
/// licensed. Aborts if the license holds no stake.
public fun withdraw<RecordingShare, CompositionShare>(
    self: &mut RecordingLicense<RecordingShare, CompositionShare>,
    _: &CompositionAdminCap<CompositionShare>,
): Stake<RecordingShare> {
    assert!(self.stake.is_some(), ENoStake);
    emit(RecordingStakeWithdrawnEvent {
        recording_id: self.recording_id,
        composition_id: self.composition_id,
    });
    self.stake.extract()
}

// === View Functions ===

/// The policy address for a composition ID, or the license address for a
/// recording ID. Computes an address, not evidence the object exists.
public fun derive_address(parent_id: ID): address {
    derived_object::derive_address(parent_id, ExtensionKey())
}

public fun rate<CompositionShare>(self: &RecordingLicensePolicy<CompositionShare>): BPS {
    self.rate
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

/// The composition's stake, for reading its value or pending royalties.
public fun stake<RecordingShare, CompositionShare>(
    self: &RecordingLicense<RecordingShare, CompositionShare>,
): &Option<Stake<RecordingShare>> {
    &self.stake
}

public fun is_licensed<RecordingShare>(recording: &Recording<RecordingShare>): bool {
    derived_object::exists(recording.uid(), ExtensionKey())
}

// === Test Functions ===

#[test_only]
public fun issued_event_fields(e: &RecordingLicenseIssuedEvent): (ID, ID, u16) {
    (e.recording_id, e.composition_id, e.rate_bps)
}

#[test_only]
public fun rate_set_event_fields(e: &RecordingLicensePolicyRateSetEvent): (ID, u16) {
    (e.composition_id, e.rate_bps)
}

#[test_only]
public fun withdrawn_event_fields(e: &RecordingStakeWithdrawnEvent): (ID, ID) {
    (e.recording_id, e.composition_id)
}

#[test_only]
public fun swept_event_fields<Currency>(e: &RecordingRoyaltySweptEvent<Currency>): (ID, ID, u64) {
    (e.recording_id, e.composition_id, e.value)
}
