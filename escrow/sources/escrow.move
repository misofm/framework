// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module escrow::escrow;

use std::type_name::{Self, TypeName};
use sui::{derived_object, dynamic_object_field as dof, event::emit};

// === Errors ===

const ESelfTransfer: u64 = 0;
const EStaleCap: u64 = 1;
const EWrongState: u64 = 2;
const EEscrowPending: u64 = 3;

// === Structs ===

public struct Escrow<Item: key + store> has key, store {
    id: UID,
    item: Item,
    nonce: u64,
    sender: address,
    recipient: address,
    state: EscrowState,
}

public struct EscrowSenderCap<phantom Item: key + store> has key {
    id: UID,
    item_id: ID,
    nonce: u64,
}

public struct EscrowRecipientCap<phantom Item: key + store> has key {
    id: UID,
    item_id: ID,
    nonce: u64,
}

public struct EscrowRegistry has key {
    id: UID,
    next_nonce: u64,
}

public struct EscrowKey(ID) has copy, drop, store;

// === Enums ===

public enum EscrowState has copy, drop, store {
    Pending,
    Accepted,
    Declined,
}

// === Events ===

public struct EscrowCreatedEvent has copy, drop {
    escrow_id: ID,
    item_id: ID,
    item_type: TypeName,
    nonce: u64,
    sender: address,
    recipient: address,
    sender_cap_id: ID,
    recipient_cap_id: ID,
}

public struct EscrowAcceptedEvent has copy, drop {
    escrow_id: ID,
    item_id: ID,
    nonce: u64,
    sender: address,
    recipient: address,
}

public struct EscrowDeclinedEvent has copy, drop {
    escrow_id: ID,
    item_id: ID,
    nonce: u64,
    sender: address,
    recipient: address,
}

public struct EscrowCompletedEvent has copy, drop {
    escrow_id: ID,
    item_id: ID,
    nonce: u64,
    sender: address,
    recipient: address,
}

public struct EscrowCancelledEvent has copy, drop {
    escrow_id: ID,
    item_id: ID,
    nonce: u64,
    sender: address,
    recipient: address,
    state: EscrowState,
}

public struct EscrowRecipientCapBurnedEvent has copy, drop {
    escrow_id: ID,
    item_id: ID,
    nonce: u64,
    recipient_cap_id: ID,
}

// === Method Aliases ===

public use fun escrow_state_is_pending as EscrowState.is_pending;
public use fun escrow_state_is_accepted as EscrowState.is_accepted;
public use fun escrow_state_is_declined as EscrowState.is_declined;

// === Init Function ===

fun init(ctx: &mut TxContext) {
    transfer::share_object(EscrowRegistry { id: object::new(ctx), next_nonce: 0 });
}

// === Public Functions ===

public fun new<Item: key + store>(
    registry: &mut EscrowRegistry,
    item: Item,
    recipient: address,
    ctx: &mut TxContext,
) {
    let sender = ctx.sender();
    assert!(recipient != sender, ESelfTransfer);
    let item_id = object::id(&item);
    let nonce = registry.next_nonce;
    registry.next_nonce = nonce + 1;
    let escrow = Escrow {
        id: derived_object::claim(&mut registry.id, EscrowKey(item_id)),
        item,
        nonce,
        sender,
        recipient,
        state: EscrowState::Pending,
    };
    let escrow_id = object::id(&escrow);
    dof::add(&mut registry.id, EscrowKey(item_id), escrow);
    let sender_cap = EscrowSenderCap<Item> { id: object::new(ctx), item_id, nonce };
    let recipient_cap = EscrowRecipientCap<Item> { id: object::new(ctx), item_id, nonce };
    emit(EscrowCreatedEvent {
        escrow_id,
        item_id,
        item_type: type_name::with_defining_ids<Item>(),
        nonce,
        sender,
        recipient,
        sender_cap_id: object::id(&sender_cap),
        recipient_cap_id: object::id(&recipient_cap),
    });
    transfer::transfer(sender_cap, sender);
    transfer::transfer(recipient_cap, recipient);
}

// === View Functions ===

public fun derive_address(registry: &EscrowRegistry, item_id: ID): address {
    derived_object::derive_address(object::id(registry), EscrowKey(item_id))
}

public fun exists(registry: &EscrowRegistry, item_id: ID): bool {
    dof::exists(&registry.id, EscrowKey(item_id))
}

public fun borrow<Item: key + store>(registry: &EscrowRegistry, item_id: ID): &Escrow<Item> {
    dof::borrow(&registry.id, EscrowKey(item_id))
}

public fun nonce<Item: key + store>(self: &Escrow<Item>): u64 {
    self.nonce
}

public fun sender<Item: key + store>(self: &Escrow<Item>): address {
    self.sender
}

public fun recipient<Item: key + store>(self: &Escrow<Item>): address {
    self.recipient
}

public fun state<Item: key + store>(self: &Escrow<Item>): EscrowState {
    self.state
}

public fun escrow_state_is_pending(state: &EscrowState): bool {
    state == &EscrowState::Pending
}

public fun escrow_state_is_accepted(state: &EscrowState): bool {
    state == &EscrowState::Accepted
}

public fun escrow_state_is_declined(state: &EscrowState): bool {
    state == &EscrowState::Declined
}

// === Admin Functions ===

public fun accept<Item: key + store>(
    registry: &mut EscrowRegistry,
    recipient_cap: EscrowRecipientCap<Item>,
) {
    let (escrow_id, item_id, nonce, sender, recipient) = registry.respond(
        recipient_cap,
        EscrowState::Accepted,
    );
    emit(EscrowAcceptedEvent { escrow_id, item_id, nonce, sender, recipient });
}

