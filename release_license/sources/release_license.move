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
    clock::Clock,
    coin::Coin,
    derived_object,
    dynamic_field as df,
    event::emit,
    transfer::Receiving
};

// === Errors ===

const EWrongSplitCount: u64 = 0;
const ESplitNotFull: u64 = 1;
const EWrongRelease: u64 = 2;
const ERecordingNotFound: u64 = 3;
const EAuthorizationNotFound: u64 = 4;
const ELicenseAlreadyAuthorized: u64 = 5;
const ESplitsLocked: u64 = 6;
const EUnauthorized: u64 = 7;
const ERecordingAlreadyAuthorized: u64 = 8;

// === Structs ===

public struct ReleaseLicense has key {
    id: UID,
    state: ReleaseLicenseState,
    release_id: ID,
    splits: vector<BPS>,
    last_redeemed_at_ms: u64,
}

public struct ReleaseLicenseKey() has copy, drop, store;

public struct ReleaseAuthorizationKey(ID) has copy, drop, store;

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

public struct ReleaseAuthorizationGrantedEvent has copy, drop {
    recording_id: ID,
    release_id: ID,
}

public struct ReleaseLicenseAuthorizedEvent has copy, drop {
    release_id: ID,
    license_id: ID,
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

public fun share(self: ReleaseLicense) {
    transfer::share_object(self);
}

public fun forward<Currency>(
    self: &ReleaseLicense,
    release: &Release,
    mut revenue: Balance<Currency>,
) {
    assert!(object::id(release) == self.release_id, EWrongRelease);
    if (revenue.value() == 0) return revenue.destroy_zero();
    let total_value = revenue.value();
    let recording_ids = release.recording_ids();
    let values = vector::tabulate!(recording_ids.length(), |i| {
        let value = self.splits[i].apply(total_value);
        if (value > 0) {
            revenue.split(value).send_funds(pool::derive_address<Currency>(recording_ids[i]))
        };
        value
    });
    let remainder = revenue.value();
    if (remainder < total_value) {
        emit(ReleaseRevenueForwardedEvent<Currency> {
            release_id: self.release_id,
            values,
            remainder,
        });
    };
    if (remainder == 0) revenue.destroy_zero()
    else revenue.send_funds(object::id(self).to_address())
}

public fun redeem_and_forward<Currency>(
    self: &mut ReleaseLicense,
    release: &Release,
    root: &AccumulatorRoot,
    clock: &Clock,
): u64 {
    assert!(object::id(release) == self.release_id, EWrongRelease);
    let now = clock.timestamp_ms();
    if (now == self.last_redeemed_at_ms) return 0;
    self.last_redeemed_at_ms = now;
    let revenue = hikida::redeem_settled_balance<Currency>(&mut self.id, root);
    let value = revenue.value();
    forward(self, release, revenue);
    value
}

public fun receive_and_forward<Currency>(
    self: &mut ReleaseLicense,
    release: &Release,
    coins: vector<Receiving<Coin<Currency>>>,
): u64 {
    let revenue = hikida::receive_coins_as_balance(&mut self.id, coins);
    let value = revenue.value();
    forward(self, release, revenue);
    value
}

// === View Functions ===

public fun release_id(self: &ReleaseLicense): ID {
    self.release_id
}

public fun splits(self: &ReleaseLicense): &vector<BPS> {
    &self.splits
}

public fun is_authorized(self: &ReleaseLicense): bool {
    match (&self.state) {
        ReleaseLicenseState::Authorizing { .. } => false,
        ReleaseLicenseState::Authorized => true,
    }
}

public fun authorized_recording_count(self: &ReleaseLicense): u8 {
    match (&self.state) {
        ReleaseLicenseState::Authorizing { authorized_recording_count } => {
            *authorized_recording_count
        },
        ReleaseLicenseState::Authorized => self.splits.length() as u8,
    }
}

public fun has_license(release: &Release): bool {
    derived_object::exists(release.uid(), ReleaseLicenseKey())
}

public fun derive_address(release: &Release): address {
    derived_object::derive_address(object::id(release), ReleaseLicenseKey())
}

public fun has_release_authorization<RecordingShare>(
    recording: &Recording<RecordingShare>,
    release_id: ID,
): bool {
    df::exists(recording.uid(), ReleaseAuthorizationKey(release_id))
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
        last_redeemed_at_ms: 0,
    };
    emit(ReleaseLicenseCreatedEvent {
        release_id,
        license_id: object::id(&license),
        splits_bps: splits_bps(&license.splits),
    });
    license
}

