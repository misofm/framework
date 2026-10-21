// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

/// A composer publishes a policy, artists record and license the composition,
/// the composition's stake earns in the recording's canonical pools, royalties
/// flow to the composition's canonical pool address, and every guard holds.
/// Cross-composition and cross-recording misuse of caps, licenses and pools is
/// rejected by the type checker, so it has no runtime tests.
#[test_only]
module recording_license::recording_license_tests;

use std::unit_test::{assert_eq, destroy};
use sui::accumulator::{Self, AccumulatorRoot};
use sui::balance;
use sui::clock::{Self, Clock};
use sui::coin_registry::{Self, CoinRegistry, Currency};
use sui::derived_object;
use sui::event::events_by_type;
use sui::test_scenario::{Self, Scenario};
use miso_music::composition::{Self, Composition, CompositionAdminCap};
use miso_music::recording::{Self, Recording, RecordingAdminCap};
use royalty_pool::pool::{Self, RoyaltyPool};
use royalty_pool::stake::{Self, Stake};
use recording_license::recording_license::{Self, RecordingLicense, RecordingLicensePolicy};

const COMPOSER: address = @0xC0;
const ARTIST: address = @0xA1;
const STRANGER: address = @0x5;
const SUPPLY: u64 = 100_000_000_000_000;
/// Clock time used throughout; the real clock is never 0.
const T0: u64 = 1_000;

public struct C1() has drop;
public struct C2() has drop;
public struct R1 has key { id: UID }
public struct R2 has key { id: UID }
public struct R3 has key { id: UID }
public struct USD() has drop;
public struct EUR() has drop;

// === Helpers ===

fun id_of(addr: address): ID { object::id_from_address(addr) }

fun policy_id(composition_id: ID): ID { id_of(recording_license::derive_address(composition_id)) }

fun license_id(recording_id: ID): ID { id_of(recording_license::derive_address(recording_id)) }

fun pool_id<Currency>(work_id: ID): ID { id_of(pool::derive_address<Currency>(work_id)) }

fun cut_for(rate_bps: u16): u64 { SUPPLY / 10_000 * (rate_bps as u64) }

/// Begins as the system address to create the accumulator root and the
/// recording coins' shared `Currency` objects, each with `SUPPLY` fixed as
/// `share::mint` leaves it.
fun begin(): Scenario {
    let mut ts = test_scenario::begin(@0x0);
    accumulator::create_for_testing(ts.ctx());
    let mut registry = coin_registry::create_coin_data_registry_for_testing(ts.ctx());
    share_currency!<R1>(&mut registry, SUPPLY, ts.ctx());
    share_currency!<R2>(&mut registry, SUPPLY, ts.ctx());
    destroy(registry);
    ts
}

/// Shares a `Currency<$RecordingShare>` with `$supply` fixed. A macro because
/// `new_currency` must be called from the coin type's module.
macro fun share_currency<$RecordingShare: key>(
    $registry: &mut CoinRegistry,
    $supply: u64,
    $ctx: &mut TxContext,
) {
    let ctx = $ctx;
    let (mut initializer, mut treasury_cap) = coin_registry::new_currency<$RecordingShare>(
        $registry,
        6,
        b"RSHARE".to_string(),
        b"Recording Share".to_string(),
        b"".to_string(),
        b"".to_string(),
        ctx,
    );
    treasury_cap.mint_balance($supply).destroy_for_testing();
    initializer.make_supply_fixed(treasury_cap);
    destroy(initializer.finalize(ctx));
}

fun clock(ts: &mut Scenario): Clock {
    let mut clock = clock::create_for_testing(ts.ctx());
    clock.set_for_testing(T0);
    clock
}

/// The composer creates and publishes a composition with a policy at
/// `rate_bps`. Returns the composition ID and the composer's cap ID.
fun compose<CompositionShare>(ts: &mut Scenario, rate_bps: u16): (ID, ID) {
    ts.next_tx(COMPOSER);
    let (mut composition, cap) = composition::new_for_testing<CompositionShare>(ts.ctx());
    recording_license::new(&mut composition, &cap, rate_bps);
    let composition_id = object::id(&composition);
    let cap_id = object::id(&cap);
    composition.publish(&cap);
    transfer::public_transfer(cap, COMPOSER);
    (composition_id, cap_id)
}

