// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module account::account_tests;

use account::account::{Self, AccountCard, AccountCardsIssuedEvent, AccountCardDestroyedEvent};
use std::unit_test::assert_eq;
use sui::{event, test_scenario as ts};

const ACCOUNT: address = @0xA;

const PHRASE: vector<u8> = x"008a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c";
const PASSKEY: vector<u8> = x"060307810ea974cea5773e63b897f37e3be9a09e7a5fe9b971a44d1065ac2a3a9311";
const WATCHDOG: vector<u8> = x"008139770ea87d175f56a35466c34c7ecccb8d8a91b4ee37a25df60f5b8fc9b394";
const SECP256K1: vector<u8> =
    x"0102531fe6068134503d2723133227c867ac8fa6c83c537e9a44c3c5bdbdcb1fe337";
const SECP256R1: vector<u8> =
    x"020273103ec30b3ccf57daae08e93534aef144a35940cf6bbba12a0cf7cbd5d65a64";

const PHRASE_ADDRESS: address = @0x29dfbf688abce7ab43bb8e70cae158ae961196e721440f515482f8ba1684390f;
const PASSKEY_ADDRESS: address =
    @0x787045b0242b76e90af3b6cf42b6526d64847449a601ce8d320ff4214d17fe8b;
const ZKLOGIN_ADDRESS: address =
    @0x0391997d6ab0a5e66769c772640ccac90212f418d24894e1e9d00532a9afa42c;
const WATCHDOG_ADDRESS: address =
    @0x7799ea80594c35644321148485238c7a7a1c6549809e1795e6747c6d4da2504c;
const SECP256K1_ADDRESS: address =
    @0x0935e59b381ab286401391a46cb1896946933b2e56edfc863cc55eee9710b4e6;
const SECP256R1_ADDRESS: address =
    @0x7dc2a36020c27a475b09b17307eed36514058b7e75ad20f6a52ea5b767bafb84;

const DESIGN_MULTISIG: address =
    @0x2a27bd03d9a1db513f7d108a2fc3430b657329322cd3f5b545fdcd104d7a2272;
const ALL_SCHEMES_MULTISIG: address =
    @0xd0c7015f2cfc2ed5917652c90690844fe84c2f0b3ceb3041ea81cc4c05014bbd;

// === Helpers ===

fun zklogin(): vector<u8> {
    let mut key = x"051b68747470733a2f2f6163636f756e74732e676f6f676c652e636f6d25";
    key.append(x"0438b38dcafbd1fc2bc06d7d602c556efa12fab8518bac424570019d2c045d");
    key
}

fun design_keys(): vector<vector<u8>> {
    vector[PHRASE, PASSKEY, zklogin(), WATCHDOG]
}

fun issue_keys(keys: vector<vector<u8>>, weights: vector<u8>, threshold: u16) {
    let mut scenario = ts::begin(ACCOUNT);
    account::issue(DESIGN_MULTISIG, keys, weights, threshold, scenario.ctx());
    scenario.end();
}

fun distinct_ed25519_keys(count: u8): vector<vector<u8>> {
    vector::tabulate!(count as u64, |i| {
        let mut key = vector[0];
        32u64.do!(|_| key.push_back(i as u8));
        key
    })
}

// === Issue ===

#[test]
fun issue_mints_a_card_to_every_member() {
    let mut scenario = ts::begin(ACCOUNT);
    account::issue(DESIGN_MULTISIG, design_keys(), vector[1, 1, 1, 1], 2, scenario.ctx());
    let events = event::events_by_type<AccountCardsIssuedEvent>();
    assert_eq!(events.length(), 1);
    scenario.next_tx(ACCOUNT);

    vector[PHRASE_ADDRESS, PASSKEY_ADDRESS, ZKLOGIN_ADDRESS, WATCHDOG_ADDRESS].do!(|holder| {
        let card = scenario.take_from_address<AccountCard>(holder);
        assert_eq!(card.account(), ACCOUNT);
        assert_eq!(card.threshold(), 2);
        assert_eq!(*card.public_keys(), design_keys());
        assert_eq!(*card.weights(), vector[1, 1, 1, 1]);
        ts::return_to_address(holder, card);
    });
    scenario.end();
}

#[test]
fun issue_accepts_every_supported_scheme_and_weights() {
    let mut scenario = ts::begin(ACCOUNT);
    account::issue(
        ALL_SCHEMES_MULTISIG,
        vector[PHRASE, SECP256K1, SECP256R1, zklogin(), PASSKEY],
        vector[1, 2, 3, 1, 1],
        3,
        scenario.ctx(),
    );
    scenario.next_tx(ACCOUNT);
    let card = scenario.take_from_address<AccountCard>(SECP256K1_ADDRESS);
    assert_eq!(*card.weights(), vector[1, 2, 3, 1, 1]);
    assert_eq!(card.threshold(), 3);
    ts::return_to_address(SECP256K1_ADDRESS, card);
    assert!(ts::has_most_recent_for_address<AccountCard>(SECP256R1_ADDRESS));
    assert!(ts::has_most_recent_for_address<AccountCard>(ZKLOGIN_ADDRESS));
    scenario.end();
}

