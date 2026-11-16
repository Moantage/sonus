---
title: Privacy policy
description: What the Sonus app collects, why, who processes it, how long it's kept and your rights.
---

# Privacy policy

**Version 1.1 · Last updated 16 November 2026**

This policy covers the official Sonus app for iPhone and iPod touch. Sonus is free: it has no ads,
no in-app purchases, no analytics and no tracking.

## Who is responsible for your data

The data controller is **Dhruva Bisht, trading as Novora Labs**, Dublin, Ireland.

For any privacy question, or to use your rights below, email
**[novoralabs+support@protonmail.com](mailto:novoralabs+support@protonmail.com)**.

## What we collect, and why

You need a Sonus account to use the official app. We collect only what the account and its
features need.

| Data | Where it comes from | Why |
| --- | --- | --- |
| Name | You, or Apple/Google when you sign in with them | To show your profile |
| Email address | You, or Apple/Google when you sign in with them | To sign you in and recover your account |
| Phone number, if you add one | You | To sign you in by text message. We store only a salted hash and the last 4 digits; the full number is held by Firebase Authentication |
| Sign-in methods (Apple, Google, email, phone) and a user ID | Created when you sign up | To run your account |
| Profile photo link, if Google provides one | Google | To show your profile |
| Your profile banner choice | You | To show your profile |
| When you accepted these terms, and which version | The app | To record your agreement |
| Your library and playlists, only when you tap **Sync across devices** | You | To sync your library between your devices |

The synced library holds your songs' details (title, artist, album, file name, length and when you
added it), your playlists, and the addresses of your music sources and cover art. It never
includes passwords, tokens or access keys, which are removed from addresses before syncing.

We **don't** collect: advertising identifiers, location, contacts, browsing history, usage
analytics or crash reports. Your music files are never uploaded to us.

### Legal bases (GDPR)

- **Performance of a contract:** creating and running your account, signing you in, and syncing
  your library when you ask.
- **Legitimate interests:** keeping the service secure and preventing abuse.
- **Legal obligation:** where the law requires us to keep or disclose data.

## What stays on your device

These never leave your iPhone or iPod touch, except to the server they belong to:

- Passwords, tokens and access keys for your music sources, stored **only in the iOS Keychain**.
  They're never synced, logged or written to files.
- Songs you import or download, and your app settings.

### Your servers and credentials

- A token is sent **only to the server it belongs to**, never to Novora Labs, Firebase or any
  analytics service:
  - a **GitHub token** goes only to `api.github.com`, `raw.githubusercontent.com` and
    `media.githubusercontent.com`;
  - any other token goes only to the host of the source it was added for;
  - if a server redirects a request to another host, Sonus drops the token from it.
- Your music goes straight from your server to your device. It never passes through our
  infrastructure.
- Remote servers must use `https://`. Plain `http://` is only allowed for addresses on your local
  network, such as a NAS at home, and tokens are only sent over `https://` or to your local
  network.

## Who processes your data

We don't sell your data or share it for advertising. These processors run parts of the service
for us, under their own terms and data-protection agreements:

- **Google (Firebase Authentication and Cloud Firestore):** stores your account and profile, and
  your synced library. Firebase may also process technical data such as your IP address to sign
  you in securely.
- **Google Sign-In** and **Sign in with Apple**, if you choose them: they confirm who you are and
  share your name and email with us.
- **Apple**, which distributes the app through the App Store and TestFlight. If you've allowed it
  in iOS settings, Apple may share anonymous crash reports and app analytics with us under Apple's
  own privacy policy.

### International transfers

Our processors may handle data on servers outside the European Economic Area. Those transfers are
covered by appropriate safeguards, such as the European Commission's Standard Contractual Clauses.

## How long we keep it

We keep your data while your account exists. When you delete your account (**Profile → Delete
account**), the app deletes your profile, your synced library and your sign-in account straight
away. Our processors may keep residual copies in their backups for a short time under their own
retention rules. We keep data longer only if the law requires it.

## Your rights

Under the GDPR you can ask us to:

- give you a copy of your data, including in a portable format;
- correct it;
- delete it;
- restrict or object to how we process it.

Email us at the address above, and we'll reply within one month. You can also delete your account
yourself in the app at any time.

You have the right to complain to a data protection authority. In Ireland that's the
[Data Protection Commission](https://www.dataprotection.ie).

## Children

Sonus isn't directed at children under 16, and we don't knowingly collect their data. If you think
a child has given us data, email us and we'll delete it.

## Changes to this policy

If we change this policy in a way that matters, we'll update the version and date above, and the
app will ask you to accept the new version.

## Reporting a security vulnerability

Please don't open a public issue. Use GitHub's
[private vulnerability reporting](https://github.com/Moantage/sonus/security/advisories/new).
