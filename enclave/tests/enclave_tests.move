// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module enclave::enclave_tests;

use enclave::enclave::{
    Self,
    EnclavePolicy,
    EnclavePolicyAdminCap,
    EnclavePolicyCreatedEvent,
    EnclavePolicyPcrsSetEvent,
    EnclaveRegisteredEvent,
    EnclaveRevokedEvent,
    StaleEnclaveRemovedEvent,
};
use std::{bcs, string::String, unit_test::{assert_eq, destroy}};
use sui::{
    clock,
    event,
    nitro_attestation::{Self, NitroAttestationDocument, PCREntry},
    test_scenario::{Self, Scenario}
};

// === Test Types ===

public struct ENCLAVE_TESTS() has drop;

public struct NotOneTimeWitness() has drop;

public struct WeatherResponse has copy, drop {
    location: String,
    temperature: u64,
}

// === Constants ===

const ADMIN: address = @0xA;
const RELAYER: address = @0xB;

const PCR0: vector<u8> =
    x"cbe1afb6ed0ff89f10295af0b802247ec5670da8f886e71a4226373b032c322f4e42c9c98288e7211682b258684505a2";
const PCR1: vector<u8> =
    x"cbe1afb6ed0ff89f10295af0b802247ec5670da8f886e71a4226373b032c322f4e42c9c98288e7211682b258684505a2";
const PCR2: vector<u8> =
    x"21b9efbc184807662e966d34f390821309eeac6802309798826296bf3e8bec7c10edb30948c90ba67310f7b964fc500a";
const OTHER_PCR: vector<u8> =
    x"111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111";
const ZERO_PCR: vector<u8> =
    x"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
const SHORT_PCR: vector<u8> = x"cbe1afb6ed0ff89f10295af0b802247ec5670da8f886e71a4226373b032c322f";

const POLICY_ADDRESS: address = @0x034401905bebdf8c04f3cd5f04f442a39372c8dc321c29edfb4f9cb30b23ab96;
const ADMIN_CAP_ADDRESS: address =
    @0x9df89cce88e2e69d40b78f5ee4679ee9e04b99f9303eade0d1a5ef9e4fa5ad2a;

const ATTESTED_AT_MS: u64 = 1_744_684_007_462;
const ATTESTED_PK: vector<u8> = x"e8e62201dbe293b703c759f653107acbc2c911fa1d2e66f2c747bec95971a2af";
const OTHER_PK: vector<u8> = x"ea4a6c63e29c520abef5507b132ec5f9954776aebebe7b92421eea691446d22c";
const SIGNED_AT_MS: u64 = 1_744_683_300_000;
const SIGNATURE: vector<u8> =
    x"77b6d8be225440d00f3d6eb52e91076a8927cebfb520e58c19daf31ecf06b3798ec3d3ce9630a9eceee46d24f057794a60dd781657cb06d952269cfc5ae19500";
