// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module record_sale::sale_tests;

use bps::bps;
use miso_music::{recording, release::{Self, Release, ReleaseAdminCap}};
use record::{pressing::{Self, Pressing, PressingAdminCap}, record::{Self, Record}};
use record_sale::{sale, witness::Witness};
use release_license::release_license::{Self, ReleaseLicense, ReleaseRevenueForwardedEvent};
use std::{u64, unit_test::{assert_eq, destroy}};
use sui::{balance::{Self, Balance}, clock::{Self, Clock}, event, test_scenario as ts};

public struct USD() has drop;
public struct EUR() has drop;

fun id(address: address): ID {
    object::id_from_address(address)
}

fun new_release(ctx: &mut TxContext): (Release, ReleaseAdminCap, ReleaseLicense) {
    let (mut first, first_cap) = recording::new_for_testing<USD>(id(@0xF1), ctx);
    let (mut second, second_cap) = recording::new_for_testing<USD>(id(@0xF2), ctx);
    let (mut release, cap) = release::new_for_testing(
        vector[object::id(&first), object::id(&second)],
        ctx,
    );
    let mut license = release_license::new(
        &mut release,
        &cap,
        vector[bps::new(6_667), bps::new(3_333)],
    );
    let splits = *license.splits();
    release_license::authorize(&mut license, &mut first, &first_cap, &release, splits);
    release_license::authorize(&mut license, &mut second, &second_cap, &release, splits);
    destroy(first);
    destroy(first_cap);
    destroy(second);
    destroy(second_cap);
    (release, cap, license)
}

fun an_unauthorized_release(ctx: &mut TxContext): (Release, ReleaseAdminCap, ReleaseLicense) {
    let (mut release, cap) = an_unlicensed_release(ctx);
    let license = release_license::new(
        &mut release,
        &cap,
        vector[bps::new(6_667), bps::new(3_333)],
    );
    (release, cap, license)
}

fun an_unlicensed_release(ctx: &mut TxContext): (Release, ReleaseAdminCap) {
    let recording_ids = vector::tabulate!(2, |_| id(ctx.fresh_object_address()));
    release::new_for_testing(recording_ids, ctx)
}

fun new_sale(
    release: &Release,
    max_supply: u32,
    price: u64,
    ctx: &mut TxContext,
): (Pressing, PressingAdminCap) {
    let (mut pressing, cap) = new_pressing(object::id(release), max_supply, ctx);
    sale::authorize<USD>(&mut pressing, &cap, release, price, 0);
    (pressing, cap)
}

fun new_pressing(
    release_id: ID,
    max_supply: u32,
    ctx: &mut TxContext,
): (Pressing, PressingAdminCap) {
    pressing::new_for_testing(release_id, 1, max_supply, ctx)
}

fun forwarded<Currency>(): vector<vector<u64>> {
    event::events_by_type<ReleaseRevenueForwardedEvent<Currency>>().map!(|event| {
        let (
            _,
            _,
            values,
            remainder,
        ) = release_license::release_revenue_forwarded_fields_for_testing(
            &event,
        );
        assert_eq!(remainder, 1);
        values
    })
}

fun payment<Currency>(value: u64): Balance<Currency> {
    balance::create_for_testing(value)
}

fun sold_prices<Currency>(): vector<u64> {
    event::events_by_type<sale::RecordSoldEvent<Currency>>().map_ref!(|event| {
        let (_, _, value) = sale::record_sold_fields_for_testing(event);
        value
    })
}

fun assert_record_purchase<Currency>(
    purchased: &sale::RecordSoldEvent<Currency>,
    record_id: ID,
    pressing: &Pressing,
    value: u64,
) {
    let (event_record_id, event_pressing_id, event_value) = sale::record_sold_fields_for_testing(
        purchased,
    );
    assert_eq!(event_record_id, record_id);
    assert_eq!(event_pressing_id, object::id(pressing));
    assert_eq!(event_value, value);
}