/// The intended setup in one PTB: the artist records the composition, licenses
/// it at `rate_bps`, creates the USD pool, registers the composition's stake
/// and a stake of all remaining shares, then shares the pool and license.
/// Returns the recording ID, the recording cap ID and the artist's stake ID.
fun record_and_license<RecordingShare, CompositionShare>(
    ts: &mut Scenario,
    composition_id: ID,
    rate_bps: u16,
): (ID, ID, ID) {
    ts.next_tx(ARTIST);
    let policy = ts.take_shared_by_id<RecordingLicensePolicy<CompositionShare>>(
        policy_id(composition_id),
    );
    let root = ts.take_shared<AccumulatorRoot>();
    let currency = ts.take_shared<Currency<RecordingShare>>();
    let clock = clock(ts);
    let (mut recording, cap) = recording::new_for_testing<RecordingShare>(composition_id, ts.ctx());
    let recording_id = object::id(&recording);
    let cut = balance::create_for_testing<RecordingShare>(cut_for(rate_bps));
    let mut license = policy.issue(&mut recording, &cap, &currency, cut, ts.ctx());
    let mut pool = pool::new_recording_pool<RecordingShare, USD>(&mut recording, &cap);
    license.register(&mut pool, &root, &clock);
    let shares = balance::create_for_testing<RecordingShare>(SUPPLY - cut_for(rate_bps));
    let mut artist_stake = stake::new(shares, ts.ctx());
    pool.register_stake(&mut artist_stake, &root, &clock);
    assert_eq!(pool.staked_shares(), SUPPLY);
    pool.share();
    license.share();
    assert!(recording_license::is_licensed(&recording));
    let cap_id = object::id(&cap);
    let artist_stake_id = object::id(&artist_stake);
    recording.publish(&cap);
    transfer::public_transfer(cap, ARTIST);
    transfer::public_transfer(artist_stake, ARTIST);
    clock.destroy_for_testing();
    test_scenario::return_shared(currency);
    test_scenario::return_shared(root);
    test_scenario::return_shared(policy);
    (recording_id, cap_id, artist_stake_id)
}

/// The artist creates and shares an empty `Currency` pool for the recording.
fun open_pool<RecordingShare, Currency>(ts: &mut Scenario, recording_id: ID, cap_id: ID) {
    ts.next_tx(ARTIST);
    let mut recording = ts.take_shared_by_id<Recording<RecordingShare>>(recording_id);
    let cap = ts.take_from_sender_by_id<RecordingAdminCap<RecordingShare>>(cap_id);
    pool::new_recording_pool<RecordingShare, Currency>(&mut recording, &cap).share();
    test_scenario::return_shared(recording);
    ts.return_to_sender(cap);
}

// === Happy paths ===

#[test]
fun licensed_recording_pays_the_composition_its_cut() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 2_000);
    let set = events_by_type<recording_license::RecordingLicensePolicyRateSetEvent>();
    assert_eq!(set.length(), 1);
    let (set_policy_id, set_composition_id, set_rate_bps) =
        recording_license::rate_set_event_fields(&set[0]);
    assert_eq!(set_policy_id, policy_id(composition_id));
    assert_eq!(set_composition_id, composition_id);
    assert_eq!(set_rate_bps, 2_000);

    let (recording_id, _, artist_stake_id) =
        record_and_license<R1, C1>(&mut ts, composition_id, 2_000);
    let issued = events_by_type<recording_license::RecordingLicenseIssuedEvent>();
    assert_eq!(issued.length(), 1);
    let (
        issued_license_id,
        issued_recording_id,
        issued_composition_id,
        issued_rate_bps,
        issued_cut,
        issued_stake_id,
    ) = recording_license::issued_event_fields(&issued[0]);
    assert_eq!(issued_license_id, license_id(recording_id));
    assert_eq!(issued_recording_id, recording_id);
    assert_eq!(issued_composition_id, composition_id);
    assert_eq!(issued_rate_bps, 2_000);
    assert_eq!(issued_cut, SUPPLY / 5);

    // 1,000 units of revenue arrive; anyone sweeps the composition's 20%.
    ts.next_tx(STRANGER);
    let mut license = ts.take_shared_by_id<RecordingLicense<R1, C1>>(license_id(recording_id));
    assert_eq!(license.recording_id(), recording_id);
    assert_eq!(license.composition_id(), composition_id);
    assert_eq!(license.stake().borrow().value(), SUPPLY / 5);
    assert_eq!(issued_stake_id, option::some(object::id(license.stake().borrow())));
    let mut recording_pool = ts.take_shared_by_id<RoyaltyPool<R1, USD>>(
        pool_id<USD>(recording_id),
    );
    recording_pool.deposit(balance::create_for_testing<USD>(1_000));
    assert_eq!(recording_pool.pending_royalties(license.stake().borrow()), 200);
    assert_eq!(license.sweep(&mut recording_pool), 200);
    let swept = events_by_type<recording_license::RecordingRoyaltySweptEvent<USD>>();
    assert_eq!(swept.length(), 1);
    let (swept_recording_id, swept_composition_id, swept_value) =
        recording_license::swept_event_fields(&swept[0]);
    assert_eq!(swept_recording_id, recording_id);
    assert_eq!(swept_composition_id, composition_id);
    assert_eq!(swept_value, 200);
    assert_eq!(license.sweep(&mut recording_pool), 0);
    test_scenario::return_shared(license);

    // The artist's stake has the other 80%.
    ts.next_tx(ARTIST);
    let mut artist_stake = ts.take_from_sender_by_id<Stake<R1>>(artist_stake_id);
    assert_eq!(recording_pool.claim_royalties(&mut artist_stake).destroy_for_testing(), 800);
    ts.return_to_sender(artist_stake);
    test_scenario::return_shared(recording_pool);
    ts.end();
}

