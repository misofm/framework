// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module party_group::party_group_tests;

use miso_party::party::{Self, Party, PartyAdminCap};
use party_group::party_group::{
    Self,
    PartyGroupInvite,
    PartyGroupInviteDeclinedEvent,
    PartyGroupJoinedEvent,
    PartyGroupLeftEvent,
    PartyMemberAddedEvent,
    PartyMemberRemovedEvent,
};
use std::unit_test::assert_eq;
use sui::{event::events_by_type, test_scenario::{Self, Scenario}};

const GROUP_ADMIN: address = @0xA;
const MEMBER_ADMIN: address = @0xB;
const OTHER_ADMIN: address = @0xC;

fun new_party(scenario: &mut Scenario, admin: address): ID {
    scenario.next_tx(admin);
    let (party, cap) = party::new(scenario.ctx());
    let party_id = object::id(&party);
    party.share();
    transfer::public_transfer(cap, admin);
    party_id
}

fun add_member(scenario: &mut Scenario, sender: address, group_id: ID, member_id: ID): ID {
    scenario.next_tx(sender);
    let mut group = scenario.take_shared_by_id<Party>(group_id);
    let member = scenario.take_shared_by_id<Party>(member_id);
    let cap = scenario.take_from_sender<PartyAdminCap>();
    party_group::add_member(&mut group, &cap, &member, scenario.ctx());
    let events = events_by_type<PartyMemberAddedEvent>();
    assert_eq!(events.length(), 1);
    let (
        event_group_id,
        event_member_id,
        invite_id,
    ) = party_group::party_member_added_fields_for_testing(
        &events[0],
    );
    assert_eq!(event_group_id, group_id);
    assert_eq!(event_member_id, member_id);
    test_scenario::return_shared(group);
    test_scenario::return_shared(member);
    scenario.return_to_sender(cap);
    invite_id
}

fun remove_member(scenario: &mut Scenario, sender: address, group_id: ID, member_id: ID) {
    scenario.next_tx(sender);
    let mut group = scenario.take_shared_by_id<Party>(group_id);
    let cap = scenario.take_from_sender<PartyAdminCap>();
    party_group::remove_member(&mut group, &cap, member_id);
    let events = events_by_type<PartyMemberRemovedEvent>();
    assert_eq!(events.length(), 1);
    let (event_group_id, event_member_id) = party_group::party_member_removed_fields_for_testing(
        &events[0],
    );
    assert_eq!(event_group_id, group_id);
    assert_eq!(event_member_id, member_id);
    test_scenario::return_shared(group);
    scenario.return_to_sender(cap);
}

fun join(scenario: &mut Scenario, sender: address, member_id: ID, group_id: ID, invite_id: ID) {
    scenario.next_tx(sender);
    let mut member = scenario.take_shared_by_id<Party>(member_id);
    let group = scenario.take_shared_by_id<Party>(group_id);
    let cap = scenario.take_from_sender<PartyAdminCap>();
    let invite = test_scenario::receiving_ticket_by_id<PartyGroupInvite>(invite_id);
    party_group::join(&mut member, &cap, &group, invite);
    let events = events_by_type<PartyGroupJoinedEvent>();
    assert_eq!(events.length(), 1);
    let (event_group_id, event_member_id) = party_group::party_group_joined_fields_for_testing(
        &events[0],
    );
    assert_eq!(event_group_id, group_id);
    assert_eq!(event_member_id, member_id);
    test_scenario::return_shared(member);
    test_scenario::return_shared(group);
    scenario.return_to_sender(cap);
}

fun decline(scenario: &mut Scenario, sender: address, member_id: ID, group_id: ID, invite_id: ID) {
    scenario.next_tx(sender);
    let mut member = scenario.take_shared_by_id<Party>(member_id);
    let cap = scenario.take_from_sender<PartyAdminCap>();
    let invite = test_scenario::receiving_ticket_by_id<PartyGroupInvite>(invite_id);
    party_group::decline(&mut member, &cap, invite);
    let events = events_by_type<PartyGroupInviteDeclinedEvent>();
    assert_eq!(events.length(), 1);
    let (
        event_group_id,
        event_member_id,
        event_invite_id,
    ) = party_group::party_group_invite_declined_fields_for_testing(
        &events[0],
    );
    assert_eq!(event_group_id, group_id);
    assert_eq!(event_member_id, member_id);
    assert_eq!(event_invite_id, invite_id);
    test_scenario::return_shared(member);
    scenario.return_to_sender(cap);
}

