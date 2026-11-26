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
use sui::{dynamic_field as df, event, test_scenario::{Self as ts, Scenario}};

const SENDER: address = @0xA1;
const RECIPIENT: address = @0xB1;
const OTHER: address = @0xC1;

public struct Token has key, store {
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
    let token = Token { id: object::new(scenario.ctx()) };
    let token_id = object::id(&token);
    transfer::public_transfer(token, owner);
    token_id
}

fun send(scenario: &mut Scenario, from: address, token_id: ID, to: address): Created {
    scenario.next_tx(from);
    let mut registry = scenario.take_shared<EscrowRegistry>();
    let token = scenario.take_from_sender_by_id<Token>(token_id);
    escrow::new(&mut registry, token, to, scenario.ctx());
    ts::return_shared(registry);
    let events = event::events_by_type<EscrowCreatedEvent>();
    let (escrow_id, _, _, nonce, _, _, sender_cap_id, recipient_cap_id) =
        escrow::escrow_created_fields_for_testing(&events[0]);
    Created { escrow_id, nonce, sender_cap_id, recipient_cap_id }
}

fun accept(scenario: &mut Scenario, recipient: address, created: &Created) {
    scenario.next_tx(recipient);
    let mut registry = scenario.take_shared<EscrowRegistry>();
    let cap = scenario.take_from_sender_by_id<EscrowRecipientCap<Token>>(created.recipient_cap_id);
    escrow::accept(&mut registry, cap);
    ts::return_shared(registry);
}

fun decline(scenario: &mut Scenario, recipient: address, created: &Created) {
    scenario.next_tx(recipient);
    let mut registry = scenario.take_shared<EscrowRegistry>();
    let cap = scenario.take_from_sender_by_id<EscrowRecipientCap<Token>>(created.recipient_cap_id);
    escrow::decline(&mut registry, cap);
    ts::return_shared(registry);
}

fun complete(scenario: &mut Scenario, sender: address, created: &Created) {
    scenario.next_tx(sender);
    let mut registry = scenario.take_shared<EscrowRegistry>();
    let cap = scenario.take_from_sender_by_id<EscrowSenderCap<Token>>(created.sender_cap_id);
    escrow::complete(&mut registry, cap);
    ts::return_shared(registry);
}

fun cancel(scenario: &mut Scenario, sender: address, created: &Created) {
    scenario.next_tx(sender);
    let mut registry = scenario.take_shared<EscrowRegistry>();
    let cap = scenario.take_from_sender_by_id<EscrowSenderCap<Token>>(created.sender_cap_id);
    escrow::cancel(&mut registry, cap);
    ts::return_shared(registry);
}

fun burn(scenario: &mut Scenario, recipient: address, created: &Created) {
    scenario.next_tx(recipient);
    let registry = scenario.take_shared<EscrowRegistry>();
    let cap = scenario.take_from_sender_by_id<EscrowRecipientCap<Token>>(created.recipient_cap_id);
    escrow::burn_recipient_cap(&registry, cap);
    ts::return_shared(registry);
}

fun is_escrowed(scenario: &mut Scenario, token_id: ID): bool {
    scenario.next_tx(OTHER);
    let registry = scenario.take_shared<EscrowRegistry>();
    let escrowed = registry.exists(token_id);
    ts::return_shared(registry);
    escrowed
}

fun owns(scenario: &mut Scenario, owner: address, token_id: ID): bool {
    scenario.next_tx(owner);
    ts::ids_for_address<Token>(owner).contains(&token_id)
}

// === Creation ===

