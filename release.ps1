$ErrorActionPreference = "Stop"

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed."
    }
}

function Get-GitOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed."
    }

    return ($output -join "`n")
}

function Get-VersionBumpPart {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$ScriptArguments
    )

    if ($ScriptArguments.Count -gt 1) {
        throw "Use only one version bump flag: -major, -minor, -M, or -m."
    }

    if ($ScriptArguments.Count -eq 1) {
        switch -CaseSensitive ($ScriptArguments[0]) {
            "-major" { return "major" }
            "--major" { return "major" }
            "-M" { return "major" }
            "-minor" { return "minor" }
            "--minor" { return "minor" }
            "-m" { return "minor" }
            default {
                throw "Unknown argument '$($ScriptArguments[0])'. Use -major, -minor, -M, or -m."
            }
        }
    }

    do {
        $Part = (Read-Host "Version bump: major or minor").Trim().ToLowerInvariant()
    } until ($Part -eq "major" -or $Part -eq "minor")

    return $Part
}

$Part = Get-VersionBumpPart -ScriptArguments $args

Set-Location -LiteralPath $PSScriptRoot
$repoRoot = Get-GitOutput -Arguments @("rev-parse", "--show-toplevel")
Set-Location -LiteralPath $repoRoot

$branch = (Get-GitOutput -Arguments @("branch", "--show-current")).Trim()
if (-not $branch) {
    throw "Cannot release from a detached HEAD. Check out main or another branch first."
}

& git rev-parse --verify --quiet HEAD | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Commit the addon files before creating the first release."
}

$dirtyFiles = Get-GitOutput -Arguments @("status", "--porcelain")
if ($dirtyFiles) {
    throw "Files have uncommitted changes. Commit or stash them before releasing.`n$dirtyFiles"
}

$tocRelativePath = "Event-Notifier.toc"
$tocPath = Join-Path $repoRoot $tocRelativePath
if (-not (Test-Path -LiteralPath $tocPath)) {
    throw "Could not find $tocRelativePath."
}

$tocContent = [System.IO.File]::ReadAllText($tocPath)
$versionPattern = "(?m)^(## Version:[ \t]*)(\d+)\.(\d+)\.(\d+)[ \t]*(?=\r?$)"
$match = [regex]::Match($tocContent, $versionPattern)
if (-not $match.Success) {
    throw "Could not find a semantic version line like '## Version: 1.2.0' in $tocRelativePath."
}

$major = [int]$match.Groups[2].Value
$minor = [int]$match.Groups[3].Value
$patch = [int]$match.Groups[4].Value

switch ($Part) {
    "major" {
        $major++
        $minor = 0
        $patch = 0
    }
    "minor" {
        $minor++
        $patch = 0
    }
}

$newVersion = "$major.$minor.$patch"
$tagName = "v$newVersion"

$localTag = & git tag --list $tagName
if ($LASTEXITCODE -ne 0) {
    throw "git tag --list $tagName failed."
}
if ($localTag) {
    throw "Tag $tagName already exists locally."
}

$remoteTag = & git ls-remote --tags origin "refs/tags/$tagName"
if ($LASTEXITCODE -ne 0) {
    throw "Could not check remote tags on origin."
}
if ($remoteTag) {
    throw "Tag $tagName already exists on origin."
}

$newTocContent = [regex]::Replace($tocContent, $versionPattern, "`${1}$newVersion")
$utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
[System.IO.File]::WriteAllText($tocPath, $newTocContent, $utf8NoBom)

Invoke-Git -Arguments @("add", "--", $tocRelativePath)
Invoke-Git -Arguments @("commit", "-m", "Release $tagName")
Invoke-Git -Arguments @("tag", "-a", $tagName, "-m", $tagName)
Invoke-Git -Arguments @("push", "origin", $branch, $tagName)

Write-Host "Released $tagName from $branch."
