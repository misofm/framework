// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module party_group::party_group_tests;

use miso_party::party::{Self, Party, PartyAdminCap};
use party_group::party_group::{
    Self as group,
    Group,
    GroupCreatedEvent,
    GroupInviteCreatedEvent,
    GroupMembershipAcceptedEvent,
    GroupMembershipClearedEvent,
    GroupInviteDeclinedEvent,
    GroupInviteRevokedEvent,
    GroupMembershipLeftEvent,
    GroupMembershipRemovedEvent,
};
use std::unit_test::{assert_eq, destroy};
use sui::{bcs, event, test_scenario};
use typed_set::typed_set as set;

const OWNER: address = @0xA;
const MEMBER: address = @0xB;

fun setup(ctx: &mut TxContext): (Party, PartyAdminCap, Group, Party, PartyAdminCap) {
    let (mut party, cap) = party::new(ctx);
    let group = group::new(&mut party, &cap);
    let (member, member_cap) = party::new(ctx);
    (party, cap, group, member, member_cap)
}

fun assert_event<T: copy + drop>(first: ID, second: ID) {
    let mut expected = bcs::to_bytes(&first);
    expected.append(bcs::to_bytes(&second));
    let events = event::events_by_type<T>();
    let last = events.length() - 1;
    assert_eq!(bcs::to_bytes(&events[last]), expected);
}

#[test]
fun identity_and_empty_views() {
    let ctx = &mut tx_context::dummy();
    let (mut party, cap) = party::new(ctx);
    assert!(!group::has_group(&party));
    let group = group::new(&mut party, &cap);
    assert!(group::has_group(&party));
    assert_eq!(group.party_id(), object::id(&party));
    assert!(group.members().is_empty());
    assert!(group.pending_invites().is_empty());
    assert!(!group.is_member(object::id(&party)));
    assert!(!group.has_pending_invite(object::id(&party)));
    assert_event<GroupCreatedEvent>(object::id(&group), object::id(&party));
    assert_eq!(object::id(&group).to_address(), group::derive_address(object::id(&party)));
    destroy(group);
    destroy(party);
    destroy(cap);
}