#[test]
fun new_escrows_the_item_and_sends_both_caps() {
    let mut scenario = setup();
    let token_id = mint(&mut scenario, SENDER);
    assert!(!is_escrowed(&mut scenario, token_id));
    scenario.next_tx(SENDER);
    let mut registry = scenario.take_shared<EscrowRegistry>();
    let token = scenario.take_from_sender_by_id<Token>(token_id);
    escrow::new(&mut registry, token, RECIPIENT, scenario.ctx());
    let events = event::events_by_type<EscrowCreatedEvent>();
    assert_eq!(events.length(), 1);
    let (
        escrow_id,
        item_id,
        item_type,
        nonce,
        sender,
        recipient,
        sender_cap_id,
        recipient_cap_id,
    ) = escrow::escrow_created_fields_for_testing(&events[0]);
    assert_eq!(escrow_id.to_address(), registry.derive_address(token_id));
    assert_eq!(item_id, token_id);
    assert_eq!(item_type, type_name::with_defining_ids<Token>());
    assert_eq!(nonce, 0);
    assert_eq!(sender, SENDER);
    assert_eq!(recipient, RECIPIENT);
    assert!(registry.exists(token_id));
    let escrow = registry.borrow<Token>(token_id);
    assert_eq!(escrow.nonce(), 0);
    assert_eq!(escrow.sender(), SENDER);
    assert_eq!(escrow.recipient(), RECIPIENT);
    assert!(escrow.state().is_pending());
    assert!(!escrow.state().is_accepted());
    assert!(!escrow.state().is_declined());
    ts::return_shared(registry);
    scenario.next_tx(SENDER);
    let sender_cap = scenario.take_from_sender<EscrowSenderCap<Token>>();
    assert_eq!(object::id(&sender_cap), sender_cap_id);
    let (cap_item_id, cap_nonce) = escrow::sender_cap_fields_for_testing(&sender_cap);
    assert_eq!(cap_item_id, token_id);
    assert_eq!(cap_nonce, 0);
    scenario.return_to_sender(sender_cap);
    scenario.next_tx(RECIPIENT);
    let recipient_cap = scenario.take_from_sender<EscrowRecipientCap<Token>>();
    assert_eq!(object::id(&recipient_cap), recipient_cap_id);
    let (cap_item_id, cap_nonce) = escrow::recipient_cap_fields_for_testing(&recipient_cap);
    assert_eq!(cap_item_id, token_id);
    assert_eq!(cap_nonce, 0);
    scenario.return_to_sender(recipient_cap);
    scenario.end();
}

#[test]
fun escrows_of_different_items_are_independent() {
    let mut scenario = setup();
    let first_token = mint(&mut scenario, SENDER);
    let second_token = mint(&mut scenario, SENDER);
    let first = send(&mut scenario, SENDER, first_token, RECIPIENT);
    let second = send(&mut scenario, SENDER, second_token, OTHER);
    assert!(first.escrow_id != second.escrow_id);
    assert_eq!(first.nonce, 0);
    assert_eq!(second.nonce, 1);
    accept(&mut scenario, OTHER, &second);
    complete(&mut scenario, SENDER, &second);
    assert!(owns(&mut scenario, OTHER, second_token));
    assert!(is_escrowed(&mut scenario, first_token));
    assert!(!is_escrowed(&mut scenario, second_token));
    scenario.end();
}

#[test, expected_failure(abort_code = escrow::ESelfTransfer)]
fun new_to_self_aborts() {
    let mut scenario = setup();
    let token_id = mint(&mut scenario, SENDER);
    send(&mut scenario, SENDER, token_id, SENDER);
    abort
}

#[test, expected_failure(abort_code = df::EFieldDoesNotExist)]
fun borrow_without_an_escrow_aborts() {
    let mut scenario = setup();
    let token_id = mint(&mut scenario, SENDER);
    scenario.next_tx(SENDER);
    let registry = scenario.take_shared<EscrowRegistry>();
    registry.borrow<Token>(token_id);
    abort
}

// === Accept and complete ===