#[test]
fun zero_rate_licenses_without_a_stake() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 0);
    let (recording_id, _, _) = record_and_license<R1, C1>(&mut ts, composition_id, 0);
    let issued = events_by_type<recording_license::RecordingLicenseIssuedEvent>();
    let (_, _, _, _, cut, stake_id) = recording_license::issued_event_fields(&issued[0]);
    assert_eq!(cut, 0);
    assert!(stake_id.is_none());

    ts.next_tx(STRANGER);
    let mut license = ts.take_shared_by_id<RecordingLicense<R1, C1>>(license_id(recording_id));
    assert!(license.stake().is_none());
    let mut recording_pool = ts.take_shared_by_id<RoyaltyPool<R1, USD>>(pool_id<USD>(recording_id));
    assert_eq!(recording_pool.staked_shares(), SUPPLY);
    let root = ts.take_shared<AccumulatorRoot>();
    let clock = clock(&mut ts);
    license.register(&mut recording_pool, &root, &clock);
    recording_pool.deposit(balance::create_for_testing<USD>(1_000));
    assert_eq!(license.sweep(&mut recording_pool), 0);
    let recording = ts.take_shared_by_id<Recording<R1>>(recording_id);
    assert!(recording_license::is_licensed(&recording));
    clock.destroy_for_testing();
    test_scenario::return_shared(recording);
    test_scenario::return_shared(root);
    test_scenario::return_shared(recording_pool);
    test_scenario::return_shared(license);
    ts.end();
}

#[test]
fun rate_changes_apply_only_to_future_licenses() {
    let mut ts = begin();
    let (composition_id, composer_cap_id) = compose<C1>(&mut ts, 2_000);
    let (first_id, _, _) = record_and_license<R1, C1>(&mut ts, composition_id, 2_000);

    ts.next_tx(COMPOSER);
    let cap = ts.take_from_sender_by_id<CompositionAdminCap<C1>>(composer_cap_id);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy<C1>>(policy_id(composition_id));
    policy.set_rate(&cap, 1_000);
    assert_eq!(policy.rate().value(), 1_000);
    // Setting the same rate again is silent.
    policy.set_rate(&cap, 1_000);
    let set = events_by_type<recording_license::RecordingLicensePolicyRateSetEvent>();
    assert_eq!(set.length(), 1);
    let (set_policy_id, set_composition_id, set_rate_bps) =
        recording_license::rate_set_event_fields(&set[0]);
    assert_eq!(set_policy_id, object::id(&policy));
    assert_eq!(set_composition_id, composition_id);
    assert_eq!(set_rate_bps, 1_000);
    test_scenario::return_shared(policy);
    ts.return_to_sender(cap);

    let (second_id, _, _) = record_and_license<R2, C1>(&mut ts, composition_id, 1_000);

    ts.next_tx(STRANGER);
    let first = ts.take_shared_by_id<RecordingLicense<R1, C1>>(license_id(first_id));
    let second = ts.take_shared_by_id<RecordingLicense<R2, C1>>(license_id(second_id));
    assert_eq!(first.stake().borrow().value(), SUPPLY / 5);
    assert_eq!(second.stake().borrow().value(), SUPPLY / 10);
    test_scenario::return_shared(first);
    test_scenario::return_shared(second);
    ts.end();
}

