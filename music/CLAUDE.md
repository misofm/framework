# Music Domain Guidance

`music/` is the music domain of the `misofm/framework` repository: independent
Sui Move packages that extend a `miso_music` `Composition`, `Recording`, or
`Release` with neutral metadata stored as cap-gated dynamic fields.
`recording_license` lives in `../economics/recording_license`.

## Project Structure

17 packages, each an independently versioned and published directory under
`music/`: 15 extensions and the `release_track_data` and
`release_track_iterator` libraries. See the package tables in `README.md` for
the full list, each package's target object, and its purpose. The shared
`credit`, `genre`, and `cover_art` libraries live in `../lib/`.

Each package owns its manifest, lockfile, publication record, source, and
tests. Audits live in the separate `misofm/audits` repository. Run Move
commands from the package directory.

## Project Rules

- Use Move 2024 syntax.
- Import modules, functions, and types with `use`; never write fully
  qualified `address::module::member` paths inline.
- In tests, reference the real error constant through the imported module:
  `expected_failure(abort_code = release::EUnauthorized)`. Move infers the
  location; do not add `location =` or mirror error constants in test files.
  Use `location = <imported module>` only for aborts with no named constant.
- One package per concern: each package defines one package-private key named
  for what it stores (`RecordingGenreKey()`, `CompositionLyricsKey(LanguageCode)`,
  `RecordingMasterKey<AudioVerifier>(pcm_digest)`), never a generic
  `ExtensionKey()`, so a schema change to one attribute never forces a data
  migration of another.
- Keep packages independently buildable and versioned.
- Depend on packages in this repository by local path
  (`credit = { local = "../../lib/credit" }`). Pin dependencies outside it to
  exact 40-character commit SHAs.
- Preserve `Published.toml` as deployment provenance.

## Sui Development Skills

Install community-maintained skills for Sui development:

```sh
npx skills https://github.com/MystenLabs/skills
```

## Official Resources

When unsure about Move patterns or Sui APIs, consult these sources. Do not guess or
extrapolate from other blockchains. Use the Sui documentation MCP server at
`https://sui.mcp.kapa.ai` when it is available.

- Move Book: https://move-book.com (use https://move-book.com/llms.txt)
- Sui Docs: https://docs.sui.io (use https://docs.sui.io/llms.txt)
- Sui Move examples: https://github.com/MystenLabs/sui/tree/main/examples/move