#[test]
fun accept_then_complete_delivers_the_item_to_the_recipient() {
    let mut scenario = setup();
    let token_id = mint(&mut scenario, SENDER);
    let created = send(&mut scenario, SENDER, token_id, RECIPIENT);
    accept(&mut scenario, RECIPIENT, &created);
    let events = event::events_by_type<EscrowAcceptedEvent>();
    assert_eq!(events.length(), 1);
    let (escrow_id, item_id, nonce, sender, recipient) =
        escrow::escrow_accepted_fields_for_testing(&events[0]);
    assert_eq!(escrow_id, created.escrow_id);
    assert_eq!(item_id, token_id);
    assert_eq!(nonce, 0);
    assert_eq!(sender, SENDER);
    assert_eq!(recipient, RECIPIENT);
    scenario.next_tx(OTHER);
    let registry = scenario.take_shared<EscrowRegistry>();
    assert!(registry.borrow<Token>(token_id).state().is_accepted());
    ts::return_shared(registry);
    assert!(!ts::has_most_recent_for_address<EscrowRecipientCap<Token>>(RECIPIENT));
    complete(&mut scenario, SENDER, &created);
    let events = event::events_by_type<EscrowCompletedEvent>();
    assert_eq!(events.length(), 1);
    let (escrow_id, item_id, nonce, sender, recipient) =
        escrow::escrow_completed_fields_for_testing(&events[0]);
    assert_eq!(escrow_id, created.escrow_id);
    assert_eq!(item_id, token_id);
    assert_eq!(nonce, 0);
    assert_eq!(sender, SENDER);
    assert_eq!(recipient, RECIPIENT);
    assert!(owns(&mut scenario, RECIPIENT, token_id));
    assert!(!owns(&mut scenario, SENDER, token_id));
    assert!(!is_escrowed(&mut scenario, token_id));
    assert!(!ts::has_most_recent_for_address<EscrowSenderCap<Token>>(SENDER));
    scenario.end();
}

#[test, expected_failure(abort_code = escrow::EWrongState)]
fun complete_while_pending_aborts() {
    let mut scenario = setup();
    let token_id = mint(&mut scenario, SENDER);
    let created = send(&mut scenario, SENDER, token_id, RECIPIENT);
    complete(&mut scenario, SENDER, &created);
    abort
}

#[test, expected_failure(abort_code = escrow::EWrongState)]
fun complete_after_decline_aborts() {
    let mut scenario = setup();
    let token_id = mint(&mut scenario, SENDER);
    let created = send(&mut scenario, SENDER, token_id, RECIPIENT);
    decline(&mut scenario, RECIPIENT, &created);
    complete(&mut scenario, SENDER, &created);
    abort
}

// === Decline and cancel ===

#[test]
fun cancel_while_pending_returns_the_item_to_the_sender() {
    let mut scenario = setup();
    let token_id = mint(&mut scenario, SENDER);
    let created = send(&mut scenario, SENDER, token_id, RECIPIENT);
    cancel(&mut scenario, SENDER, &created);
    let events = event::events_by_type<EscrowCancelledEvent>();
    assert_eq!(events.length(), 1);
    let (escrow_id, item_id, nonce, sender, recipient, state) =
        escrow::escrow_cancelled_fields_for_testing(&events[0]);
    assert_eq!(escrow_id, created.escrow_id);
    assert_eq!(item_id, token_id);
    assert_eq!(nonce, 0);
    assert_eq!(sender, SENDER);
    assert_eq!(recipient, RECIPIENT);
    assert!(state.is_pending());
    assert!(owns(&mut scenario, SENDER, token_id));
    assert!(!is_escrowed(&mut scenario, token_id));
    assert!(!ts::has_most_recent_for_address<EscrowSenderCap<Token>>(SENDER));
    assert!(ts::has_most_recent_for_address<EscrowRecipientCap<Token>>(RECIPIENT));
    scenario.end();
}

#[test]
fun cancel_after_accept_returns_the_item_to_the_sender() {
    let mut scenario = setup();
    let token_id = mint(&mut scenario, SENDER);
    let created = send(&mut scenario, SENDER, token_id, RECIPIENT);
    accept(&mut scenario, RECIPIENT, &created);
    cancel(&mut scenario, SENDER, &created);
    let events = event::events_by_type<EscrowCancelledEvent>();
    let (_, _, _, _, _, state) = escrow::escrow_cancelled_fields_for_testing(&events[0]);
    assert!(state.is_accepted());
    assert!(owns(&mut scenario, SENDER, token_id));
    assert!(!owns(&mut scenario, RECIPIENT, token_id));
    assert!(!is_escrowed(&mut scenario, token_id));
    scenario.end();
}