fun assert_record_created(
    created: &record::RecordCreatedEvent<Witness>,
    record_id: ID,
    pressing: &Pressing,
    number: u32,
) {
    let (
        event_record_id,
        event_pressing_id,
        event_release_id,
        event_edition,
        event_number,
    ) = record::record_created_fields_for_testing(created);
    assert_eq!(event_record_id, record_id);
    assert_eq!(event_pressing_id, object::id(pressing));
    assert_eq!(event_release_id, pressing.release_id());
    assert_eq!(event_edition, pressing.edition());
    assert_eq!(event_number, number);
}

fun authorized_prices<Currency>(): vector<u64> {
    event::events_by_type<sale::SaleAuthorizedEvent<Currency>>().map_ref!(|event| {
        let (_, price, _) = sale::sale_authorized_fields_for_testing(event);
        price
    })
}

fun cleanup(
    pressing: Pressing,
    cap: PressingAdminCap,
    release: Release,
    release_cap: ReleaseAdminCap,
    license: ReleaseLicense,
) {
    destroy(pressing);
    destroy(cap);
    destroy(release);
    destroy(license);
    destroy(release_cap);
}

#[test]
fun complete_sale_delivers_record_and_forwards_proceeds_to_the_tracks() {
    let seller = @0xA;
    let buyer = @0xB;
    let final_recipient = @0xC;
    let price = 25;
    let mut scenario = ts::begin(seller);
    let (mut release, release_cap, license) = new_release(scenario.ctx());
    let release_id = object::id(&release);
    let (mut pressing, pressing_cap) = pressing::new(&mut release, &release_cap, 1, 1);
    let pressing_id = object::id(&pressing);
    sale::authorize<USD>(&mut pressing, &pressing_cap, &release, price, 0);
    assert_eq!(pressing_id.to_address(), pressing::derive_address(&release, 1));
    release.share();
    license.share();
    pressing.share();
    transfer::public_transfer(release_cap, seller);
    transfer::public_transfer(pressing_cap, seller);
    scenario.next_tx(buyer);
    let mut pressing = scenario.take_shared<Pressing>();
    let release = scenario.take_shared<Release>();
    let license = scenario.take_shared<ReleaseLicense>();
    let clock = clock::create_for_testing(scenario.ctx());
    let record = sale::purchase(&mut pressing, &release, &license, payment<USD>(price), &clock);
    let record_id = object::id(&record);
    assert_eq!(record.release_id(), release_id);
    assert_eq!(record.pressing_id(), pressing_id);
    assert_eq!(record.edition(), 1);
    assert_eq!(record.number(), 1);
    assert_eq!(object::id_address(&record), record::derive_address(&pressing, 1));
    assert_eq!(pressing.supply(), 1);
    assert_eq!(forwarded<USD>(), vector[vector[16, 8]]);
    let forwarded_events = event::events_by_type<ReleaseRevenueForwardedEvent<USD>>();
    let (event_release_id, _, _, _) = release_license::release_revenue_forwarded_fields_for_testing(
        &forwarded_events[0],
    );
    assert_eq!(event_release_id, release_id);
    let purchased = event::events_by_type<sale::RecordSoldEvent<USD>>();
    assert_eq!(purchased.length(), 1);
    assert_record_purchase(&purchased[0], record_id, &pressing, price);
    let created = event::events_by_type<record::RecordCreatedEvent<Witness>>();
    assert_eq!(created.length(), 1);
    assert_record_created(&created[0], record_id, &pressing, 1);
    ts::return_shared(pressing);
    ts::return_shared(release);
    ts::return_shared(license);
    clock.destroy_for_testing();
    transfer::public_transfer(record, final_recipient);
    scenario.next_tx(final_recipient);
    let owned_record = scenario.take_from_sender<Record>();
    assert_eq!(object::id(&owned_record), record_id);
    owned_record.destroy();
    scenario.next_tx(seller);
    destroy(scenario.take_from_sender<ReleaseAdminCap>());
    destroy(scenario.take_from_sender<PressingAdminCap>());
    scenario.end();
}