const ATTESTATION: vector<u8> =
    x"8444a1013822a0591120a9696d6f64756c655f69647827692d30366534623938633635343966663830332d656e633031393633373362313935666237323366646967657374665348413338346974696d657374616d701b000001963743f8f06470637273b0005830cbe1afb6ed0ff89f10295af0b802247ec5670da8f886e71a4226373b032c322f4e42c9c98288e7211682b258684505a2015830cbe1afb6ed0ff89f10295af0b802247ec5670da8f886e71a4226373b032c322f4e42c9c98288e7211682b258684505a202583021b9efbc184807662e966d34f390821309eeac6802309798826296bf3e8bec7c10edb30948c90ba67310f7b964fc500a0358309af4960cd10ff0ddb81dc6660d16bf92165923d7ce3cbc53b9e42257424049b55bf459ca68ba632f39ff510064293c5f045830f3e18816e8d0ba69088d034522e742f0e1909ab34d5e83a1f579ffb43c58f0f0f35d64401efc9426097565d0506a8a5f0558300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000658300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000758300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000858300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000958300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a58300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b58300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c58300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d58300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e58300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f58300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006b636572746966696361746559027f3082027b30820201a00302010202100196373b195fb7230000000067fdc1ce300a06082a8648ce3d04030330818e310b30090603550406130255533113301106035504080c0a57617368696e67746f6e3110300e06035504070c0753656174746c65310f300d060355040a0c06416d617a6f6e310c300a060355040b0c034157533139303706035504030c30692d30366534623938633635343966663830332e75732d656173742d312e6177732e6e6974726f2d656e636c61766573301e170d3235303431353032313734375a170d3235303431353035313735305a308193310b30090603550406130255533113301106035504080c0a57617368696e67746f6e3110300e06035504070c0753656174746c65310f300d060355040a0c06416d617a6f6e310c300a060355040b0c03415753313e303c06035504030c35692d30366534623938633635343966663830332d656e63303139363337336231393566623732332e75732d656173742d312e6177733076301006072a8648ce3d020106052b8104002203620004490136a3059279a6f8632e540e52ed40f92f891fedf5bdfbbddc3ec066bdbe0f45e0c3e8b07e689a8c3ad57f940181b8a7d8940772290efc58e56d1a9fcc50a969e55ec546e325c09d22c9eb1ed581dd00c70e184368b2330e7ef4b94d3f3833a31d301b300c0603551d130101ff04023000300b0603551d0f0404030206c0300a06082a8648ce3d0403030368003065023100d6d67e427ae4d86ba2f9d7848aba398d89271decf60d772fb8f68a95e01aedfdfa1dc46d0e7c65d42c8328af205cfc02023037bdff62ac37852595143477c8cdf43937c4b56e7165256017c9aa6083cbe6e99365cf38c3984e2e7450d1578293f3c668636162756e646c65845902153082021130820196a003020102021100f93175681b90afe11d46ccb4e4e7f856300a06082a8648ce3d0403033049310b3009060355040613025553310f300d060355040a0c06416d617a6f6e310c300a060355040b0c03415753311b301906035504030c126177732e6e6974726f2d656e636c61766573301e170d3139313032383133323830355a170d3439313032383134323830355a3049310b3009060355040613025553310f300d060355040a0c06416d617a6f6e310c300a060355040b0c03415753311b301906035504030c126177732e6e6974726f2d656e636c617665733076301006072a8648ce3d020106052b8104002203620004fc0254eba608c1f36870e29ada90be46383292736e894bfff672d989444b5051e534a4b1f6dbe3c0bc581a32b7b176070ede12d69a3fea211b66e752cf7dd1dd095f6f1370f4170843d9dc100121e4cf63012809664487c9796284304dc53ff4a3423040300f0603551d130101ff040530030101ff301d0603551d0e041604149025b50dd90547e796c396fa729dcf99a9df4b96300e0603551d0f0101ff040403020186300a06082a8648ce3d0403030369003066023100a37f2f91a1c9bd5ee7b8627c1698d255038e1f0343f95b63a9628c3d39809545a11ebcbf2e3b55d8aeee71b4c3d6adf3023100a2f39b1605b27028a5dd4ba069b5016e65b4fbde8fe0061d6a53197f9cdaf5d943bc61fc2beb03cb6fee8d2302f3dff65902c2308202be30820245a003020102021100aca2293d4cf500edd86a7bd187ba1338300a06082a8648ce3d0403033049310b3009060355040613025553310f300d060355040a0c06416d617a6f6e310c300a060355040b0c03415753311b301906035504030c126177732e6e6974726f2d656e636c61766573301e170d3235303431313136333235355a170d3235303530313137333235355a3064310b3009060355040613025553310f300d060355040a0c06416d617a6f6e310c300a060355040b0c034157533136303406035504030c2d356139363331373264336535616338622e75732d656173742d312e6177732e6e6974726f2d656e636c617665733076301006072a8648ce3d020106052b810400220362000490c21b3f525af903e794663217497520278d2139f1d1a0b20eb8ff5355c8aed6ac269cea960f70493d0a4133b6cba128c820e80f40864bc032ac9b818e45c587f53d07eafc78fb530b2a1869858e55ef33c8e61e2dc6f370a308ad65d94ed1eea381d53081d230120603551d130101ff040830060101ff020102301f0603551d230418301680149025b50dd90547e796c396fa729dcf99a9df4b96301d0603551d0e04160414add2c2173808b510358d217b3b86fb8f1ad6b173300e0603551d0f0101ff040403020186306c0603551d1f046530633061a05fa05d865b687474703a2f2f6177732d6e6974726f2d656e636c617665732d63726c2e73332e616d617a6f6e6177732e636f6d2f63726c2f61623439363063632d376436332d343262642d396539662d3539333338636236376638342e63726c300a06082a8648ce3d040303036700306402300249f3400cd372979e8b38574f68abb0c09985ebba87d6ff7ed39565b5d60cf1219e5148ac25ec631730542aebd5c5810230615675a1d4841c819082db134b1717eb4b6676c812f09130b1cfe7a9f62a02a072b5c336425a14fbbd1d80d74b356b85590319308203153082029ba003020102021100969362d18653a5d07019712d46af35ca300a06082a8648ce3d0403033064310b3009060355040613025553310f300d060355040a0c06416d617a6f6e310c300a060355040b0c034157533136303406035504030c2d356139363331373264336535616338622e75732d656173742d312e6177732e6e6974726f2d656e636c61766573301e170d3235303431353030323331395a170d3235303432303138323331395a308189313c303a06035504030c33613833653764313231306434313335632e7a6f6e616c2e75732d656173742d312e6177732e6e6974726f2d656e636c61766573310c300a060355040b0c03415753310f300d060355040a0c06416d617a6f6e310b3009060355040613025553310b300906035504080c0257413110300e06035504070c0753656174746c653076301006072a8648ce3d020106052b81040022036200048d5a8ecd047ea37a3fb8d9e94294ae4bea46c9750e50fe1689ba34e522aa77e22a873d3369e89e7e5672ced6337ae0efbfb8a31ac3bba48b522798b2b86b033adac2e253fc2f048d7c26b9bc7c3c306451a90650305504ba3bd869c9d382027ba381ea3081e730120603551d130101ff040830060101ff020101301f0603551d23041830168014add2c2173808b510358d217b3b86fb8f1ad6b173301d0603551d0e04160414f5273e07c37b153782a854f34bf8941eb280ef6e300e0603551d0f0101ff0404030201863081800603551d1f047930773075a073a071866f687474703a2f2f63726c2d75732d656173742d312d6177732d6e6974726f2d656e636c617665732e73332e75732d656173742d312e616d617a6f6e6177732e636f6d2f63726c2f66326463623035372d333434352d343963642d626131382d3733396663666466353261632e63726c300a06082a8648ce3d0403030368003065023100a446d4c6ebe8dc4ac3196b5a7488d470128a69c843db43ce55e139cd95a1f977074066d9f23e45530b6850217b57cdf402305f358040394462762ca1094b9302a4e1e51cf61dde52a048d1de90d25a239574e0f615659945b64264b997bb5a0ccb335902c2308202be30820245a003020102021500d2582b5520ba5712e796e4f758e577ee985f5954300a06082a8648ce3d040303308189313c303a06035504030c33613833653764313231306434313335632e7a6f6e616c2e75732d656173742d312e6177732e6e6974726f2d656e636c61766573310c300a060355040b0c03415753310f300d060355040a0c06416d617a6f6e310b3009060355040613025553310b300906035504080c0257413110300e06035504070c0753656174746c65301e170d3235303431353031343333385a170d3235303431363031343333385a30818e310b30090603550406130255533113301106035504080c0a57617368696e67746f6e3110300e06035504070c0753656174746c65310f300d060355040a0c06416d617a6f6e310c300a060355040b0c034157533139303706035504030c30692d30366534623938633635343966663830332e75732d656173742d312e6177732e6e6974726f2d656e636c617665733076301006072a8648ce3d020106052b81040022036200049f84fd231f0332361556d06121290b042aba0fc8119cf62b530a34fde2ba0a5213eaf4bcd79cd240492f51702315beebedc7c29d42a72912e0add5975ff35fe8ac7b9167ad19b2984114aa5c6bc466a20d63e5f2bb5d7dc4a9e7a6400545d95fa366306430120603551d130101ff040830060101ff020100300e0603551d0f0101ff040403020204301d0603551d0e0416041431b3f2a9c91d2fbfe1230f702391caeec8567e0d301f0603551d23041830168014f5273e07c37b153782a854f34bf8941eb280ef6e300a06082a8648ce3d040303036700306402300299d6641d327fd9b5986cbfccf00ea02d95eeb7ee6f4193fd4ba28a17a329f67ba20e551ceb3b1c739df61308799d3102302ab166a5394bb64e6e6149da899acde27417ba137083bc4b6f156cde3deea56cde0bf57186c80bd6dafdeb898aeb71566a7075626c69635f6b65795820e8e62201dbe293b703c759f653107acbc2c911fa1d2e66f2c747bec95971a2af69757365725f64617461f6656e6f6e6365f65860b8397a987eb8327f75b4ab764c74dd068cbc107faa518b5d97bc074cf4ea1e8cb5cbaa0446b54d42ac55ad9c84094cedcddaa3b74b4a3b8f681a00cf311232dd663f8e3c9c67b7926e7b9dbdf697e1358e3b380a8e76d088db535d607d96b8a1";

