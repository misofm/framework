// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module party_roles::party_roles_tests;

use miso_party::party;
use party_roles::party_roles as roles;
use std::unit_test::{assert_eq, destroy};
use sui::{bcs, event, test_scenario as ts};

const OWNER: address = @0xA;

fun bytes_of_len(len: u64, seed: u8): vector<u8> {
    let mut bytes = vector[];
    if (len > 0) {
        bytes.push_back(seed);
        (len - 1).do!(|_| bytes.push_back(65));
    };
    bytes
}

fun custom_letter(i: u64): roles::ArtistRole {
    roles::custom(vector[(65 + i) as u8].to_string())
}

fun multibyte_bytes(): vector<u8> {
    let mut bytes = vector[];
    30u64.do!(|_| {
        bytes.push_back(0xc3);
        bytes.push_back(0xa9);
    });
    bytes
}

fun new_party(ctx: &mut TxContext): (party::Party, party::PartyAdminCap) {
    party::new(ctx)
}

#[test]
fun add_remove_and_query() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    assert!(!roles::has_roles(&p));
    roles::add_role(&mut p, &cap, roles::artist());
    roles::add_role(&mut p, &cap, roles::producer());
    roles::add_role(&mut p, &cap, roles::custom(b"Visual Artist".to_string()));
    assert!(roles::has_roles(&p));
    assert!(roles::has_role(&p, roles::artist()));
    assert!(roles::has_role(&p, roles::producer()));
    assert!(!roles::has_role(&p, roles::dj()));
    assert_eq!(roles::roles(&p).length(), 3);
    assert_eq!(roles::dj().name(), b"DJ".to_string());
    assert_eq!(roles::custom(b"Visual Artist".to_string()).name(), b"Visual Artist".to_string());
    roles::remove_role(&mut p, &cap, roles::producer());
    assert!(!roles::has_role(&p, roles::producer()));
    assert_eq!(roles::roles(&p).length(), 2);
    roles::remove_role(&mut p, &cap, roles::artist());
    roles::remove_role(&mut p, &cap, roles::custom(b"Visual Artist".to_string()));
    assert!(!roles::has_roles(&p));
    roles::add_role(&mut p, &cap, roles::band());
    roles::clear_roles(&mut p, &cap);
    assert!(!roles::has_roles(&p));
    roles::clear_roles(&mut p, &cap);
    destroy(p);
    destroy(cap);
}

#[test]
fun shared_party_roles_workflow() {
    let mut scenario = ts::begin(OWNER);
    let (p, cap) = new_party(scenario.ctx());
    party::share(p, &cap);
    transfer::public_transfer(cap, OWNER);
    scenario.next_tx(OWNER);
    let mut p = scenario.take_shared<party::Party>();
    let cap = scenario.take_from_sender<party::PartyAdminCap>();
    roles::add_role(&mut p, &cap, roles::composer());
    ts::return_shared(p);
    scenario.return_to_sender(cap);
    scenario.next_tx(@0xB);
    let p = scenario.take_shared<party::Party>();
    assert!(roles::has_role(&p, roles::composer()));
    ts::return_shared(p);
    scenario.end();
}

#[test, expected_failure(abort_code = roles::EEmptyCustomName)]
fun rejects_empty_custom() {
    let _ = roles::custom(b"".to_string());
    abort
}

#[test, expected_failure(abort_code = roles::ECustomNameTooLong)]
fun rejects_overlong_custom() {
    let name = vector::tabulate!(61, |_| 97u8).to_string();
    let _ = roles::custom(name);
    abort
}

#[test, expected_failure(abort_code = typed_set::typed_set::EDuplicateItem)]
fun rejects_duplicate() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    roles::add_role(&mut p, &cap, roles::artist());
    roles::add_role(&mut p, &cap, roles::artist());
    abort
}

#[test, expected_failure(abort_code = typed_set::typed_set::EItemNotPresent)]
fun remove_absent_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    roles::add_role(&mut p, &cap, roles::artist());
    roles::remove_role(&mut p, &cap, roles::dj());
    abort
}

