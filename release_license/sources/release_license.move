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
    derived_object,
    dynamic_field,
    event::emit,
    transfer::Receiving
};

// === Errors ===

const EWrongSplitCount: u64 = 0;
const ESplitNotFull: u64 = 1;
const EWrongRelease: u64 = 2;
const ENotTrack: u64 = 3;
const ENoAuthorization: u64 = 4;
const EAlreadyAuthorized: u64 = 5;
const ESplitsLocked: u64 = 6;
const EUnauthorized: u64 = 7;

// === Structs ===

public struct ReleaseLicense has key {
    id: UID,
    state: ReleaseLicenseState,
    release_id: ID,
    splits: vector<BPS>,
}

public struct ReleaseLicenseKey() has copy, drop, store;

public struct ReleaseAuthorization(ID) has copy, drop, store;

// === Enums ===

public enum ReleaseLicenseState has copy, drop, store {
    Authorizing { authorized_recording_count: u8 },
    Authorized,
}

// === Events ===

public struct ReleaseLicenseCreatedEvent has copy, drop {
    release_id: ID,
    license_id: ID,
    splits_bps: vector<u16>,
}

public struct ReleaseLicenseSplitsSetEvent has copy, drop {
    release_id: ID,
    license_id: ID,
    splits_bps: vector<u16>,
}

