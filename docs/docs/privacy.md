---
title: Privacy and security
description: What Sonus does with your servers, credentials and listening data.
---

# Privacy and security

Self-hosting your music is about keeping control of it. These are Sonus's commitments.

## Your servers and credentials

- Server addresses, passwords, tokens and access keys are stored **only in the iPhone Keychain**.
- They're sent **only to the server they belong to**, never to Novora Labs, Firebase or any
  analytics service.
- Your music files go straight from your server to your phone. They never pass through our
  infrastructure.

## Your Sonus account

The official app asks you to sign in. The account holds:

- your profile and plan (free or Premium)
- with Premium, the data needed to sync your library layout across your devices

Source lists synced to your account never include passwords, tokens or keys.

## Networking rules

- Remote servers must use `https://`.
- Plain `http://` is only allowed for addresses on your local network, e.g. a NAS at home.

## Reporting a vulnerability

Please don't open a public issue. Use GitHub's
[private vulnerability reporting](https://github.com/Moantage/sonus/security/advisories/new).
