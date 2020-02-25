# DENV - Development environment

Set up a web development environment on Windows.

Included tools:

 - [ConEmu](https://chocolatey.org/packages/ConEmu)
 - [GIT](https://chocolatey.org/packages/git)
 - [posh-git](https://chocolatey.org/packages/poshgit)
 - [KiTTy](https://chocolatey.org/packages/kitty.portable)
 - [PHP](https://chocolatey.org/packages/php)
 - [Composer](https://getcomposer.org/)
 - [NodeJS](https://chocolatey.org/packages/nodejs.install)

## Requirements

 - PowerShell 5.0 or higher

## Installation

First, you must change execution policy for PowerShell. Run PowerShell as Administrator and call:

    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

To install dev tools, run PowerShell as Administrator and call:

    iex ((new-object net.webclient).DownloadString('https://raw.githubusercontent.com/yethee/denv/master/setup.ps1'))
