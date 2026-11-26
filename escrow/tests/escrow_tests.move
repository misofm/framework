// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module escrow::escrow_tests;

use escrow::escrow::{
    Self,
    EscrowRegistry,
    EscrowSenderCap,
    EscrowRecipientCap,
    EscrowCreatedEvent,
    EscrowAcceptedEvent,
    EscrowDeclinedEvent,
    EscrowCompletedEvent,
    EscrowCancelledEvent,
    EscrowRecipientCapBurnedEvent
};
use std::{type_name, unit_test::assert_eq};
use sui::{event, test_scenario::{Self as ts, Scenario}};

const SENDER: address = @0xA1;
const RECIPIENT: address = @0xB1;
const OTHER: address = @0xC1;

public struct Item has key, store {
    id: UID,
}

public struct Created has copy, drop {
    escrow_id: ID,
    nonce: u64,
    sender_cap_id: ID,
    recipient_cap_id: ID,
}

// === Helpers ===

fun setup(): Scenario {
    let mut scenario = ts::begin(SENDER);
    escrow::init_for_testing(scenario.ctx());
    scenario
}

fun mint(scenario: &mut Scenario, owner: address): ID {
    scenario.next_tx(owner);
    let item = Item { id: object::new(scenario.ctx()) };
    let item_id = object::id(&item);
    transfer::public_transfer(item, owner);
    item_id
}

fun send(scenario: &mut Scenario, from: address, item_id: ID, to: address): Created {
    scenario.next_tx(from);
    let mut registry = scenario.take_shared<EscrowRegistry>();
    let item = scenario.take_from_sender_by_id<Item>(item_id);
    escrow::new(&mut registry, item, to, scenario.ctx());
    ts::return_shared(registry);
    let events = event::events_by_type<EscrowCreatedEvent>();
    let (escrow_id, _, _, nonce, _, _, sender_cap_id, recipient_cap_id) =
        escrow::escrow_created_fields_for_testing(&events[0]);
    Created { escrow_id, nonce, sender_cap_id, recipient_cap_id }
}

fun accept(scenario: &mut Scenario, recipient: address, created: &Created) {
    scenario.next_tx(recipient);
    let mut registry = scenario.take_shared<EscrowRegistry>();
    let cap = scenario.take_from_sender_by_id<EscrowRecipientCap<Item>>(created.recipient_cap_id);
    escrow::accept(&mut registry, cap);
    ts::return_shared(registry);
}

fun decline(scenario: &mut Scenario, recipient: address, created: &Created) {
    scenario.next_tx(recipient);
    let mut registry = scenario.take_shared<EscrowRegistry>();
    let cap = scenario.take_from_sender_by_id<EscrowRecipientCap<Item>>(created.recipient_cap_id);
    escrow::decline(&mut registry, cap);
    ts::return_shared(registry);
}

fun complete(scenario: &mut Scenario, sender: address, created: &Created) {
    scenario.next_tx(sender);
    let mut registry = scenario.take_shared<EscrowRegistry>();
    let cap = scenario.take_from_sender_by_id<EscrowSenderCap<Item>>(created.sender_cap_id);
    escrow::complete(&mut registry, cap);
    ts::return_shared(registry);
}

fun cancel(scenario: &mut Scenario, sender: address, created: &Created) {
    scenario.next_tx(sender);
    let mut registry = scenario.take_shared<EscrowRegistry>();
    let cap = scenario.take_from_sender_by_id<EscrowSenderCap<Item>>(created.sender_cap_id);
    escrow::cancel(&mut registry, cap);
    ts::return_shared(registry);
}

fun burn(scenario: &mut Scenario, recipient: address, created: &Created) {
    scenario.next_tx(recipient);
    let registry = scenario.take_shared<EscrowRegistry>();
    let cap = scenario.take_from_sender_by_id<EscrowRecipientCap<Item>>(created.recipient_cap_id);
    escrow::burn_recipient_cap(&registry, cap);
    ts::return_shared(registry);
}