#[test]
fun invitation_requires_acceptance_and_exit_reclaims_membership() {
    let ctx = &mut tx_context::dummy();
    let (party, cap, mut group, mut member, member_cap) = setup(ctx);
    let group_id = object::id(&group);
    let member_id = object::id(&member);
    group.invite_party(&cap, &member);
    assert!(group.has_pending_invite(member_id));
    assert!(!group.is_member(member_id));
    assert_eq!(group.pending_invites(), vector[member_id]);
    assert_event<GroupInviteCreatedEvent>(group_id, member_id);
    assert!(!group::has_group_membership(&member, group_id));
    group.accept_invite(&mut member, &member_cap);
    assert!(group::has_group_membership(&member, group_id));
    assert!(!group.has_pending_invite(member_id));
    assert!(group.pending_invites().is_empty());
    assert_eq!(group.members(), vector[member_id]);
    assert_event<GroupMembershipAcceptedEvent>(group_id, member_id);
    group.leave(&mut member, &member_cap);
    assert!(!group::has_group_membership(&member, group_id));
    assert!(!group.is_member(member_id));
    assert!(group.members().is_empty());
    assert_event<GroupMembershipLeftEvent>(group_id, member_id);
    group.invite_party(&cap, &member);
    group.accept_invite(&mut member, &member_cap);
    group.remove_member(&cap, member_id);
    assert!(!group.is_member(member_id));
    assert_event<GroupMembershipRemovedEvent>(group_id, member_id);
    destroy(group);
    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

#[test]
fun decline_revoke_and_reinvite() {
    let ctx = &mut tx_context::dummy();
    let (party, cap, mut group, mut member, member_cap) = setup(ctx);
    let group_id = object::id(&group);
    let member_id = object::id(&member);
    group.invite_party(&cap, &member);
    group.decline_invite(&member_cap);
    assert!(!group.has_pending_invite(member_id));
    assert_event<GroupInviteDeclinedEvent>(group_id, member_id);
    group.invite_party(&cap, &member);
    group.revoke_invite(&cap, member_id);
    assert!(group.pending_invites().is_empty());
    assert_event<GroupInviteRevokedEvent>(group_id, member_id);
    group.invite_party(&cap, &member);
    group.accept_invite(&mut member, &member_cap);
    assert!(group.is_member(member_id));
    destroy(group);
    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

#[test]
fun members_can_have_their_own_optional_group() {
    let ctx = &mut tx_context::dummy();
    let (party, cap, mut group, mut member, member_cap) = setup(ctx);
    let nested = group::new(&mut member, &member_cap);
    group.invite_party(&cap, &member);
    group.accept_invite(&mut member, &member_cap);
    assert!(group.is_member(object::id(&member)));
    assert!(!nested.is_member(object::id(&party)));
    destroy(nested);
    destroy(group);
    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

#[test]
fun shared_group_supports_independent_administrators() {
    let mut scenario = test_scenario::begin(OWNER);
    let (mut party, cap) = party::new(scenario.ctx());
    let party_id = object::id(&party);
    let group = group::new(&mut party, &cap);
    let group_id = object::id(&group);
    group.share();
    party.share();
    transfer::public_transfer(cap, OWNER);
    assert_event<GroupCreatedEvent>(group_id, party_id);
    scenario.next_tx(MEMBER);
    let (mut member, member_cap) = party::new(scenario.ctx());
    let member_id = object::id(&member);
    member.share();
    transfer::public_transfer(member_cap, MEMBER);
    scenario.next_tx(OWNER);
    let mut party = scenario.take_shared_by_id<Party>(party_id);
    let mut member = scenario.take_shared_by_id<Party>(member_id);
    let mut group = scenario.take_shared_by_id<Group>(group_id);
    let cap = scenario.take_from_sender<PartyAdminCap>();
    group.invite_party(&cap, &member);
    assert!(!group.is_member(member_id));
    test_scenario::return_shared(party);
    test_scenario::return_shared(member);
    test_scenario::return_shared(group);
    scenario.return_to_sender(cap);
    scenario.next_tx(MEMBER);
    let mut member = scenario.take_shared_by_id<Party>(member_id);
    let member_cap = scenario.take_from_sender<PartyAdminCap>();
    let mut group = scenario.take_shared_by_id<Group>(group_id);
    group.accept_invite(&mut member, &member_cap);
    assert!(group.is_member(member_id));
    test_scenario::return_shared(member);
    test_scenario::return_shared(group);
    scenario.return_to_sender(member_cap);
    scenario.next_tx(MEMBER);
    let mut member = scenario.take_shared_by_id<Party>(member_id);
    let member_cap = scenario.take_from_sender<PartyAdminCap>();
    let mut group = scenario.take_shared_by_id<Group>(group_id);
    group.leave(&mut member, &member_cap);
    assert!(!group.is_member(member_id));
    test_scenario::return_shared(member);
    test_scenario::return_shared(group);
    scenario.return_to_sender(member_cap);
    scenario.end();
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun create_with_wrong_cap() {
    let ctx = &mut tx_context::dummy();
    let (mut party, cap, mut group, member, member_cap) = setup(ctx);
    let other = group::new(&mut party, &member_cap);
    destroy(other);
    destroy(group);
    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

#[test, expected_failure(abort_code = group::EUnauthorized)]
fun invite_with_wrong_cap() {
    let ctx = &mut tx_context::dummy();
    let (party, cap, mut group, member, member_cap) = setup(ctx);
    group.invite_party(&member_cap, &member);
    destroy(group);
    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

#[test, expected_failure(abort_code = group::ESelfMembership)]
fun invite_self() {
    let ctx = &mut tx_context::dummy();
    let (party, cap, mut group, member, member_cap) = setup(ctx);
    group.invite_party(&cap, &party);
    destroy(group);
    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

#[test, expected_failure(abort_code = set::EItemNotPresent)]
fun accept_with_another_partys_cap() {
    let ctx = &mut tx_context::dummy();
    let (mut party, cap, mut group, member, member_cap) = setup(ctx);
    group.invite_party(&cap, &member);
    group.accept_invite(&mut party, &cap);
    destroy(group);
    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

#[test, expected_failure(abort_code = set::EItemNotPresent)]
fun decline_with_another_partys_cap() {
    let ctx = &mut tx_context::dummy();
    let (party, cap, mut group, member, member_cap) = setup(ctx);
    group.decline_invite(&cap);
    destroy(group);
    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

#[test, expected_failure(abort_code = group::EUnauthorized)]
fun revoke_with_wrong_cap() {
    let ctx = &mut tx_context::dummy();
    let (party, cap, mut group, member, member_cap) = setup(ctx);
    group.revoke_invite(&member_cap, object::id(&member));
    destroy(group);
    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

#[test, expected_failure(abort_code = set::EItemNotPresent)]
fun leave_with_another_partys_cap() {
    let ctx = &mut tx_context::dummy();
    let (mut party, cap, mut group, member, member_cap) = setup(ctx);
    group.leave(&mut party, &cap);
    destroy(group);
    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

#[test, expected_failure(abort_code = group::EUnauthorized)]
fun remove_with_wrong_cap() {
    let ctx = &mut tx_context::dummy();
    let (party, cap, mut group, member, member_cap) = setup(ctx);
    group.remove_member(&member_cap, object::id(&member));
    destroy(group);
    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

#[test, expected_failure(abort_code = set::EItemNotPresent)]
fun accept_without_invite() {
    let ctx = &mut tx_context::dummy();
    let (party, cap, mut group, mut member, member_cap) = setup(ctx);
    group.accept_invite(&mut member, &member_cap);
    destroy(group);
    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

#[test, expected_failure(abort_code = set::EItemNotPresent)]
fun decline_without_invite() {
    let ctx = &mut tx_context::dummy();
    let (party, cap, mut group, member, member_cap) = setup(ctx);
    group.decline_invite(&member_cap);
    destroy(group);
    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

#[test, expected_failure(abort_code = set::EItemNotPresent)]
fun revoke_without_invite() {
    let ctx = &mut tx_context::dummy();
    let (party, cap, mut group, member, member_cap) = setup(ctx);
    group.revoke_invite(&cap, object::id(&member));
    destroy(group);
    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

#[test, expected_failure(abort_code = set::EItemNotPresent)]
fun leave_without_membership() {
    let ctx = &mut tx_context::dummy();
    let (party, cap, mut group, mut member, member_cap) = setup(ctx);
    group.leave(&mut member, &member_cap);
    destroy(group);
    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

#[test, expected_failure(abort_code = set::EItemNotPresent)]
fun remove_without_membership() {
    let ctx = &mut tx_context::dummy();
    let (party, cap, mut group, member, member_cap) = setup(ctx);
    group.remove_member(&cap, object::id(&member));
    destroy(group);
    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

#[test, expected_failure(abort_code = set::EDuplicateItem)]
fun duplicate_invite() {
    let ctx = &mut tx_context::dummy();
    let (party, cap, mut group, member, member_cap) = setup(ctx);
    group.invite_party(&cap, &member);
    group.invite_party(&cap, &member);
    destroy(group);
    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

#[test, expected_failure(abort_code = group::EAlreadyMember)]
fun invite_existing_member() {
    let ctx = &mut tx_context::dummy();
    let (party, cap, mut group, mut member, member_cap) = setup(ctx);
    group.invite_party(&cap, &member);
    group.accept_invite(&mut member, &member_cap);
    group.invite_party(&cap, &member);
    destroy(group);
    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

#[test, expected_failure(abort_code = group::ETooManyGroupMembers)]
fun invite_at_member_capacity() {
    let ctx = &mut tx_context::dummy();
    let (party, cap, mut group, member, member_cap) = setup(ctx);
    group.fill_for_testing(200, 0, ctx);
    group.invite_party(&cap, &member);
    destroy(group);
    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

#[test, expected_failure(abort_code = set::EMaxItemsExceeded)]
fun pending_invites_are_bounded() {
    let ctx = &mut tx_context::dummy();
    let (party, cap, mut group, member, member_cap) = setup(ctx);
    group.fill_for_testing(0, 200, ctx);
    group.invite_party(&cap, &member);
    destroy(group);
    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

#[test, expected_failure(abort_code = set::EMaxItemsExceeded)]
fun accept_rechecks_capacity() {
    let ctx = &mut tx_context::dummy();
    let (party, cap, mut group, mut member, member_cap) = setup(ctx);
    group.fill_for_testing(199, 0, ctx);
    let (mut last, last_cap) = party::new(ctx);
    group.invite_party(&cap, &last);
    group.invite_party(&cap, &member);
    group.accept_invite(&mut last, &last_cap);
    group.accept_invite(&mut member, &member_cap);
    destroy(last);
    destroy(last_cap);
    destroy(group);
    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

#[test, expected_failure(abort_code = sui::derived_object::EObjectAlreadyExists)]
fun only_one_group_per_party_in_this_package() {
    let ctx = &mut tx_context::dummy();
    let (mut party, cap, group, member, member_cap) = setup(ctx);
    let another = group::new(&mut party, &cap);
    destroy(another);
    destroy(group);
    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

#[test]
fun removed_member_keeps_stale_marker_until_cleared() {
    let ctx = &mut tx_context::dummy();
    let (party, cap, mut group, mut member, member_cap) = setup(ctx);
    let group_id = object::id(&group);
    let member_id = object::id(&member);
    group.invite_party(&cap, &member);
    group.accept_invite(&mut member, &member_cap);
    group.remove_member(&cap, member_id);
    assert!(!group.is_member(member_id));
    assert!(group::has_group_membership(&member, group_id));
    group::clear_membership(&mut member, &member_cap, &group);
    assert_event<GroupMembershipClearedEvent>(group_id, member_id);
    assert!(!group::has_group_membership(&member, group_id));
    group.invite_party(&cap, &member);
    group.accept_invite(&mut member, &member_cap);
    assert!(group.is_member(member_id));
    assert!(group::has_group_membership(&member, group_id));
    destroy(group);
    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

#[test]
fun markers_are_tracked_per_group() {
    let ctx = &mut tx_context::dummy();
    let (party, cap, mut group, mut member, member_cap) = setup(ctx);
    let (mut other_party, other_cap) = party::new(ctx);
    let other_group = group::new(&mut other_party, &other_cap);
    let other_group_id = object::id(&other_group);
    group.invite_party(&cap, &member);
    group.accept_invite(&mut member, &member_cap);
    assert!(group::has_group_membership(&member, object::id(&group)));
    assert!(!group::has_group_membership(&member, other_group_id));
    destroy(other_group);
    destroy(other_party);
    destroy(other_cap);
    destroy(group);
    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun accept_with_wrong_member_cap() {
    let ctx = &mut tx_context::dummy();
    let (mut party, cap, mut group, member, member_cap) = setup(ctx);
    group.invite_party(&cap, &member);
    group.accept_invite(&mut party, &member_cap);
    destroy(group);
    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun leave_with_wrong_member_cap() {
    let ctx = &mut tx_context::dummy();
    let (mut party, cap, mut group, mut member, member_cap) = setup(ctx);
    group.invite_party(&cap, &member);
    group.accept_invite(&mut member, &member_cap);
    group.leave(&mut party, &member_cap);
    destroy(group);
    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

#[test, expected_failure(abort_code = group::EAlreadyMember)]
fun rejoin_after_removal_requires_clearing_the_marker() {
    let ctx = &mut tx_context::dummy();
    let (party, cap, mut group, mut member, member_cap) = setup(ctx);
    let member_id = object::id(&member);
    group.invite_party(&cap, &member);
    group.accept_invite(&mut member, &member_cap);
    group.remove_member(&cap, member_id);
    group.invite_party(&cap, &member);
    group.accept_invite(&mut member, &member_cap);
    destroy(group);
    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

#[test, expected_failure(abort_code = group::EStillMember)]
fun clear_membership_while_member() {
    let ctx = &mut tx_context::dummy();
    let (party, cap, mut group, mut member, member_cap) = setup(ctx);
    group.invite_party(&cap, &member);
    group.accept_invite(&mut member, &member_cap);
    group::clear_membership(&mut member, &member_cap, &group);
    destroy(group);
    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

#[test, expected_failure(abort_code = group::EMembershipNotFound)]
fun clear_membership_without_marker() {
    let ctx = &mut tx_context::dummy();
    let (party, cap, group, mut member, member_cap) = setup(ctx);
    group::clear_membership(&mut member, &member_cap, &group);
    destroy(group);
    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun clear_membership_with_wrong_cap() {
    let ctx = &mut tx_context::dummy();
    let (party, cap, group, mut member, member_cap) = setup(ctx);
    group::clear_membership(&mut member, &cap, &group);
    destroy(group);
    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}