#[test]
fun sale_is_cap_gated_and_observable() {
    let mut ctx = tx_context::dummy();
    let (release, release_cap, license) = new_release(&mut ctx);
    let (mut pressing, cap) = new_pressing(object::id(&release), 100, &mut ctx);
    assert!(!sale::has_sale(&pressing));
    assert!(!sale::is_currency<USD>(&pressing));
    sale::authorize<USD>(&mut pressing, &cap, &release, 10, 5_000);
    assert!(sale::has_sale(&pressing));
    assert!(sale::is_currency<USD>(&pressing));
    assert!(!sale::is_currency<EUR>(&pressing));
    assert_eq!(sale::price<USD>(&pressing), 10);
    assert_eq!(sale::starts_at_ms<USD>(&pressing), 5_000);
    destroy(pressing);
    destroy(cap);
    destroy(release);
    destroy(release_cap);
    destroy(license);
}

#[test]
fun authorize_emits_the_price() {
    let mut ctx = tx_context::dummy();
    let (release, release_cap, license) = new_release(&mut ctx);
    let (mut pressing, cap) = new_pressing(object::id(&release), 100, &mut ctx);
    let pressing_id = object::id(&pressing);
    sale::authorize<USD>(&mut pressing, &cap, &release, 10, 0);
    let added = event::events_by_type<sale::SaleAuthorizedEvent<USD>>();
    let (event_pressing_id, _, event_starts_at_ms) = sale::sale_authorized_fields_for_testing(&added[0]);
    assert_eq!(event_starts_at_ms, 0);
    assert_eq!(event_pressing_id, pressing_id);
    assert_eq!(authorized_prices<USD>(), vector[10]);
    assert_eq!(authorized_prices<EUR>(), vector[]);
    assert!(pressing.is_distributor_authorized<Witness>());
    assert_eq!(sale::price<USD>(&pressing), 10);
    destroy(pressing);
    destroy(cap);
    destroy(release);
    destroy(release_cap);
    destroy(license);
}

#[test, expected_failure(abort_code = pressing::EDistributorNotAuthorized)]
fun revoked_record_sale_cannot_press() {
    let mut ctx = tx_context::dummy();
    let clock = clock::create_for_testing(&mut ctx);
    let (release, release_cap, license) = new_release(&mut ctx);
    let (mut pressing, cap) = new_sale(&release, 100, 10, &mut ctx);
    pressing.revoke_distributor<Witness>(&cap);
    let record = sale::purchase(&mut pressing, &release, &license, payment<USD>(10), &clock);
    record.destroy();
    destroy(clock);
    cleanup(pressing, cap, release, release_cap, license);
}

#[test, expected_failure(abort_code = sale::ENotAuthorized)]
fun purchase_rejects_a_release_not_every_recording_has_authorized() {
    let mut ctx = tx_context::dummy();
    let clock = clock::create_for_testing(&mut ctx);
    let (release, _release_cap, license) = an_unauthorized_release(&mut ctx);
    let (mut pressing, _cap) = new_sale(&release, 100, 10, &mut ctx);
    let _record = sale::purchase(&mut pressing, &release, &license, payment<USD>(10), &clock);
    abort
}

#[test, expected_failure(abort_code = sale::EWrongRelease)]
fun purchase_rejects_a_different_release() {
    let mut ctx = tx_context::dummy();
    let clock = clock::create_for_testing(&mut ctx);
    let (release, release_cap, license) = new_release(&mut ctx);
    let (other, other_cap, other_license) = new_release(&mut ctx);
    let (mut pressing, cap) = new_sale(&release, 100, 10, &mut ctx);
    let record = sale::purchase(&mut pressing, &other, &license, payment<USD>(10), &clock);
    record.destroy();
    destroy(other);
    destroy(other_cap);
    destroy(other_license);
    destroy(clock);
    cleanup(pressing, cap, release, release_cap, license);
}

