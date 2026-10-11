---
title: OpenSubsonic servers
description: Use Sonus with Navidrome, Gonic, Ampache and other Subsonic-compatible servers.
---

# OpenSubsonic servers

Plenty of people already run a music server on their NAS. Rather than asking them to switch, Sonus
speaks the [OpenSubsonic API](https://opensubsonic.netlify.app/), which most self-hosted music
servers implement, including:

- [Navidrome](https://www.navidrome.org/)
- [Gonic](https://github.com/sentriz/gonic)
- [Ampache](https://ampache.org/)
- Airsonic-Advanced, LMS and Nextcloud Music

## Connecting (planned)

1. In Sonus, choose **Add music → Music server**.
2. Enter the server address, username and password.
3. Sonus uses token authentication (a salted hash), so the password itself isn't sent with every
   request. Credentials stay in the iPhone Keychain.

## What Sonus uses

| Feature | OpenSubsonic endpoints |
|---|---|
| Library | `getArtists`, `getArtist`, `getAlbum`, `getAlbumList2` |
| Playlists | `getPlaylists`, `getPlaylist` |
| Search | `search3` |
| Streaming and downloads | `stream` (with `maxBitRate` for cellular quality), `download` |
| Artwork | `getCoverArt` |

:::note Status
OpenSubsonic support is in development. This page will list tested servers and versions once it
ships.
:::