// === Helpers ===

fun begin(): Scenario {
    test_scenario::begin(ADMIN)
}

fun new_policy(
    scenario: &mut Scenario,
): (EnclavePolicy<ENCLAVE_TESTS>, EnclavePolicyAdminCap<ENCLAVE_TESTS>) {
    enclave::new(ENCLAVE_TESTS(), scenario.ctx())
}

fun configured_policy(
    scenario: &mut Scenario,
): (EnclavePolicy<ENCLAVE_TESTS>, EnclavePolicyAdminCap<ENCLAVE_TESTS>) {
    let (mut policy, cap) = new_policy(scenario);
    policy.set_pcrs(&cap, PCR0, PCR1, PCR2);
    (policy, cap)
}

fun registered_policy(
    scenario: &mut Scenario,
): (EnclavePolicy<ENCLAVE_TESTS>, EnclavePolicyAdminCap<ENCLAVE_TESTS>) {
    let (mut policy, cap) = configured_policy(scenario);
    policy.register(document(scenario));
    (policy, cap)
}

fun document(scenario: &mut Scenario): NitroAttestationDocument {
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(ATTESTED_AT_MS);
    let document = nitro_attestation::load_nitro_attestation(ATTESTATION, &clock);
    clock.destroy_for_testing();
    document
}