fun leave(scenario: &mut Scenario, sender: address, member_id: ID, group_id: ID) {
    scenario.next_tx(sender);
    let mut member = scenario.take_shared_by_id<Party>(member_id);
    let cap = scenario.take_from_sender<PartyAdminCap>();
    party_group::leave(&mut member, &cap, group_id);
    let events = events_by_type<PartyGroupLeftEvent>();
    assert_eq!(events.length(), 1);
    let (event_group_id, event_member_id) = party_group::party_group_left_fields_for_testing(
        &events[0],
    );
    assert_eq!(event_group_id, group_id);
    assert_eq!(event_member_id, member_id);
    test_scenario::return_shared(member);
    scenario.return_to_sender(cap);
}

fun assert_state(
    scenario: &mut Scenario,
    group_id: ID,
    member_id: ID,
    group_half: bool,
    member_half: bool,
) {
    scenario.next_tx(OTHER_ADMIN);
    let group = scenario.take_shared_by_id<Party>(group_id);
    let member = scenario.take_shared_by_id<Party>(member_id);
    assert_eq!(party_group::has_member(&group, member_id), group_half);
    assert_eq!(party_group::has_group_membership(&member, group_id), member_half);
    assert_eq!(party_group::is_member(&group, &member), group_half && member_half);
    test_scenario::return_shared(group);
    test_scenario::return_shared(member);
}

fun invite_count(scenario: &mut Scenario, member_id: ID): u64 {
    scenario.next_tx(OTHER_ADMIN);
    test_scenario::ids_for_address<PartyGroupInvite>(member_id.to_address()).length()
}

#[test]
fun full_flow_from_invite_to_member() {
    let mut scenario = test_scenario::begin(GROUP_ADMIN);
    let group_id = new_party(&mut scenario, GROUP_ADMIN);
    let member_id = new_party(&mut scenario, MEMBER_ADMIN);
    assert_state(&mut scenario, group_id, member_id, false, false);
    let invite_id = add_member(&mut scenario, GROUP_ADMIN, group_id, member_id);
    assert_state(&mut scenario, group_id, member_id, true, false);
    let invites = test_scenario::ids_for_address<PartyGroupInvite>(member_id.to_address());
    assert_eq!(invites, vector[invite_id]);
    let invite = scenario.take_from_address_by_id<PartyGroupInvite>(
        member_id.to_address(),
        invite_id,
    );
    assert_eq!(invite.group_id(), group_id);
    assert_eq!(party_group::party_group_invite_group_id(&invite), group_id);
    test_scenario::return_to_address(member_id.to_address(), invite);
    join(&mut scenario, MEMBER_ADMIN, member_id, group_id, invite_id);
    assert_state(&mut scenario, group_id, member_id, true, true);
    assert_eq!(invite_count(&mut scenario, member_id), 0);
    scenario.end();
}

#[test]
fun member_leaves_then_group_removes() {
    let mut scenario = test_scenario::begin(GROUP_ADMIN);
    let group_id = new_party(&mut scenario, GROUP_ADMIN);
    let member_id = new_party(&mut scenario, MEMBER_ADMIN);
    let invite_id = add_member(&mut scenario, GROUP_ADMIN, group_id, member_id);
    join(&mut scenario, MEMBER_ADMIN, member_id, group_id, invite_id);
    leave(&mut scenario, MEMBER_ADMIN, member_id, group_id);
    assert_state(&mut scenario, group_id, member_id, true, false);
    remove_member(&mut scenario, GROUP_ADMIN, group_id, member_id);
    assert_state(&mut scenario, group_id, member_id, false, false);
    scenario.end();
}

#[test]
fun group_removes_then_member_leaves() {
    let mut scenario = test_scenario::begin(GROUP_ADMIN);
    let group_id = new_party(&mut scenario, GROUP_ADMIN);
    let member_id = new_party(&mut scenario, MEMBER_ADMIN);
    let invite_id = add_member(&mut scenario, GROUP_ADMIN, group_id, member_id);
    join(&mut scenario, MEMBER_ADMIN, member_id, group_id, invite_id);
    remove_member(&mut scenario, GROUP_ADMIN, group_id, member_id);
    assert_state(&mut scenario, group_id, member_id, false, true);
    leave(&mut scenario, MEMBER_ADMIN, member_id, group_id);
    assert_state(&mut scenario, group_id, member_id, false, false);
    scenario.end();
}