public struct ReleaseLicenseAuthorizedEvent has copy, drop {
    release_id: ID,
    license_id: ID,
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

public fun share(license: ReleaseLicense) {
    transfer::share_object(license);
}

public fun forward<Currency>(
    license: &ReleaseLicense,
    release: &Release,
    mut revenue: Balance<Currency>,
) {
    assert!(object::id(release) == license.release_id, EWrongRelease);
    if (revenue.value() == 0) return revenue.destroy_zero();
    let total_value = revenue.value();
    let recording_ids = release.recording_ids();
    let values = vector::tabulate!(recording_ids.length(), |i| {
        let value = license.splits[i].apply(total_value);
        if (value > 0) {
            revenue.split(value).send_funds(pool::derive_address<Currency>(recording_ids[i]))
        };
        value
    });
    let remainder = revenue.value();
    if (remainder < total_value) {
        emit(ReleaseRevenueForwardedEvent<Currency> {
            release_id: license.release_id,
            values,
            remainder,
        });
    };
    if (remainder == 0) revenue.destroy_zero()
    else revenue.send_funds(object::id(license).to_address())
}

public fun redeem_and_forward<Currency>(
    license: &mut ReleaseLicense,
    release: &Release,
    root: &AccumulatorRoot,
) {
    let revenue = hikida::redeem_settled_balance<Currency>(&mut license.id, root);
    forward(license, release, revenue)
}

public fun receive_and_forward<Currency>(
    license: &mut ReleaseLicense,
    release: &Release,
    coins: vector<Receiving<Coin<Currency>>>,
) {
    let revenue = hikida::receive_coins_as_balance(&mut license.id, coins);
    forward(license, release, revenue)
}

public fun authorize<RecordingShare>(
    license: &mut ReleaseLicense,
    release: &Release,
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
) {
    let release_id = license.release_id;
    assert!(object::id(release) == release_id, EWrongRelease);
    let uid = recording.uid_mut(cap);
    let recording_id = uid.to_inner();
    assert!(release.recording_ids().contains(&recording_id), ENotTrack);
    let key = ReleaseAuthorization(release_id);
    if (dynamic_field::exists(uid, key)) return;
    dynamic_field::add(uid, key, true);
    emit(ReleaseAuthorizedEvent { recording_id, release_id });
    let authorized_recording_count = license.authorized_recording_count() + 1;
    if (authorized_recording_count == license.splits.length() as u8) {
        license.state = ReleaseLicenseState::Authorized;
        emit(ReleaseLicenseAuthorizedEvent { release_id, license_id: object::id(license) });
    } else {
        license.state = ReleaseLicenseState::Authorizing { authorized_recording_count };
    }
}

public fun revoke<RecordingShare>(
    license: &mut ReleaseLicense,
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
) {
    assert!(!license.is_authorized(), EAlreadyAuthorized);
    let release_id = license.release_id;
    let uid = recording.uid_mut(cap);
    let recording_id = uid.to_inner();
    let key = ReleaseAuthorization(release_id);
    assert!(dynamic_field::exists(uid, key), ENoAuthorization);
    let _: bool = dynamic_field::remove(uid, key);
    emit(ReleaseAuthorizationRevokedEvent { recording_id, release_id });
    let authorized_recording_count = license.authorized_recording_count() - 1;
    license.state = ReleaseLicenseState::Authorizing { authorized_recording_count };
}

// === View Functions ===

public fun release_id(license: &ReleaseLicense): ID {
    license.release_id
}

public fun splits(license: &ReleaseLicense): &vector<BPS> {
    &license.splits
}

public fun is_authorized(license: &ReleaseLicense): bool {
    match (&license.state) {
        ReleaseLicenseState::Authorizing { .. } => false,
        ReleaseLicenseState::Authorized => true,
    }
}

public fun authorized_recording_count(license: &ReleaseLicense): u8 {
    match (&license.state) {
        ReleaseLicenseState::Authorizing { authorized_recording_count } => {
            *authorized_recording_count
        },
        ReleaseLicenseState::Authorized => license.splits.length() as u8,
    }
}

public fun has_release_authorization<RecordingShare>(
    recording: &Recording<RecordingShare>,
    release_id: ID,
): bool {
    dynamic_field::exists(recording.uid(), ReleaseAuthorization(release_id))
}

public fun has_license(release: &Release): bool {
    derived_object::exists(release.uid(), ReleaseLicenseKey())
}

public fun derive_address(release_id: ID): address {
    derived_object::derive_address(release_id, ReleaseLicenseKey())
}

// === Admin Functions ===

public fun new(release: &mut Release, cap: &ReleaseAdminCap, splits: vector<BPS>): ReleaseLicense {
    let release_id = object::id(release);
    assert_splits(&splits, release.recording_ids().length());
    let uid = release.uid_mut(cap);
    let license = ReleaseLicense {
        id: derived_object::claim(uid, ReleaseLicenseKey()),
        state: ReleaseLicenseState::Authorizing { authorized_recording_count: 0 },
        release_id,
        splits,
    };
    emit(ReleaseLicenseCreatedEvent {
        release_id,
        license_id: object::id(&license),
        splits_bps: splits_bps(&license.splits),
    });
    license
}

public fun set_splits(license: &mut ReleaseLicense, cap: &ReleaseAdminCap, splits: vector<BPS>) {
    assert!(cap.release_id() == license.release_id, EUnauthorized);
    assert!(license.authorized_recording_count() == 0, ESplitsLocked);
    assert_splits(&splits, license.splits.length());
    if (license.splits == splits) return;
    license.splits = splits;
    emit(ReleaseLicenseSplitsSetEvent {
        release_id: license.release_id,
        license_id: object::id(license),
        splits_bps: splits_bps(&license.splits),
    });
}

// === Private Functions ===

fun assert_splits(splits: &vector<BPS>, track_count: u64) {
    assert!(splits.length() == track_count, EWrongSplitCount);
    let mut total = 0u64;
    splits.do_ref!(|split| total = total + ((*split).value() as u64));
    assert!(total == (bps::max().value() as u64), ESplitNotFull);
}

fun splits_bps(splits: &vector<BPS>): vector<u16> {
    splits.map_ref!(|split| (*split).value())
}

// === Test Functions ===

#[test_only]
public fun release_license_created_event_fields(
    event: &ReleaseLicenseCreatedEvent,
): (ID, ID, vector<u16>) {
    (event.release_id, event.license_id, event.splits_bps)
}

#[test_only]
public fun release_license_authorized_event_fields(
    event: &ReleaseLicenseAuthorizedEvent,
): (ID, ID) {
    (event.release_id, event.license_id)
}

#[test_only]
public fun release_license_splits_set_event_fields(
    event: &ReleaseLicenseSplitsSetEvent,
): (ID, ID, vector<u16>) {
    (event.release_id, event.license_id, event.splits_bps)
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