fun weather(temperature: u64): WeatherResponse {
    WeatherResponse { location: b"San Francisco".to_string(), temperature }
}

fun verify(policy: &EnclavePolicy<ENCLAVE_TESTS>, intent: u8, temperature: u64) {
    let signature = SIGNATURE;
    policy.verify_signature(ATTESTED_PK, intent, SIGNED_AT_MS, weather(temperature), &signature);
}

// === Policy ===

#[test]
fun new_policy_starts_unset_at_version_zero() {
    let mut scenario = begin();
    let (policy, cap) = new_policy(&mut scenario);
    assert!(policy.pcr0().is_empty());
    assert!(policy.pcr1().is_empty());
    assert!(policy.pcr2().is_empty());
    assert_eq!(policy.version(), 0);
    assert!(!policy.is_registered(ATTESTED_PK));
    policy.share();
    destroy(cap);
    scenario.end();
}

#[test]
fun new_policy_emits_the_created_event() {
    let mut scenario = begin();
    let (policy, cap) = new_policy(&mut scenario);
    let events = event::events_by_type<EnclavePolicyCreatedEvent<ENCLAVE_TESTS>>();
    assert_eq!(events.length(), 1);
    assert_eq!(enclave::enclave_policy_created_fields_for_testing(&events[0]), object::id(&policy));
    assert_eq!(event::events_by_type<EnclavePolicyPcrsSetEvent<ENCLAVE_TESTS>>().length(), 0);
    destroy(policy);
    destroy(cap);
    scenario.end();
}

#[test, expected_failure(abort_code = enclave::ENotOneTimeWitness)]
fun new_policy_rejects_a_plain_witness() {
    let mut scenario = begin();
    let (_policy, _cap) = enclave::new(NotOneTimeWitness(), scenario.ctx());
    abort
}

