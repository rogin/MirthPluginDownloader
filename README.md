# Mirth (NextGen Connect) plugin downloader

Has the following features

- Downloads your specified version of Mirth plugins (ex. 4.2)
- Ability to limit which plugins to download
- Option to also download plugins' attachments (user guides)
- Integrates with 1Password to obtain login credentials
- Warns when your Support Level bars you from downloading a plugin

## Pre-requisites

1. PS v6+
2. module _powerhtml_

## Usage

1. Edit desired plugin version
2. Edit list of plugins to download (an empty list means all)
3. Edit $1PASS_UUID or override function ObtainCredentials to obtain login creds
4. Run Scraper.ps1, files will download into current directory
