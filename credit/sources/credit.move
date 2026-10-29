// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module credit::credit;

use std::string::String;
use sui::vec_set;

// === Errors ===

const EDisplayNameTooLong: u64 = 0;
const EEmptyDisplayName: u64 = 1;
const EEmptyRoles: u64 = 2;
const ETooManyRoles: u64 = 3;
const ERoleAlreadyAdded: u64 = 4;

// === Constants ===

const MAX_DISPLAY_NAME_LENGTH: u64 = 200;
const MIN_ROLES: u64 = 1;
const MAX_ROLES: u64 = 50;

// === Structs ===

public struct Credit<Role: copy + drop + store> has copy, drop, store {
    display_name: String,
    roles: vector<Role>,
}

// === Public Functions ===

public fun new<Role: copy + drop + store>(display_name: String, roles: vector<Role>): Credit<Role> {
    assert!(!display_name.is_empty(), EEmptyDisplayName);
    assert!(display_name.length() <= MAX_DISPLAY_NAME_LENGTH, EDisplayNameTooLong);
    assert!(roles.length() >= MIN_ROLES, EEmptyRoles);
    assert!(roles.length() <= MAX_ROLES, ETooManyRoles);
    let mut seen = vec_set::empty();
    roles.do_ref!(|role| {
        assert!(!seen.contains(role), ERoleAlreadyAdded);
        seen.insert(*role);
    });
    Credit { display_name, roles }
}

// === View Functions ===

public fun display_name<Role: copy + drop + store>(self: &Credit<Role>): &String {
    &self.display_name
}

public fun roles<Role: copy + drop + store>(self: &Credit<Role>): &vector<Role> {
    &self.roles
}
