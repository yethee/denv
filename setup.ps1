$installDir = Split-Path $MyInvocation.MyCommand.Path -Parent

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

if ((Get-Command choco -ErrorAction SilentlyContinue) -eq $null) {
    iex ((new-object net.webclient).DownloadString('http://chocolatey.org/install.ps1'))
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
    Update-SessionEnvironment

    Write-Host "Installing composer..."
    $composerSetup = Join-Path $installDir composer-setup.exe
    Invoke-WebRequest https://getcomposer.org/Composer-Setup.exe -OutFile $composerSetup
    & $composerSetup | Out-Null
    Remove-Item $composerSetup
}

if (Install-NeededFor 'NodeJS' $true) {
    choco install nodejs.install -y
}