/// The migration path: the composer withdraws the stake with its unclaimed
/// royalties, then unregisters it, collecting them, and unwraps it into the cut.
#[test]
fun withdrawn_stake_migrates_with_its_royalties() {
    let mut ts = begin();
    let (composition_id, composer_cap_id) = compose<C1>(&mut ts, 2_500);
    let (recording_id, _, _) = record_and_license<R1, C1>(&mut ts, composition_id, 2_500);

    ts.next_tx(COMPOSER);
    let cap = ts.take_from_sender_by_id<CompositionAdminCap<C1>>(composer_cap_id);
    let mut license = ts.take_shared_by_id<RecordingLicense<R1, C1>>(license_id(recording_id));
    let mut recording_pool = ts.take_shared_by_id<RoyaltyPool<R1, USD>>(pool_id<USD>(recording_id));
    let root = ts.take_shared<AccumulatorRoot>();
    let clock = clock(&mut ts);
    recording_pool.deposit(balance::create_for_testing<USD>(1_000));
    let mut stake = license.withdraw(&cap);
    let withdrawn = events_by_type<recording_license::RecordingStakeWithdrawnEvent>();
    assert_eq!(withdrawn.length(), 1);
    let (withdrawn_recording_id, withdrawn_composition_id) =
        recording_license::withdrawn_event_fields(&withdrawn[0]);
    assert_eq!(withdrawn_recording_id, recording_id);
    assert_eq!(withdrawn_composition_id, composition_id);
    assert!(license.stake().is_none());

    // The emptied license is inert, so keeper batches continue.
    assert_eq!(license.sweep(&mut recording_pool), 0);
    license.register(&mut recording_pool, &root, &clock);
    assert_eq!(recording_pool.staked_shares(), SUPPLY);

    let royalties = recording_pool.unregister_stake(&mut stake, &root, &clock);
    assert_eq!(royalties.destroy_for_testing(), 250);
    assert_eq!(recording_pool.staked_shares(), SUPPLY / 4 * 3);
    assert_eq!(stake.destroy().destroy_for_testing(), SUPPLY / 4);

    let recording = ts.take_shared_by_id<Recording<R1>>(recording_id);
    assert!(recording_license::is_licensed(&recording));
    clock.destroy_for_testing();
    test_scenario::return_shared(recording);
    test_scenario::return_shared(root);
    test_scenario::return_shared(recording_pool);
    test_scenario::return_shared(license);
    ts.return_to_sender(cap);
    ts.end();
}

/// A pool added later, such as one for merch revenue in another currency, takes
/// the same composition stake.
#[test]
fun register_adds_the_stake_to_a_later_currency_pool() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 2_000);
    let (recording_id, recording_cap_id, _) =
        record_and_license<R1, C1>(&mut ts, composition_id, 2_000);

    ts.next_tx(ARTIST);
    let mut license = ts.take_shared_by_id<RecordingLicense<R1, C1>>(license_id(recording_id));
    let mut recording = ts.take_shared_by_id<Recording<R1>>(recording_id);
    let cap = ts.take_from_sender_by_id<RecordingAdminCap<R1>>(recording_cap_id);
    let root = ts.take_shared<AccumulatorRoot>();
    let clock = clock(&mut ts);
    let mut eur_pool = pool::new_recording_pool<R1, EUR>(&mut recording, &cap);
    license.register(&mut eur_pool, &root, &clock);
    assert_eq!(eur_pool.staked_shares(), SUPPLY / 5);
    eur_pool.deposit(balance::create_for_testing<EUR>(10));
    assert_eq!(license.sweep(&mut eur_pool), 10);
    eur_pool.share();
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    test_scenario::return_shared(license);
    test_scenario::return_shared(recording);
    ts.return_to_sender(cap);
    ts.end();
}

/// A pool shared before the composition's stake was registered can be fixed by
/// anyone, and a repeat registration is a no-op.
#[test]
fun anyone_registers_the_stake_once() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 2_000);
    let (recording_id, recording_cap_id, _) =
        record_and_license<R1, C1>(&mut ts, composition_id, 2_000);
    open_pool<R1, EUR>(&mut ts, recording_id, recording_cap_id);

    ts.next_tx(STRANGER);
    let mut license = ts.take_shared_by_id<RecordingLicense<R1, C1>>(license_id(recording_id));
    let mut eur_pool = ts.take_shared_by_id<RoyaltyPool<R1, EUR>>(pool_id<EUR>(recording_id));
    assert_eq!(eur_pool.staked_shares(), 0);
    let root = ts.take_shared<AccumulatorRoot>();
    let clock = clock(&mut ts);
    license.register(&mut eur_pool, &root, &clock);
    assert_eq!(eur_pool.staked_shares(), SUPPLY / 5);
    license.register(&mut eur_pool, &root, &clock);
    assert_eq!(eur_pool.staked_shares(), SUPPLY / 5);
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    test_scenario::return_shared(eur_pool);
    test_scenario::return_shared(license);
    ts.end();
}

