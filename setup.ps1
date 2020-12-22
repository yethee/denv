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

function Install-PHP([string] $version) {
    $phpVer = [System.Version]::new($version)
    $installPath = Join-Path $env:ChocolateyToolsLocation "php$($phpVer.Major)$($phpVer.Minor)"

    choco install php -my --version $version --params "/InstallDir:${installPath}"

    $phpIniFile = Join-Path $installPath 'php.ini'

    if (-not (Test-Path $phpIniFile)) {
         Copy-Item (Join-Path $installPath 'php.ini-development') -Destination $phpIniFile
    }

    (Get-Content (Join-Path $installPath 'php.ini-development')) |
        ForEach-Object { $_ -replace ';(date.timezone =)', '$1 Europe/Moscow' } |
        ForEach-Object { $_ -replace '^(memory_limit =)(.+)$', '$1 512M' } |
        ForEach-Object { $_ -replace ';\s*(extension_dir = "ext")', '$1' } |
        ForEach-Object { $_ -replace ';(extension=curl)', '$1' } |
        ForEach-Object { $_ -replace ';(extension=fileinfo)', '$1' } |
        ForEach-Object { $_ -replace ';(extension=gd2)', '$1' } |
        ForEach-Object { $_ -replace ';(extension=intl)', '$1' } |
        ForEach-Object { $_ -replace ';(extension=mbstring)', '$1' } |
        ForEach-Object { $_ -replace ';(extension=exif)', '$1' } |
        ForEach-Object { $_ -replace ';(extension=openssl)', '$1' } |
        ForEach-Object { $_ -replace ';(extension=pdo_mysql)', '$1' } |
        ForEach-Object { $_ -replace ';(extension=pdo_pgsql)', '$1' } |
        ForEach-Object { $_ -replace ';(extension=pdo_sqlite)', '$1' } |
        ForEach-Object { $_ -replace ';(extension=soap)', '$1' } |
        ForEach-Object { $_ -replace ';(extension=sockets)', '$1' } |
        ForEach-Object { $_ -replace ';(extension=sodium)', '$1' } |
        ForEach-Object { $_ -replace ';(extension=xsl)', '$1' } |
        Set-Content $phpIniFile

    # Setup curl

    $cacertFile = Join-Path $installPath 'extras/cacert.pem'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri "https://curl.haxx.se/ca/cacert.pem" -OutFile $cacertFile
    (Get-Content $phpIniFile) -replace ';curl.cainfo =', "curl.cainfo = ${cacertFile}" | Set-Content $phpIniFile

    # Install xdebug extension

    $extensionFile = (Join-Path $installPath 'ext\php_xdebug.dll')
    $extensionUrl = "https://xdebug.org/files/php_xdebug-3.0.1-$($phpVer.Major).$($phpVer.Minor)-vc15-nts.dll"
    if (Get-ProcessorBits 64) {
        $extensionUrl = "https://xdebug.org/files/php_xdebug-3.0.1-$($phpVer.Major).$($phpVer.Minor)-vc15-nts-x86_64.dll"
    }

    Write-Host "Download ${extensionUrl} to ${extensionFile}"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $extensionUrl -OutFile $extensionFile

    Add-LineToFile $phpIniFile 'zend_extension=xdebug'

    # Install amqp extension
    if ($phpVer -lt [System.Version]"8.0") {
        $tmpFile = Download-ExtensionFromPECL "amqp" "1.10.2" $phpVer
        Install-PECLFromFile $tmpFile "amqp" "${installPath}\ext" $phpIniFile

        $rmqLibFile = "rabbitmq.4.dll"

        $zip = [System.IO.Compression.ZipFile]::OpenRead($tmpFile)
        $zip.Entries |
            Where-Object { $_.FullName -like $rmqLibFile } |
            ForEach-Object {
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($_, "${installPath}\${rmqLibFile}", $true)
            }
        $zip.Dispose()

        Remove-Item $tmpFile
    }

    # Install ds extension
    $tmpFile = Download-ExtensionFromPECL "ds" "1.3.0" $phpVer
    Install-PECLFromFile $tmpFile "ds" "${installPath}\ext" $phpIniFile
    Remove-Item $tmpFile

    # Install pdo_sqlsrv extension
    $tmpFile = Download-ExtensionFromPECL "pdo_sqlsrv" "5.8.1" $phpVer
    Install-PECLFromFile $tmpFile "pdo_sqlsrv" "${installPath}\ext" $phpIniFile
    Remove-Item $tmpFile
}

