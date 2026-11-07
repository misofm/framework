// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module account::account;

use sui::{address, bcs, event::emit, hash::blake2b256};

// === Errors ===

const EMultisigMismatch: u64 = 0;
const ENoMembers: u64 = 1;
const ETooManyMembers: u64 = 2;
const ELengthMismatch: u64 = 3;
const EZeroThreshold: u64 = 4;
const EZeroWeight: u64 = 5;
const EThresholdUnreachable: u64 = 6;
const EDuplicateMember: u64 = 7;
const EUnsupportedScheme: u64 = 8;
const EInvalidPublicKey: u64 = 9;

// === Constants ===

const MAX_MEMBERS: u64 = 10;
const MULTISIG_FLAG: u8 = 0x03;
const ED25519_FLAG: u8 = 0x00;
const SECP256K1_FLAG: u8 = 0x01;
const SECP256R1_FLAG: u8 = 0x02;
const ZKLOGIN_FLAG: u8 = 0x05;
const PASSKEY_FLAG: u8 = 0x06;
const ED25519_KEY_LENGTH: u64 = 33;
const COMPRESSED_KEY_LENGTH: u64 = 34;
const ZKLOGIN_SEED_MAX_LENGTH: u64 = 32;

// === Structs ===

public struct AccountCard has key {
    id: UID,
    account: address,
    threshold: u16,
    public_keys: vector<vector<u8>>,
    weights: vector<u8>,
}

// === Events ===

public struct AccountCardsIssuedEvent has copy, drop {
    account: address,
    multisig: address,
    threshold: u16,
    public_keys: vector<vector<u8>>,
    weights: vector<u8>,
    card_ids: vector<ID>,
}

public struct AccountCardDestroyedEvent has copy, drop {
    card_id: ID,
}

// === Public Functions ===

public fun issue(
    multisig: address,
    public_keys: vector<vector<u8>>,
    weights: vector<u8>,
    threshold: u16,
    ctx: &mut TxContext,
) {
    let count = public_keys.length();
    assert!(count > 0, ENoMembers);
    assert!(count <= MAX_MEMBERS, ETooManyMembers);
    assert!(weights.length() == count, ELengthMismatch);
    assert!(threshold > 0, EZeroThreshold);

    let mut preimage = vector[MULTISIG_FLAG];
    preimage.append(bcs::to_bytes(&threshold));
    let mut total: u16 = 0;
    count.do!(|i| {
        let public_key = &public_keys[i];
        let weight = weights[i];
        assert!(weight > 0, EZeroWeight);
        i.do!(|j| assert!(&public_keys[j] != public_key, EDuplicateMember));
        validate_public_key(public_key);
        preimage.append(*public_key);
        preimage.push_back(weight);
        total = total + (weight as u16);
    });
    assert!(total >= threshold, EThresholdUnreachable);
    assert!(address::from_bytes(blake2b256(&preimage)) == multisig, EMultisigMismatch);

    let account = ctx.sender();
    let card_ids = public_keys.map_ref!(|public_key| {
        let card = AccountCard {
            id: object::new(ctx),
            account,
            threshold,
            public_keys: copy public_keys,
            weights: copy weights,
        };
        let card_id = object::id(&card);
        transfer::transfer(card, address::from_bytes(blake2b256(public_key)));
        card_id
    });
    emit(AccountCardsIssuedEvent { account, multisig, threshold, public_keys, weights, card_ids });
}

public fun destroy(card: AccountCard) {
    let AccountCard { id, .. } = card;
    emit(AccountCardDestroyedEvent { card_id: id.to_inner() });
    id.delete();
}

// === View Functions ===

public fun account(card: &AccountCard): address {
    card.account
}

public fun threshold(card: &AccountCard): u16 {
    card.threshold
}

public fun public_keys(card: &AccountCard): &vector<vector<u8>> {
    &card.public_keys
}

public fun weights(card: &AccountCard): &vector<u8> {
    &card.weights
}

// === Private Functions ===

fun validate_public_key(public_key: &vector<u8>) {
    let length = public_key.length();
    assert!(length > 0, EInvalidPublicKey);
    let flag = public_key[0];
    if (flag == ED25519_FLAG) {
        assert!(length == ED25519_KEY_LENGTH, EInvalidPublicKey);
    } else if (flag == SECP256K1_FLAG || flag == SECP256R1_FLAG || flag == PASSKEY_FLAG) {
        assert!(length == COMPRESSED_KEY_LENGTH, EInvalidPublicKey);
    } else if (flag == ZKLOGIN_FLAG) {
        assert!(length > 2, EInvalidPublicKey);
        let iss_length = public_key[1] as u64;
        assert!(iss_length > 0, EInvalidPublicKey);
        assert!(length > 2 + iss_length, EInvalidPublicKey);
        assert!(length <= 2 + iss_length + ZKLOGIN_SEED_MAX_LENGTH, EInvalidPublicKey);
    } else {
        abort EUnsupportedScheme
    }
}