#[test]
fun sweep_returns_zero_in_an_unregistered_currency() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 2_000);
    let (recording_id, recording_cap_id, _) =
        record_and_license<R1, C1>(&mut ts, composition_id, 2_000);
    open_pool<R1, EUR>(&mut ts, recording_id, recording_cap_id);

    ts.next_tx(STRANGER);
    let mut license = ts.take_shared_by_id<RecordingLicense<R1, C1>>(license_id(recording_id));
    let mut eur_pool = ts.take_shared_by_id<RoyaltyPool<R1, EUR>>(pool_id<EUR>(recording_id));
    assert_eq!(license.sweep(&mut eur_pool), 0);
    assert!(events_by_type<recording_license::RecordingRoyaltySweptEvent<EUR>>().is_empty());
    test_scenario::return_shared(eur_pool);
    test_scenario::return_shared(license);
    ts.end();
}

/// Each sweep pays only what accrued since the last one.
#[test]
fun sweep_after_sweep_pays_only_the_new_cut() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 2_000);
    let (recording_id, _, _) = record_and_license<R1, C1>(&mut ts, composition_id, 2_000);

    ts.next_tx(STRANGER);
    let mut license = ts.take_shared_by_id<RecordingLicense<R1, C1>>(license_id(recording_id));
    let mut recording_pool = ts.take_shared_by_id<RoyaltyPool<R1, USD>>(
        pool_id<USD>(recording_id),
    );
    recording_pool.deposit(balance::create_for_testing<USD>(1_000));
    assert_eq!(license.sweep(&mut recording_pool), 200);
    recording_pool.deposit(balance::create_for_testing<USD>(500));
    assert_eq!(license.sweep(&mut recording_pool), 100);
    assert_eq!(license.sweep(&mut recording_pool), 0);
    test_scenario::return_shared(recording_pool);
    test_scenario::return_shared(license);
    ts.end();
}

/// The cut floors `supply × rate / 10_000`: 10,001 shares at 1 bps owe 1.
#[test]
fun issue_floors_an_indivisible_supply() {
    let mut ts = begin();
    let mut registry = coin_registry::create_coin_data_registry_for_testing(ts.ctx());
    share_currency!<R3>(&mut registry, 10_001, ts.ctx());
    destroy(registry);
    let (composition_id, _) = compose<C1>(&mut ts, 1);

    ts.next_tx(ARTIST);
    let policy = ts.take_shared_by_id<RecordingLicensePolicy<C1>>(policy_id(composition_id));
    let currency = ts.take_shared<Currency<R3>>();
    let (mut recording, cap) = recording::new_for_testing<R3>(composition_id, ts.ctx());
    let cut = balance::create_for_testing<R3>(1);
    let license = policy.issue(&mut recording, &cap, &currency, cut, ts.ctx());
    assert_eq!(license.stake().borrow().value(), 1);
    license.share();
    recording.publish(&cap);
    destroy(cap);
    test_scenario::return_shared(currency);
    test_scenario::return_shared(policy);
    ts.end();
}

/// A nonzero rate of a small supply can floor to a zero cut: no stake.
#[test]
fun issue_with_a_zero_cut_at_a_nonzero_rate_has_no_stake() {
    let mut ts = begin();
    let mut registry = coin_registry::create_coin_data_registry_for_testing(ts.ctx());
    share_currency!<R3>(&mut registry, 9_999, ts.ctx());
    destroy(registry);
    let (composition_id, _) = compose<C1>(&mut ts, 1);

    ts.next_tx(ARTIST);
    let policy = ts.take_shared_by_id<RecordingLicensePolicy<C1>>(policy_id(composition_id));
    let currency = ts.take_shared<Currency<R3>>();
    let (mut recording, cap) = recording::new_for_testing<R3>(composition_id, ts.ctx());
    let cut = balance::zero<R3>();
    let license = policy.issue(&mut recording, &cap, &currency, cut, ts.ctx());
    assert!(license.stake().is_none());
    let issued = events_by_type<recording_license::RecordingLicenseIssuedEvent>();
    assert_eq!(issued.length(), 1);
    let (event_license_id, _, _, rate_bps, cut, stake_id) =
        recording_license::issued_event_fields(&issued[0]);
    assert_eq!(event_license_id, object::id(&license));
    assert_eq!(rate_bps, 1);
    assert_eq!(cut, 0);
    assert!(stake_id.is_none());
    license.share();
    recording.publish(&cap);
    destroy(cap);
    test_scenario::return_shared(currency);
    test_scenario::return_shared(policy);
    ts.end();
}

