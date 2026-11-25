# party_link_discord

Discord as a [`party_link`](../../) platform. It defines the `Discord` witness and one
`add` that checks the invite code and appends it to a `PartyLinks` list under `Discord`'s
type name. Only this package can create `Discord`, so every Discord link a party stores has
passed this check.

## What it stores

None itself: `add` appends to a `PartyLinks` list that `party_link::set_links` stores.

- Input: 2 to 32 bytes of letters and digits, plus `-`.
- Stored bytes: UTF-8 bytes of the identifier as given.
- Profile URL (client convention): `https://discord.gg/{}`.

## API

### Writes

| Function | Description | Aborts |
|---|---|---|
| `add(links, invite_code)` | Check the input and append it to `links` as the party's Discord link | `EInvalidLength`, `EInvalidCharacter`, `EPlatformAlreadyAdded`, `ETooManyLinks` |

### Views

None: read links with `party_link::links`.

## Events

None: `party_link` emits `PartyLinksSetEvent` when the list is saved.

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EInvalidLength` | Not 2 to 32 bytes |
| 1 | `EInvalidCharacter` | A byte other than letters and digits or `-` |

`add` also aborts with `party_link` errors (`EPlatformAlreadyAdded`, `ETooManyLinks`); see the
[`party_link` README](../../README.md).

## Dependencies

- [`party_link`](../../) (local path): `PartyLinks` and `add`.
- [`miso_party`](https://github.com/misofm/party-protocol) at
  `12b628fec89fd72ec96f22f709aa123658fa35db`: already a dependency of `party_link`;
  named here for the tests, which save links to a real `Party`.

## Integrator notes

- **Type name.** Match entries on the full `TypeName` string of
  `party_link_discord::party_link_discord::Discord`, with this package's published ID.
- **Untrusted bytes.** Build the URL from the template above, never from the bytes alone.