#[test, expected_failure(abort_code = sale::EWrongCurrency)]
fun purchase_rejects_a_currency_not_on_sale() {
    let mut ctx = tx_context::dummy();
    let clock = clock::create_for_testing(&mut ctx);
    let (release, release_cap, license) = new_release(&mut ctx);
    let (mut pressing, cap) = new_sale(&release, 100, 10, &mut ctx);
    let record = sale::purchase(&mut pressing, &release, &license, payment<EUR>(10), &clock);
    record.destroy();
    destroy(clock);
    cleanup(pressing, cap, release, release_cap, license);
}

#[test, expected_failure(abort_code = sale::ENoSale)]
fun reading_a_missing_sale_aborts() {
    let mut ctx = tx_context::dummy();
    let (release, _release_cap, _license) = new_release(&mut ctx);
    let (pressing, _cap) = new_pressing(object::id(&release), 100, &mut ctx);
    sale::price<USD>(&pressing);
    abort
}

#[test, expected_failure(abort_code = sale::ENoSale)]
fun purchase_without_a_sale_aborts() {
    let mut ctx = tx_context::dummy();
    let clock = clock::create_for_testing(&mut ctx);
    let (release, _release_cap, license) = new_release(&mut ctx);
    let (mut pressing, cap) = new_pressing(object::id(&release), 100, &mut ctx);
    pressing.authorize_distributor<Witness>(&cap);
    let _record = sale::purchase(&mut pressing, &release, &license, payment<USD>(10), &clock);
    abort
}

#[test, expected_failure(abort_code = pressing::EUnauthorized)]
fun authorize_checks_the_cap_before_the_release() {
    let mut ctx = tx_context::dummy();
    let (release, _release_cap, _license) = new_release(&mut ctx);
    let (mut pressing, _cap) = new_pressing(id(@0xB), 100, &mut ctx);
    let foreign = pressing::foreign_admin_cap_for_testing(id(@0xDEAD), &mut ctx);
    sale::authorize<USD>(&mut pressing, &foreign, &release, 10, 0);
    abort
}

#[test, expected_failure(abort_code = pressing::EUnauthorized)]
fun authorize_rejects_a_foreign_pressing_cap() {
    let mut ctx = tx_context::dummy();
    let (release, release_cap, license) = new_release(&mut ctx);
    let (mut pressing, cap) = new_pressing(object::id(&release), 100, &mut ctx);
    let (other, other_cap) = new_pressing(id(@0xB), 100, &mut ctx);
    sale::authorize<USD>(&mut pressing, &other_cap, &release, 10, 0);
    destroy(pressing);
    destroy(cap);
    destroy(release);
    destroy(release_cap);
    destroy(license);
    destroy(other);
    destroy(other_cap);
}

#[test, expected_failure(abort_code = sale::EWrongPayment)]
fun purchase_rejects_underpayment() {
    let mut ctx = tx_context::dummy();
    let clock = clock::create_for_testing(&mut ctx);
    let (release, release_cap, license) = new_release(&mut ctx);
    let (mut pressing, cap) = new_sale(&release, 100, 10, &mut ctx);
    let record = sale::purchase(&mut pressing, &release, &license, payment<USD>(9), &clock);
    record.destroy();
    destroy(clock);
    cleanup(pressing, cap, release, release_cap, license);
}

#[test, expected_failure(abort_code = sale::EWrongPayment)]
fun purchase_rejects_overpayment() {
    let mut ctx = tx_context::dummy();
    let clock = clock::create_for_testing(&mut ctx);
    let (release, release_cap, license) = new_release(&mut ctx);
    let (mut pressing, cap) = new_sale(&release, 100, 10, &mut ctx);
    let record = sale::purchase(&mut pressing, &release, &license, payment<USD>(11), &clock);
    record.destroy();
    destroy(clock);
    cleanup(pressing, cap, release, release_cap, license);
}