/// `set_rate` accepts the cap itself and zero.
#[test]
fun set_rate_accepts_the_cap_and_zero() {
    let mut ts = begin();
    let (composition_id, composer_cap_id) = compose<C1>(&mut ts, 2_000);

    ts.next_tx(COMPOSER);
    let cap = ts.take_from_sender_by_id<CompositionAdminCap<C1>>(composer_cap_id);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy<C1>>(policy_id(composition_id));
    policy.set_rate(&cap, 2_500);
    assert_eq!(policy.rate().value(), 2_500);
    policy.set_rate(&cap, 0);
    assert_eq!(policy.rate().value(), 0);
    let set = events_by_type<recording_license::RecordingLicensePolicyRateSetEvent>();
    assert_eq!(set.length(), 2);
    let (_, _, first_rate_bps) = recording_license::rate_set_event_fields(&set[0]);
    let (_, _, second_rate_bps) = recording_license::rate_set_event_fields(&set[1]);
    assert_eq!(first_rate_bps, 2_500);
    assert_eq!(second_rate_bps, 0);
    test_scenario::return_shared(policy);
    ts.return_to_sender(cap);
    ts.end();
}

/// `has_policy`, `policy_composition_id` and `is_licensed` before and after.
#[test]
fun policy_and_license_views() {
    let mut ts = begin();
    ts.next_tx(COMPOSER);
    let (mut composition, cap) = composition::new_for_testing<C1>(ts.ctx());
    assert!(!recording_license::has_policy(&composition));
    recording_license::new(&mut composition, &cap, 2_000);
    assert!(recording_license::has_policy(&composition));
    let composition_id = object::id(&composition);
    composition.publish(&cap);
    transfer::public_transfer(cap, COMPOSER);

    ts.next_tx(ARTIST);
    let policy = ts.take_shared_by_id<RecordingLicensePolicy<C1>>(policy_id(composition_id));
    assert_eq!(policy.policy_composition_id(), composition_id);
    let currency = ts.take_shared<Currency<R1>>();
    let (mut recording, cap) = recording::new_for_testing<R1>(composition_id, ts.ctx());
    assert!(!recording_license::is_licensed(&recording));
    let cut = balance::create_for_testing<R1>(SUPPLY / 5);
    let license = policy.issue(&mut recording, &cap, &currency, cut, ts.ctx());
    assert!(recording_license::is_licensed(&recording));
    assert_eq!(license.composition_id(), policy.policy_composition_id());
    license.share();
    recording.publish(&cap);
    destroy(cap);
    test_scenario::return_shared(currency);
    test_scenario::return_shared(policy);
    ts.end();
}

// === Properties ===

/// With the composition's stake registered from the start, it earns at least
/// its rate of every deposit however other holders join and leave, and the
/// pool pays out everything but dust.
#[random_test]
fun composition_earns_at_least_its_rate(
    rate_seed: u16,
    artist_seed: u64,
    fan_seed: u64,
    first_seed: u64,
    second_seed: u64,
    third_seed: u64,
) {
    let rate_bps = rate_seed % 2_501;
    let cut = cut_for(rate_bps);
    let remaining = SUPPLY - cut;
    let artist_amount = 1 + artist_seed % remaining;
    let fan_amount = fan_seed % (remaining - artist_amount + 1);
    let first = 1 + first_seed % 1_000_000_000_000;
    let second = 1 + second_seed % 1_000_000_000_000;
    let third = 1 + third_seed % 1_000_000_000_000;

    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, rate_bps);
    ts.next_tx(ARTIST);
    let policy = ts.take_shared_by_id<RecordingLicensePolicy<C1>>(policy_id(composition_id));
    let root = ts.take_shared<AccumulatorRoot>();
    let currency = ts.take_shared<Currency<R1>>();
    let clock = clock(&mut ts);
    let (mut recording, cap) = recording::new_for_testing<R1>(composition_id, ts.ctx());
    let cut_balance = balance::create_for_testing<R1>(cut);
    let mut license = policy.issue(&mut recording, &cap, &currency, cut_balance, ts.ctx());
    let mut pool = pool::new_recording_pool<R1, USD>(&mut recording, &cap);
    license.register(&mut pool, &root, &clock);
    let artist_shares = balance::create_for_testing<R1>(artist_amount);
    let mut artist = stake::new(artist_shares, ts.ctx());
    pool.register_stake(&mut artist, &root, &clock);
    let mut paid = 0u128;

    // The fan stakes for the first deposit, leaves for the second and
    // returns for the third.
    let mut fan = if (fan_amount > 0) {
        let mut fan = stake::new(balance::create_for_testing<R1>(fan_amount), ts.ctx());
        pool.register_stake(&mut fan, &root, &clock);
        option::some(fan)
    } else option::none();
    pool.deposit(balance::create_for_testing<USD>(first));
    if (fan.is_some()) {
        let fan = fan.borrow_mut();
        paid = paid + (pool.unregister_stake(fan, &root, &clock).destroy_for_testing() as u128);
    };
    pool.deposit(balance::create_for_testing<USD>(second));
    if (fan.is_some()) pool.register_stake(fan.borrow_mut(), &root, &clock);
    pool.deposit(balance::create_for_testing<USD>(third));

    let deposited = (first as u128) + (second as u128) + (third as u128);
    let composition_paid = license.sweep(&mut pool) as u128;
    assert!(composition_paid >= (cut as u128) * deposited / (SUPPLY as u128));
    paid = paid + composition_paid;
    paid = paid + (pool.claim_royalties(&mut artist).destroy_for_testing() as u128);
    if (fan.is_some()) {
        paid = paid + (pool.claim_royalties(fan.borrow_mut()).destroy_for_testing() as u128);
    };
    assert!(paid <= deposited);
    assert!(deposited - paid <= 5);

    pool.share();
    license.share();
    recording.publish(&cap);
    destroy(artist);
    destroy(fan);
    destroy(cap);
    clock.destroy_for_testing();
    test_scenario::return_shared(currency);
    test_scenario::return_shared(root);
    test_scenario::return_shared(policy);
    ts.end();
}

