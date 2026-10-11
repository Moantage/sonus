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

Good for small libraries and music you have the rights to share.

- Commit the audio and `sonus.json`, then use the raw URL:
  `https://raw.githubusercontent.com/<owner>/<repo>/<branch>/sonus.json`.
- GitHub limits file sizes and bandwidth, and Git LFS has its own quotas. Large libraries belong in a
  bucket or on a NAS.
- Private repositories need a token. That's planned and will follow the same Keychain rules.

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
