# party_link

Where to find a party on other platforms: an ordered list of profile links, one per
platform, for a profile page that doubles as a link-in-bio page. A platform is a type:
each link is keyed by the `TypeName` of a droppable witness, and only the module that
defines the witness can create it, so the bytes under a platform's name have passed that
module's checks. Each platform package owns its own rules and errors; this package only
bounds and orders the list. Each platform is its own package in [`platforms/`](platforms), built on
this one; links go to where fans find the artist (a profile, channel or page), never to
a single song or album. The whole list is replaced on every write.

## What it stores

- Key: `PartyLinksKey()` (unit struct; one list per party).
- Value: `VecMap<TypeName, vector<u8>>`: platform witness type to that platform's
  encoded data, in display order.
- Limits: at most 50 links; each value 1 to 2048 bytes; each platform at most once.
- `set_links` replaces the list in place; an empty list removes the dynamic field
  (storage reclaimed).

## API

### Writes (cap-gated)

| Function | Description | Aborts |
|---|---|---|
| `set_links(party, cap, links)` | Replace the party's list with `links`, in its order. An empty list clears; a list equal to the stored one (same platforms, order and data) changes nothing and emits nothing | wrong cap at `miso_party::party` |

### Building a list (no cap)

| Function | Description | Aborts |
|---|---|---|
| `new(): PartyLinks` | An empty list to fill in a transaction | none |
| `add<Platform: drop>(links, witness, data)` | Append `data` under `Platform`'s type name; the witness proves it came from `Platform`'s module | `EPlatformAlreadyAdded`, `ETooManyLinks`, `EEmptyData`, `EDataTooLong` |

`PartyLinks` has `drop`: a list never passed to `set_links` writes nothing.

### Platforms

Each platform package defines a droppable witness, its own error constants, and one
`add(links, ...)` that checks the input and appends it under the witness's type name.
Platforms with an identifier check its length and characters; Merch, Website and Email
take free-form text and check nothing beyond this package's 1–2048 byte bound, since the
chain cannot tell whether a link works. For all but Custom the bytes are the UTF-8
identifier as given; Custom holds a list of labeled links, BCS-encoded as
`vector<CustomLink { label: String, url: String }>`. The URL column is the template a client
fills with the identifier (`{}`); it is a client convention, not checked on chain.

| Platform | Package | Function | Identifier | URL |
|---|---|---|---|---|
| **Streaming** | | | | |
| Spotify | [`party_link_spotify`](platforms/party_link_spotify) | `add(links, artist_id)` | 22 bytes: letters, digits | `https://open.spotify.com/artist/{}` |
| Apple Music | [`party_link_apple_music`](platforms/party_link_apple_music) | `add(links, artist_id)` | 1–20 bytes: digits | `https://music.apple.com/artist/{}` |
| YouTube Music | [`party_link_youtube_music`](platforms/party_link_youtube_music) | `add(links, channel_id)` | 24 bytes: letters, digits, `-_`; starts with `UC` | `https://music.youtube.com/channel/{}` |
| Amazon Music | [`party_link_amazon_music`](platforms/party_link_amazon_music) | `add(links, artist_id)` | 10 bytes: uppercase letters, digits | `https://music.amazon.com/artists/{}` |
| TIDAL | [`party_link_tidal`](platforms/party_link_tidal) | `add(links, artist_id)` | 1–20 bytes: digits | `https://tidal.com/artist/{}` |
| Deezer | [`party_link_deezer`](platforms/party_link_deezer) | `add(links, artist_id)` | 1–20 bytes: digits | `https://www.deezer.com/artist/{}` |
| SoundCloud | [`party_link_soundcloud`](platforms/party_link_soundcloud) | `add(links, username)` | 1–64 bytes: lowercase letters, digits, `-_` | `https://soundcloud.com/{}` |
| Audiomack | [`party_link_audiomack`](platforms/party_link_audiomack) | `add(links, username)` | 1–64 bytes: lowercase letters, digits, `-_` | `https://audiomack.com/{}` |
| **Social** | | | | |
| Instagram | [`party_link_instagram`](platforms/party_link_instagram) | `add(links, username)` | 1–30 bytes: letters, digits, `._`; not only dots | `https://www.instagram.com/{}` |
| TikTok | [`party_link_tiktok`](platforms/party_link_tiktok) | `add(links, username)` | 1–24 bytes: letters, digits, `._` | `https://www.tiktok.com/@{}` |
| YouTube | [`party_link_youtube`](platforms/party_link_youtube) | `add(links, channel_id)` | 24 bytes: letters, digits, `-_`; starts with `UC` | `https://www.youtube.com/channel/{}` |
| X | [`party_link_x`](platforms/party_link_x) | `add(links, username)` | 1–15 bytes: letters, digits, `_` | `https://x.com/{}` |
| Threads | [`party_link_threads`](platforms/party_link_threads) | `add(links, username)` | 1–30 bytes: letters, digits, `._` | `https://www.threads.com/@{}` |
| Bluesky | [`party_link_bluesky`](platforms/party_link_bluesky) | `add(links, handle)` | 3–253 bytes: letters, digits, `.-` | `https://bsky.app/profile/{}` |
| Facebook | [`party_link_facebook`](platforms/party_link_facebook) | `add(links, username)` | 1–50 bytes: letters, digits, `.`; not only dots | `https://www.facebook.com/{}` |
| Twitch | [`party_link_twitch`](platforms/party_link_twitch) | `add(links, username)` | 1–25 bytes: letters, digits, `_` | `https://www.twitch.tv/{}` |
| Discord | [`party_link_discord`](platforms/party_link_discord) | `add(links, invite_code)` | 2–32 bytes: letters, digits, `-` | `https://discord.gg/{}` |
| **Support and shop** | | | | |
| Bandcamp | [`party_link_bandcamp`](platforms/party_link_bandcamp) | `add(links, subdomain)` | 1–63 bytes: lowercase letters, digits, `-` | `https://{}.bandcamp.com` |
| Patreon | [`party_link_patreon`](platforms/party_link_patreon) | `add(links, username)` | 1–64 bytes: letters, digits, `_` | `https://www.patreon.com/{}` |
| Merch store | [`party_link_merch`](platforms/party_link_merch) | `add(links, url)` | any text | `{}` |
| **Live** | | | | |
| Bandsintown | [`party_link_bandsintown`](platforms/party_link_bandsintown) | `add(links, artist_id)` | 1–20 bytes: digits | `https://www.bandsintown.com/a/{}` |
| Songkick | [`party_link_songkick`](platforms/party_link_songkick) | `add(links, artist_id)` | 1–20 bytes: digits | `https://www.songkick.com/artists/{}` |
| **Other** | | | | |
| Website | [`party_link_website`](platforms/party_link_website) | `add(links, url)` | any text | `{}` |
| Email | [`party_link_email`](platforms/party_link_email) | `add(links, address)` | any text | `mailto:{}` |
| Custom links | [`party_link_custom`](platforms/party_link_custom) | `add(links, labels, urls)` | 1–20 pairs; each label 1–40 bytes, each URL non-empty text | none: each URL as given |