public fun set_splits(self: &mut ReleaseLicense, cap: &ReleaseAdminCap, splits: vector<BPS>) {
    assert!(cap.release_id() == self.release_id, EUnauthorized);
    assert!(self.authorized_recording_count() == 0, ESplitsLocked);
    assert_splits(&splits, self.splits.length());
    if (self.splits == splits) return;
    self.splits = splits;
    emit(ReleaseLicenseSplitsSetEvent {
        release_id: self.release_id,
        license_id: object::id(self),
        splits_bps: splits_bps(&self.splits),
    });
}

public fun authorize<RecordingShare>(
    self: &mut ReleaseLicense,
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    release: &Release,
) {
    let uid = recording.uid_mut(cap);
    let release_id = self.release_id;
    assert!(object::id(release) == release_id, EWrongRelease);
    let recording_id = uid.to_inner();
    assert!(release.recording_ids().contains(&recording_id), ERecordingNotFound);
    let key = ReleaseAuthorizationKey(release_id);
    assert!(!df::exists(uid, key), ERecordingAlreadyAuthorized);
    df::add(uid, key, true);
    emit(ReleaseAuthorizationGrantedEvent { recording_id, release_id });
    let authorized_recording_count = self.authorized_recording_count() + 1;
    if (authorized_recording_count == self.splits.length() as u8) {
        self.state = ReleaseLicenseState::Authorized;
        emit(ReleaseLicenseAuthorizedEvent { release_id, license_id: object::id(self) });
    } else {
        self.state = ReleaseLicenseState::Authorizing { authorized_recording_count };
    }
}

public fun revoke<RecordingShare>(
    self: &mut ReleaseLicense,
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
) {
    let uid = recording.uid_mut(cap);
    assert!(!self.is_authorized(), ELicenseAlreadyAuthorized);
    let release_id = self.release_id;
    let recording_id = uid.to_inner();
    let key = ReleaseAuthorizationKey(release_id);
    assert!(df::exists(uid, key), EAuthorizationNotFound);
    let _: bool = df::remove(uid, key);
    emit(ReleaseAuthorizationRevokedEvent { recording_id, release_id });
    let authorized_recording_count = self.authorized_recording_count() - 1;
    self.state = ReleaseLicenseState::Authorizing { authorized_recording_count };
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
public fun release_license_created_fields_for_testing(
    event: &ReleaseLicenseCreatedEvent,
): (ID, ID, vector<u16>) {
    (event.release_id, event.license_id, event.splits_bps)
}

#[test_only]
public fun release_license_splits_set_fields_for_testing(
    event: &ReleaseLicenseSplitsSetEvent,
): (ID, ID, vector<u16>) {
    (event.release_id, event.license_id, event.splits_bps)
}

#[test_only]
public fun release_authorization_granted_fields_for_testing(
    event: &ReleaseAuthorizationGrantedEvent,
): (ID, ID) {
    (event.recording_id, event.release_id)
}

#[test_only]
public fun release_license_authorized_fields_for_testing(
    event: &ReleaseLicenseAuthorizedEvent,
): (ID, ID) {
    (event.release_id, event.license_id)
}

#[test_only]
public fun release_authorization_revoked_fields_for_testing(
    event: &ReleaseAuthorizationRevokedEvent,
): (ID, ID) {
    (event.recording_id, event.release_id)
}

#[test_only]
public fun release_revenue_forwarded_fields_for_testing<Currency>(
    event: &ReleaseRevenueForwardedEvent<Currency>,
): (ID, vector<u64>, u64) {
    (event.release_id, event.values, event.remainder)
}
