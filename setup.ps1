function Install-NeededFor {
    param(
        [String] $PackageName,
        [Bool] $DefaultAnswer = $true
    )

    $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

    $question = "Do you need to install ${PackageName}?"
    $decision = $Host.UI.PromptForChoice("Install ${PackageName}", $question, $choices, (1, 0)[$DefaultAnswer])

    if ($decision -eq 0) {
        Write-Host "Installing ${PackageName}"
        return $true
    }

    Write-Host "Not installing ${PackageName}"
    return $false
}

function Set-GitConfig {
    param(
        [String] $Key,
        [AllowNull()]
        [String] $DefaultValue,
        [String] $Prompt
    )

    $value = git config --global $Key | Out-String
    $value = $value.Trim("`n", "`r", " ")

    while (!$value) {
        if ($Prompt) {
            $value = Read-Host $Prompt
        }

        if (!$value -and $DefaultValue) {
            $value = $DefaultValue
        }
    }

    git config --global $Key $value
}

function Install-PHP {
    param(
        [String] $Version
    )

    $phpVer = [System.Version]::new($Version)
    $installPath = Join-Path $env:ChocolateyToolsLocation "php$($phpVer.Major)$($phpVer.Minor)"

    choco install php -my --version $Version --force --params "/InstallDir:${installPath} /DontAddToPath"

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
    $archPart = ""

    if (Get-ProcessorBits 64) {
        $archPart = "-x86_64"
    }

    if ($phpVer -ge [System.Version]"8.0") {
        $extensionUrl = "https://xdebug.org/files/php_xdebug-3.3.2-$($phpVer.Major).$($phpVer.Minor)-vs16-nts${archPart}.dll"
    } else {
        $extensionUrl = "https://xdebug.org/files/php_xdebug-3.1.6-$($phpVer.Major).$($phpVer.Minor)-vc15-nts${archPart}.dll"
    }

    Write-Host "Download ${extensionUrl} to ${extensionFile}"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $extensionUrl -OutFile $extensionFile

    Add-LineToFile $phpIniFile 'zend_extension=xdebug'

    # Install amqp extension
    if ($phpVer -lt [System.Version]"8.4") {
        $extensionVersion = $phpVer -ge [System.Version]"8.0" ? "2.1.2" : "1.11.0"

        $tmpFile = Download-ExtensionFromPECL "amqp" $extensionVersion $phpVer
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

    # Install pdo_sqlsrv extension
    if ($phpVer -lt [System.Version]"8.2") {
        $extensionVersion = $phpVer -ge [System.Version]"7.4" ? "5.10.0" : "5.9.0"

        $tmpFile = Download-ExtensionFromPECL "pdo_sqlsrv" $extensionVersion $phpVer
        Install-PECLFromFile $tmpFile "pdo_sqlsrv" "${installPath}\ext" $phpIniFile
        Remove-Item $tmpFile
    }

    # Install grpc extension
    if ($phpVer -ge [System.Version]"8.1") {
        $tmpFile = Download-ExtensionFromPECL "grpc" "1.64.1" $phpVer
        Install-PECLFromFile $tmpFile "grpc" "${installPath}\ext" $phpIniFile
        Remove-Item $tmpFile
    }
}

function Download-ExtensionFromPECL {
    param(
        [String] $ExtName,
        [String] $ExtVersion,
        [System.Version] $PhpVersion
    )

    $tmpFile = New-TemporaryFile

    $arch = "x86"
    $vc = "vc15"

    if ($PhpVersion -ge [System.Version]"8.0") {
        $vc = "vs16"
    }

    if (Get-ProcessorBits 64) {
        $arch = "x64"
    }

    $extensionUrl = "https://downloads.php.net/~windows/pecl/releases/${ExtName}/${ExtVersion}/php_${ExtName}-${ExtVersion}-$($PhpVersion.Major).$($PhpVersion.Minor)-nts-${vc}-${arch}.zip"

    Write-Host "Download ${extensionUrl} to ${tmpFile}"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $extensionUrl -OutFile $tmpFile

    return $tmpFile
}

function Install-PECLFromFile {
    param(
        [String] $ArchiveFile,
        [String] $ExtName,
        [String] $InstallPath,
        [String] $IniFile
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $extensionFile = "php_${ExtName}.dll"

    $zip = [System.IO.Compression.ZipFile]::OpenRead($ArchiveFile)
    $zip.Entries |
        Where-Object { $_.FullName -like $extensionFile } |
        ForEach-Object {
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($_, "${InstallPath}\${extensionFile}", $true)
        }
    $zip.Dispose()

    Add-LineToFile -Path $IniFile -Content "extension=${ExtName}"
}

function Test-ContentInFile {
    param(
        [String] $Path,
        [String] $Content
    )

    if (!(Test-Path -LiteralPath $Path)) {
        return $false
    }

    $match = (@(Get-Content $Path -ErrorAction SilentlyContinue) -match $Content).Count -gt 0
    return $match
}

function Add-LineToFile {
    param(
        [String] $Path,
        [String] $Content
    )

    if (Test-ContentInFile $Path $Content) {
        return
    }

    Add-Content -Path $Path -Value $Content
}

if (-not $env:ChocolateyInstall -or -not (Test-Path "$env:ChocolateyInstall")) {
    iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
}

Import-Module "$env:ChocolateyInstall\helpers\chocolateyInstaller.psm1" -Force
Get-ToolsLocation

if (Install-NeededFor 'openssh' -DefaultAnswer $false) {
    choco install openssh -y --pre -params '"/SSHAgentFeature"'
}

choco install git -y --params="/GitAndUnixToolsOnPath /NoAutoCrlf"

Update-SessionEnvironment

Write-Host 'Configuring git...'

Write-Host 'Set your user name and email address. This is important'
Write-Host 'because every Git commit uses this information.'
Set-GitConfig 'user.name' $null -Prompt 'Please, enter your name'
Set-GitConfig 'user.email' $null -Prompt 'Please, enter your email'

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

if (Install-NeededFor 'posh-git' -DefaultAnswer $true) {
    PowerShellGet\Install-Module posh-git -Scope CurrentUser -AllowPrerelease -Force
    Add-PoshGitToProfile
}

if (Install-NeededFor 'KiTTy' -DefaultAnswer $false) {
    choco install kitty --params "/Portable" -y
}

if (Install-NeededFor 'PHP' -DefaultAnswer $true) {
    choco install sqlserver-odbcdriver -y

    Install-PHP -Version "7.3.30"
    Install-PHP -Version "7.4.33"
    Install-PHP -Version "8.1.29"
    Install-PHP -Version "8.3.8"

    Write-Host "Installing composer..."
    choco install composer -y
}

if (Install-NeededFor 'NodeJS' -DefaultAnswer $true) {
    choco install nodejs-lts -y
}

if (Install-NeededFor 'Python' -DefaultAnswer $true) {
    $installPath = Join-Path $env:ChocolateyToolsLocation "python311"

    choco install python3 -y --version 3.11.8 --params "/InstallDir:${installPath}"
    python -m pip install --upgrade pip
    Update-SessionEnvironment
    pip install pipenv

    $profilePath = $PROFILE.CurrentUserCurrentHost
    Write-Verbose "`$profilePath = '${profilePath}'"

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