// === Guards ===

#[test, expected_failure(abort_code = recording_license::ERateTooHigh)]
fun new_rejects_rate_above_cap() {
    let ctx = &mut tx_context::dummy();
    let (mut composition, cap) = composition::new_for_testing<C1>(ctx);
    recording_license::new(&mut composition, &cap, 2_501);
    destroy(composition);
    destroy(cap);
}

#[test, expected_failure(abort_code = recording_license::ERateTooHigh)]
fun set_rate_rejects_rate_above_cap() {
    let mut ts = begin();
    let (composition_id, composer_cap_id) = compose<C1>(&mut ts, 2_000);
    ts.next_tx(COMPOSER);
    let cap = ts.take_from_sender_by_id<CompositionAdminCap<C1>>(composer_cap_id);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy<C1>>(policy_id(composition_id));
    policy.set_rate(&cap, 2_501);
    abort
}

/// A cut for an older or wrong rate aborts, so a concurrent rate change fails.
#[test, expected_failure(abort_code = recording_license::EWrongCut)]
fun issue_rejects_a_cut_for_a_lower_rate() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 2_000);
    record_and_license<R1, C1>(&mut ts, composition_id, 1_500);
    abort
}

#[test, expected_failure(abort_code = recording_license::EWrongCut)]
fun issue_rejects_a_cut_for_a_higher_rate() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 2_000);
    record_and_license<R1, C1>(&mut ts, composition_id, 2_500);
    abort
}

#[test, expected_failure(abort_code = recording_license::EWrongCut)]
fun issue_rejects_a_wrong_cut() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 2_000);

    ts.next_tx(ARTIST);
    let policy = ts.take_shared_by_id<RecordingLicensePolicy<C1>>(policy_id(composition_id));
    let (mut recording, cap) = recording::new_for_testing<R1>(composition_id, ts.ctx());
    let cut = balance::create_for_testing<R1>(SUPPLY / 5 - 1);
    let currency = ts.take_shared<Currency<R1>>();
    policy.issue(&mut recording, &cap, &currency, cut, ts.ctx()).share();
    abort
}

/// The cut is a rate of the supply fixed in the coin's `Currency`, not of a
/// constant: a coin with a tenth of the usual supply owes a tenth of the cut.
#[test]
fun issue_reads_the_supply_from_the_currency() {
    let mut ts = begin();
    let mut registry = coin_registry::create_coin_data_registry_for_testing(ts.ctx());
    share_currency!<R3>(&mut registry, SUPPLY / 10, ts.ctx());
    destroy(registry);
    let (composition_id, _) = compose<C1>(&mut ts, 2_000);

    ts.next_tx(ARTIST);
    let policy = ts.take_shared_by_id<RecordingLicensePolicy<C1>>(policy_id(composition_id));
    let currency = ts.take_shared<Currency<R3>>();
    let (mut recording, cap) = recording::new_for_testing<R3>(composition_id, ts.ctx());
    let cut = balance::create_for_testing<R3>(SUPPLY / 50);
    let license = policy.issue(&mut recording, &cap, &currency, cut, ts.ctx());
    assert_eq!(license.stake().borrow().value(), SUPPLY / 50);
    license.share();
    recording.publish(&cap);
    destroy(cap);
    test_scenario::return_shared(currency);
    test_scenario::return_shared(policy);
    ts.end();
}

