// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

/// A composition's standing license to record it and distribute the recording.
///
/// The composition admin publishes a `RecordingLicensePolicy` with a rate. Any
/// recording admin may then take a `RecordingLicense` for a recording of that
/// composition, without the composition admin's involvement. Issuing the
/// license creates the recording's shares under this scheme and gives the
/// composition `rate` of them as a registered stake that the policy holds.
/// The rate is the composition's whole share of the recording's sales and
/// streams; sync, broadcast and live performance are separate.
///
/// Shares are scheme-specific: the composition's shares are issued under the
/// policy, and the recording's under its license. Core objects are never
/// issuance parents.
module recording_license::recording_license;

// === Imports ===

use sui::derived_object::{Self, claim};
use sui::dynamic_object_field as dof;
use sui::event::emit;

use bps::bps::{Self, BPS};
use share::share::{Self, Issuance, Share};
use royalty_pool::pool::{Self, RoyaltyPool};
use royalty_pool::stake::{Self, Stake};

use musicos::composition::{Composition, CompositionAdminCap};
use musicos::recording::{Recording, RecordingAdminCap};

// === Errors ===

/// The policy is not derived from this composition.
const EWrongPolicy: u64 = 0;
/// The rate exceeds `MAX_RATE_BPS`.
const ERateTooHigh: u64 = 1;
/// The license belongs to another recording.
const EWrongLicense: u64 = 2;
/// The policy's rate differs from the rate the recording admin agreed to.
const ERateMismatch: u64 = 3;

// === Constants ===

/// Upper bound on a rate: a quarter of a recording's shares.
const MAX_RATE_BPS: u16 = 2_500;
/// Scheme share supply in base units: 100M shares at 6 decimals.
const SUPPLY: u64 = 100_000_000_000_000;
const DECIMALS: u8 = 6;

// === Structs ===

/// Derivation key for both the policy (under a composition) and the license
/// (under a recording).
public struct ExtensionKey() has copy, drop, store;

/// A composition's standing terms for recording it. Permanent. Parent of the
/// composition's scheme shares and pools. Holds the composition's recording
/// stakes as dynamic object fields keyed by recording ID.
public struct RecordingLicensePolicy has key {
    id: UID,
    composition_id: ID,
    /// Rate for new licenses. Existing licenses keep the rate they took.
    rate: BPS,
}

/// A recording's license. Permanent. Parent of the recording's scheme shares
/// and pools.
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

/// Publishes the composition's policy and returns the composition's full
/// scheme share supply.
public fun new(composition: &mut Composition, cap: &CompositionAdminCap, rate_bps: u16): Share {
    assert!(rate_bps <= MAX_RATE_BPS, ERateTooHigh);
    let composition_id = object::id(composition);
    let mut policy = RecordingLicensePolicy {
        id: claim(composition.uid_mut(cap), ExtensionKey()),
        composition_id,
        rate: bps::new(rate_bps),
    };
    let (issuance, shares) = share::new(&mut policy.id, SUPPLY, DECIMALS);
    issuance.share();
    transfer::share_object(policy);
    emit(RecordingLicensePolicyRateSetEvent { composition_id, rate_bps });
    shares
}

/// Sets the rate for future licenses. No-op if unchanged.
public fun set_rate(
    self: &mut RecordingLicensePolicy,
    composition: &Composition,
    cap: &CompositionAdminCap,
    rate_bps: u16,
) {
    assert!(rate_bps <= MAX_RATE_BPS, ERateTooHigh);
    self.authorize(composition, cap);
    if (self.rate.value() == rate_bps) return;
    self.rate = bps::new(rate_bps);
    emit(RecordingLicensePolicyRateSetEvent { composition_id: self.composition_id, rate_bps });
}

/// Creates and shares a composition pool for `Currency`. Swept royalties
/// arrive at its address.
public fun new_composition_pool<Currency>(
    self: &mut RecordingLicensePolicy,
    composition: &Composition,
    cap: &CompositionAdminCap,
    issuance: &Issuance,
) {
    self.authorize(composition, cap);
    pool::new<Currency>(&mut self.id, issuance).share();
}

/// Takes a recording stake out of the policy. The recording stays licensed.
public fun withdraw(
    self: &mut RecordingLicensePolicy,
    composition: &Composition,
    cap: &CompositionAdminCap,
    recording_id: ID,
): Stake {
    self.authorize(composition, cap);
    let stake = dof::remove(&mut self.id, recording_id);
    emit(RecordingStakeWithdrawnEvent { composition_id: self.composition_id, recording_id });
    stake
}

