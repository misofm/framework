// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module credit::credit;

use std::string::String;

// === Errors ===

const EMaxDisplayNameLengthExceeded: u64 = 0;
const EEmptyString: u64 = 1;
const ENoRoles: u64 = 2;
const EMaxRolesExceeded: u64 = 3;
const EDuplicateRoles: u64 = 4;

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
    assert!(!display_name.is_empty(), EEmptyString);
    assert!(display_name.length() <= MAX_DISPLAY_NAME_LENGTH, EMaxDisplayNameLengthExceeded);
    assert!(roles.length() >= MIN_ROLES, ENoRoles);
    assert!(roles.length() <= MAX_ROLES, EMaxRolesExceeded);
    let len = roles.length();
    let mut i = 0;
    while (i < len) {
        let mut j = i + 1;
        while (j < len) {
            assert!(&roles[i] != &roles[j], EDuplicateRoles);
            j = j + 1;
        };
        i = i + 1;
    };
    Credit { display_name, roles }
}

// === View Functions ===

public fun display_name<Role: copy + drop + store>(self: &Credit<Role>): &String {
    &self.display_name
}

public fun roles<Role: copy + drop + store>(self: &Credit<Role>): &vector<Role> {
    &self.roles
}
