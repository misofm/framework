# party_link_merch

Merch store as a [`party_link`](../../) platform. It defines the `Merch` witness and one
`add` that appends the value to a `PartyLinks` list under `Merch`'s type name. The
value is free-form: the chain cannot tell whether a link works, so it checks only
what it must store.

## What it stores

None itself: `add` appends to a `PartyLinks` list that `party_link::set_links` stores.

- Input: any text, unchecked here; `party_link` bounds it to 1 to 2048 bytes.
- Stored bytes: UTF-8 bytes as given.
- Profile URL (client convention): the URL as given.

## API

### Writes

| Function | Description | Aborts |
|---|---|---|
| `add(links, url)` | Append it to `links` as the party's Merch store link | `EEmptyData`, `EDataTooLong`, `EPlatformAlreadyAdded`, `ETooManyLinks` |

### Views

None: read links with `party_link::links`.

## Events

None: `party_link` emits `PartyLinksSetEvent` when the list is saved.

## Errors

None defined here. `add` aborts with `party_link` errors (`EEmptyData`,
`EDataTooLong`, `EPlatformAlreadyAdded`, `ETooManyLinks`); see the
[`party_link` README](../../README.md).

## Dependencies

- [`party_link`](../../) (local path): `PartyLinks` and `add`.
- [`miso_party`](https://github.com/misofm/party-protocol) at
  `12b628fec89fd72ec96f22f709aa123658fa35db`: already a dependency of `party_link`;
  named here for the tests, which save links to a real `Party`.

## Integrator notes

- **Type name.** Match entries on the full `TypeName` string of
  `party_link_merch::party_link_merch::Merch`, with this package's published ID.
- **Untrusted bytes.** The value is unchecked text. Accept only the schemes you support (`https:`, `mailto:`) and escape it when rendering.