### Views

| Function | Returns |
|---|---|
| `links(party)` | `VecMap<TypeName, vector<u8>>`, a copy of the list in order; empty when none is set |

## Events

| Event | When | Payload |
|---|---|---|
| `PartyLinksSetEvent` | The list is set and differs from the stored one | `party_id: ID`, `links: vector<PartyLinkEntry { platform: String, data: vector<u8> }>`, the full list in order |
| `PartyLinksClearedEvent` | A stored list is removed by setting an empty one; not emitted when none was set | `party_id: ID` |

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `ETooManyLinks` | Adding a 51st link |
| 1 | `EEmptyData` | `data` is empty |
| 2 | `EDataTooLong` | `data` exceeds 2048 bytes |
| 3 | `EPlatformAlreadyAdded` | The platform is already in the list |

Platform packages define their own errors, listed in each package's README.

`set_links` also surfaces `EUnauthorized` (0) at `miso_party::party` on a wrong cap.

## Dependencies

- [`miso_party`](https://github.com/misofm/party-protocol) at
  `12b628fec89fd72ec96f22f709aa123658fa35db`: the `Party` authorization core.

## Integrator notes

- **One transaction per save.** In a PTB: `party_link::new()`, then each link's platform
  `add(links, ...)` in display order, then `set_links`. Adding, removing and reordering
  are all the same save.
- **Show only what you support.** Any droppable type can key a link, including ones from
  packages an app has never seen; a new platform is a new package, with no change here. Render
  the type names you know and skip the rest; the admin removes them by saving without.
- **Event entries are read off-chain.** `PartyLinkEntry` has no `store` and no public
  getters: it exists only inside `PartyLinksSetEvent`. On-chain code reads `links(party)`.
- **Type names are full.** `platform` is `TypeName::into_string()` of the witness: the
  platform package's ID without `0x`, then e.g. `::party_link_spotify::Spotify`. Match
  the whole string.
- **Indexers replace, never merge.** Each `PartyLinksSetEvent` carries the complete list
  in order; `PartyLinksClearedEvent` empties it.
- **One entry per platform.** Each platform appears at most once; Custom carries several
  labeled links in its one entry. Website and Merch hold one URL each.
- **Popular platforms with stable identifiers only.** Platforms whose artist URLs carry
  no stable ID (a slug or region beside it) are left out.
- **Rules are loose on purpose.** Checks are lengths and character sets, not each
  platform's current handle policy; they keep out mistakes and anything that could break
  a URL. A value can still name one of a platform's own routes (`instagram.com/explore`);
  check a link resolves before saving.
- **Data is untrusted bytes.** Build URLs from your own templates. Website, Merch, Email
  and Custom's URL are unchecked text: accept only the schemes you support (`https:`,
  `mailto:`) and escape them when rendering.