#[test, expected_failure(abort_code = pressing::EMaxSupplyReached)]
fun maximum_supply_boundary_rejects_the_next_purchase() {
    let mut ctx = tx_context::dummy();
    let clock = clock::create_for_testing(&mut ctx);
    let (release, release_cap, license) = new_release(&mut ctx);
    let (mut pressing, cap) = new_sale(&release, 2, 10, &mut ctx);
    sale::purchase(&mut pressing, &release, &license, payment<USD>(10), &clock).destroy();
    sale::purchase(&mut pressing, &release, &license, payment<USD>(10), &clock).destroy();
    sale::purchase(&mut pressing, &release, &license, payment<USD>(10), &clock).destroy();
    destroy(clock);
    cleanup(pressing, cap, release, release_cap, license);
}

#[test]
fun free_sale_presses_a_zero_price_record_and_forwards_nothing() {
    let mut ctx = tx_context::dummy();
    let clock = clock::create_for_testing(&mut ctx);
    let (release, release_cap, license) = new_release(&mut ctx);
    let (mut pressing, cap) = new_sale(&release, 100, 0, &mut ctx);
    let record = sale::purchase(&mut pressing, &release, &license, balance::zero<USD>(), &clock);
    assert_eq!(forwarded<USD>(), vector[]);
    let events = event::events_by_type<sale::RecordSoldEvent<USD>>();
    assert_record_purchase(&events[0], object::id(&record), &pressing, 0);
    record.destroy();
    destroy(clock);
    cleanup(pressing, cap, release, release_cap, license);
}

#[test, expected_failure(abort_code = sale::EWrongPayment)]
fun free_sale_rejects_payment() {
    let mut ctx = tx_context::dummy();
    let clock = clock::create_for_testing(&mut ctx);
    let (release, release_cap, license) = new_release(&mut ctx);
    let (mut pressing, cap) = new_sale(&release, 100, 0, &mut ctx);
    let record = sale::purchase(&mut pressing, &release, &license, payment<USD>(1), &clock);
    record.destroy();
    destroy(clock);
    cleanup(pressing, cap, release, release_cap, license);
}

#[test]
fun a_tip_is_forwarded_beside_a_free_sale() {
    let mut ctx = tx_context::dummy();
    let clock = clock::create_for_testing(&mut ctx);
    let (release, release_cap, license) = new_release(&mut ctx);
    let (mut pressing, cap) = new_sale(&release, 100, 0, &mut ctx);
    let free = sale::purchase(&mut pressing, &release, &license, balance::zero<USD>(), &clock);
    release_license::forward(&license, &release, payment<USD>(7));
    assert_eq!(sold_prices<USD>(), vector[0]);
    assert_eq!(forwarded<USD>(), vector[vector[4, 2]]);
    free.destroy();
    destroy(clock);
    cleanup(pressing, cap, release, release_cap, license);
}

#[test]
fun sale_supports_the_u16_maximum_edition() {
    let mut ctx = tx_context::dummy();
    let clock = clock::create_for_testing(&mut ctx);
    let (release, release_cap, license) = new_release(&mut ctx);
    let (mut pressing, cap) = pressing::new_for_testing(object::id(&release), 65_535, 1, &mut ctx);
    sale::authorize<USD>(&mut pressing, &cap, &release, 10, 0);
    let record = sale::purchase(&mut pressing, &release, &license, payment<USD>(10), &clock);
    assert_eq!(record.edition(), 65_535);
    let purchased = event::events_by_type<sale::RecordSoldEvent<USD>>();
    assert_record_purchase(&purchased[0], object::id(&record), &pressing, 10);
    let created = event::events_by_type<record::RecordCreatedEvent<Witness>>();
    assert_record_created(&created[0], object::id(&record), &pressing, 1);
    record.destroy();
    destroy(clock);
    cleanup(pressing, cap, release, release_cap, license);
}

#[test]
fun purchase_accepts_the_maximum_price() {
    let mut ctx = tx_context::dummy();
    let clock = clock::create_for_testing(&mut ctx);
    let (release, release_cap, license) = new_release(&mut ctx);
    let max = u64::max_value!();
    let (mut pressing, cap) = new_sale(&release, 100, max, &mut ctx);
    let record = sale::purchase(&mut pressing, &release, &license, payment<USD>(max), &clock);
    assert_eq!(sold_prices<USD>(), vector[max]);
    assert_eq!(
        forwarded<USD>(),
        vector[vector[12_298_444_273_942_158_061, 6_148_299_799_767_393_553]],
    );
    record.destroy();
    destroy(clock);
    cleanup(pressing, cap, release, release_cap, license);
}