#[test, expected_failure(abort_code = typed_set::typed_set::EMaxItemsExceeded)]
fun rejects_over_max() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    roles::add_role(&mut p, &cap, roles::artist());
    roles::add_role(&mut p, &cap, roles::producer());
    roles::add_role(&mut p, &cap, roles::dj());
    roles::add_role(&mut p, &cap, roles::composer());
    roles::add_role(&mut p, &cap, roles::songwriter());
    roles::add_role(&mut p, &cap, roles::band());
    roles::add_role(&mut p, &cap, roles::label());
    roles::add_role(&mut p, &cap, roles::collective());
    5u64.do!(|i| roles::add_role(&mut p, &cap, custom_letter(i)));
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun add_role_with_wrong_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, _cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    roles::add_role(&mut p, &other_cap, roles::artist());
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun add_role_with_wrong_cap_on_full_set_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    roles::add_role(&mut p, &cap, roles::artist());
    roles::add_role(&mut p, &cap, roles::producer());
    roles::add_role(&mut p, &cap, roles::dj());
    roles::add_role(&mut p, &cap, roles::composer());
    roles::add_role(&mut p, &cap, roles::songwriter());
    roles::add_role(&mut p, &cap, roles::band());
    roles::add_role(&mut p, &cap, roles::label());
    roles::add_role(&mut p, &cap, roles::collective());
    4u64.do!(|i| roles::add_role(&mut p, &cap, custom_letter(i)));
    roles::add_role(&mut p, &other_cap, custom_letter(4));
    abort
}

#[test]
fun events_carry_role_values_and_custom_identity() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let party_id = object::id(&p);
    let role_values = vector[
        roles::artist(),
        roles::producer(),
        roles::dj(),
        roles::composer(),
        roles::songwriter(),
        roles::band(),
        roles::label(),
        roles::collective(),
        roles::custom(b"Artist".to_string()),
    ];
    9u64.do!(|i| roles::add_role(&mut p, &cap, *role_values.borrow(i)));
    assert_eq!(roles::roles(&p).length(), 9);
    assert!(roles::has_role(&p, roles::artist()));
    assert!(roles::has_role(&p, roles::custom(b"Artist".to_string())));
    let added = event::events_by_type<roles::PartyRoleAddedEvent>();
    assert_eq!(added.length(), 9);
    9u64.do!(|i| {
        let (event_party_id, role) = roles::party_role_added_fields_for_testing(&added[i]);
        assert_eq!(event_party_id, party_id);
        assert_eq!(role, role_values[i]);
    });
    destroy(p);
    destroy(cap);
}

#[test]
fun middle_and_final_remove_events_carry_roles() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let party_id = object::id(&p);
    roles::add_role(&mut p, &cap, roles::artist());
    roles::add_role(&mut p, &cap, roles::producer());
    roles::add_role(&mut p, &cap, roles::dj());
    roles::remove_role(&mut p, &cap, roles::producer());
    let removed = event::events_by_type<roles::PartyRoleRemovedEvent>();
    assert_eq!(removed.length(), 1);
    let (event_party_id, role) = roles::party_role_removed_fields_for_testing(&removed[0]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(role, roles::producer());
    roles::remove_role(&mut p, &cap, roles::artist());
    roles::remove_role(&mut p, &cap, roles::dj());
    assert!(!roles::has_roles(&p));
    let removed = event::events_by_type<roles::PartyRoleRemovedEvent>();
    let (event_party_id, role) = roles::party_role_removed_fields_for_testing(&removed[2]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(role, roles::dj());
    destroy(p);
    destroy(cap);
}

#[test]
fun clear_twelve_max_custom_names_emits_party_id() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let party_id = object::id(&p);
    12u64.do!(|i| {
        let name = bytes_of_len(60, (65 + i) as u8);
        roles::add_role(&mut p, &cap, roles::custom(name.to_string()));
    });
    roles::clear_roles(&mut p, &cap);
    let cleared = event::events_by_type<roles::PartyRolesClearedEvent>();
    assert_eq!(cleared.length(), 1);
    assert_eq!(bcs::to_bytes(&cleared[0]).length(), 32);
    assert_eq!(roles::party_roles_cleared_fields_for_testing(&cleared[0]), party_id);
    assert!(!roles::has_roles(&p));
    destroy(p);
    destroy(cap);
}

#[test]
fun multibyte_sixty_byte_name_is_bounded_and_event_is_94_bytes() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let name = multibyte_bytes();
    roles::add_role(&mut p, &cap, roles::custom(name.to_string()));
    let added = event::events_by_type<roles::PartyRoleAddedEvent>();
    assert_eq!(added.length(), 1);
    assert_eq!(bcs::to_bytes(&added[0]).length(), 94);
    let (_, role) = roles::party_role_added_fields_for_testing(&added[0]);
    assert_eq!(role, roles::custom(name.to_string()));
    assert_eq!(role.name(), name.to_string());
    roles::remove_role(&mut p, &cap, roles::custom(name.to_string()));
    let removed = event::events_by_type<roles::PartyRoleRemovedEvent>();
    assert_eq!(bcs::to_bytes(&removed[0]).length(), 94);
    let (_, role) = roles::party_role_removed_fields_for_testing(&removed[0]);
    assert_eq!(role, roles::custom(name.to_string()));
    assert!(!roles::has_roles(&p));
    destroy(p);
    destroy(cap);
}