#[test]
fun decline_deletes_invite_and_leaves_group_half() {
    let mut scenario = test_scenario::begin(GROUP_ADMIN);
    let group_id = new_party(&mut scenario, GROUP_ADMIN);
    let member_id = new_party(&mut scenario, MEMBER_ADMIN);
    let invite_id = add_member(&mut scenario, GROUP_ADMIN, group_id, member_id);
    decline(&mut scenario, MEMBER_ADMIN, member_id, group_id, invite_id);
    assert_eq!(invite_count(&mut scenario, member_id), 0);
    assert_state(&mut scenario, group_id, member_id, true, false);
    remove_member(&mut scenario, GROUP_ADMIN, group_id, member_id);
    assert_state(&mut scenario, group_id, member_id, false, false);
    scenario.end();
}

#[test]
fun revoked_invite_is_cleaned_up_by_decline() {
    let mut scenario = test_scenario::begin(GROUP_ADMIN);
    let group_id = new_party(&mut scenario, GROUP_ADMIN);
    let member_id = new_party(&mut scenario, MEMBER_ADMIN);
    let invite_id = add_member(&mut scenario, GROUP_ADMIN, group_id, member_id);
    remove_member(&mut scenario, GROUP_ADMIN, group_id, member_id);
    assert_eq!(invite_count(&mut scenario, member_id), 1);
    decline(&mut scenario, MEMBER_ADMIN, member_id, group_id, invite_id);
    assert_eq!(invite_count(&mut scenario, member_id), 0);
    assert_state(&mut scenario, group_id, member_id, false, false);
    scenario.end();
}

#[test]
fun reinvite_after_leave_succeeds() {
    let mut scenario = test_scenario::begin(GROUP_ADMIN);
    let group_id = new_party(&mut scenario, GROUP_ADMIN);
    let member_id = new_party(&mut scenario, MEMBER_ADMIN);
    let first_invite_id = add_member(&mut scenario, GROUP_ADMIN, group_id, member_id);
    join(&mut scenario, MEMBER_ADMIN, member_id, group_id, first_invite_id);
    remove_member(&mut scenario, GROUP_ADMIN, group_id, member_id);
    leave(&mut scenario, MEMBER_ADMIN, member_id, group_id);
    let second_invite_id = add_member(&mut scenario, GROUP_ADMIN, group_id, member_id);
    assert!(first_invite_id != second_invite_id);
    join(&mut scenario, MEMBER_ADMIN, member_id, group_id, second_invite_id);
    assert_state(&mut scenario, group_id, member_id, true, true);
    scenario.end();
}

#[test, expected_failure(abort_code = party_group::EMembershipStillPresent)]
fun reinvite_while_member_half_remains_aborts() {
    let mut scenario = test_scenario::begin(GROUP_ADMIN);
    let group_id = new_party(&mut scenario, GROUP_ADMIN);
    let member_id = new_party(&mut scenario, MEMBER_ADMIN);
    let invite_id = add_member(&mut scenario, GROUP_ADMIN, group_id, member_id);
    join(&mut scenario, MEMBER_ADMIN, member_id, group_id, invite_id);
    remove_member(&mut scenario, GROUP_ADMIN, group_id, member_id);
    add_member(&mut scenario, GROUP_ADMIN, group_id, member_id);
    abort
}

#[test, expected_failure(abort_code = party_group::EInviteNotFound)]
fun join_with_revoked_invite_aborts() {
    let mut scenario = test_scenario::begin(GROUP_ADMIN);
    let group_id = new_party(&mut scenario, GROUP_ADMIN);
    let member_id = new_party(&mut scenario, MEMBER_ADMIN);
    let invite_id = add_member(&mut scenario, GROUP_ADMIN, group_id, member_id);
    remove_member(&mut scenario, GROUP_ADMIN, group_id, member_id);
    join(&mut scenario, MEMBER_ADMIN, member_id, group_id, invite_id);
    abort
}

#[test, expected_failure(abort_code = party_group::EWrongInvite)]
fun join_with_another_groups_invite_aborts() {
    let mut scenario = test_scenario::begin(GROUP_ADMIN);
    let group_id = new_party(&mut scenario, GROUP_ADMIN);
    let other_group_id = new_party(&mut scenario, OTHER_ADMIN);
    let member_id = new_party(&mut scenario, MEMBER_ADMIN);
    add_member(&mut scenario, GROUP_ADMIN, group_id, member_id);
    let other_invite_id = add_member(&mut scenario, OTHER_ADMIN, other_group_id, member_id);
    join(&mut scenario, MEMBER_ADMIN, member_id, group_id, other_invite_id);
    abort
}