#[test, expected_failure(abort_code = pressing::EUnauthorized)]
fun authorize_rejects_a_foreign_admin_cap() {
    let mut ctx = tx_context::dummy();
    let (release, release_cap, license) = new_release(&mut ctx);
    let (mut pressing, cap) = new_pressing(object::id(&release), 100, &mut ctx);
    let foreign = pressing::foreign_admin_cap_for_testing(id(@0xDEAD), &mut ctx);
    sale::authorize<USD>(&mut pressing, &foreign, &release, 10, 0);
    destroy(pressing);
    destroy(cap);
    destroy(release);
    destroy(release_cap);
    destroy(license);
    destroy(foreign);
}

#[test, expected_failure(abort_code = sale::ENoLicense)]
fun authorize_rejects_a_release_without_a_license() {
    let mut ctx = tx_context::dummy();
    let (release, release_cap) = an_unlicensed_release(&mut ctx);
    let (mut pressing, cap) = new_pressing(object::id(&release), 100, &mut ctx);
    sale::authorize<USD>(&mut pressing, &cap, &release, 10, 0);
    destroy(pressing);
    destroy(cap);
    destroy(release);
    destroy(release_cap);
}

#[test, expected_failure(abort_code = sale::EWrongRelease)]
fun authorize_rejects_a_different_release() {
    let mut ctx = tx_context::dummy();
    let (release, release_cap, license) = new_release(&mut ctx);
    let (other, other_cap, other_license) = new_release(&mut ctx);
    let (mut pressing, cap) = new_pressing(object::id(&release), 100, &mut ctx);
    sale::authorize<USD>(&mut pressing, &cap, &other, 10, 0);
    destroy(pressing);
    destroy(cap);
    destroy(release);
    destroy(release_cap);
    destroy(license);
    destroy(other);
    destroy(other_cap);
    destroy(other_license);
}

#[test, expected_failure(abort_code = pressing::EDistributorAlreadyAuthorized)]
fun authorizing_twice_aborts() {
    let mut ctx = tx_context::dummy();
    let (release, _release_cap, _license) = new_release(&mut ctx);
    let (mut pressing, cap) = new_sale(&release, 100, 10, &mut ctx);
    sale::authorize<EUR>(&mut pressing, &cap, &release, 8, 0);
    abort
}

#[test, expected_failure(abort_code = sale::ESaleExists)]
fun authorizing_again_after_revoke_cannot_replace_the_sale() {
    let mut ctx = tx_context::dummy();
    let (release, _release_cap, _license) = new_release(&mut ctx);
    let (mut pressing, cap) = new_sale(&release, 100, 10, &mut ctx);
    pressing.revoke_distributor<Witness>(&cap);
    sale::authorize<USD>(&mut pressing, &cap, &release, 8, 0);
    abort
}

#[test, expected_failure(abort_code = sale::ESaleExists)]
fun authorizing_again_after_revoke_cannot_add_a_second_currency() {
    let mut ctx = tx_context::dummy();
    let (release, _release_cap, _license) = new_release(&mut ctx);
    let (mut pressing, cap) = new_sale(&release, 100, 10, &mut ctx);
    pressing.revoke_distributor<Witness>(&cap);
    sale::authorize<EUR>(&mut pressing, &cap, &release, 8, 0);
    abort
}

#[test]
fun restoring_a_revoked_sale_keeps_the_original_sale() {
    let mut ctx = tx_context::dummy();
    let clock = clock::create_for_testing(&mut ctx);
    let (release, release_cap, license) = new_release(&mut ctx);
    let (mut pressing, cap) = new_sale(&release, 100, 10, &mut ctx);
    pressing.revoke_distributor<Witness>(&cap);
    pressing.authorize_distributor<Witness>(&cap);
    let record = sale::purchase(&mut pressing, &release, &license, payment<USD>(10), &clock);
    assert_eq!(sold_prices<USD>(), vector[10]);
    record.destroy();
    destroy(clock);
    cleanup(pressing, cap, release, release_cap, license);
}

