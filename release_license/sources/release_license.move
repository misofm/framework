// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module release_license::release_license;

use bps::bps::{Self, BPS};
use hikida::hikida;
use miso_music::{recording::{Recording, RecordingAdminCap}, release::{Release, ReleaseAdminCap}};
use royalty_pool::pool;
use sui::{
    accumulator::AccumulatorRoot,
    balance::Balance,
    coin::Coin,
    dynamic_field,
    event::emit,
    transfer::Receiving
};

// === Errors ===

const ENoSplit: u64 = 0;
const EWrongShareCount: u64 = 1;
const ESplitNotFull: u64 = 2;
const ENotTrack: u64 = 3;
const ENotAuthorized: u64 = 4;
const EAlreadyLicensed: u64 = 5;

// === Structs ===

public struct ReleaseSplitKey() has copy, drop, store;

public struct ReleaseAuthorization(ID) has copy, drop, store;

// === Events ===

public struct ReleaseLicenseCreatedEvent has copy, drop {
    release_id: ID,
    shares: vector<BPS>,
}

public struct ReleaseAuthorizedEvent has copy, drop {
    recording_id: ID,
    release_id: ID,
}

public struct ReleaseAuthorizationRevokedEvent has copy, drop {
    recording_id: ID,
    release_id: ID,
}

public struct ReleaseRevenueForwardedEvent<phantom Currency> has copy, drop {
    release_id: ID,
    values: vector<u64>,
    remainder: u64,
}

// === Public Functions ===

public fun forward<Currency>(release: &Release, mut revenue: Balance<Currency>) {
    if (revenue.value() == 0) return revenue.destroy_zero();
    let release_id = object::id(release);
    let shares = borrow_split(release);
    let total_value = revenue.value();
    let recording_ids = release.recording_ids();
    let values = vector::tabulate!(recording_ids.length(), |i| {
        let value = shares[i].apply(total_value);
        if (value > 0) {
            revenue.split(value).send_funds(pool::derive_address<Currency>(recording_ids[i]))
        };
        value
    });
    let remainder = revenue.value();
    if (remainder < total_value) {
        emit(ReleaseRevenueForwardedEvent<Currency> { release_id, values, remainder });
    };
    if (remainder == 0) revenue.destroy_zero() else revenue.send_funds(release_id.to_address())
}

// === View Functions ===

public fun has_split(release: &Release): bool {
    dynamic_field::exists(release.uid(), ReleaseSplitKey())
}

public fun split_shares(release: &Release): &vector<BPS> {
    borrow_split(release)
}

public fun is_authorized<RecordingShare>(
    recording: &Recording<RecordingShare>,
    release_id: ID,
): bool {
    dynamic_field::exists(recording.uid(), ReleaseAuthorization(release_id))
}

// === Admin Functions ===

public fun new(release: &mut Release, cap: &ReleaseAdminCap, shares: vector<BPS>) {
    let release_id = object::id(release);
    let track_count = release.recording_ids().length();
    let uid = release.uid_mut(cap);
    assert!(!dynamic_field::exists(uid, ReleaseSplitKey()), EAlreadyLicensed);
    assert!(shares.length() == track_count, EWrongShareCount);
    let total = shares.fold!(0u64, |total, share| total + (share.value() as u64));
    assert!(total == (bps::max().value() as u64), ESplitNotFull);
    dynamic_field::add(uid, ReleaseSplitKey(), shares);
    emit(ReleaseLicenseCreatedEvent { release_id, shares });
}

public fun authorize<RecordingShare>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    release: &Release,
) {
    let uid = recording.uid_mut(cap);
    let recording_id = uid.to_inner();
    assert!(has_split(release), ENoSplit);
    assert!(release.recording_ids().contains(&recording_id), ENotTrack);
    let release_id = object::id(release);
    let key = ReleaseAuthorization(release_id);
    if (dynamic_field::exists(uid, key)) return;
    dynamic_field::add(uid, key, true);
    emit(ReleaseAuthorizedEvent { recording_id, release_id });
}

public fun revoke<RecordingShare>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    release_id: ID,
) {
    let uid = recording.uid_mut(cap);
    let recording_id = uid.to_inner();
    let key = ReleaseAuthorization(release_id);
    assert!(dynamic_field::exists(uid, key), ENotAuthorized);
    let _: bool = dynamic_field::remove(uid, key);
    emit(ReleaseAuthorizationRevokedEvent { recording_id, release_id });
}

public fun redeem_and_forward<Currency>(
    release: &mut Release,
    cap: &ReleaseAdminCap,
    root: &AccumulatorRoot,
) {
    let revenue = hikida::redeem_settled_balance<Currency>(release.uid_mut(cap), root);
    forward(release, revenue)
}

public fun receive_and_forward<Currency>(
    release: &mut Release,
    cap: &ReleaseAdminCap,
    coins: vector<Receiving<Coin<Currency>>>,
) {
    let revenue = hikida::receive_coins_as_balance(release.uid_mut(cap), coins);
    forward(release, revenue)
}

// === Private Functions ===

fun borrow_split(release: &Release): &vector<BPS> {
    let uid = release.uid();
    assert!(dynamic_field::exists(uid, ReleaseSplitKey()), ENoSplit);
    dynamic_field::borrow(uid, ReleaseSplitKey())
}

// === Test Functions ===

#[test_only]
public fun release_license_created_event_fields(
    event: &ReleaseLicenseCreatedEvent,
): (ID, vector<BPS>) {
    (event.release_id, event.shares)
}

#[test_only]
public fun release_authorized_event_fields(event: &ReleaseAuthorizedEvent): (ID, ID) {
    (event.recording_id, event.release_id)
}

#[test_only]
public fun release_authorization_revoked_event_fields(
    event: &ReleaseAuthorizationRevokedEvent,
): (ID, ID) {
    (event.recording_id, event.release_id)
}

#[test_only]
public fun release_revenue_forwarded_event_fields<Currency>(
    event: &ReleaseRevenueForwardedEvent<Currency>,
): (ID, vector<u64>, u64) {
    (event.release_id, event.values, event.remainder)
}