fun is_escrowed(scenario: &mut Scenario, item_id: ID): bool {
    scenario.next_tx(OTHER);
    let registry = scenario.take_shared<EscrowRegistry>();
    let escrowed = registry.exists(item_id);
    ts::return_shared(registry);
    escrowed
}

fun owns(scenario: &mut Scenario, owner: address, item_id: ID): bool {
    scenario.next_tx(owner);
    ts::ids_for_address<Item>(owner).contains(&item_id)
}

// === Creation ===

#[test]
fun new_escrows_the_item_and_sends_both_caps() {
    let mut scenario = setup();
    let item_id = mint(&mut scenario, SENDER);
    assert!(!is_escrowed(&mut scenario, item_id));
    scenario.next_tx(SENDER);
    let mut registry = scenario.take_shared<EscrowRegistry>();
    let item = scenario.take_from_sender_by_id<Item>(item_id);
    escrow::new(&mut registry, item, RECIPIENT, scenario.ctx());
    let events = event::events_by_type<EscrowCreatedEvent>();
    assert_eq!(events.length(), 1);
    let (
        escrow_id,
        event_item_id,
        item_type,
        nonce,
        sender,
        recipient,
        sender_cap_id,
        recipient_cap_id,
    ) = escrow::escrow_created_fields_for_testing(&events[0]);
    assert_eq!(escrow_id.to_address(), registry.derive_address(item_id));
    assert_eq!(event_item_id, item_id);
    assert_eq!(item_type, type_name::with_defining_ids<Item>());
    assert_eq!(nonce, 0);
    assert_eq!(sender, SENDER);
    assert_eq!(recipient, RECIPIENT);
    assert!(registry.exists(item_id));
    let escrow = registry.borrow<Item>(item_id);
    assert_eq!(escrow.nonce(), 0);
    assert_eq!(escrow.sender(), SENDER);
    assert_eq!(escrow.recipient(), RECIPIENT);
    assert!(escrow.state().is_pending());
    assert!(!escrow.state().is_accepted());
    assert!(!escrow.state().is_declined());
    ts::return_shared(registry);

    scenario.next_tx(SENDER);
    let sender_cap = scenario.take_from_sender<EscrowSenderCap<Item>>();
    assert_eq!(object::id(&sender_cap), sender_cap_id);
    let (cap_escrow_id, cap_item_id, cap_nonce) = escrow::sender_cap_fields_for_testing(
        &sender_cap,
    );
    assert_eq!(cap_escrow_id, escrow_id);
    assert_eq!(cap_item_id, item_id);
    assert_eq!(cap_nonce, 0);
    scenario.return_to_sender(sender_cap);

    scenario.next_tx(RECIPIENT);
    let recipient_cap = scenario.take_from_sender<EscrowRecipientCap<Item>>();
    assert_eq!(object::id(&recipient_cap), recipient_cap_id);
    let (cap_escrow_id, cap_item_id, cap_nonce) = escrow::recipient_cap_fields_for_testing(
        &recipient_cap,
    );
    assert_eq!(cap_escrow_id, escrow_id);
    assert_eq!(cap_item_id, item_id);
    assert_eq!(cap_nonce, 0);
    scenario.return_to_sender(recipient_cap);
    scenario.end();
}

#[test]
fun escrows_of_different_items_are_independent() {
    let mut scenario = setup();
    let first_item = mint(&mut scenario, SENDER);
    let second_item = mint(&mut scenario, SENDER);
    let first = send(&mut scenario, SENDER, first_item, RECIPIENT);
    let second = send(&mut scenario, SENDER, second_item, OTHER);
    assert!(first.escrow_id != second.escrow_id);
    assert_eq!(first.nonce, 0);
    assert_eq!(second.nonce, 1);
    accept(&mut scenario, OTHER, &second);
    complete(&mut scenario, SENDER, &second);
    assert!(owns(&mut scenario, OTHER, second_item));
    assert!(is_escrowed(&mut scenario, first_item));
    assert!(!is_escrowed(&mut scenario, second_item));
    scenario.end();
}

#[test, expected_failure(abort_code = escrow::ESelfTransfer)]
fun new_to_self_aborts() {
    let mut scenario = setup();
    let item_id = mint(&mut scenario, SENDER);
    send(&mut scenario, SENDER, item_id, SENDER);
    scenario.end();
}