// === The start ===

fun scheduled_sale(
    release: &Release,
    price: u64,
    starts_at_ms: u64,
    ctx: &mut TxContext,
): (Pressing, PressingAdminCap) {
    let (mut pressing, cap) = new_pressing(object::id(release), 100, ctx);
    sale::authorize<USD>(&mut pressing, &cap, release, price, starts_at_ms);
    (pressing, cap)
}

fun clock_at(ms: u64, ctx: &mut TxContext): Clock {
    let mut clock = clock::create_for_testing(ctx);
    clock.set_for_testing(ms);
    clock
}

#[test, expected_failure(abort_code = sale::ENotStarted)]
fun purchase_before_the_start_aborts() {
    let mut ctx = tx_context::dummy();
    let (release, _release_cap, license) = new_release(&mut ctx);
    let (mut pressing, _cap) = scheduled_sale(&release, 10, 1_000, &mut ctx);
    let clock = clock_at(999, &mut ctx);
    let _record = sale::purchase(&mut pressing, &release, &license, payment<USD>(10), &clock);
    abort
}

#[test]
fun purchase_opens_exactly_at_the_start() {
    let mut ctx = tx_context::dummy();
    let (release, release_cap, license) = new_release(&mut ctx);
    let (mut pressing, cap) = scheduled_sale(&release, 10, 1_000, &mut ctx);
    let clock = clock_at(1_000, &mut ctx);
    assert!(sale::is_started<USD>(&pressing, &clock));
    sale::purchase(&mut pressing, &release, &license, payment<USD>(10), &clock).destroy();
    assert_eq!(sold_prices<USD>(), vector[10]);
    destroy(clock);
    cleanup(pressing, cap, release, release_cap, license);
}

#[test]
fun a_start_in_the_past_sells_at_once() {
    let mut ctx = tx_context::dummy();
    let (release, release_cap, license) = new_release(&mut ctx);
    let (mut pressing, cap) = scheduled_sale(&release, 10, 1_000, &mut ctx);
    let clock = clock_at(5_000, &mut ctx);
    sale::purchase(&mut pressing, &release, &license, payment<USD>(10), &clock).destroy();
    destroy(clock);
    cleanup(pressing, cap, release, release_cap, license);
}

#[test]
fun update_before_the_start_changes_the_price_and_the_start() {
    let mut ctx = tx_context::dummy();
    let (release, release_cap, license) = new_release(&mut ctx);
    let (mut pressing, cap) = scheduled_sale(&release, 10, 1_000, &mut ctx);
    let mut clock = clock_at(500, &mut ctx);
    assert!(!sale::is_started<USD>(&pressing, &clock));
    sale::update<USD>(&mut pressing, &cap, 12, 2_000, &clock);
    assert_eq!(sale::price<USD>(&pressing), 12);
    assert_eq!(sale::starts_at_ms<USD>(&pressing), 2_000);
    let updated = event::events_by_type<sale::SaleUpdatedEvent<USD>>();
    assert_eq!(updated.length(), 1);
    let (pressing_id, price, starts_at_ms) = sale::sale_updated_fields_for_testing(&updated[0]);
    assert_eq!(pressing_id, object::id(&pressing));
    assert_eq!(price, 12);
    assert_eq!(starts_at_ms, 2_000);
    clock.set_for_testing(2_000);
    sale::purchase(&mut pressing, &release, &license, payment<USD>(12), &clock).destroy();
    assert_eq!(sold_prices<USD>(), vector[12]);
    destroy(clock);
    cleanup(pressing, cap, release, release_cap, license);
}

