// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module recording_credits::recording_party_role;

use std::string::String;

// === Errors ===

const EEmptyInstrument: u64 = 0;
const EInstrumentTooLong: u64 = 1;

// === Constants ===

const MAX_INSTRUMENT_LENGTH: u64 = 100;

// === Enums ===

public enum RecordingPartyRole has copy, drop, store {
    Actor(Option<RecordingPartyRoleLevel>),
    Arranger(Option<RecordingPartyRoleLevel>),
    ArtistsAndRepertoire,
    BandLeader(Option<RecordingPartyRoleLevel>),
    Choir(Option<RecordingPartyRoleLevel>),
    ChoirMaster(Option<RecordingPartyRoleLevel>),
    ConcertMaster(Option<RecordingPartyRoleLevel>),
    Conductor(Option<RecordingPartyRoleLevel>),
    Contractor(Option<RecordingPartyRoleLevel>),
    Copyist,
    DJ(Option<RecordingPartyRoleLevel>),
    Editor(Option<RecordingPartyRoleLevel>),
    Engineer(Option<RecordingPartyRoleLevel>),
    Ensemble(Option<RecordingPartyRoleLevel>),
    Instrumentalist(String, Option<RecordingPartyRoleLevel>),
    MasteringEngineer(Option<RecordingPartyRoleLevel>),
    MixingEngineer(Option<RecordingPartyRoleLevel>),
    MusicDirector(Option<RecordingPartyRoleLevel>),
    MusicSupervisor(Option<RecordingPartyRoleLevel>),
    Narrator(Option<RecordingPartyRoleLevel>),
    Orchestra(Option<RecordingPartyRoleLevel>),
    Orchestrator(Option<RecordingPartyRoleLevel>),
    Performer(Option<RecordingPartyRoleLevel>),
    Producer(Option<RecordingPartyRoleLevel>),
    Programmer(Option<RecordingPartyRoleLevel>),
    RecordingEngineer(Option<RecordingPartyRoleLevel>),
    RemixingEngineer(Option<RecordingPartyRoleLevel>),
    Soloist(Option<RecordingPartyRoleLevel>),
    SoundDesigner(Option<RecordingPartyRoleLevel>),
    Speaker(Option<RecordingPartyRoleLevel>),
    Vocalist(Option<RecordingPartyRoleLevel>),
}

public enum RecordingPartyRoleLevel has copy, drop, store {
    Additional,
    Assistant,
    Associate,
    Backing,
    Executive,
    Featured,
    Lead,
    Primary,
    Principal,
}

// === Public Functions ===

public fun new_actor_role(level: Option<RecordingPartyRoleLevel>): RecordingPartyRole {
    RecordingPartyRole::Actor(level)
}

public fun new_arranger_role(level: Option<RecordingPartyRoleLevel>): RecordingPartyRole {
    RecordingPartyRole::Arranger(level)
}

public fun new_artists_and_repertoire_role(): RecordingPartyRole {
    RecordingPartyRole::ArtistsAndRepertoire
}

public fun new_band_leader_role(level: Option<RecordingPartyRoleLevel>): RecordingPartyRole {
    RecordingPartyRole::BandLeader(level)
}

public fun new_choir_role(level: Option<RecordingPartyRoleLevel>): RecordingPartyRole {
    RecordingPartyRole::Choir(level)
}

public fun new_choir_master_role(level: Option<RecordingPartyRoleLevel>): RecordingPartyRole {
    RecordingPartyRole::ChoirMaster(level)
}

public fun new_concert_master_role(level: Option<RecordingPartyRoleLevel>): RecordingPartyRole {
    RecordingPartyRole::ConcertMaster(level)
}

public fun new_conductor_role(level: Option<RecordingPartyRoleLevel>): RecordingPartyRole {
    RecordingPartyRole::Conductor(level)
}

public fun new_contractor_role(level: Option<RecordingPartyRoleLevel>): RecordingPartyRole {
    RecordingPartyRole::Contractor(level)
}

public fun new_copyist_role(): RecordingPartyRole {
    RecordingPartyRole::Copyist
}

public fun new_dj_role(level: Option<RecordingPartyRoleLevel>): RecordingPartyRole {
    RecordingPartyRole::DJ(level)
}

public fun new_editor_role(level: Option<RecordingPartyRoleLevel>): RecordingPartyRole {
    RecordingPartyRole::Editor(level)
}

public fun new_engineer_role(level: Option<RecordingPartyRoleLevel>): RecordingPartyRole {
    RecordingPartyRole::Engineer(level)
}

public fun new_ensemble_role(level: Option<RecordingPartyRoleLevel>): RecordingPartyRole {
    RecordingPartyRole::Ensemble(level)
}

public fun new_instrumentalist_role(
    instrument: String,
    level: Option<RecordingPartyRoleLevel>,
): RecordingPartyRole {
    assert!(!instrument.is_empty(), EEmptyInstrument);
    assert!(instrument.length() <= MAX_INSTRUMENT_LENGTH, EInstrumentTooLong);
    RecordingPartyRole::Instrumentalist(instrument, level)
}

public fun new_mastering_engineer_role(level: Option<RecordingPartyRoleLevel>): RecordingPartyRole {
    RecordingPartyRole::MasteringEngineer(level)
}

public fun new_mixing_engineer_role(level: Option<RecordingPartyRoleLevel>): RecordingPartyRole {
    RecordingPartyRole::MixingEngineer(level)
}