#[test, expected_failure(abort_code = escrow::EEscrowNotFound)]
fun borrow_without_an_escrow_aborts() {
    let mut scenario = setup();
    let item_id = mint(&mut scenario, SENDER);
    scenario.next_tx(SENDER);
    let registry = scenario.take_shared<EscrowRegistry>();
    registry.borrow<Item>(item_id);
    ts::return_shared(registry);
    scenario.end();
}

// === Accept and complete ===

#[test]
fun accept_then_complete_delivers_the_item_to_the_recipient() {
    let mut scenario = setup();
    let item_id = mint(&mut scenario, SENDER);
    let created = send(&mut scenario, SENDER, item_id, RECIPIENT);

    accept(&mut scenario, RECIPIENT, &created);
    let events = event::events_by_type<EscrowAcceptedEvent>();
    assert_eq!(events.length(), 1);
    let (escrow_id, event_item_id, nonce, sender, recipient) =
        escrow::escrow_accepted_fields_for_testing(&events[0]);
    assert_eq!(escrow_id, created.escrow_id);
    assert_eq!(event_item_id, item_id);
    assert_eq!(nonce, 0);
    assert_eq!(sender, SENDER);
    assert_eq!(recipient, RECIPIENT);
    scenario.next_tx(OTHER);
    let registry = scenario.take_shared<EscrowRegistry>();
    assert!(registry.borrow<Item>(item_id).state().is_accepted());
    ts::return_shared(registry);
    assert!(!ts::has_most_recent_for_address<EscrowRecipientCap<Item>>(RECIPIENT));

    complete(&mut scenario, SENDER, &created);
    let events = event::events_by_type<EscrowCompletedEvent>();
    assert_eq!(events.length(), 1);
    let (escrow_id, event_item_id, nonce, sender, recipient) =
        escrow::escrow_completed_fields_for_testing(&events[0]);
    assert_eq!(escrow_id, created.escrow_id);
    assert_eq!(event_item_id, item_id);
    assert_eq!(nonce, 0);
    assert_eq!(sender, SENDER);
    assert_eq!(recipient, RECIPIENT);
    assert!(owns(&mut scenario, RECIPIENT, item_id));
    assert!(!owns(&mut scenario, SENDER, item_id));
    assert!(!is_escrowed(&mut scenario, item_id));
    assert!(!ts::has_most_recent_for_address<EscrowSenderCap<Item>>(SENDER));
    scenario.end();
}

#[test, expected_failure(abort_code = escrow::EWrongState)]
fun complete_while_pending_aborts() {
    let mut scenario = setup();
    let item_id = mint(&mut scenario, SENDER);
    let created = send(&mut scenario, SENDER, item_id, RECIPIENT);
    complete(&mut scenario, SENDER, &created);
    scenario.end();
}

#[test, expected_failure(abort_code = escrow::EWrongState)]
fun complete_after_decline_aborts() {
    let mut scenario = setup();
    let item_id = mint(&mut scenario, SENDER);
    let created = send(&mut scenario, SENDER, item_id, RECIPIENT);
    decline(&mut scenario, RECIPIENT, &created);
    complete(&mut scenario, SENDER, &created);
    scenario.end();
}

// === Decline and cancel ===

#[test]
fun cancel_while_pending_returns_the_item_to_the_sender() {
    let mut scenario = setup();
    let item_id = mint(&mut scenario, SENDER);
    let created = send(&mut scenario, SENDER, item_id, RECIPIENT);
    cancel(&mut scenario, SENDER, &created);
    let events = event::events_by_type<EscrowCancelledEvent>();
    assert_eq!(events.length(), 1);
    let (escrow_id, event_item_id, nonce, sender, recipient, state) =
        escrow::escrow_cancelled_fields_for_testing(&events[0]);
    assert_eq!(escrow_id, created.escrow_id);
    assert_eq!(event_item_id, item_id);
    assert_eq!(nonce, 0);
    assert_eq!(sender, SENDER);
    assert_eq!(recipient, RECIPIENT);
    assert!(state.is_pending());
    assert!(owns(&mut scenario, SENDER, item_id));
    assert!(!is_escrowed(&mut scenario, item_id));
    assert!(!ts::has_most_recent_for_address<EscrowSenderCap<Item>>(SENDER));
    assert!(ts::has_most_recent_for_address<EscrowRecipientCap<Item>>(RECIPIENT));
    scenario.end();
}