#[test, expected_failure(abort_code = derived_object::EObjectAlreadyExists)]
fun a_recording_is_licensed_once() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 2_000);
    let (recording_id, recording_cap_id, _) =
        record_and_license<R1, C1>(&mut ts, composition_id, 2_000);

    ts.next_tx(ARTIST);
    let policy = ts.take_shared_by_id<RecordingLicensePolicy<C1>>(policy_id(composition_id));
    let mut recording = ts.take_shared_by_id<Recording<R1>>(recording_id);
    let cap = ts.take_from_sender_by_id<RecordingAdminCap<R1>>(recording_cap_id);
    let cut = balance::create_for_testing<R1>(SUPPLY / 5);
    let currency = ts.take_shared<Currency<R1>>();
    policy.issue(&mut recording, &cap, &currency, cut, ts.ctx()).share();
    abort
}

#[test, expected_failure(abort_code = recording_license::EWrongPolicy)]
fun issue_rejects_another_compositions_policy() {
    let mut ts = begin();
    let (first_id, _) = compose<C1>(&mut ts, 2_000);
    let (second_id, _) = compose<C2>(&mut ts, 2_000);

    ts.next_tx(ARTIST);
    let first_policy = ts.take_shared_by_id<RecordingLicensePolicy<C1>>(policy_id(first_id));
    let (mut recording, cap) = recording::new_for_testing<R1>(second_id, ts.ctx());
    let cut = balance::create_for_testing<R1>(SUPPLY / 5);
    let currency = ts.take_shared<Currency<R1>>();
    first_policy.issue(&mut recording, &cap, &currency, cut, ts.ctx()).share();
    abort
}

#[test, expected_failure(abort_code = recording_license::ENoStake)]
fun withdraw_rejects_a_license_without_a_stake() {
    let mut ts = begin();
    let (composition_id, composer_cap_id) = compose<C1>(&mut ts, 0);
    let (recording_id, _, _) = record_and_license<R1, C1>(&mut ts, composition_id, 0);

    ts.next_tx(COMPOSER);
    let cap = ts.take_from_sender_by_id<CompositionAdminCap<C1>>(composer_cap_id);
    let mut license = ts.take_shared_by_id<RecordingLicense<R1, C1>>(license_id(recording_id));
    destroy(license.withdraw(&cap));
    abort
}

/// The recording admin cannot open a second pool in a currency to route
/// revenue around the composition's stake.
#[test, expected_failure(abort_code = derived_object::EObjectAlreadyExists)]
fun recording_admin_cannot_open_a_second_pool() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 2_000);
    let (recording_id, recording_cap_id, _) =
        record_and_license<R1, C1>(&mut ts, composition_id, 2_000);
    open_pool<R1, USD>(&mut ts, recording_id, recording_cap_id);
    abort
}

/// A composition has one policy.
#[test, expected_failure(abort_code = derived_object::EObjectAlreadyExists)]
fun new_twice_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut composition, cap) = composition::new_for_testing<C1>(ctx);
    recording_license::new(&mut composition, &cap, 2_000);
    recording_license::new(&mut composition, &cap, 1_000);
    abort
}

/// A zero-rate policy owes a zero cut.
#[test, expected_failure(abort_code = recording_license::EWrongCut)]
fun issue_rejects_a_positive_cut_at_a_zero_rate() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 0);
    record_and_license<R1, C1>(&mut ts, composition_id, 1);
    abort
}

#[test, expected_failure(abort_code = recording_license::ENoStake)]
fun withdraw_twice_aborts() {
    let mut ts = begin();
    let (composition_id, composer_cap_id) = compose<C1>(&mut ts, 2_000);
    let (recording_id, _, _) = record_and_license<R1, C1>(&mut ts, composition_id, 2_000);

    ts.next_tx(COMPOSER);
    let cap = ts.take_from_sender_by_id<CompositionAdminCap<C1>>(composer_cap_id);
    let mut license = ts.take_shared_by_id<RecordingLicense<R1, C1>>(license_id(recording_id));
    let stake = license.withdraw(&cap);
    destroy(stake);
    destroy(license.withdraw(&cap));
    abort
}
