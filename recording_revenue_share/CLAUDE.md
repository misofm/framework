# Repository Guidance

This directory is the `recording_revenue_share` Sui Move package: a recording
gives its composition a share of itself, permanently, built on `miso_music` and
`royalty_pool`. It derives its terms and revenue share objects from a
composition and a recording. It is a voluntary revenue share, not a copyright
license; keep docs and names free of licensing and mechanical-royalty framing.

## Project Rules

- Use Move 2024 syntax.
- Import modules, functions, and types with `use`; never write fully
  qualified `address::module::member` paths inline.
- In tests, reference the real error constant through the imported module:
  `expected_failure(abort_code = recording_revenue_share::EWrongTerms)`. Move infers
  the location; do not add `location =` or mirror error constants in test files.
  Use `location = <imported module>` only for aborts with no named constant.
- `RecordingRevenueShareTermsKey()` derives the composition's terms and
  `RecordingRevenueShareKey()` derives the recording's revenue share.
- Depend on packages in this repository by local path (`royalty_pool = { local = "../royalty_pool" }`); pin dependencies outside it to exact 40-character commit SHAs.

## Official Resources

When unsure about Move patterns or Sui APIs, consult these sources. Do not guess or
extrapolate from other blockchains. Use the Sui documentation MCP server at
`https://sui.mcp.kapa.ai` when it is available.

- Move Book: https://move-book.com (use https://move-book.com/llms.txt)
- Sui Docs: https://docs.sui.io (use https://docs.sui.io/llms.txt)
- Sui Move examples: https://github.com/MystenLabs/sui/tree/main/examples/move
