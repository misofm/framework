// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module release_license::release_license;

// === Imports ===

use sui::accumulator::AccumulatorRoot;
use sui::balance::Balance;
use sui::bcs::to_bytes;
use sui::coin::Coin;
use sui::dynamic_field;
use sui::event::emit;
use sui::hash::blake2b256;
use sui::transfer::Receiving;
use hikida::hikida;
use miso_music::recording::{Recording, RecordingAdminCap};
use miso_music::release::{Release, ReleaseAdminCap};
use royalty_pool::pool;

// === Errors ===

const ENoSplit: u64 = 0;
const EWrongWeightCount: u64 = 1;
const EZeroWeight: u64 = 2;
const ESplitMismatch: u64 = 3;
const ENotTrack: u64 = 4;
const ENotAuthorized: u64 = 5;

// === Structs ===

public struct ReleaseSplit has store {
    weights: vector<u64>,
    hash: vector<u8>,
}

public struct ReleaseSplitKey() has copy, drop, store;

public struct ReleaseAuthorization(vector<u8>) has copy, drop, store;

// === Events ===

public struct ReleaseSplitSetEvent has copy, drop {
    release_id: ID,
    weights: vector<u64>,
    hash: vector<u8>,
}

public struct ReleaseAuthorizedEvent has copy, drop {
    recording_id: ID,
    release_id: ID,
    hash: vector<u8>,
}

public struct ReleaseAuthorizationRevokedEvent has copy, drop {
    recording_id: ID,
    release_id: ID,
    hash: vector<u8>,
}

public struct ReleaseRevenueForwardedEvent<phantom Currency> has copy, drop {
    release_id: ID,
    hash: vector<u8>,
    values: vector<u64>,
    remainder: u64,
}

// === Public Functions ===

public fun forward<Currency>(release: &Release, mut revenue: Balance<Currency>) {
    if (revenue.value() == 0) return revenue.destroy_zero();
    let release_id = object::id(release);
    let split = borrow_split(release);
    let total_value = revenue.value();
    let mut total_weight = 0u128;
    split.weights.do_ref!(|weight| total_weight = total_weight + (*weight as u128));
    let recording_ids = release.recording_ids();
    let values = vector::tabulate!(recording_ids.length(), |i| {
        let value = ((total_value as u128) * (split.weights[i] as u128) / total_weight) as u64;
        if (value > 0) {
            revenue.split(value).send_funds(pool::derive_address<Currency>(recording_ids[i]))
        };
        value
    });
    let remainder = revenue.value();
    if (remainder < total_value) {
        emit(ReleaseRevenueForwardedEvent<Currency> {
            release_id,
            hash: split.hash,
            values,
            remainder,
        });
    };
    if (remainder == 0) revenue.destroy_zero()
    else revenue.send_funds(release_id.to_address())
}

// === View Functions ===

public fun has_split(release: &Release): bool {
    dynamic_field::exists(release.uid(), ReleaseSplitKey())
}

public fun split_weights(release: &Release): &vector<u64> {
    &borrow_split(release).weights
}

public fun split_hash(release: &Release): &vector<u8> {
    &borrow_split(release).hash
}

public fun is_authorized<RecordingShare>(
    recording: &Recording<RecordingShare>,
    hash: vector<u8>,
): bool {
    dynamic_field::exists(recording.uid(), ReleaseAuthorization(hash))
}

// === Admin Functions ===

public fun set_split(release: &mut Release, cap: &ReleaseAdminCap, weights: vector<u64>) {
    let release_id = object::id(release);
    let track_count = release.recording_ids().length();
    let uid = release.uid_mut(cap);
    assert!(weights.length() == track_count, EWrongWeightCount);
    assert!(weights.all!(|weight| *weight > 0), EZeroWeight);
    let mut hash_input = to_bytes(&release_id);
    hash_input.append(to_bytes(&weights));
    let hash = blake2b256(&hash_input);
    if (dynamic_field::exists(uid, ReleaseSplitKey())) {
        let split: &mut ReleaseSplit = dynamic_field::borrow_mut(uid, ReleaseSplitKey());
        split.weights = weights;
        split.hash = hash;
    } else {
        dynamic_field::add(uid, ReleaseSplitKey(), ReleaseSplit { weights, hash });
    };
    emit(ReleaseSplitSetEvent { release_id, weights, hash });
}

public fun authorize<RecordingShare>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    release: &Release,
    hash: vector<u8>,
) {
    let uid = recording.uid_mut(cap);
    let recording_id = uid.to_inner();
    assert!(borrow_split(release).hash == hash, ESplitMismatch);
    assert!(release.recording_ids().contains(&recording_id), ENotTrack);
    let key = ReleaseAuthorization(hash);
    if (dynamic_field::exists(uid, key)) return;
    let release_id = object::id(release);
    dynamic_field::add(uid, key, release_id);
    emit(ReleaseAuthorizedEvent { recording_id, release_id, hash });
}

public fun revoke<RecordingShare>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    hash: vector<u8>,
) {
    let uid = recording.uid_mut(cap);
    let recording_id = uid.to_inner();
    let key = ReleaseAuthorization(hash);
    assert!(dynamic_field::exists(uid, key), ENotAuthorized);
    let release_id: ID = dynamic_field::remove(uid, key);
    emit(ReleaseAuthorizationRevokedEvent { recording_id, release_id, hash });
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

fun borrow_split(release: &Release): &ReleaseSplit {
    let uid = release.uid();
    assert!(dynamic_field::exists(uid, ReleaseSplitKey()), ENoSplit);
    dynamic_field::borrow(uid, ReleaseSplitKey())
}

// === Test Functions ===

#[test_only]
public fun release_split_set_event_fields(
    event: &ReleaseSplitSetEvent,
): (ID, vector<u64>, vector<u8>) {
    (event.release_id, event.weights, event.hash)
}

#[test_only]
public fun release_authorized_event_fields(event: &ReleaseAuthorizedEvent): (ID, ID, vector<u8>) {
    (event.recording_id, event.release_id, event.hash)
}

#[test_only]
public fun release_authorization_revoked_event_fields(
    event: &ReleaseAuthorizationRevokedEvent,
): (ID, ID, vector<u8>) {
    (event.recording_id, event.release_id, event.hash)
}

#[test_only]
public fun release_revenue_forwarded_event_fields<Currency>(
    event: &ReleaseRevenueForwardedEvent<Currency>,
): (ID, vector<u8>, vector<u64>, u64) {
    (event.release_id, event.hash, event.values, event.remainder)
}