#[test]
fun decline_then_cancel_returns_the_item_to_the_sender() {
    let mut scenario = setup();
    let token_id = mint(&mut scenario, SENDER);
    let created = send(&mut scenario, SENDER, token_id, RECIPIENT);
    decline(&mut scenario, RECIPIENT, &created);
    let events = event::events_by_type<EscrowDeclinedEvent>();
    assert_eq!(events.length(), 1);
    let (escrow_id, item_id, nonce, sender, recipient) =
        escrow::escrow_declined_fields_for_testing(&events[0]);
    assert_eq!(escrow_id, created.escrow_id);
    assert_eq!(item_id, token_id);
    assert_eq!(nonce, 0);
    assert_eq!(sender, SENDER);
    assert_eq!(recipient, RECIPIENT);
    scenario.next_tx(OTHER);
    let registry = scenario.take_shared<EscrowRegistry>();
    assert!(registry.borrow<Token>(token_id).state().is_declined());
    ts::return_shared(registry);
    assert!(!ts::has_most_recent_for_address<EscrowRecipientCap<Token>>(RECIPIENT));
    cancel(&mut scenario, SENDER, &created);
    let events = event::events_by_type<EscrowCancelledEvent>();
    let (_, _, _, _, _, state) = escrow::escrow_cancelled_fields_for_testing(&events[0]);
    assert!(state.is_declined());
    assert!(owns(&mut scenario, SENDER, token_id));
    assert!(!is_escrowed(&mut scenario, token_id));
    scenario.end();
}

// === Re-escrow ===

#[test]
fun the_same_item_can_be_escrowed_again_after_complete() {
    let mut scenario = setup();
    let token_id = mint(&mut scenario, SENDER);
    let first = send(&mut scenario, SENDER, token_id, RECIPIENT);
    accept(&mut scenario, RECIPIENT, &first);
    complete(&mut scenario, SENDER, &first);
    let second = send(&mut scenario, RECIPIENT, token_id, SENDER);
    assert_eq!(second.escrow_id, first.escrow_id);
    assert_eq!(second.nonce, 1);
    accept(&mut scenario, SENDER, &second);
    complete(&mut scenario, RECIPIENT, &second);
    assert!(owns(&mut scenario, SENDER, token_id));
    assert!(!is_escrowed(&mut scenario, token_id));
    scenario.end();
}

#[test]
fun the_same_item_can_be_escrowed_again_after_cancel() {
    let mut scenario = setup();
    let token_id = mint(&mut scenario, SENDER);
    let first = send(&mut scenario, SENDER, token_id, RECIPIENT);
    cancel(&mut scenario, SENDER, &first);
    let second = send(&mut scenario, SENDER, token_id, OTHER);
    assert_eq!(second.escrow_id, first.escrow_id);
    assert_eq!(second.nonce, 1);
    accept(&mut scenario, OTHER, &second);
    complete(&mut scenario, SENDER, &second);
    assert!(owns(&mut scenario, OTHER, token_id));
    scenario.end();
}

// === Stale and foreign caps ===

#[test, expected_failure(abort_code = df::EFieldDoesNotExist)]
fun recipient_cap_of_a_cancelled_escrow_cannot_accept() {
    let mut scenario = setup();
    let token_id = mint(&mut scenario, SENDER);
    let created = send(&mut scenario, SENDER, token_id, RECIPIENT);
    cancel(&mut scenario, SENDER, &created);
    accept(&mut scenario, RECIPIENT, &created);
    abort
}

#[test, expected_failure(abort_code = escrow::EStaleCap)]
fun stale_recipient_cap_cannot_accept_the_next_escrow_of_the_item() {
    let mut scenario = setup();
    let token_id = mint(&mut scenario, SENDER);
    let first = send(&mut scenario, SENDER, token_id, RECIPIENT);
    cancel(&mut scenario, SENDER, &first);
    send(&mut scenario, SENDER, token_id, RECIPIENT);
    accept(&mut scenario, RECIPIENT, &first);
    abort
}

