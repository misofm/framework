// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module record_audience_seal::seal;

use record_access::record_access::RecordAccess;
use record_audience_seal::record_audience::RecordAudience;
use sui::bcs;

// === Errors ===

const EWrongAudience: u64 = 0;
const ENotOwner: u64 = 1;
const ENoMatchingRule: u64 = 2;

// === Private Functions ===

entry fun seal_approve(
    id: vector<u8>,
    audience: &RecordAudience,
    access: &RecordAccess,
    ctx: &TxContext,
) {
    let mut id = bcs::new(id);
    assert!(id.peel_address() == object::id(audience).to_address(), EWrongAudience);
    id.peel_u256();
    assert!(id.into_remainder_bytes().is_empty(), EWrongAudience);
    assert!(access.owner() == ctx.sender(), ENotOwner);
    let admitted = audience.admits(access.release_id(), access.edition(), access.number());
    assert!(admitted, ENoMatchingRule);
}

// === Test Functions ===

#[test_only]
public fun seal_approve_for_testing(
    id: vector<u8>,
    audience: &RecordAudience,
    access: &RecordAccess,
    ctx: &mut TxContext,
) {
    seal_approve(id, audience, access, ctx)
}