#[test]
fun update_to_a_start_at_or_before_now_opens_the_sale() {
    let mut ctx = tx_context::dummy();
    let (release, release_cap, license) = new_release(&mut ctx);
    let (mut pressing, cap) = scheduled_sale(&release, 10, 1_000, &mut ctx);
    let clock = clock_at(500, &mut ctx);
    sale::update<USD>(&mut pressing, &cap, 10, 500, &clock);
    sale::purchase(&mut pressing, &release, &license, payment<USD>(10), &clock).destroy();
    destroy(clock);
    cleanup(pressing, cap, release, release_cap, license);
}

#[test]
fun an_update_that_changes_nothing_emits_nothing() {
    let mut ctx = tx_context::dummy();
    let (release, release_cap, license) = new_release(&mut ctx);
    let (mut pressing, cap) = scheduled_sale(&release, 10, 1_000, &mut ctx);
    let clock = clock_at(500, &mut ctx);
    sale::update<USD>(&mut pressing, &cap, 10, 1_000, &clock);
    assert_eq!(event::events_by_type<sale::SaleUpdatedEvent<USD>>().length(), 0);
    destroy(clock);
    cleanup(pressing, cap, release, release_cap, license);
}

#[test, expected_failure(abort_code = sale::EStarted)]
fun update_at_the_start_aborts() {
    let mut ctx = tx_context::dummy();
    let (release, _release_cap, _license) = new_release(&mut ctx);
    let (mut pressing, cap) = scheduled_sale(&release, 10, 1_000, &mut ctx);
    let clock = clock_at(1_000, &mut ctx);
    sale::update<USD>(&mut pressing, &cap, 12, 2_000, &clock);
    abort
}

#[test, expected_failure(abort_code = sale::EStarted)]
fun a_sale_on_from_authorization_cannot_be_updated() {
    let mut ctx = tx_context::dummy();
    let (release, _release_cap, _license) = new_release(&mut ctx);
    let (mut pressing, cap) = new_sale(&release, 100, 10, &mut ctx);
    let clock = clock::create_for_testing(&mut ctx);
    sale::update<USD>(&mut pressing, &cap, 12, 2_000, &clock);
    abort
}

#[test, expected_failure(abort_code = sale::EWrongCurrency)]
fun update_in_another_currency_aborts() {
    let mut ctx = tx_context::dummy();
    let (release, _release_cap, _license) = new_release(&mut ctx);
    let (mut pressing, cap) = scheduled_sale(&release, 10, 1_000, &mut ctx);
    let clock = clock_at(500, &mut ctx);
    sale::update<EUR>(&mut pressing, &cap, 12, 1_000, &clock);
    abort
}

#[test, expected_failure(abort_code = sale::ENoSale)]
fun update_without_a_sale_aborts() {
    let mut ctx = tx_context::dummy();
    let (release, _release_cap, _license) = new_release(&mut ctx);
    let (mut pressing, cap) = new_pressing(object::id(&release), 100, &mut ctx);
    let clock = clock_at(500, &mut ctx);
    sale::update<USD>(&mut pressing, &cap, 12, 1_000, &clock);
    abort
}

#[test, expected_failure(abort_code = pressing::EUnauthorized)]
fun update_checks_the_cap_first() {
    let mut ctx = tx_context::dummy();
    let (release, _release_cap, _license) = new_release(&mut ctx);
    let (mut pressing, _cap) = scheduled_sale(&release, 10, 1_000, &mut ctx);
    let foreign = pressing::foreign_admin_cap_for_testing(id(@0xDEAD), &mut ctx);
    let clock = clock_at(500, &mut ctx);
    sale::update<EUR>(&mut pressing, &foreign, 12, 1_000, &clock);
    abort
}

#[test, expected_failure(abort_code = sale::ESaleExists)]
fun a_second_sale_in_another_currency_aborts_even_after_revoke() {
    let mut ctx = tx_context::dummy();
    let (release, _release_cap, _license) = new_release(&mut ctx);
    let (mut pressing, cap) = scheduled_sale(&release, 10, 1_000, &mut ctx);
    pressing.revoke_distributor<Witness>(&cap);
    sale::authorize<EUR>(&mut pressing, &cap, &release, 8, 0);
    abort
}
