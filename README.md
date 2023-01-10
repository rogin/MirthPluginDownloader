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
2. module _powerhtml_
3. An active NextGen subscription

## Usage

1. Edit desired plugin version
2. Edit list of plugins to download (an empty list means all)
3. Edit $IncludeAttachments toggling the additional download of the plugins' user guides
4. Edit $1PASS_UUID _or_ override function ObtainCredentials to provide your login creds
5. Run Scraper.ps1, files will download into current directory
