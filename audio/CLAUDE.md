# audio

Move 2024 package. `sources/audio.move` holds `Audio`. Tests are in
`tests/audio_tests.move`.

## Project Rules

- `Audio<phantom AudioVerifier, Format, Layout>` is a `store + drop` value
  without `copy` or `key`: a format, a layout and an `ori::data::WalrusBlob`.
  Only `new<AudioVerifier: drop>`, given the verifier's witness, creates one.
  Its fields never change. Verification logic lives in verifier packages such
  as `audio_verifier`, with its enclave in `misofm/audio-verifier-enclave`,
  never here.
- `audio` depends on no format or layout package. Formats (`audio_format_pcm`)
  and layouts (`audio_channel_layout`) are their own packages, so a new format
  never changes `audio`.
- There is no registry, no UID and no freeze. Where an Audio is stored decides
  who holds it. `recording_master` stores masters on a Recording, keyed by blob
  ID.
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