#[test]
fun admin_cap_address_matches_the_pinned_vector() {
    let mut scenario = begin();
    let (policy, cap) = new_policy(&mut scenario);
    assert_eq!(object::id(&policy).to_address(), POLICY_ADDRESS);
    assert_eq!(object::id(&cap).to_address(), policy.derive_admin_cap_address());
    assert_eq!(object::id(&cap).to_address(), ADMIN_CAP_ADDRESS);
    destroy(policy);
    destroy(cap);
    scenario.end();
}

#[test]
fun policy_for_testing_derives_its_admin_cap() {
    let mut scenario = begin();
    let (policy, cap) = enclave::new_for_testing<ENCLAVE_TESTS>(scenario.ctx());
    assert_eq!(object::id(&cap).to_address(), policy.derive_admin_cap_address());
    assert_eq!(policy.version(), 0);
    destroy(policy);
    destroy(cap);
    scenario.end();
}

#[test]
fun set_pcrs_stores_them_and_bumps_the_version() {
    let mut scenario = begin();
    let (policy, cap) = configured_policy(&mut scenario);
    assert_eq!(*policy.pcr0(), PCR0);
    assert_eq!(*policy.pcr1(), PCR1);
    assert_eq!(*policy.pcr2(), PCR2);
    assert_eq!(policy.version(), 1);
    let events = event::events_by_type<EnclavePolicyPcrsSetEvent<ENCLAVE_TESTS>>();
    assert_eq!(events.length(), 1);
    let (
        policy_id,
        version,
        pcr0,
        pcr1,
        pcr2,
    ) = enclave::enclave_policy_pcrs_set_fields_for_testing(
        &events[0],
    );
    assert_eq!(policy_id, object::id(&policy));
    assert_eq!(version, 1);
    assert_eq!(pcr0, PCR0);
    assert_eq!(pcr1, PCR1);
    assert_eq!(pcr2, PCR2);
    destroy(policy);
    destroy(cap);
    scenario.end();
}

#[test]
fun set_pcrs_rotates_to_other_pcrs() {
    let mut scenario = begin();
    let (mut policy, cap) = configured_policy(&mut scenario);
    policy.set_pcrs(&cap, PCR0, PCR1, OTHER_PCR);
    assert_eq!(*policy.pcr2(), OTHER_PCR);
    assert_eq!(policy.version(), 2);
    let events = event::events_by_type<EnclavePolicyPcrsSetEvent<ENCLAVE_TESTS>>();
    assert_eq!(events.length(), 2);
    let (_, version, pcr0, pcr1, pcr2) = enclave::enclave_policy_pcrs_set_fields_for_testing(
        &events[1],
    );
    assert_eq!(version, 2);
    assert_eq!(pcr0, PCR0);
    assert_eq!(pcr1, PCR1);
    assert_eq!(pcr2, OTHER_PCR);
    destroy(policy);
    destroy(cap);
    scenario.end();
}

#[test, expected_failure(abort_code = enclave::EUnauthorized)]
fun set_pcrs_rejects_another_policys_cap() {
    let mut scenario = begin();
    let (mut policy, _cap) = new_policy(&mut scenario);
    let (_other, other_cap) = enclave::new_for_testing<ENCLAVE_TESTS>(scenario.ctx());
    policy.set_pcrs(&other_cap, PCR0, PCR1, PCR2);
    abort
}

#[test, expected_failure(abort_code = enclave::ESamePcrs)]
fun set_pcrs_rejects_the_current_pcrs() {
    let mut scenario = begin();
    let (mut policy, cap) = configured_policy(&mut scenario);
    policy.set_pcrs(&cap, PCR0, PCR1, PCR2);
    abort
}

#[test, expected_failure(abort_code = enclave::EInvalidPcrLength)]
fun set_pcrs_rejects_a_short_pcr() {
    let mut scenario = begin();
    let (mut policy, cap) = new_policy(&mut scenario);
    policy.set_pcrs(&cap, PCR0, PCR1, SHORT_PCR);
    abort
}

#[test, expected_failure(abort_code = enclave::EDebugPcrs)]
fun set_pcrs_rejects_debug_mode_zeros() {
    let mut scenario = begin();
    let (mut policy, cap) = new_policy(&mut scenario);
    policy.set_pcrs(&cap, PCR0, ZERO_PCR, PCR2);
    abort
}