#[test]
fun cancel_after_accept_returns_the_item_to_the_sender() {
    let mut scenario = setup();
    let item_id = mint(&mut scenario, SENDER);
    let created = send(&mut scenario, SENDER, item_id, RECIPIENT);
    accept(&mut scenario, RECIPIENT, &created);
    cancel(&mut scenario, SENDER, &created);
    let events = event::events_by_type<EscrowCancelledEvent>();
    let (_, _, _, _, _, state) = escrow::escrow_cancelled_fields_for_testing(&events[0]);
    assert!(state.is_accepted());
    assert!(owns(&mut scenario, SENDER, item_id));
    assert!(!owns(&mut scenario, RECIPIENT, item_id));
    assert!(!is_escrowed(&mut scenario, item_id));
    scenario.end();
}

#[test]
fun decline_then_cancel_returns_the_item_to_the_sender() {
    let mut scenario = setup();
    let item_id = mint(&mut scenario, SENDER);
    let created = send(&mut scenario, SENDER, item_id, RECIPIENT);

    decline(&mut scenario, RECIPIENT, &created);
    let events = event::events_by_type<EscrowDeclinedEvent>();
    assert_eq!(events.length(), 1);
    let (escrow_id, event_item_id, nonce, sender, recipient) =
        escrow::escrow_declined_fields_for_testing(&events[0]);
    assert_eq!(escrow_id, created.escrow_id);
    assert_eq!(event_item_id, item_id);
    assert_eq!(nonce, 0);
    assert_eq!(sender, SENDER);
    assert_eq!(recipient, RECIPIENT);
    scenario.next_tx(OTHER);
    let registry = scenario.take_shared<EscrowRegistry>();
    assert!(registry.borrow<Item>(item_id).state().is_declined());
    ts::return_shared(registry);
    assert!(!ts::has_most_recent_for_address<EscrowRecipientCap<Item>>(RECIPIENT));

    cancel(&mut scenario, SENDER, &created);
    let events = event::events_by_type<EscrowCancelledEvent>();
    let (_, _, _, _, _, state) = escrow::escrow_cancelled_fields_for_testing(&events[0]);
    assert!(state.is_declined());
    assert!(owns(&mut scenario, SENDER, item_id));
    assert!(!is_escrowed(&mut scenario, item_id));
    scenario.end();
}

// === Re-escrow ===

#[test]
fun the_same_item_can_be_escrowed_again_after_complete() {
    let mut scenario = setup();
    let item_id = mint(&mut scenario, SENDER);
    let first = send(&mut scenario, SENDER, item_id, RECIPIENT);
    accept(&mut scenario, RECIPIENT, &first);
    complete(&mut scenario, SENDER, &first);
    let second = send(&mut scenario, RECIPIENT, item_id, SENDER);
    assert_eq!(second.escrow_id, first.escrow_id);
    assert_eq!(second.nonce, 1);
    accept(&mut scenario, SENDER, &second);
    complete(&mut scenario, RECIPIENT, &second);
    assert!(owns(&mut scenario, SENDER, item_id));
    assert!(!is_escrowed(&mut scenario, item_id));
    scenario.end();
}

#[test]
fun the_same_item_can_be_escrowed_again_after_cancel() {
    let mut scenario = setup();
    let item_id = mint(&mut scenario, SENDER);
    let first = send(&mut scenario, SENDER, item_id, RECIPIENT);
    cancel(&mut scenario, SENDER, &first);
    let second = send(&mut scenario, SENDER, item_id, OTHER);
    assert_eq!(second.escrow_id, first.escrow_id);
    assert_eq!(second.nonce, 1);
    accept(&mut scenario, OTHER, &second);
    complete(&mut scenario, SENDER, &second);
    assert!(owns(&mut scenario, OTHER, item_id));
    scenario.end();
}

