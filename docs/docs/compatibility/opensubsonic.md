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

## Connecting

1. In Sonus, open **Your Library**, tap **+** and choose **Music server**. You can also use
   **Profile → Music sources → Connect a music server**.
2. Enter the server address, username and password. `music.example.com` means `https://`; a home
   network address such as `192.168.1.20:4533` or `nas.local:4533` may use plain `http`. A server
   in a sub-folder works too, for example `https://example.com/navidrome`.
3. Sonus checks the sign-in, lists the library and adds every song. Nothing is saved if the server
   can't be read.

Sonus uses token authentication (a salted MD5 hash of the password, as the Subsonic API requires),
so the password itself is never sent. The username and password stay in the iPhone Keychain, and
the token goes only to the server's own host. Stream URLs saved in your library carry no
credentials; Sonus adds a fresh token to each request.

Servers that check passwords with LDAP often can't accept token authentication (error 41); Sonus
says so when you connect.

To refresh or remove a server, open **Profile → Music sources** and tap it. Removing a server
removes its songs and their downloads from Sonus; nothing changes on the server. Sonus also
refreshes each server in the background when it's more than 12 hours old.

## What Sonus uses

| Feature | OpenSubsonic endpoints |
|---|---|
| Sign-in check | `ping` |
| Library | `getAlbumList2` (500 albums per page), then `getAlbum` for each album |
| Streaming and downloads | `stream` with `format=raw`, so seeking uses byte ranges on the original file |
| Formats iOS can't play (OGG, Opus, WMA, ...) | `stream` with `format=mp3`; the server converts while streaming |
| Artwork | `getCoverArt` |

Playlists (`getPlaylists`), server-side search (`search3`) and a lower bit rate on cellular
(`maxBitRate`) are planned.

:::note Status
OpenSubsonic support is new. It's tested against a server that follows the API documentation;
reports from Navidrome, Gonic, Ampache and other servers are welcome as GitHub issues.
:::
