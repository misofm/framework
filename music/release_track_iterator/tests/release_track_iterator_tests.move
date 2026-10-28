// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module release_track_iterator::release_track_iterator_tests;

use miso_music::release::{Self, Release};
use release_track_iterator::release_track_iterator;
use std::unit_test::{assert_eq, destroy};
use sui::address;

public struct Witness() has drop;
public struct OtherWitness() has drop;

fun release(n: u64, ctx: &mut TxContext): (Release, vector<ID>) {
    let recording_ids = vector::tabulate!(
        n,
        |i| object::id_from_address(address::from_u256((i + 1) as u256)),
    );
    let (release, cap) = release::new_for_testing(recording_ids, ctx);
    destroy(cap);
    (release, recording_ids)
}

#[test]
fun visits_every_track_in_order() {
    let mut ctx = tx_context::dummy();
    let (release, recording_ids) = release(3, &mut ctx);
    let mut tracks = release_track_iterator::new(&release, Witness());
    assert_eq!(tracks.release_id(), object::id(&release));
    recording_ids.length().do!(|i| {
        assert_eq!(tracks.position() as u64, i);
        assert_eq!(tracks.remaining() as u64, 3 - i);
        assert_eq!(tracks.next(Witness()), recording_ids[i]);
    });
    assert_eq!(tracks.remaining(), 0);
    tracks.finish(Witness());
    destroy(release);
}

#[test, expected_failure(abort_code = release_track_iterator::ETracksRemaining)]
fun finish_with_tracks_remaining_aborts() {
    let mut ctx = tx_context::dummy();
    let (release, _) = release(2, &mut ctx);
    let mut tracks = release_track_iterator::new(&release, Witness());
    tracks.next(Witness());
    tracks.finish(Witness());
    destroy(release);
}

#[test, expected_failure(abort_code = release_track_iterator::ENoTracksRemaining)]
fun next_past_last_track_aborts() {
    let mut ctx = tx_context::dummy();
    let (release, _) = release(1, &mut ctx);
    let mut tracks = release_track_iterator::new(&release, Witness());
    tracks.next(Witness());
    tracks.next(Witness());
    tracks.finish(Witness());
    destroy(release);
}

#[test]
fun empty_release_finishes_immediately() {
    let mut ctx = tx_context::dummy();
    let (release, _) = release(0, &mut ctx);
    let tracks = release_track_iterator::new(&release, Witness());
    assert_eq!(tracks.remaining(), 0);
    tracks.finish(Witness());
    destroy(release);
}

#[test, expected_failure(abort_code = release_track_iterator::ENoTracksRemaining)]
fun next_on_empty_release_aborts() {
    let mut ctx = tx_context::dummy();
    let (release, _) = release(0, &mut ctx);
    let mut tracks = release_track_iterator::new(&release, Witness());
    tracks.next(Witness());
    tracks.finish(Witness());
    destroy(release);
}

#[test, expected_failure(abort_code = release_track_iterator::ETracksRemaining)]
fun finish_before_any_track_aborts() {
    let mut ctx = tx_context::dummy();
    let (release, _) = release(2, &mut ctx);
    let tracks = release_track_iterator::new(&release, Witness());
    tracks.finish(Witness());
    destroy(release);
}

#[test]
fun single_track_release() {
    let mut ctx = tx_context::dummy();
    let (release, recording_ids) = release(1, &mut ctx);
    let mut tracks = release_track_iterator::new(&release, Witness());
    assert_eq!(tracks.next(Witness()), recording_ids[0]);
    assert_eq!(tracks.position(), 1);
    assert_eq!(tracks.remaining(), 0);
    tracks.finish(Witness());
    destroy(release);
}

#[test]
fun walks_a_max_tracks_release() {
    let mut ctx = tx_context::dummy();
    let max = release::max_tracks();
    let (release, recording_ids) = release(max, &mut ctx);
    let mut tracks = release_track_iterator::new(&release, Witness());
    max.do!(|i| {
        assert_eq!(tracks.position() as u64, i);
        assert_eq!(tracks.next(Witness()), recording_ids[i]);
    });
    assert_eq!(tracks.remaining(), 0);
    tracks.finish(Witness());
    destroy(release);
}

#[test]
fun iterators_with_different_witnesses_advance_independently() {
    let mut ctx = tx_context::dummy();
    let (release, recording_ids) = release(3, &mut ctx);
    let mut first = release_track_iterator::new(&release, Witness());
    let mut second = release_track_iterator::new(&release, OtherWitness());
    assert_eq!(first.next(Witness()), recording_ids[0]);
    assert_eq!(first.next(Witness()), recording_ids[1]);
    assert_eq!(second.next(OtherWitness()), recording_ids[0]);
    assert_eq!(first.position(), 2);
    assert_eq!(second.position(), 1);
    assert_eq!(first.next(Witness()), recording_ids[2]);
    assert_eq!(second.next(OtherWitness()), recording_ids[1]);
    assert_eq!(second.next(OtherWitness()), recording_ids[2]);
    first.finish(Witness());
    second.finish(OtherWitness());
    destroy(release);
}
