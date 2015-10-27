function Install-NeededFor {
param(
    [string] $packageName = ''
    ,[bool] $defaultAnswer = $true
)
    if ($packageName -eq '') {
        return $false
    }

    $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

    $question = "Do you need to install $($packageName)?"
    $decision = $Host.UI.PromptForChoice("Install $packageName", $question, $choices, (1, 0)[$defaultAnswer])

    if ($decision -eq 0) {
        Write-Host "Installing $packageName"
        return $true
    }

    Write-Host "Not installing $packageName"
    return $false
}

function Set-GitConfig($key, $defaultValue, $prompt) {
    $value = git config --global $key | Out-String
    $value = $value.Trim("`n", "`r", " ")

    while (!$value) {
        if ($prompt) {
            $value = Read-Host $prompt
        }
        
        if (!$value -and $defaultValue) {
            $value = $defaultValue
        }
    }

    git config --global $key $value
}

if (-not $env:ChocolateyInstall -or -not (Test-Path "$env:ChocolateyInstall")) {
    iex ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1'))
}

# Import chocolatey's helpers
Get-Item $env:ChocolateyInstall\helpers\functions\*.ps1 |
  ? { -not ($_.Name.Contains(".Tests.")) } |
    % {
	  . $_.FullName;
    }


if (Install-NeededFor 'ConEmu' $true) {
    choco install conemu -y
}

if (Install-NeededFor 'cwRsync' $false) {
    choco install cwrsync -y
}

choco install git --params="/GitAndUnixToolsOnPath /NoAutoCrlf" -y

Update-SessionEnvironment

Write-Host 'Configuring git...'

Write-Host 'Set your user name and email address. This is important'
Write-Host 'because every Git commit uses this information.'
Set-GitConfig 'user.name' $null 'Please, enter your name'
Set-GitConfig 'user.email' $null 'Please, enter your email'

Set-GitConfig 'core.autocrlf' 'input'
Set-GitConfig 'core.eol' 'lf'

$gitIgnoreFile = '~/.gitignore'
if (!(Test-Path $gitIgnoreFile)) {
    Add-Content $gitIgnoreFile '# Windows image file caches'
    Add-Content $gitIgnoreFile 'Thumbs.db'
    Add-Content $gitIgnoreFile 'ehthumbs.db'
    Add-Content $gitIgnoreFile '# Folder config file'
    Add-Content $gitIgnoreFile 'Desktop.ini'
    Add-Content $gitIgnoreFile '# IDE files'
    Add-Content $gitIgnoreFile '.idea/'

    Set-GitConfig 'core.excludesfile' $gitIgnoreFile
}

if (Install-NeededFor 'posh-git' $true) {
    choco install poshgit -y
}

if (Install-NeededFor 'KiTTy' $false) {
    choco install kitty.portable -y
}

if (Install-NeededFor 'PHP' $true) {
    choco install vcredist2012 -y
    choco install php -y

    $phpPath = Join-Path $(Get-BinRoot) 'php'
    Install-ChocolateyPath $phpPath

    $phpIni = Join-Path $phpPath 'php.ini'

    if (!(Test-Path $phpIni)) {
        Write-Host 'Configuring php...'
        (Get-Content (Join-Path $phpPath 'php.ini-development')) |
            ForEach-Object { $_ -Replace ';(date.timezone =)', '$1 Europe/Moscow' } |
            ForEach-Object { $_ -Replace ';\s*(extension_dir = "ext")', '$1' } |
            ForEach-Object { $_ -Replace ';(extension=php_curl.dll)', '$1' } |
            ForEach-Object { $_ -Replace ';(extension=php_gd2.dll)', '$1' } |
            ForEach-Object { $_ -Replace ';(extension=php_intl.dll)', '$1' } |
            ForEach-Object { $_ -Replace ';(extension=php_mbstring.dll)', '$1' } |
            ForEach-Object { $_ -Replace ';(extension=php_openssl.dll)', '$1' } |
            ForEach-Object { $_ -Replace ';(extension=php_pdo_mysql.dll)', '$1' } |
            ForEach-Object { $_ -Replace ';(extension=php_pdo_pgsql.dll)', '$1' } |
            ForEach-Object { $_ -Replace ';(extension=php_pdo_sqlite.dll)', '$1' } |
            ForEach-Object { $_ -Replace ';(extension=php_soap.dll)', '$1' } |
            ForEach-Object { $_ -Replace ';(extension=php_sqlite3.dll)', '$1' } |
            Set-Content $phpIni
    }

    Write-Host "Installing composer..."
    $composerPath = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'composer'
    $installer = Join-Path $composerPath 'installer.php'

    if (-not (Test-Path $composerPath)) {
        New-Item -Path $composerPath -ItemType Directory | Out-Null
    }

    (New-Object Net.WebClient).DownloadString('https://getcomposer.org/installer') | Out-File -Encoding utf8 $installer
    php $installer --install-dir=$composerPath | Out-Null
    
    Install-ChocolateyPath $composerPath
    Install-ChocolateyPath (Join-Path $env:APPDATA 'Composer\vendor\bin') 

    "@ECHO OFF
php ""%~dp0composer.phar"" %*" | Out-File -Encoding ASCII (Join-Path $composerPath 'composer.bat')

    Remove-Item $installer

    if (Install-NeededFor 'PHPUnit' $false) {
        composer global require "phpunit/phpunit=~4.8"
        composer global require "phpunit/dbunit=~1.4"
    }
}

if (Install-NeededFor 'NodeJS' $true) {
    choco install nodejs.install -y

    npm install gulp -g
}