public fun new_music_director_role(level: Option<RecordingPartyRoleLevel>): RecordingPartyRole {
    RecordingPartyRole::MusicDirector(level)
}

public fun new_music_supervisor_role(level: Option<RecordingPartyRoleLevel>): RecordingPartyRole {
    RecordingPartyRole::MusicSupervisor(level)
}

public fun new_narrator_role(level: Option<RecordingPartyRoleLevel>): RecordingPartyRole {
    RecordingPartyRole::Narrator(level)
}

public fun new_orchestra_role(level: Option<RecordingPartyRoleLevel>): RecordingPartyRole {
    RecordingPartyRole::Orchestra(level)
}

public fun new_orchestrator_role(level: Option<RecordingPartyRoleLevel>): RecordingPartyRole {
    RecordingPartyRole::Orchestrator(level)
}

public fun new_performer_role(level: Option<RecordingPartyRoleLevel>): RecordingPartyRole {
    RecordingPartyRole::Performer(level)
}

public fun new_producer_role(level: Option<RecordingPartyRoleLevel>): RecordingPartyRole {
    RecordingPartyRole::Producer(level)
}

public fun new_programmer_role(level: Option<RecordingPartyRoleLevel>): RecordingPartyRole {
    RecordingPartyRole::Programmer(level)
}

public fun new_recording_engineer_role(level: Option<RecordingPartyRoleLevel>): RecordingPartyRole {
    RecordingPartyRole::RecordingEngineer(level)
}

public fun new_remixing_engineer_role(level: Option<RecordingPartyRoleLevel>): RecordingPartyRole {
    RecordingPartyRole::RemixingEngineer(level)
}

public fun new_soloist_role(level: Option<RecordingPartyRoleLevel>): RecordingPartyRole {
    RecordingPartyRole::Soloist(level)
}

public fun new_sound_designer_role(level: Option<RecordingPartyRoleLevel>): RecordingPartyRole {
    RecordingPartyRole::SoundDesigner(level)
}

public fun new_speaker_role(level: Option<RecordingPartyRoleLevel>): RecordingPartyRole {
    RecordingPartyRole::Speaker(level)
}

public fun new_vocalist_role(level: Option<RecordingPartyRoleLevel>): RecordingPartyRole {
    RecordingPartyRole::Vocalist(level)
}

public fun new_additional_role_level(): RecordingPartyRoleLevel {
    RecordingPartyRoleLevel::Additional
}

public fun new_assistant_role_level(): RecordingPartyRoleLevel {
    RecordingPartyRoleLevel::Assistant
}

public fun new_associate_role_level(): RecordingPartyRoleLevel {
    RecordingPartyRoleLevel::Associate
}

public fun new_backing_role_level(): RecordingPartyRoleLevel {
    RecordingPartyRoleLevel::Backing
}

public fun new_executive_role_level(): RecordingPartyRoleLevel {
    RecordingPartyRoleLevel::Executive
}

public fun new_featured_role_level(): RecordingPartyRoleLevel {
    RecordingPartyRoleLevel::Featured
}

public fun new_lead_role_level(): RecordingPartyRoleLevel {
    RecordingPartyRoleLevel::Lead
}

public fun new_primary_role_level(): RecordingPartyRoleLevel {
    RecordingPartyRoleLevel::Primary
}

public fun new_principal_role_level(): RecordingPartyRoleLevel {
    RecordingPartyRoleLevel::Principal
}

// === View Functions ===

public fun level(self: &RecordingPartyRole): Option<RecordingPartyRoleLevel> {
    match (self) {
        RecordingPartyRole::Actor(level) => *level,
        RecordingPartyRole::Arranger(level) => *level,
        RecordingPartyRole::ArtistsAndRepertoire => option::none(),
        RecordingPartyRole::BandLeader(level) => *level,
        RecordingPartyRole::Choir(level) => *level,
        RecordingPartyRole::ChoirMaster(level) => *level,
        RecordingPartyRole::ConcertMaster(level) => *level,
        RecordingPartyRole::Conductor(level) => *level,
        RecordingPartyRole::Contractor(level) => *level,
        RecordingPartyRole::Copyist => option::none(),
        RecordingPartyRole::DJ(level) => *level,
        RecordingPartyRole::Editor(level) => *level,
        RecordingPartyRole::Engineer(level) => *level,
        RecordingPartyRole::Ensemble(level) => *level,
        RecordingPartyRole::Instrumentalist(_, level) => *level,
        RecordingPartyRole::MasteringEngineer(level) => *level,
        RecordingPartyRole::MixingEngineer(level) => *level,
        RecordingPartyRole::MusicDirector(level) => *level,
        RecordingPartyRole::MusicSupervisor(level) => *level,
        RecordingPartyRole::Narrator(level) => *level,
        RecordingPartyRole::Orchestra(level) => *level,
        RecordingPartyRole::Orchestrator(level) => *level,
        RecordingPartyRole::Performer(level) => *level,
        RecordingPartyRole::Producer(level) => *level,
        RecordingPartyRole::Programmer(level) => *level,
        RecordingPartyRole::RecordingEngineer(level) => *level,
        RecordingPartyRole::RemixingEngineer(level) => *level,
        RecordingPartyRole::Soloist(level) => *level,
        RecordingPartyRole::SoundDesigner(level) => *level,
        RecordingPartyRole::Speaker(level) => *level,
        RecordingPartyRole::Vocalist(level) => *level,
    }
}
