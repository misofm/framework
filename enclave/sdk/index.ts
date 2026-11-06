// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

import { bcs } from "@mysten/sui/bcs";
import type { CoreClient } from "@mysten/sui/client";
import { deriveDynamicFieldID, deriveObjectID } from "@mysten/sui/utils";

const EnclavePolicyAdminCapKeyBcs = bcs.struct("EnclavePolicyAdminCapKey", {
  dummy_field: bcs.bool(),
});

const EnclaveKeyBcs = bcs.struct("EnclaveKey", {
  pos0: bcs.vector(bcs.u8()),
});

const EnclaveKeyFieldBcs = bcs.struct("Field", {
  id: bcs.Address,
  name: EnclaveKeyBcs,
  value: bcs.u64(),
});

/** Any Sui client exposing the core `getObjects` API (gRPC, GraphQL or JSON-RPC). */
export type EnclaveClient = { core: Pick<CoreClient, "getObjects"> };

/** Arguments identifying one enclave key registration on a policy. */
export type EnclaveKeyRef = {
  policyId: string;
  publicKey: Uint8Array;
  packageId: string;
};

function enclaveKeyBytes(publicKey: Uint8Array): Uint8Array {
  return EnclaveKeyBcs.serialize({ pos0: Array.from(publicKey) }).toBytes();
}

/**
 * Derive the `EnclavePolicyAdminCap<App>` object ID from its policy ID.
 *
 * Mirrors `derived_object::claim(&mut policy.id, EnclavePolicyAdminCapKey())`.
 */
export function derivePolicyAdminCapId(
  policyId: string,
  packageId: string,
): string {
  const keyBytes = EnclavePolicyAdminCapKeyBcs.serialize({
    dummy_field: false,
  }).toBytes();
  return deriveObjectID(
    policyId,
    `${packageId}::enclave::EnclavePolicyAdminCapKey`,
    keyBytes,
  );
}

/**
 * Derive the object ID of the `EnclaveKey(publicKey) -> u64` dynamic field on
 * a policy, as created by `dynamic_field::add`.
 */
export function enclaveKeyFieldId(
  policyId: string,
  publicKey: Uint8Array,
  packageId: string,
): string {
  return deriveDynamicFieldID(
    policyId,
    `${packageId}::enclave::EnclaveKey`,
    enclaveKeyBytes(publicKey),
  );
}

/**
 * Read the policy version a key was registered under, over plain RPC.
 *
 * Returns `null` when the key has no registration. Transport failures reject.
 */
export async function getRegisteredVersion(
  client: EnclaveClient,
  { policyId, publicKey, packageId }: EnclaveKeyRef,
): Promise<bigint | null> {
  const fieldId = enclaveKeyFieldId(policyId, publicKey, packageId);
  const {
    objects: [field],
  } = await client.core.getObjects({
    objectIds: [fieldId],
    include: { content: true },
  });
  if (field === undefined || field instanceof Error) return null;
  return BigInt(EnclaveKeyFieldBcs.parse(field.content).value);
}

/**
 * Whether a key is registered under the given current policy version.
 */
export async function isKeyUsable(
  client: EnclaveClient,
  ref: EnclaveKeyRef & { policyVersion: bigint },
): Promise<boolean> {
  return (await getRegisteredVersion(client, ref)) === ref.policyVersion;
}