// === Registration ===

#[test]
fun register_is_permissionless_and_the_key_verifies() {
    let mut scenario = begin();
    let (policy, cap) = configured_policy(&mut scenario);
    let policy_id = object::id(&policy);
    policy.share();
    scenario.next_tx(RELAYER);
    let mut policy = scenario.take_shared_by_id<EnclavePolicy<ENCLAVE_TESTS>>(policy_id);
    policy.register(document(&mut scenario));
    assert!(policy.is_registered(ATTESTED_PK));
    assert_eq!(policy.registered_version(ATTESTED_PK), 1);
    verify(&policy, 0, 13);
    test_scenario::return_shared(policy);
    destroy(cap);
    scenario.end();
}

#[test]
fun register_emits_the_registered_event() {
    let mut scenario = begin();
    let (policy, cap) = registered_policy(&mut scenario);
    let events = event::events_by_type<EnclaveRegisteredEvent<ENCLAVE_TESTS>>();
    assert_eq!(events.length(), 1);
    let (policy_id, pk, version) = enclave::enclave_registered_fields_for_testing(&events[0]);
    assert_eq!(policy_id, object::id(&policy));
    assert_eq!(pk, ATTESTED_PK);
    assert_eq!(version, 1);
    destroy(policy);
    destroy(cap);
    scenario.end();
}

#[test]
fun load_pk_reads_the_attested_key() {
    let mut scenario = begin();
    let (policy, cap) = configured_policy(&mut scenario);
    let document = document(&mut scenario);
    assert_eq!(policy.load_pk_for_testing(&document), ATTESTED_PK);
    destroy(policy);
    destroy(cap);
    scenario.end();
}

#[test, expected_failure(abort_code = enclave::EInvalidPcrs)]
fun register_rejects_unset_pcrs() {
    let mut scenario = begin();
    let (mut policy, _cap) = new_policy(&mut scenario);
    policy.register(document(&mut scenario));
    abort
}

#[test, expected_failure(abort_code = enclave::EInvalidPcrs)]
fun register_rejects_other_pcrs() {
    let mut scenario = begin();
    let (mut policy, cap) = new_policy(&mut scenario);
    policy.set_pcrs(&cap, PCR0, PCR1, OTHER_PCR);
    policy.register(document(&mut scenario));
    abort
}

#[test, expected_failure(abort_code = enclave::EEnclaveAlreadyRegistered)]
fun register_rejects_the_same_key_twice() {
    let mut scenario = begin();
    let (mut policy, _cap) = registered_policy(&mut scenario);
    policy.register(document(&mut scenario));
    abort
}

#[test, expected_failure(abort_code = enclave::EMissingPcr)]
fun pcr_at_rejects_a_missing_pcr() {
    let entries = vector<PCREntry>[];
    enclave::pcr_at_for_testing(&entries, 0);
}

#[test]
fun checked_public_key_accepts_an_ed25519_key() {
    assert_eq!(enclave::checked_public_key_for_testing(option::some(ATTESTED_PK)), ATTESTED_PK);
}

#[test, expected_failure(abort_code = enclave::EMissingPublicKey)]
fun checked_public_key_rejects_a_missing_key() {
    enclave::checked_public_key_for_testing(option::none());
}

#[test, expected_failure(abort_code = enclave::EInvalidPublicKeyLength)]
fun checked_public_key_rejects_a_short_key() {
    enclave::checked_public_key_for_testing(option::some(x"e8e622"));
}

#[test, expected_failure(abort_code = enclave::EInvalidPublicKeyLength)]
fun checked_public_key_rejects_a_long_key() {
    enclave::checked_public_key_for_testing(option::some(PCR0));
}

#[test, expected_failure(abort_code = enclave::EEnclaveNotRegistered)]
fun registered_version_rejects_an_unregistered_key() {
    let mut scenario = begin();
    let (policy, _cap) = configured_policy(&mut scenario);
    policy.registered_version(ATTESTED_PK);
    abort
}

