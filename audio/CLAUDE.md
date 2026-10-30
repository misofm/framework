# audio

Move 2024 package. `sources/audio.move` holds the registry, `Audio` and its
facts; `sources/audio_encoding.move` holds the encodings registered on an
Audio. Tests are in `tests/audio_tests.move` and
`tests/audio_encoding_tests.move`.

## Project Rules

- `Audio<phantom AudioVerifier>` is a `key`-only shared object, derived from the
  shared `AudioRegistry` by `AudioKey<AudioVerifier>` over the five facts, and
  created only by `new<AudioVerifier: drop>` with the verifier's witness. Its
  facts never change. Verification logic lives in verifier packages such as
  `misofm/audio-verifier`, never here.
- Field order everywhere is `channels, bit_depth, sample_rate_hz,
  samples_per_channel, pcm_digest`: frame shape, then time, then content, as in
  the verifier's signed payload. It is part of the key's BCS, so it fixes every
  derived address; don't change it.
- Encodings are `AudioEncodingKey<AudioEncodingVerifier>(blob_id) → true` on
  the Audio, registered with `audio_encoding::register_encoding` under the encoding verifier's
  own witness type, write-once, never removed. `audio_encoding` reaches the
  Audio's UID through the package-only `uid_mut`. Formats are not stored. Blobs are plain `u256` Walrus
  blob IDs; there is no ori dependency.
- Audio means integer linear PCM. Float PCM or DSD would be separate types.
- PCM digests are unkeyed BLAKE3 with the default 32-byte output, over the spec
  in the README.
- Follow the misofm brain MOVE-STANDARDS: no comments except the license header
  and section banners, plain numeric error codes, prefer macros.
- Validate with `sui move build --build-env mainnet` and `sui move test --coverage`.

## Sui Development Skills

Install community-maintained skills for Sui development:

```sh
npx skills https://github.com/MystenLabs/skills
```

## Official Resources

When unsure about Move patterns or Sui APIs, consult these sources:

- Move Book: https://move-book.com (https://move-book.com/llms.txt)
- Sui Docs: https://docs.sui.io (https://docs.sui.io/llms.txt)
- Sui Move examples: https://github.com/MystenLabs/sui/tree/main/examples/move

Use the Sui documentation MCP server at https://sui.mcp.kapa.ai when available.
