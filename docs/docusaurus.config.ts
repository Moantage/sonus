import {themes as prismThemes} from 'prism-react-renderer';
import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';
import type * as OpenApiPlugin from 'docusaurus-plugin-openapi-docs';

// This runs in Node.js - Don't use client-side code here (browser APIs, JSX...)
//
// Content that is generated before every build (see scripts/prepare-content.mjs, gitignored):
//   .generated/openapi.yaml   ← bundled from ../spec/openapi.yaml
//   docs/server-api/          ← API reference pages generated from that bundle
//   static/schemas, static/examples ← copied from ../spec
//   src/pages/changelog.md    ← copied from ../CHANGELOG.md

const repoUrl = 'https://github.com/Moantage/sonus';

const config: Config = {
  title: 'Sonus',
  tagline: 'Stream or download music from your own servers, in a player that already feels familiar.',
  favicon: 'img/favicon.svg',

  future: {
    v4: true,
  },

  url: 'https://moantage.github.io',
  baseUrl: '/sonus/',
  organizationName: 'Moantage',
  projectName: 'sonus',
  trailingSlash: false,

  onBrokenLinks: 'throw',
  onBrokenAnchors: 'throw',
  markdown: {
    hooks: {
      onBrokenMarkdownLinks: 'throw',
    },
  },

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      {
        docs: {
          routeBasePath: '/',
          sidebarPath: './sidebars.ts',
          editUrl: `${repoUrl}/edit/main/docs/`,
          docItemComponent: '@theme/ApiItem',
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  plugins: [
    [
      'docusaurus-plugin-openapi-docs',
      {
        id: 'api',
        docsPluginId: 'classic',
        config: {
          sonus: {
            specPath: '.generated/openapi.yaml',
            outputDir: 'docs/server-api',
            // Servers are user-hosted, so "try it" requests from the browser can't reach them.
            hideSendButton: true,
            sidebarOptions: {
              groupPathsBy: 'tag',
              categoryLinkSource: 'tag',
            },
          } satisfies OpenApiPlugin.Options,
        },
      },
    ],
  ],

  themes: ['docusaurus-theme-openapi-docs'],

  themeConfig: {
    colorMode: {
      defaultMode: 'dark',
      respectPrefersColorScheme: true,
    },
    navbar: {
      title: 'Sonus',
      logo: {
        alt: 'Sonus waveform mark',
        src: 'img/logo.svg',
      },
      items: [
        {type: 'docSidebar', sidebarId: 'docs', position: 'left', label: 'Docs'},
        {to: '/spec/manifest', label: 'Manifest spec', position: 'left'},
        {to: '/server-api/sonus-server-api', label: 'Server API', position: 'left'},
        {to: '/changelog', label: 'Changelog', position: 'right'},
        {href: repoUrl, label: 'GitHub', position: 'right'},
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Spec',
          items: [
            {label: 'Sonus Manifest', to: '/spec/manifest'},
            {label: 'Server API', to: '/server-api/sonus-server-api'},
            {label: 'OpenSubsonic', to: '/compatibility/opensubsonic'},
          ],
        },
        {
          title: 'Project',
          items: [
            {label: 'Contributing', to: '/contributing'},
            {label: 'Privacy', to: '/privacy'},
            {label: 'Changelog', to: '/changelog'},
          ],
        },
        {
          title: 'Source',
          items: [{label: 'GitHub', href: repoUrl}],
        },
      ],
      copyright: `Sonus by Novora Labs. Code under Apache-2.0.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ['bash', 'json', 'yaml'],
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