#[test]
fun register_for_testing_round_trips() {
    let mut scenario = begin();
    let (mut policy, cap) = enclave::new_for_testing<ENCLAVE_TESTS>(scenario.ctx());
    policy.register_for_testing(OTHER_PK, 3);
    assert!(policy.is_registered(OTHER_PK));
    assert!(!policy.is_registered(ATTESTED_PK));
    assert_eq!(policy.registered_version(OTHER_PK), 3);
    assert_eq!(event::events_by_type<EnclaveRegisteredEvent<ENCLAVE_TESTS>>().length(), 0);
    destroy(policy);
    destroy(cap);
    scenario.end();
}

#[test, expected_failure(abort_code = enclave::EEnclaveAlreadyRegistered)]
fun register_for_testing_rejects_the_same_key_twice() {
    let mut scenario = begin();
    let (mut policy, _cap) = enclave::new_for_testing<ENCLAVE_TESTS>(scenario.ctx());
    policy.register_for_testing(OTHER_PK, 0);
    policy.register_for_testing(OTHER_PK, 0);
    abort
}

#[test, expected_failure(abort_code = enclave::EInvalidPublicKeyLength)]
fun register_for_testing_rejects_a_short_key() {
    let mut scenario = begin();
    let (mut policy, _cap) = enclave::new_for_testing<ENCLAVE_TESTS>(scenario.ctx());
    policy.register_for_testing(x"e8e622", 0);
    abort
}

// === Signatures ===

#[test]
fun verify_signature_accepts_the_enclave_signature() {
    let mut scenario = begin();
    let (policy, cap) = registered_policy(&mut scenario);
    verify(&policy, 0, 13);
    destroy(policy);
    destroy(cap);
    scenario.end();
}

#[test]
fun verify_signature_accepts_a_test_registered_key() {
    let mut scenario = begin();
    let (mut policy, cap) = enclave::new_for_testing<ENCLAVE_TESTS>(scenario.ctx());
    policy.register_for_testing(ATTESTED_PK, 0);
    verify(&policy, 0, 13);
    destroy(policy);
    destroy(cap);
    scenario.end();
}

#[test, expected_failure(abort_code = enclave::EInvalidSignature)]
fun verify_signature_rejects_a_tampered_payload() {
    let mut scenario = begin();
    let (policy, _cap) = registered_policy(&mut scenario);
    verify(&policy, 0, 14);
    abort
}

#[test, expected_failure(abort_code = enclave::EInvalidSignature)]
fun verify_signature_rejects_another_intent() {
    let mut scenario = begin();
    let (policy, _cap) = registered_policy(&mut scenario);
    verify(&policy, 1, 13);
    abort
}

#[test, expected_failure(abort_code = enclave::EEnclaveNotRegistered)]
fun verify_signature_rejects_an_unregistered_key() {
    let mut scenario = begin();
    let (policy, _cap) = configured_policy(&mut scenario);
    verify(&policy, 0, 13);
    abort
}

#[test, expected_failure(abort_code = enclave::EStaleEnclave)]
fun set_pcrs_is_the_kill_switch() {
    let mut scenario = begin();
    let (mut policy, cap) = registered_policy(&mut scenario);
    policy.set_pcrs(&cap, PCR0, PCR1, OTHER_PCR);
    verify(&policy, 0, 13);
    abort
}

#[test]
fun intent_message_layout_matches_nautilus_rust() {
    let message = enclave::create_intent_message(0, 1_744_038_900_000, weather(13));
    assert_eq!(
        bcs::to_bytes(&message),
        x"0020b1d110960100000d53616e204672616e636973636f0d00000000000000",
    );
}

// === Revocation ===

#[test]
fun revoke_removes_the_key() {
    let mut scenario = begin();
    let (mut policy, cap) = registered_policy(&mut scenario);
    policy.revoke(&cap, ATTESTED_PK);
    assert!(!policy.is_registered(ATTESTED_PK));
    let events = event::events_by_type<EnclaveRevokedEvent<ENCLAVE_TESTS>>();
    assert_eq!(events.length(), 1);
    let (policy_id, pk, version) = enclave::enclave_revoked_fields_for_testing(&events[0]);
    assert_eq!(policy_id, object::id(&policy));
    assert_eq!(pk, ATTESTED_PK);
    assert_eq!(version, 1);
    destroy(policy);
    destroy(cap);
    scenario.end();
}