/// Licenses the recording at `rate_bps`, which must equal the policy's current
/// rate, so a concurrent rate change aborts the transaction. Creates the recording's scheme shares and its first pool,
/// keeps the composition's cut as a stake registered in that pool, and returns
/// the remaining shares and the pool. The pool is unshared: register the
/// recording's own stakes, then `pool::share` it in the same transaction, so
/// no revenue reaches it before they are registered. Aborts if the recording
/// is already licensed.
public fun issue<Currency>(
    self: &mut RecordingLicensePolicy,
    recording: &mut Recording,
    cap: &RecordingAdminCap,
    rate_bps: u16,
    ctx: &mut TxContext,
): (Share, RoyaltyPool<Currency>) {
    let composition_id = recording.composition_id();
    assert!(object::id_address(self) == derive_address(composition_id), EWrongPolicy);
    assert!(self.rate.value() == rate_bps, ERateMismatch);

    let recording_id = object::id(recording);
    let mut license = RecordingLicense {
        id: claim(recording.uid_mut(cap), ExtensionKey()),
        recording_id,
    };
    let (issuance, mut shares) = share::new(&mut license.id, SUPPLY, DECIMALS);
    let mut pool = pool::new<Currency>(&mut license.id, &issuance);

    let cut = self.rate.apply(SUPPLY);
    if (cut > 0) {
        let mut stake = stake::new(shares.split(cut), ctx);
        pool.register_stake(&mut stake);
        dof::add(&mut self.id, recording_id, stake);
    };

    issuance.share();
    transfer::share_object(license);
    emit(RecordingLicenseIssuedEvent { recording_id, composition_id, rate_bps });
    (shares, pool)
}

/// Creates another recording pool, registering the composition's stake if the
/// policy still holds it. Returned unshared, as with `issue`.
public fun new_recording_pool<Currency>(
    self: &mut RecordingLicensePolicy,
    license: &mut RecordingLicense,
    recording: &Recording,
    cap: &RecordingAdminCap,
    issuance: &Issuance,
): RoyaltyPool<Currency> {
    recording.authorize(cap);
    let recording_id = object::id(recording);
    assert!(license.recording_id == recording_id, EWrongLicense);
    assert!(object::id_address(self) == derive_address(recording.composition_id()), EWrongPolicy);

    let mut pool = pool::new<Currency>(&mut license.id, issuance);
    if (dof::exists(&self.id, recording_id)) {
        pool.register_stake(dof::borrow_mut(&mut self.id, recording_id));
    };
    pool
}

/// Claims a held stake's royalties from its recording pool and sends them to
/// the composition pool's address, where `pool::settle` folds them in.
/// Permissionless. Returns the value sent; 0 if the stake was withdrawn.
public fun sweep<Currency>(
    self: &mut RecordingLicensePolicy,
    recording_id: ID,
    recording_pool: &mut RoyaltyPool<Currency>,
): u64 {
    if (!dof::exists(&self.id, recording_id)) return 0;
    let reward = recording_pool.claim_rewards(dof::borrow_mut(&mut self.id, recording_id));
    let value = reward.value();
    if (value == 0) {
        reward.destroy_zero();
        return 0
    };
    reward.send_funds(derive_pool_address<Currency>(object::id(self)));
    emit(RecordingRoyaltySweptEvent<Currency> {
        composition_id: self.composition_id,
        recording_id,
        value,
    });
    value
}

// === View Functions ===

/// The policy address for a composition ID, or the license address for a
/// recording ID. Computes an address, not evidence the object exists.
public fun derive_address(parent_id: ID): address {
    derived_object::derive_address(parent_id, ExtensionKey())
}

/// The `Currency` pool address for a policy or license ID. Revenue for a
/// recording goes to its license's pool address; it waits there until the
/// pool exists and has registered stakes.
public fun derive_pool_address<Currency>(parent_id: ID): address {
    pool::derived_address<Currency>(parent_id, share::derive_address(parent_id).to_id())
}

public fun rate(self: &RecordingLicensePolicy): BPS { self.rate }

public fun composition_id(self: &RecordingLicensePolicy): ID { self.composition_id }

public fun recording_id(self: &RecordingLicense): ID { self.recording_id }

public fun is_licensed(recording: &Recording): bool {
    derived_object::exists(recording.uid(), ExtensionKey())
}

// === Private Functions ===

fun authorize(self: &RecordingLicensePolicy, composition: &Composition, cap: &CompositionAdminCap) {
    composition.authorize(cap);
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