#[test]
fun constructors_and_views_are_silent() {
    let ctx = &mut tx_context::dummy();
    let (p, cap) = new_party(ctx);
    let before = event::num_events();
    let artist = roles::artist();
    let producer = roles::producer();
    let dj = roles::dj();
    let composer = roles::composer();
    let songwriter = roles::songwriter();
    let band = roles::band();
    let label = roles::label();
    let collective = roles::collective();
    let custom = roles::custom(b"Custom".to_string());
    assert_eq!(artist.name(), b"Artist".to_string());
    assert_eq!(producer.name(), b"Producer".to_string());
    assert_eq!(dj.name(), b"DJ".to_string());
    assert_eq!(composer.name(), b"Composer".to_string());
    assert_eq!(songwriter.name(), b"Songwriter".to_string());
    assert_eq!(band.name(), b"Band".to_string());
    assert_eq!(label.name(), b"Label".to_string());
    assert_eq!(collective.name(), b"Collective".to_string());
    assert_eq!(custom.name(), b"Custom".to_string());
    assert_eq!(event::num_events(), before);
    assert!(!roles::has_roles(&p));
    assert!(!roles::has_role(&p, artist));
    assert_eq!(event::num_events(), before);
    destroy(p);
    destroy(cap);
}

#[test]
fun clear_repeated_is_silent_and_readd_emits() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let party_id = object::id(&p);
    roles::add_role(&mut p, &cap, roles::artist());
    roles::clear_roles(&mut p, &cap);
    roles::clear_roles(&mut p, &cap);
    roles::add_role(&mut p, &cap, roles::custom(b"Readded".to_string()));
    let added = event::events_by_type<roles::PartyRoleAddedEvent>();
    assert_eq!(added.length(), 2);
    let (event_party_id, role) = roles::party_role_added_fields_for_testing(&added[1]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(role, roles::custom(b"Readded".to_string()));
    let cleared = event::events_by_type<roles::PartyRolesClearedEvent>();
    assert_eq!(cleared.length(), 1);
    assert_eq!(roles::party_roles_cleared_fields_for_testing(&cleared[0]), party_id);
    destroy(p);
    destroy(cap);
}

#[test, expected_failure(abort_code = typed_set::typed_set::EDuplicateItem)]
fun authorized_duplicate_on_full_set_aborts_as_duplicate() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    12u64.do!(|i| roles::add_role(&mut p, &cap, custom_letter(i)));
    roles::add_role(&mut p, &cap, roles::custom(b"A".to_string()));
    abort
}

#[test, expected_failure(abort_code = typed_set::typed_set::EItemNotPresent)]
fun remove_from_missing_field_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    roles::remove_role(&mut p, &cap, roles::artist());
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun remove_with_wrong_cap_and_present_role_aborts_as_unauthorized() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    roles::add_role(&mut p, &cap, roles::artist());
    roles::remove_role(&mut p, &other_cap, roles::artist());
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun remove_with_wrong_cap_and_missing_role_aborts_as_unauthorized() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    roles::add_role(&mut p, &cap, roles::artist());
    roles::remove_role(&mut p, &other_cap, roles::dj());
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun remove_with_wrong_cap_and_missing_field_aborts_as_unauthorized() {
    let ctx = &mut tx_context::dummy();
    let (mut p, _cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    roles::remove_role(&mut p, &other_cap, roles::artist());
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun clear_with_wrong_cap_and_populated_set_aborts_as_unauthorized() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    roles::add_role(&mut p, &cap, roles::artist());
    roles::clear_roles(&mut p, &other_cap);
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun clear_with_wrong_cap_and_absent_set_aborts_as_unauthorized() {
    let ctx = &mut tx_context::dummy();
    let (mut p, _cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    roles::clear_roles(&mut p, &other_cap);
    abort
}

#[test, expected_failure(abort_code = roles::ENoRoles)]
fun reading_roles_without_roles_aborts() {
    let ctx = &mut tx_context::dummy();
    let (p, cap) = new_party(ctx);
    roles::roles(&p);
    destroy(p);
    destroy(cap);
}
