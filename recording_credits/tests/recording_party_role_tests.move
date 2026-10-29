// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module recording_credits::recording_party_role_tests;

use recording_credits::recording_party_role as rpr;
use std::{string::String, unit_test::assert_eq};
use sui::bcs::to_bytes;

fun long_string(len: u64): String {
    let mut bytes = vector[];
    len.do!(|_| bytes.push_back(65));
    bytes.to_string()
}

fun lead(): Option<rpr::RecordingPartyRoleLevel> {
    option::some(rpr::new_lead_role_level())
}

#[test]
fun leveled_roles_encode_their_index_and_report_their_level() {
    let roles = vector[
        rpr::new_actor_role(lead()),
        rpr::new_arranger_role(lead()),
        rpr::new_band_leader_role(lead()),
        rpr::new_choir_role(lead()),
        rpr::new_choir_master_role(lead()),
        rpr::new_concert_master_role(lead()),
        rpr::new_conductor_role(lead()),
        rpr::new_contractor_role(lead()),
        rpr::new_dj_role(lead()),
        rpr::new_editor_role(lead()),
        rpr::new_engineer_role(lead()),
        rpr::new_ensemble_role(lead()),
        rpr::new_mastering_engineer_role(lead()),
        rpr::new_mixing_engineer_role(lead()),
        rpr::new_music_director_role(lead()),
        rpr::new_music_supervisor_role(lead()),
        rpr::new_narrator_role(lead()),
        rpr::new_orchestra_role(lead()),
        rpr::new_orchestrator_role(lead()),
        rpr::new_performer_role(lead()),
        rpr::new_producer_role(lead()),
        rpr::new_programmer_role(lead()),
        rpr::new_recording_engineer_role(lead()),
        rpr::new_remixing_engineer_role(lead()),
        rpr::new_soloist_role(lead()),
        rpr::new_sound_designer_role(lead()),
        rpr::new_speaker_role(lead()),
        rpr::new_vocalist_role(lead()),
    ];
    let indices = vector[
        0,
        1,
        3,
        4,
        5,
        6,
        7,
        8,
        10,
        11,
        12,
        13,
        15,
        16,
        17,
        18,
        19,
        20,
        21,
        22,
        23,
        24,
        25,
        26,
        27,
        28,
        29,
        30,
    ];
    let encoded = roles.map_ref!(|role| to_bytes(role));
    let expected = indices.map!(|i| vector[i, 1, 6]);
    assert_eq!(encoded, expected);
    let levels = roles.map_ref!(|role| role.level());
    assert_eq!(levels, vector::tabulate!(roles.length(), |_| lead()));
}

#[test]
fun clerical_roles_have_no_level() {
    let ar = rpr::new_artists_and_repertoire_role();
    let cp = rpr::new_copyist_role();
    assert_eq!(ar.level(), option::none());
    assert_eq!(to_bytes(&ar), vector[2]);
    assert_eq!(cp.level(), option::none());
    assert_eq!(to_bytes(&cp), vector[9]);
}

#[test]
fun instrumentalist_role_encodes_instrument_name_and_level() {
    let with_level = rpr::new_instrumentalist_role(b"Piano".to_string(), lead());
    assert_eq!(with_level.level(), lead());
    assert_eq!(to_bytes(&with_level), vector[14, 5, 80, 105, 97, 110, 111, 1, 6]);
    let without_level = rpr::new_instrumentalist_role(b"Guitar".to_string(), option::none());
    assert_eq!(without_level.level(), option::none());
    assert_eq!(to_bytes(&without_level), vector[14, 6, 71, 117, 105, 116, 97, 114, 0]);
}

#[test]
fun artist_roles_have_no_level_and_append_after_existing_variants() {
    let featured = rpr::new_featured_role();
    let primary = rpr::new_primary_role();
    assert_eq!(featured.level(), option::none());
    assert_eq!(to_bytes(&featured), vector[31]);
    assert_eq!(primary.level(), option::none());
    assert_eq!(to_bytes(&primary), vector[32]);
    assert!(featured != primary);
}

#[test]
fun level_bcs_variant_indices_are_stable() {
    let levels = vector[
        rpr::new_additional_role_level(),
        rpr::new_assistant_role_level(),
        rpr::new_associate_role_level(),
        rpr::new_backing_role_level(),
        rpr::new_executive_role_level(),
        rpr::new_featured_role_level(),
        rpr::new_lead_role_level(),
        rpr::new_primary_role_level(),
        rpr::new_principal_role_level(),
    ];
    levels.length().do!(|i| {
        assert_eq!(to_bytes(&levels[i]), vector[(i as u8)]);
        let producer = rpr::new_producer_role(option::some(levels[i]));
        assert_eq!(to_bytes(&producer), vector[23, 1, (i as u8)]);
    });
    assert_eq!(to_bytes(&rpr::new_producer_role(option::none())), vector[23, 0]);
}

#[test]
fun role_levels_round_trip() {
    assert_eq!(
        rpr::new_producer_role(option::some(rpr::new_additional_role_level())).level(),
        option::some(rpr::new_additional_role_level()),
    );
    assert_eq!(
        rpr::new_producer_role(option::some(rpr::new_assistant_role_level())).level(),
        option::some(rpr::new_assistant_role_level()),
    );
    assert_eq!(
        rpr::new_producer_role(option::some(rpr::new_associate_role_level())).level(),
        option::some(rpr::new_associate_role_level()),
    );
    assert_eq!(
        rpr::new_producer_role(option::some(rpr::new_backing_role_level())).level(),
        option::some(rpr::new_backing_role_level()),
    );
    assert_eq!(
        rpr::new_producer_role(option::some(rpr::new_executive_role_level())).level(),
        option::some(rpr::new_executive_role_level()),
    );
    assert_eq!(
        rpr::new_producer_role(option::some(rpr::new_featured_role_level())).level(),
        option::some(rpr::new_featured_role_level()),
    );
    assert_eq!(
        rpr::new_producer_role(option::some(rpr::new_lead_role_level())).level(),
        option::some(rpr::new_lead_role_level()),
    );
    assert_eq!(
        rpr::new_producer_role(option::some(rpr::new_primary_role_level())).level(),
        option::some(rpr::new_primary_role_level()),
    );
    assert_eq!(
        rpr::new_producer_role(option::some(rpr::new_principal_role_level())).level(),
        option::some(rpr::new_principal_role_level()),
    );
}

#[test, expected_failure(abort_code = rpr::EEmptyInstrument)]
fun new_instrumentalist_role_rejects_empty_name() {
    let _ = rpr::new_instrumentalist_role(b"".to_string(), option::none());
    abort
}

#[test, expected_failure(abort_code = rpr::EInstrumentTooLong)]
fun new_instrumentalist_role_rejects_too_long_name() {
    let name = long_string(101);
    let _ = rpr::new_instrumentalist_role(name, option::none());
    abort
}

#[test]
fun new_instrumentalist_role_accepts_max_length_name() {
    let name = long_string(100);
    let role = rpr::new_instrumentalist_role(name, option::none());
    assert_eq!(role.level(), option::none());
    assert_eq!(to_bytes(&role).length(), 1 + 1 + 100 + 1);
}