#[test]
fun destroy_deletes_the_card() {
    let mut scenario = ts::begin(ACCOUNT);
    account::issue(DESIGN_MULTISIG, design_keys(), vector[1, 1, 1, 1], 2, scenario.ctx());
    scenario.next_tx(PHRASE_ADDRESS);
    let card = scenario.take_from_sender<AccountCard>();
    account::destroy(card);
    assert_eq!(event::events_by_type<AccountCardDestroyedEvent>().length(), 1);
    scenario.next_tx(PHRASE_ADDRESS);
    assert!(!ts::has_most_recent_for_sender<AccountCard>(&scenario));
    assert!(ts::has_most_recent_for_address<AccountCard>(PASSKEY_ADDRESS));
    scenario.end();
}

// === Validation ===

#[test, expected_failure(abort_code = account::EMultisigMismatch)]
fun issue_rejects_a_multisig_that_does_not_match_the_members() {
    issue_keys(design_keys(), vector[1, 1, 1, 2], 2);
}

#[test, expected_failure(abort_code = account::EMultisigMismatch)]
fun issue_rejects_reordered_members() {
    issue_keys(vector[PASSKEY, PHRASE, zklogin(), WATCHDOG], vector[1, 1, 1, 1], 2);
}

#[test, expected_failure(abort_code = account::ENoMembers)]
fun issue_rejects_no_members() {
    issue_keys(vector[], vector[], 1);
}

#[test, expected_failure(abort_code = account::ETooManyMembers)]
fun issue_rejects_more_than_ten_members() {
    issue_keys(distinct_ed25519_keys(11), vector::tabulate!(11, |_| 1), 1);
}

#[test, expected_failure(abort_code = account::ELengthMismatch)]
fun issue_rejects_weight_count_mismatch() {
    issue_keys(design_keys(), vector[1, 1, 1], 2);
}

#[test, expected_failure(abort_code = account::EZeroThreshold)]
fun issue_rejects_zero_threshold() {
    issue_keys(design_keys(), vector[1, 1, 1, 1], 0);
}

#[test, expected_failure(abort_code = account::EZeroWeight)]
fun issue_rejects_zero_weight() {
    issue_keys(design_keys(), vector[1, 0, 1, 1], 2);
}

#[test, expected_failure(abort_code = account::EThresholdUnreachable)]
fun issue_rejects_unreachable_threshold() {
    issue_keys(design_keys(), vector[1, 1, 1, 1], 5);
}

#[test, expected_failure(abort_code = account::EDuplicateMember)]
fun issue_rejects_duplicate_members() {
    issue_keys(vector[PHRASE, PASSKEY, PHRASE], vector[1, 1, 1], 2);
}

#[test, expected_failure(abort_code = account::EUnsupportedScheme)]
fun issue_rejects_nested_multisig_keys() {
    issue_keys(vector[x"030102"], vector[1], 1);
}

#[test, expected_failure(abort_code = account::EInvalidPublicKey)]
fun issue_rejects_empty_keys() {
    issue_keys(vector[vector[]], vector[1], 1);
}

#[test, expected_failure(abort_code = account::EInvalidPublicKey)]
fun issue_rejects_short_ed25519_keys() {
    let mut key = PHRASE;
    key.pop_back();
    issue_keys(vector[key], vector[1], 1);
}

#[test, expected_failure(abort_code = account::EInvalidPublicKey)]
fun issue_rejects_short_secp256k1_keys() {
    let mut key = SECP256K1;
    key.pop_back();
    issue_keys(vector[key], vector[1], 1);
}

#[test, expected_failure(abort_code = account::EInvalidPublicKey)]
fun issue_rejects_short_secp256r1_keys() {
    let mut key = SECP256R1;
    key.pop_back();
    issue_keys(vector[key], vector[1], 1);
}

#[test, expected_failure(abort_code = account::EInvalidPublicKey)]
fun issue_rejects_short_passkey_keys() {
    let mut key = PASSKEY;
    key.pop_back();
    issue_keys(vector[key], vector[1], 1);
}

#[test, expected_failure(abort_code = account::EInvalidPublicKey)]
fun issue_rejects_zklogin_without_identifier() {
    issue_keys(vector[x"0501"], vector[1], 1);
}

#[test, expected_failure(abort_code = account::EInvalidPublicKey)]
fun issue_rejects_zklogin_with_empty_issuer() {
    issue_keys(vector[x"050001"], vector[1], 1);
}

#[test, expected_failure(abort_code = account::EInvalidPublicKey)]
fun issue_rejects_zklogin_without_address_seed() {
    issue_keys(vector[x"05026869"], vector[1], 1);
}

#[test, expected_failure(abort_code = account::EInvalidPublicKey)]
fun issue_rejects_zklogin_with_oversized_address_seed() {
    let mut key = zklogin();
    key.push_back(0);
    issue_keys(vector[key], vector[1], 1);
}
