// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module record_audience_seal::record_audience;

use sui::{event::emit, table::{Self, Table}};

// === Errors ===

const EUnauthorized: u64 = 0;
const ETooManyRules: u64 = 1;
const EInvalidRange: u64 = 2;
const ERuleNotFound: u64 = 3;

// === Constants ===

const MAX_RULES: u64 = 1000;

// === Structs ===

public struct RecordAudience has key {
    id: UID,
    rules: Table<ID, RecordAudienceRule>,
}

public struct RecordAudienceAdminCap has key, store {
    id: UID,
    audience_id: ID,
}

public struct RecordAudienceRule has copy, drop, store {
    edition_min: Option<u16>,
    edition_max: Option<u16>,
    number_min: Option<u32>,
    number_max: Option<u32>,
}

// === Events ===

public struct RecordAudienceCreatedEvent has copy, drop {
    audience_id: ID,
    admin_cap_id: ID,
}

public struct RecordAudienceRuleSetEvent has copy, drop {
    audience_id: ID,
    release_id: ID,
    rule: RecordAudienceRule,
}

public struct RecordAudienceRuleRemovedEvent has copy, drop {
    audience_id: ID,
    release_id: ID,
}

// === Method Aliases ===

public use fun record_audience_admin_cap_audience_id as RecordAudienceAdminCap.audience_id;
public use fun record_audience_rule_edition_min as RecordAudienceRule.edition_min;
public use fun record_audience_rule_edition_max as RecordAudienceRule.edition_max;
public use fun record_audience_rule_number_min as RecordAudienceRule.number_min;
public use fun record_audience_rule_number_max as RecordAudienceRule.number_max;

// === Public Functions ===

public fun new(ctx: &mut TxContext): (RecordAudience, RecordAudienceAdminCap) {
    let audience = RecordAudience { id: object::new(ctx), rules: table::new(ctx) };
    let audience_id = object::id(&audience);
    let cap = RecordAudienceAdminCap { id: object::new(ctx), audience_id };
    emit(RecordAudienceCreatedEvent { audience_id, admin_cap_id: object::id(&cap) });
    (audience, cap)
}

public fun share(self: RecordAudience) {
    transfer::share_object(self);
}

public fun new_rule(
    edition_min: Option<u16>,
    edition_max: Option<u16>,
    number_min: Option<u32>,
    number_max: Option<u32>,
): RecordAudienceRule {
    assert!(ordered!(edition_min, edition_max), EInvalidRange);
    assert!(ordered!(number_min, number_max), EInvalidRange);
    RecordAudienceRule { edition_min, edition_max, number_min, number_max }
}

// === View Functions ===

public fun rule_count(self: &RecordAudience): u64 {
    self.rules.length()
}

public fun has_rule(self: &RecordAudience, release_id: ID): bool {
    self.rules.contains(release_id)
}

public fun rule(self: &RecordAudience, release_id: ID): RecordAudienceRule {
    assert!(self.rules.contains(release_id), ERuleNotFound);
    self.rules[release_id]
}

public fun admits(self: &RecordAudience, release_id: ID, edition: u16, number: u32): bool {
    if (!self.rules.contains(release_id)) return false;
    let rule = &self.rules[release_id];
    within!(rule.edition_min, rule.edition_max, edition) &&
        within!(rule.number_min, rule.number_max, number)
}

public fun max_rules(): u64 {
    MAX_RULES
}

public fun record_audience_admin_cap_audience_id(cap: &RecordAudienceAdminCap): ID {
    cap.audience_id
}

public fun record_audience_rule_edition_min(rule: &RecordAudienceRule): Option<u16> {
    rule.edition_min
}

public fun record_audience_rule_edition_max(rule: &RecordAudienceRule): Option<u16> {
    rule.edition_max
}

public fun record_audience_rule_number_min(rule: &RecordAudienceRule): Option<u32> {
    rule.number_min
}

public fun record_audience_rule_number_max(rule: &RecordAudienceRule): Option<u32> {
    rule.number_max
}

// === Admin Functions ===

public fun set_rule(
    self: &mut RecordAudience,
    cap: &RecordAudienceAdminCap,
    release_id: ID,
    rule: RecordAudienceRule,
) {
    assert!(cap.audience_id == object::id(self), EUnauthorized);
    if (self.rules.contains(release_id)) {
        let previous = &mut self.rules[release_id];
        if (*previous == rule) return;
        *previous = rule;
    } else {
        assert!(self.rules.length() < MAX_RULES, ETooManyRules);
        self.rules.add(release_id, rule);
    };
    emit(RecordAudienceRuleSetEvent {
        audience_id: object::id(self),
        release_id,
        rule,
    });
}

public fun remove_rule(self: &mut RecordAudience, cap: &RecordAudienceAdminCap, release_id: ID) {
    assert!(cap.audience_id == object::id(self), EUnauthorized);
    if (!self.rules.contains(release_id)) return;
    self.rules.remove(release_id);
    emit(RecordAudienceRuleRemovedEvent {
        audience_id: object::id(self),
        release_id,
    });
}

// === Private Functions ===

macro fun within<$T>($min: Option<$T>, $max: Option<$T>, $value: $T): bool {
    let (min, max, value) = ($min, $max, $value);
    min.is_none_or!(|min| value >= *min) && max.is_none_or!(|max| value <= *max)
}

macro fun ordered<$T>($min: Option<$T>, $max: Option<$T>): bool {
    let (min, max) = ($min, $max);
    min.is_none_or!(|min| max.is_none_or!(|max| *min <= *max))
}

// === Test Functions ===

#[test_only]
public fun record_audience_created_fields_for_testing(
    event: &RecordAudienceCreatedEvent,
): (ID, ID) {
    (event.audience_id, event.admin_cap_id)
}

#[test_only]
public fun record_audience_rule_set_fields_for_testing(
    event: &RecordAudienceRuleSetEvent,
): (ID, ID, RecordAudienceRule) {
    (event.audience_id, event.release_id, event.rule)
}

#[test_only]
public fun record_audience_rule_removed_fields_for_testing(
    event: &RecordAudienceRuleRemovedEvent,
): (ID, ID) {
    (event.audience_id, event.release_id)
}