// === Stale recipient caps ===

#[test, expected_failure(abort_code = escrow::EEscrowNotFound)]
fun recipient_cap_of_a_cancelled_escrow_cannot_accept() {
    let mut scenario = setup();
    let item_id = mint(&mut scenario, SENDER);
    let created = send(&mut scenario, SENDER, item_id, RECIPIENT);
    cancel(&mut scenario, SENDER, &created);
    accept(&mut scenario, RECIPIENT, &created);
    scenario.end();
}

#[test, expected_failure(abort_code = escrow::EStaleCap)]
fun stale_recipient_cap_cannot_accept_the_next_escrow_of_the_item() {
    let mut scenario = setup();
    let item_id = mint(&mut scenario, SENDER);
    let first = send(&mut scenario, SENDER, item_id, RECIPIENT);
    cancel(&mut scenario, SENDER, &first);
    send(&mut scenario, SENDER, item_id, RECIPIENT);
    accept(&mut scenario, RECIPIENT, &first);
    scenario.end();
}

#[test, expected_failure(abort_code = escrow::EStaleCap)]
fun stale_recipient_cap_cannot_decline_the_next_escrow_of_the_item() {
    let mut scenario = setup();
    let item_id = mint(&mut scenario, SENDER);
    let first = send(&mut scenario, SENDER, item_id, RECIPIENT);
    cancel(&mut scenario, SENDER, &first);
    send(&mut scenario, SENDER, item_id, OTHER);
    decline(&mut scenario, RECIPIENT, &first);
    scenario.end();
}

// === Burn ===

#[test]
fun burn_deletes_the_recipient_cap_of_a_cancelled_escrow() {
    let mut scenario = setup();
    let item_id = mint(&mut scenario, SENDER);
    let created = send(&mut scenario, SENDER, item_id, RECIPIENT);
    cancel(&mut scenario, SENDER, &created);
    burn(&mut scenario, RECIPIENT, &created);
    let events = event::events_by_type<EscrowRecipientCapBurnedEvent>();
    assert_eq!(events.length(), 1);
    let (escrow_id, event_item_id, nonce, recipient_cap_id) =
        escrow::escrow_recipient_cap_burned_fields_for_testing(&events[0]);
    assert_eq!(escrow_id, created.escrow_id);
    assert_eq!(event_item_id, item_id);
    assert_eq!(nonce, 0);
    assert_eq!(recipient_cap_id, created.recipient_cap_id);
    scenario.next_tx(RECIPIENT);
    assert!(!ts::has_most_recent_for_address<EscrowRecipientCap<Item>>(RECIPIENT));
    scenario.end();
}

#[test]
fun burn_deletes_a_stale_recipient_cap_while_the_next_escrow_is_live() {
    let mut scenario = setup();
    let item_id = mint(&mut scenario, SENDER);
    let first = send(&mut scenario, SENDER, item_id, RECIPIENT);
    cancel(&mut scenario, SENDER, &first);
    let second = send(&mut scenario, SENDER, item_id, RECIPIENT);
    burn(&mut scenario, RECIPIENT, &first);
    let events = event::events_by_type<EscrowRecipientCapBurnedEvent>();
    let (_, _, nonce, recipient_cap_id) = escrow::escrow_recipient_cap_burned_fields_for_testing(
        &events[0],
    );
    assert_eq!(nonce, 0);
    assert_eq!(recipient_cap_id, first.recipient_cap_id);
    accept(&mut scenario, RECIPIENT, &second);
    complete(&mut scenario, SENDER, &second);
    assert!(owns(&mut scenario, RECIPIENT, item_id));
    scenario.end();
}

#[test, expected_failure(abort_code = escrow::EEscrowPending)]
fun burn_of_a_live_recipient_cap_aborts() {
    let mut scenario = setup();
    let item_id = mint(&mut scenario, SENDER);
    let created = send(&mut scenario, SENDER, item_id, RECIPIENT);
    burn(&mut scenario, RECIPIENT, &created);
    scenario.end();
}
