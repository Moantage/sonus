---
slug: /
sidebar_position: 1
title: What is Sonus?
description: An open-source iOS music player that streams or downloads music from servers you own.
---

# Sonus

Sonus is an open-source iPhone music player for music **you already host**: on a NAS, in an AWS or
Google Cloud bucket, in a GitHub repository or on your own server. Point Sonus at it and either
**stream** songs directly or **download** them for offline play.

The player deliberately feels like the streaming apps people already know: a mini-player that
follows you, a library with filters, and a one-tap download toggle on every playlist. There's
nothing new to learn; the only difference is that the music comes from your servers.

## How Sonus reads your music

| You have… | Use | What you host |
|---|---|---|
| Files in a bucket, a GitHub repo or any web server | [Sonus Manifest](/spec/manifest) | A `sonus.json` file next to your audio |
| A server you're building yourself | [Sonus Server API](/server-api/sonus-server-api) | A small REST API |
| Navidrome, Gonic, Ampache or another Subsonic-style server | [OpenSubsonic](/compatibility/opensubsonic) | Nothing new; Sonus talks to it directly |
| Files on your phone, iCloud Drive or an SMB share mounted in Files | The Files app import | Nothing |

## Project status

:::caution Draft
The spec on this site is **version 1.0-draft** and may still change. Today's app imports from the
Files app. Support for manifests, the Server API and OpenSubsonic is being built and will ship in
upcoming releases. The [changelog](/changelog) tracks every change.
:::

## Open source

The app, the spec and this site live in one repository:
[github.com/Moantage/sonus](https://github.com/Moantage/sonus). The spec files in `spec/` are the
single source of truth: the reference pages here are generated from them on every merge, and the
app's tests run against the same example files.