#[test, expected_failure(abort_code = party_group::EMembershipAlreadyAdded)]
fun join_twice_through_a_stale_invite_aborts() {
    let mut scenario = test_scenario::begin(GROUP_ADMIN);
    let group_id = new_party(&mut scenario, GROUP_ADMIN);
    let member_id = new_party(&mut scenario, MEMBER_ADMIN);
    let first_invite_id = add_member(&mut scenario, GROUP_ADMIN, group_id, member_id);
    remove_member(&mut scenario, GROUP_ADMIN, group_id, member_id);
    let second_invite_id = add_member(&mut scenario, GROUP_ADMIN, group_id, member_id);
    join(&mut scenario, MEMBER_ADMIN, member_id, group_id, first_invite_id);
    join(&mut scenario, MEMBER_ADMIN, member_id, group_id, second_invite_id);
    abort
}

#[test, expected_failure(abort_code = party_group::EMemberAlreadyAdded)]
fun add_member_twice_aborts() {
    let mut scenario = test_scenario::begin(GROUP_ADMIN);
    let group_id = new_party(&mut scenario, GROUP_ADMIN);
    let member_id = new_party(&mut scenario, MEMBER_ADMIN);
    add_member(&mut scenario, GROUP_ADMIN, group_id, member_id);
    add_member(&mut scenario, GROUP_ADMIN, group_id, member_id);
    abort
}

#[test, expected_failure(abort_code = party_group::EMemberNotFound)]
fun remove_missing_member_aborts() {
    let mut scenario = test_scenario::begin(GROUP_ADMIN);
    let group_id = new_party(&mut scenario, GROUP_ADMIN);
    let member_id = new_party(&mut scenario, MEMBER_ADMIN);
    remove_member(&mut scenario, GROUP_ADMIN, group_id, member_id);
    abort
}

#[test, expected_failure(abort_code = party_group::EMembershipNotFound)]
fun leave_without_membership_aborts() {
    let mut scenario = test_scenario::begin(GROUP_ADMIN);
    let group_id = new_party(&mut scenario, GROUP_ADMIN);
    let member_id = new_party(&mut scenario, MEMBER_ADMIN);
    leave(&mut scenario, MEMBER_ADMIN, member_id, group_id);
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun add_member_with_wrong_cap_aborts() {
    let mut scenario = test_scenario::begin(GROUP_ADMIN);
    let group_id = new_party(&mut scenario, GROUP_ADMIN);
    let member_id = new_party(&mut scenario, MEMBER_ADMIN);
    add_member(&mut scenario, MEMBER_ADMIN, group_id, member_id);
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun remove_member_with_wrong_cap_aborts() {
    let mut scenario = test_scenario::begin(GROUP_ADMIN);
    let group_id = new_party(&mut scenario, GROUP_ADMIN);
    let member_id = new_party(&mut scenario, MEMBER_ADMIN);
    add_member(&mut scenario, GROUP_ADMIN, group_id, member_id);
    remove_member(&mut scenario, MEMBER_ADMIN, group_id, member_id);
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun join_with_wrong_cap_aborts() {
    let mut scenario = test_scenario::begin(GROUP_ADMIN);
    let group_id = new_party(&mut scenario, GROUP_ADMIN);
    let member_id = new_party(&mut scenario, MEMBER_ADMIN);
    let invite_id = add_member(&mut scenario, GROUP_ADMIN, group_id, member_id);
    join(&mut scenario, GROUP_ADMIN, member_id, group_id, invite_id);
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun decline_with_wrong_cap_aborts() {
    let mut scenario = test_scenario::begin(GROUP_ADMIN);
    let group_id = new_party(&mut scenario, GROUP_ADMIN);
    let member_id = new_party(&mut scenario, MEMBER_ADMIN);
    let invite_id = add_member(&mut scenario, GROUP_ADMIN, group_id, member_id);
    decline(&mut scenario, GROUP_ADMIN, member_id, group_id, invite_id);
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun leave_with_wrong_cap_aborts() {
    let mut scenario = test_scenario::begin(GROUP_ADMIN);
    let group_id = new_party(&mut scenario, GROUP_ADMIN);
    let member_id = new_party(&mut scenario, MEMBER_ADMIN);
    let invite_id = add_member(&mut scenario, GROUP_ADMIN, group_id, member_id);
    join(&mut scenario, MEMBER_ADMIN, member_id, group_id, invite_id);
    leave(&mut scenario, GROUP_ADMIN, member_id, group_id);
    abort
}
