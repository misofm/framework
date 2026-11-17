# party_link_custom

Custom links as a [`party_link`](../../) platform. It defines the `Custom` witness and one
`add` that appends a list of labeled links to a `PartyLinks` list under `Custom`'s type
name. A party has one Custom entry, so the entry holds the whole list (tickets, newsletter,
press kit). The values are free-form: the chain cannot tell whether a link works, so it
checks only what it must store.

## What it stores

None itself: `add` appends to a `PartyLinks` list that `party_link::set_links` stores.

- Input: `labels` and `urls`, equal length, 1 to 20 pairs; each label 1 to 40 bytes; each
  URL any non-empty text, unchecked here.
- Stored bytes: BCS of `vector<CustomLink { label: String, url: String }>`: a ULEB128
  count, then each label and URL as ULEB128-length-prefixed UTF-8. The core's 2048-byte
  limit applies to the whole encoding.
- Profile URL (client convention): none: each URL is used as given.

## API

### Writes

| Function | Description | Aborts |
|---|---|---|
| `add(links, labels, urls)` | Check each pair and append the list to `links` as the party's Custom entry | `EInvalidCount`, `ELengthMismatch`, `EInvalidLabel`, `EEmptyUrl`, `EDataTooLong`, `EPlatformAlreadyAdded`, `ETooManyLinks` |

### Views

None: read links with `party_link::links`.

## Events

None: `party_link` emits `PartyLinksSetEvent` when the list is saved.

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EInvalidCount` | `labels` is empty or has more than 20 entries |
| 1 | `ELengthMismatch` | `urls` and `labels` differ in length |
| 2 | `EInvalidLabel` | a label is empty or over 40 bytes |
| 3 | `EEmptyUrl` | a URL is empty |

`add` also aborts with `party_link` errors (`EPlatformAlreadyAdded`, `ETooManyLinks`, `EDataTooLong`); see the
[`party_link` README](../../README.md).

## Dependencies

- [`party_link`](../../) (local path): `PartyLinks` and `add`.
- [`miso_party`](https://github.com/misofm/party-protocol) at
  `12b628fec89fd72ec96f22f709aa123658fa35db`: already a dependency of `party_link`;
  named here for the tests, which save links to a real `Party`.

## Integrator notes

- **Type name.** Match entries on the full `TypeName` string of
  `party_link_custom::party_link_custom::Custom`, with this package's published ID.
- **Decoding.** Decode the entry as `vector<CustomLink>` with fields `label` and `url`, both
  `String`, in the order the party gave them.
- **Size.** With 20 links the encoding leaves about 2000 bytes for labels and URLs together;
  long URLs mean fewer links. `EDataTooLong` comes from `party_link`.
- **Untrusted bytes.** Each URL is unchecked text. Accept only the schemes you support (`https:`, `mailto:`) and escape it when rendering.