public fun decline<Item: key + store>(
    registry: &mut EscrowRegistry,
    recipient_cap: EscrowRecipientCap<Item>,
) {
    let (escrow_id, item_id, nonce, sender, recipient) = registry.respond(
        recipient_cap,
        EscrowState::Declined,
    );
    emit(EscrowDeclinedEvent { escrow_id, item_id, nonce, sender, recipient });
}

public fun complete<Item: key + store>(
    registry: &mut EscrowRegistry,
    sender_cap: EscrowSenderCap<Item>,
) {
    let (item, escrow_id, item_id, nonce, sender, recipient, state) = registry.close(sender_cap);
    state.require(EscrowState::Accepted);
    transfer::public_transfer(item, recipient);
    emit(EscrowCompletedEvent { escrow_id, item_id, nonce, sender, recipient });
}

public fun cancel<Item: key + store>(
    registry: &mut EscrowRegistry,
    sender_cap: EscrowSenderCap<Item>,
) {
    let (item, escrow_id, item_id, nonce, sender, recipient, state) = registry.close(sender_cap);
    transfer::public_transfer(item, sender);
    emit(EscrowCancelledEvent { escrow_id, item_id, nonce, sender, recipient, state });
}

public fun burn_recipient_cap<Item: key + store>(
    registry: &EscrowRegistry,
    recipient_cap: EscrowRecipientCap<Item>,
) {
    let EscrowRecipientCap { id, item_id, nonce } = recipient_cap;
    assert!(
        !registry.exists(item_id) || registry.borrow<Item>(item_id).nonce != nonce,
        EEscrowPending,
    );
    emit(EscrowRecipientCapBurnedEvent {
        escrow_id: registry.derive_address(item_id).to_id(),
        item_id,
        nonce,
        recipient_cap_id: id.to_inner(),
    });
    id.delete();
}

// === Private Functions ===

fun respond<Item: key + store>(
    registry: &mut EscrowRegistry,
    recipient_cap: EscrowRecipientCap<Item>,
    state: EscrowState,
): (ID, ID, u64, address, address) {
    let EscrowRecipientCap { id, item_id, nonce } = recipient_cap;
    id.delete();
    let escrow: &mut Escrow<Item> = dof::borrow_mut(&mut registry.id, EscrowKey(item_id));
    escrow.authorize(nonce);
    escrow.state.require(EscrowState::Pending);
    escrow.state = state;
    (object::id(escrow), item_id, nonce, escrow.sender, escrow.recipient)
}

fun close<Item: key + store>(
    registry: &mut EscrowRegistry,
    sender_cap: EscrowSenderCap<Item>,
): (Item, ID, ID, u64, address, address, EscrowState) {
    let EscrowSenderCap { id, item_id, nonce } = sender_cap;
    id.delete();
    let escrow: Escrow<Item> = dof::remove(&mut registry.id, EscrowKey(item_id));
    escrow.authorize(nonce);
    let Escrow { id, item, nonce: _, sender, recipient, state } = escrow;
    let escrow_id = id.to_inner();
    derived_object::release(&mut registry.id, id);
    (item, escrow_id, item_id, nonce, sender, recipient, state)
}

fun authorize<Item: key + store>(self: &Escrow<Item>, nonce: u64) {
    assert!(self.nonce == nonce, EStaleCap);
}

fun require(state: &EscrowState, expected: EscrowState) {
    assert!(state == &expected, EWrongState);
}

// === Test Functions ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx)
}

#[test_only]
public fun sender_cap_fields_for_testing<Item: key + store>(
    cap: &EscrowSenderCap<Item>,
): (ID, u64) {
    (cap.item_id, cap.nonce)
}

#[test_only]
public fun recipient_cap_fields_for_testing<Item: key + store>(
    cap: &EscrowRecipientCap<Item>,
): (ID, u64) {
    (cap.item_id, cap.nonce)
}

#[test_only]
public fun escrow_created_fields_for_testing(
    event: &EscrowCreatedEvent,
): (ID, ID, TypeName, u64, address, address, ID, ID) {
    (
        event.escrow_id,
        event.item_id,
        event.item_type,
        event.nonce,
        event.sender,
        event.recipient,
        event.sender_cap_id,
        event.recipient_cap_id,
    )
}

#[test_only]
public fun escrow_accepted_fields_for_testing(
    event: &EscrowAcceptedEvent,
): (ID, ID, u64, address, address) {
    (event.escrow_id, event.item_id, event.nonce, event.sender, event.recipient)
}

#[test_only]
public fun escrow_declined_fields_for_testing(
    event: &EscrowDeclinedEvent,
): (ID, ID, u64, address, address) {
    (event.escrow_id, event.item_id, event.nonce, event.sender, event.recipient)
}

#[test_only]
public fun escrow_completed_fields_for_testing(
    event: &EscrowCompletedEvent,
): (ID, ID, u64, address, address) {
    (event.escrow_id, event.item_id, event.nonce, event.sender, event.recipient)
}

#[test_only]
public fun escrow_cancelled_fields_for_testing(
    event: &EscrowCancelledEvent,
): (ID, ID, u64, address, address, EscrowState) {
    (event.escrow_id, event.item_id, event.nonce, event.sender, event.recipient, event.state)
}

#[test_only]
public fun escrow_recipient_cap_burned_fields_for_testing(
    event: &EscrowRecipientCapBurnedEvent,
): (ID, ID, u64, ID) {
    (event.escrow_id, event.item_id, event.nonce, event.recipient_cap_id)
}