#[test]
fun revoke_reports_the_stored_version() {
    let mut scenario = begin();
    let (mut policy, cap) = registered_policy(&mut scenario);
    policy.set_pcrs(&cap, PCR0, PCR1, OTHER_PCR);
    policy.revoke(&cap, ATTESTED_PK);
    let events = event::events_by_type<EnclaveRevokedEvent<ENCLAVE_TESTS>>();
    let (_, _, version) = enclave::enclave_revoked_fields_for_testing(&events[0]);
    assert_eq!(version, 1);
    destroy(policy);
    destroy(cap);
    scenario.end();
}

#[test, expected_failure(abort_code = enclave::EEnclaveNotRegistered)]
fun verify_signature_rejects_a_revoked_key() {
    let mut scenario = begin();
    let (mut policy, cap) = registered_policy(&mut scenario);
    policy.revoke(&cap, ATTESTED_PK);
    verify(&policy, 0, 13);
    abort
}

#[test, expected_failure(abort_code = enclave::EEnclaveNotRegistered)]
fun revoke_rejects_an_unregistered_key() {
    let mut scenario = begin();
    let (mut policy, cap) = configured_policy(&mut scenario);
    policy.revoke(&cap, ATTESTED_PK);
    abort
}

#[test, expected_failure(abort_code = enclave::EUnauthorized)]
fun revoke_rejects_another_policys_cap() {
    let mut scenario = begin();
    let (mut policy, _cap) = registered_policy(&mut scenario);
    let (_other, other_cap) = enclave::new_for_testing<ENCLAVE_TESTS>(scenario.ctx());
    policy.revoke(&other_cap, ATTESTED_PK);
    abort
}

// === Stale Removal ===

#[test]
fun remove_stale_after_rotation() {
    let mut scenario = begin();
    let (mut policy, cap) = registered_policy(&mut scenario);
    policy.set_pcrs(&cap, PCR0, PCR1, OTHER_PCR);
    let policy_id = object::id(&policy);
    policy.share();
    scenario.next_tx(RELAYER);
    let mut policy = scenario.take_shared_by_id<EnclavePolicy<ENCLAVE_TESTS>>(policy_id);
    policy.remove_stale(ATTESTED_PK);
    assert!(!policy.is_registered(ATTESTED_PK));
    let events = event::events_by_type<StaleEnclaveRemovedEvent<ENCLAVE_TESTS>>();
    assert_eq!(events.length(), 1);
    let (event_policy_id, pk, version) = enclave::stale_enclave_removed_fields_for_testing(
        &events[0],
    );
    assert_eq!(event_policy_id, policy_id);
    assert_eq!(pk, ATTESTED_PK);
    assert_eq!(version, 1);
    test_scenario::return_shared(policy);
    destroy(cap);
    scenario.end();
}

#[test, expected_failure(abort_code = enclave::ENotStale)]
fun remove_stale_rejects_a_current_key() {
    let mut scenario = begin();
    let (mut policy, _cap) = registered_policy(&mut scenario);
    policy.remove_stale(ATTESTED_PK);
    abort
}

#[test, expected_failure(abort_code = enclave::EEnclaveNotRegistered)]
fun remove_stale_rejects_an_unregistered_key() {
    let mut scenario = begin();
    let (mut policy, _cap) = configured_policy(&mut scenario);
    policy.remove_stale(ATTESTED_PK);
    abort
}

#[test]
fun rollback_re_registers_the_same_attestation_without_reboot() {
    let mut scenario = begin();
    let (mut policy, cap) = registered_policy(&mut scenario);
    policy.set_pcrs(&cap, PCR0, PCR1, OTHER_PCR);
    policy.set_pcrs(&cap, PCR0, PCR1, PCR2);
    assert_eq!(policy.version(), 3);
    assert_eq!(policy.registered_version(ATTESTED_PK), 1);
    policy.remove_stale(ATTESTED_PK);
    policy.register(document(&mut scenario));
    assert_eq!(policy.registered_version(ATTESTED_PK), 3);
    verify(&policy, 0, 13);
    destroy(policy);
    destroy(cap);
    scenario.end();
}
