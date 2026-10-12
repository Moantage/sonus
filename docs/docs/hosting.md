---
sidebar_position: 2
title: Host your music
description: Put your library somewhere Sonus can reach it, from a bucket to a NAS.
---

# Host your music

Anything that can serve files over HTTPS can host a Sonus library. Put a
[Sonus Manifest](/spec/manifest) (`sonus.json`) next to your audio files, then add the manifest's URL
in the app.

:::tip Seeking and resuming need range requests
Sonus streams with HTTP range requests, so it can seek and resume downloads. Every host below
supports them out of the box.
:::

## AWS S3 and S3-compatible storage

Works with AWS S3, Cloudflare R2, Backblaze B2, Wasabi and MinIO.

1. Upload your audio files and `sonus.json` to a bucket, keeping the paths the manifest uses.
2. **Public library:** allow public reads on the objects (or put CloudFront in front) and add
   `https://<bucket>.s3.<region>.amazonaws.com/sonus.json` in the app.
3. **Private library:** keep the bucket private. Native S3 sign-in with access keys stored in the
   iPhone Keychain is planned; until then, use a public bucket or a server that issues tokens.

## Google Cloud Storage

1. Upload the audio and `sonus.json` to a bucket.
2. **Public library:** grant `allUsers` the *Storage Object Viewer* role and use
   `https://storage.googleapis.com/<bucket>/sonus.json`.
3. **Private library:** planned, using HMAC interoperability keys (same as S3).

## GitHub

Good for small libraries and music you have the rights to store there. Add a repository as
`owner/repo`, optionally with a branch (`owner/repo@main`) and a folder inside it.

- **No setup needed.** Sonus lists every playable audio file in the repository (MP3, M4A/AAC,
  FLAC, WAV, AIFF and CAF) and uses its path as the track's ID. Titles come from file names until
  Sonus has read each file's own tags.
- **With a manifest.** Put a `sonus.json` at the root, or in the folder you picked, to set titles,
  artists, albums and order. Relative track URLs resolve inside the repository.
- **Git LFS works.** Sonus recognises LFS pointer files and streams the real audio from GitHub's
  media host.
- **Public repositories** need nothing else. You can also add a public manifest's raw URL,
  `https://raw.githubusercontent.com/<owner>/<repo>/<branch>/sonus.json`, as a manifest source.

### Private repositories

Private repositories work with a **fine-grained personal access token** that can read only that
repository:

1. On GitHub, open **Settings → Developer settings → Personal access tokens → Fine-grained tokens**
   and choose **Generate new token**.
2. Under **Repository access**, choose **Only select repositories** and pick your music repository.
3. Under **Repository permissions**, set **Contents** to **Read-only**. Leave everything else at
   *No access*.
4. Pick an expiry date. When the token expires, Sonus tells you; create a new one the same way.

Sonus keeps the token in the iPhone Keychain and sends it only to `api.github.com`,
`raw.githubusercontent.com` and `media.githubusercontent.com`. See
[Privacy and security](/privacy).

### Limits

- GitHub caps files at 100 MB and limits bandwidth, and Git LFS has its own storage and bandwidth
  quotas. Large libraries belong in a bucket or on a NAS.
- GitHub's API allows 60 requests an hour without a token and 5,000 with one. If you hit the limit,
  Sonus tells you when to try again.
- GitHub's terms apply to private repositories too, so only store music you have the rights to.

## NAS or your own server

- **Running Navidrome, Gonic, Ampache or another Subsonic-style server?** Skip the manifest and
  connect with [OpenSubsonic](/compatibility/opensubsonic).
- **Plain web server** (Synology Web Station, nginx, Caddy): serve your music folder plus a
  `sonus.json`.
- **Building your own?** Implement the [Sonus Server API](/server-api/sonus-server-api).

On your home network, `http://` addresses such as `http://192.168.1.20` are allowed. Anything
reachable from the internet must use `https://`.

## Generating `sonus.json`

A command-line tool that scans a folder, reads the tags and writes `sonus.json` is planned. Until
then, write the file by hand or with a script, and check it against the
[JSON Schema](pathname:///sonus/schemas/v1/manifest.schema.json).