#[test, expected_failure(abort_code = escrow::EStaleCap)]
fun stale_recipient_cap_cannot_decline_the_next_escrow_of_the_item() {
    let mut scenario = setup();
    let token_id = mint(&mut scenario, SENDER);
    let first = send(&mut scenario, SENDER, token_id, RECIPIENT);
    cancel(&mut scenario, SENDER, &first);
    send(&mut scenario, SENDER, token_id, OTHER);
    decline(&mut scenario, RECIPIENT, &first);
    abort
}

#[test, expected_failure(abort_code = df::EFieldDoesNotExist)]
fun a_sender_cap_cannot_act_through_another_registry() {
    let mut scenario = setup();
    let token_id = mint(&mut scenario, SENDER);
    let created = send(&mut scenario, SENDER, token_id, RECIPIENT);
    scenario.next_tx(SENDER);
    let registry = scenario.take_shared<EscrowRegistry>();
    let registry_id = object::id(&registry);
    ts::return_shared(registry);
    escrow::init_for_testing(scenario.ctx());
    scenario.next_tx(SENDER);
    let other_id = ts::most_recent_id_shared<EscrowRegistry>().destroy_some();
    assert!(other_id != registry_id);
    let mut other = scenario.take_shared_by_id<EscrowRegistry>(other_id);
    let cap = scenario.take_from_sender_by_id<EscrowSenderCap<Token>>(created.sender_cap_id);
    escrow::cancel(&mut other, cap);
    abort
}

// === Burn ===

#[test]
fun burn_deletes_the_recipient_cap_of_a_cancelled_escrow() {
    let mut scenario = setup();
    let token_id = mint(&mut scenario, SENDER);
    let created = send(&mut scenario, SENDER, token_id, RECIPIENT);
    cancel(&mut scenario, SENDER, &created);
    burn(&mut scenario, RECIPIENT, &created);
    let events = event::events_by_type<EscrowRecipientCapBurnedEvent>();
    assert_eq!(events.length(), 1);
    let (escrow_id, item_id, nonce, recipient_cap_id) =
        escrow::escrow_recipient_cap_burned_fields_for_testing(&events[0]);
    assert_eq!(escrow_id, created.escrow_id);
    assert_eq!(item_id, token_id);
    assert_eq!(nonce, 0);
    assert_eq!(recipient_cap_id, created.recipient_cap_id);
    scenario.next_tx(RECIPIENT);
    assert!(!ts::has_most_recent_for_address<EscrowRecipientCap<Token>>(RECIPIENT));
    scenario.end();
}

#[test]
fun burn_deletes_a_stale_recipient_cap_while_the_next_escrow_is_live() {
    let mut scenario = setup();
    let token_id = mint(&mut scenario, SENDER);
    let first = send(&mut scenario, SENDER, token_id, RECIPIENT);
    cancel(&mut scenario, SENDER, &first);
    let second = send(&mut scenario, SENDER, token_id, RECIPIENT);
    burn(&mut scenario, RECIPIENT, &first);
    let events = event::events_by_type<EscrowRecipientCapBurnedEvent>();
    let (escrow_id, _, nonce, recipient_cap_id) =
        escrow::escrow_recipient_cap_burned_fields_for_testing(&events[0]);
    assert_eq!(escrow_id, first.escrow_id);
    assert_eq!(nonce, 0);
    assert_eq!(recipient_cap_id, first.recipient_cap_id);
    accept(&mut scenario, RECIPIENT, &second);
    complete(&mut scenario, SENDER, &second);
    assert!(owns(&mut scenario, RECIPIENT, token_id));
    scenario.end();
}

#[test, expected_failure(abort_code = escrow::EEscrowPending)]
fun burn_of_a_live_recipient_cap_aborts() {
    let mut scenario = setup();
    let token_id = mint(&mut scenario, SENDER);
    let created = send(&mut scenario, SENDER, token_id, RECIPIENT);
    burn(&mut scenario, RECIPIENT, &created);
    abort
}