function Download-ExtensionFromPECL([string] $extName, [string] $extVersion, [System.Version] $phpVersion) {
    $tmpFile = New-TemporaryFile

    $extensionUrl = "https://windows.php.net/downloads/pecl/releases/${extName}/${extVersion}/php_${extName}-${extVersion}-$($phpVersion.Major).$($phpVersion.Minor)-nts-vc15-x86.zip"
    if (Get-ProcessorBits 64) {
        $extensionUrl = "https://windows.php.net/downloads/pecl/releases/${extName}/${extVersion}/php_${extName}-${extVersion}-$($phpVersion.Major).$($phpVersion.Minor)-nts-vc15-x64.zip"
    }

    Write-Host "Download ${extensionUrl} to ${tmpFile}"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $extensionUrl -OutFile $tmpFile

    return $tmpFile
}

function Install-PECLFromFile([string] $zipFile, [string] $extName, [string] $installPath, [string] $phpIniFile) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $extensionFile = "php_${extName}.dll"

    $zip = [System.IO.Compression.ZipFile]::OpenRead($zipFile)
    $zip.Entries |
        Where-Object { $_.FullName -like $extensionFile } |
        ForEach-Object {
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($_, "${installPath}\${extensionFile}", $true)
        }
    $zip.Dispose()

    Add-LineToFile $phpIniFile  "extension=${extName}"
}

function Test-ContentInFile([string] $path, [string] $content) {
    if (!(Test-Path -LiteralPath $path)) {
        return $false
    }

    $match = (@(Get-Content $path -ErrorAction SilentlyContinue) -match $content).Count -gt 0
    return $match
}

function Add-LineToFile([string] $path, [string] $content) {
    if (Test-ContentInFile $path $content) {
        return
    }

    Add-Content $path -Value $content
}

if (-not $env:ChocolateyInstall -or -not (Test-Path "$env:ChocolateyInstall")) {
    iex ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1'))
}

Import-Module "$env:ChocolateyInstall\helpers\chocolateyInstaller.psm1" -Force

if (Install-NeededFor 'ConEmu' $false) {
    choco install conemu -y
}

choco install openssh -y --pre -params '"/SSHAgentFeature"'
choco install git -y --params="/GitAndUnixToolsOnPath /NoAutoCrlf"

Update-SessionEnvironment

Write-Host 'Configuring git...'

Write-Host 'Set your user name and email address. This is important'
Write-Host 'because every Git commit uses this information.'
Set-GitConfig 'user.name' $null 'Please, enter your name'
Set-GitConfig 'user.email' $null 'Please, enter your email'

Set-GitConfig 'core.autocrlf' 'input'
Set-GitConfig 'core.eol' 'lf'

$sshPath = (Get-Command ssh -ErrorAction SilentlyContinue).Path

if (Test-Path $sshPath) {
    Set-GitConfig 'core.sshCommand' "'${sshPath}'"
}

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
    PowerShellGet\Install-Module posh-git -Scope CurrentUser -AllowPrerelease -Force
    Add-PoshGitToProfile
}

if (Install-NeededFor 'KiTTy' $false) {
    choco install kitty -y
}

if (Install-NeededFor 'PHP' $true) {
    choco install sqlserver-odbcdriver -y

    Install-PHP "7.3.25"
    Install-PHP "7.4.13"

    Write-Host "Installing composer..."
    choco install composer -y
}

if (Install-NeededFor 'NodeJS' $true) {
    choco install nodejs-lts -y
}

if (Install-NeededFor 'Python' $true) {
    $installPath = Join-Path $env:ChocolateyToolsLocation "python38"

    choco install python3 -y --version 3.8.6 --params "/InstallDir:${installPath}"
    python -m pip install --upgrade pip
    Update-SessionEnvironment
    pip install pipenv

    $profilePath = $PROFILE.CurrentUserCurrentHost
    Write-Verbose "`$profilePath = '$profilePath'"

    if (!(Test-ContentInFile $profilePath '\$env:PIPENV_VENV_IN_PROJECT=')) {
        Add-Content -LiteralPath $profilePath -Value "`n`$env:PIPENV_VENV_IN_PROJECT=1" -Encoding UTF8
    }

    if (!(Test-ContentInFile $profilePath 'if \(\$env:PIPENV_ACTIVE -eq "1"\) {')) {
        $profileContent = @"

if (`$env:PIPENV_ACTIVE -eq `"1`") {
  `$GitPromptSettings.DefaultPromptPrefix.Text = `"(pipenv) `"
  `$GitPromptSettings.DefaultPromptPrefix.ForegroundColor = [ConsoleColor]::Blue
}
"@
        Add-Content -LiteralPath $profilePath -Value $profileContent -Encoding UTF8
    }
}
