# Mirth (NextGen Connect) plugin downloader

Downloads NextGen's commercial plugins from their site.

Has the following features

- Downloads your specified version of Mirth plugins (ex. 4.2)
- Ability to limit which plugins to download
- Option to also download plugins' attachments (user guides)
- Integrates with 1Password to obtain login credentials
- Warns when your Support Level bars you from downloading a plugin

## Pre-requisites

1. PS v6+
1. module _powerhtml_
1. module SalesForceLogin
1. An active NextGen subscription

## Usage

1. Set desired plugin version
1. Set list of plugins to download (an empty list means all)
1. Set Support Level
1. Set $IncludeAttachments toggling the additional download of the plugins' user guides
1. Set $1PASS_UUID _or_ override function ObtainCredentials to provide your NextGen login creds
1. Run Scraper.ps1, files will download into current directory
