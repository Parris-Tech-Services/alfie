param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-RelativeRepoPath {
    param(
        [string]$BasePath,
        [string]$TargetPath
    )

    $resolvedBase = (Resolve-Path -LiteralPath $BasePath).Path.TrimEnd("\") + "\"
    $resolvedTarget = (Resolve-Path -LiteralPath $TargetPath).Path
    $baseUri = [System.Uri]$resolvedBase
    $targetUri = [System.Uri]$resolvedTarget
    $relative = [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString())
    return ($relative -replace "\\", "/")
}

function Get-LogicalGroup {
    param(
        [string]$RelativePath,
        [bool]$IsDirectory
    )

    if ($IsDirectory) {
        if ($RelativePath -eq "docs") { return "Documentation" }
        if ($RelativePath -like "docs/*") { return "Documentation" }
        if ($RelativePath -eq "scripts") { return "Automation" }
        if ($RelativePath -like "scripts/*") { return "Automation" }
        if ($RelativePath -eq "site") { return "Browser Data" }
        if ($RelativePath -like "site/*") { return "Browser Data" }
        return "Folders"
    }

    switch -Wildcard ($RelativePath) {
        "index.html" { return "Start Here" }
        "docs/character/*" { return "Character Reference" }
        "docs/repo/*" { return "Repository Reference" }
        "scripts/*" { return "Automation" }
        "site/*" { return "Browser Data" }
        "*handover*" { return "Campaign Handovers" }
        "*inventory*" { return "Campaign Inventory" }
        default { return "Root Files" }
    }
}

function Get-FileTypeLabel {
    param([string]$Extension)

    switch ($Extension.ToLowerInvariant()) {
        ".md" { return "Markdown" }
        ".html" { return "HTML" }
        ".js" { return "JavaScript" }
        ".ps1" { return "PowerShell" }
        default {
            if ([string]::IsNullOrWhiteSpace($Extension)) {
                return "File"
            }

            return $Extension.TrimStart(".").ToUpperInvariant()
        }
    }
}

function Escape-JavaScriptString {
    param([string]$Value)

    if ($null -eq $Value) {
        return "null"
    }

    $escaped = $Value.Replace("\", "\\").Replace("`r", "\r").Replace("`n", "\n").Replace("'", "\'")
    return "'" + $escaped + "'"
}

function Convert-ToJsLiteral {
    param($Value)

    if ($null -eq $Value) {
        return "null"
    }

    if ($Value -is [bool]) {
        return $Value.ToString().ToLowerInvariant()
    }

    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
        return $Value.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }

    if ($Value -is [datetime]) {
        return Escape-JavaScriptString $Value.ToString("o")
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $parts = @()
        foreach ($item in $Value) {
            $parts += Convert-ToJsLiteral $item
        }
        return "[" + ($parts -join ", ") + "]"
    }

    if ($Value -is [pscustomobject] -or $Value -is [hashtable]) {
        $properties = @()

        if ($Value -is [hashtable]) {
            $enumerable = $Value.GetEnumerator() | Sort-Object Key
            foreach ($entry in $enumerable) {
                $properties += ("{0}: {1}" -f $entry.Key, (Convert-ToJsLiteral $entry.Value))
            }
        }
        else {
            foreach ($property in $Value.PSObject.Properties) {
                $properties += ("{0}: {1}" -f $property.Name, (Convert-ToJsLiteral $property.Value))
            }
        }

        return "{ " + ($properties -join ", ") + " }"
    }

    return Escape-JavaScriptString ([string]$Value)
}

function Get-TreeLines {
    param([string]$BasePath)

    $lines = New-Object System.Collections.Generic.List[string]
    $rootName = Split-Path -Leaf $BasePath
    $lines.Add($rootName)

    function Add-ChildLines {
        param(
            [string]$CurrentPath,
            [string]$Prefix
        )

        $children = @(Get-ChildItem -LiteralPath $CurrentPath -Force | Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name)
        for ($index = 0; $index -lt $children.Count; $index++) {
            $child = $children[$index]
            $isLast = $index -eq ($children.Count - 1)
            $branch = if ($isLast) { "\-- " } else { "|-- " }
            $lines.Add($Prefix + $branch + $child.Name)

            if ($child.PSIsContainer) {
                $nextPrefix = if ($isLast) { $Prefix + "    " } else { $Prefix + "|   " }
                Add-ChildLines -CurrentPath $child.FullName -Prefix $nextPrefix
            }
        }
    }

    Add-ChildLines -CurrentPath $BasePath -Prefix ""
    return $lines
}

$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$generatedAt = Get-Date
$selfGeneratedPaths = @(
    "docs/repo/repository-inventory.md",
    "site/repo-data.js"
)

$directories = @(Get-ChildItem -LiteralPath $resolvedRoot -Directory -Force -Recurse |
    Sort-Object FullName |
    ForEach-Object {
        $relativePath = Get-RelativeRepoPath -BasePath $resolvedRoot -TargetPath $_.FullName
        [pscustomobject]@{
            path = $relativePath
            name = $_.Name
            parent = (Split-Path -Parent $relativePath) -replace "\\", "/"
            depth = ($relativePath.Split("/").Count)
            group = Get-LogicalGroup -RelativePath $relativePath -IsDirectory $true
            lastModified = $_.LastWriteTime
        }
    })

$files = @(Get-ChildItem -LiteralPath $resolvedRoot -File -Force -Recurse |
    Sort-Object FullName |
    ForEach-Object {
        $relativePath = Get-RelativeRepoPath -BasePath $resolvedRoot -TargetPath $_.FullName
        $extension = $_.Extension.ToLowerInvariant()
        $isSelfGenerated = $selfGeneratedPaths -contains $relativePath
        [pscustomobject]@{
            path = $relativePath
            name = $_.Name
            folder = ((Split-Path -Parent $relativePath) -replace "\\", "/")
            extension = $extension
            type = Get-FileTypeLabel -Extension $extension
            sizeBytes = if ($isSelfGenerated) { $null } else { [int64]$_.Length }
            sizeKB = if ($isSelfGenerated) { $null } else { [math]::Round($_.Length / 1KB, 2) }
            group = Get-LogicalGroup -RelativePath $relativePath -IsDirectory $false
            lastModified = if ($isSelfGenerated) { $null } else { $_.LastWriteTime }
            dynamicMetadata = $isSelfGenerated
        }
    })

$summary = [ordered]@{
    fileCount = @($files).Count
    folderCount = @($directories).Count
    markdownCount = @($files | Where-Object { $_.extension -eq ".md" }).Count
    htmlCount = @($files | Where-Object { $_.extension -eq ".html" }).Count
    scriptCount = @($files | Where-Object { $_.extension -eq ".ps1" -or $_.extension -eq ".js" }).Count
}

$quickLinkPaths = New-Object System.Collections.Generic.List[string]
$quickLinkPaths.Add("docs/character/alfie-current-inventory.md")
$quickLinkPaths.Add("docs/repo/repository-inventory.md")
$quickLinkPaths.Add("index.html")
$quickLinkPaths.Add("Alphie_Complete_Inventory.md")
$quickLinkPaths.Add("REPOSITORY_FILE_TREE.md")
$quickLinkPaths.Add("scripts/build-repo-browser.ps1")

$handoverPaths = $files |
    Where-Object { $_.name -match "handover" -and $_.extension -eq ".md" } |
    Sort-Object path |
    Select-Object -ExpandProperty path

foreach ($handoverPath in $handoverPaths) {
    if (-not $quickLinkPaths.Contains($handoverPath)) {
        $quickLinkPaths.Add($handoverPath)
    }
}

$quickLinks = New-Object System.Collections.Generic.List[object]
foreach ($preferredPath in $quickLinkPaths) {
    $match = $files | Where-Object { $_.path -eq $preferredPath } | Select-Object -First 1
    if ($null -ne $match) {
        $quickLinks.Add([pscustomobject]@{
            title = $match.name
            path = $match.path
            group = $match.group
            type = $match.type
        })
    }
}

$treeLines = Get-TreeLines -BasePath $resolvedRoot

$markdownPath = Join-Path $resolvedRoot "docs\repo\repository-inventory.md"
$manifestPath = Join-Path $resolvedRoot "site\repo-data.js"

$markdown = New-Object System.Collections.Generic.List[string]
$markdown.Add("# Repository Inventory")
$markdown.Add("")
$markdown.Add(("Generated: {0}" -f $generatedAt.ToString("yyyy-MM-dd HH:mm:ss")))
$markdown.Add("")
$markdown.Add(('Repository root: `{0}`' -f $resolvedRoot))
$markdown.Add("")
$markdown.Add("## Summary")
$markdown.Add("")
$markdown.Add("| Metric | Count |")
$markdown.Add("|---|---:|")
$markdown.Add(("| Files | {0} |" -f $summary.fileCount))
$markdown.Add(("| Folders | {0} |" -f $summary.folderCount))
$markdown.Add(("| Markdown files | {0} |" -f $summary.markdownCount))
$markdown.Add(("| HTML files | {0} |" -f $summary.htmlCount))
$markdown.Add(("| Script files | {0} |" -f $summary.scriptCount))
$markdown.Add("")
$markdown.Add("Note: `docs/repo/repository-inventory.md` and `site/repo-data.js` are generated by this script, so their size and modified-time fields are marked as `Generated at refresh` to avoid false self-referential metadata.")
$markdown.Add("")
$markdown.Add("## Quick Links")
$markdown.Add("")
$markdown.Add("| File | Group | Type |")
$markdown.Add("|---|---|---|")
foreach ($item in $quickLinks) {
    $markdown.Add(('| `{0}` | {1} | {2} |' -f $item.path, $item.group, $item.type))
}
$markdown.Add("")
$markdown.Add("## Folders")
$markdown.Add("")
$markdown.Add("| Folder | Depth | Group | Last Modified |")
$markdown.Add("|---|---:|---|---|")
foreach ($folder in $directories) {
    $markdown.Add(('| `{0}` | {1} | {2} | {3} |' -f $folder.path, $folder.depth, $folder.group, $folder.lastModified.ToString("yyyy-MM-dd HH:mm:ss")))
}
$markdown.Add("")
$markdown.Add("## Files")
$markdown.Add("")
$markdown.Add("| File | Folder | Group | Type | Size (bytes) | Last Modified |")
$markdown.Add("|---|---|---|---|---:|---|")
foreach ($file in $files) {
    $folderLabel = if ([string]::IsNullOrWhiteSpace($file.folder)) { "." } else { $file.folder }
    $sizeLabel = if ($file.dynamicMetadata) { "Generated at refresh" } else { [string]$file.sizeBytes }
    $modifiedLabel = if ($file.dynamicMetadata) { "Generated at refresh" } else { $file.lastModified.ToString("yyyy-MM-dd HH:mm:ss") }
    $markdown.Add(('| `{0}` | `{1}` | {2} | {3} | {4} | {5} |' -f $file.path, $folderLabel, $file.group, $file.type, $sizeLabel, $modifiedLabel))
}
$markdown.Add("")
$markdown.Add("## Tree")
$markdown.Add("")
$markdown.Add('```text')
foreach ($line in $treeLines) {
    $markdown.Add($line)
}
$markdown.Add('```')
$markdown.Add("")
$markdown.Add("## Refresh")
$markdown.Add("")
$markdown.Add('Run `powershell -ExecutionPolicy Bypass -File scripts/build-repo-browser.ps1` from the repo root to regenerate this inventory and the browser data.')

$jsManifest = @(
    "window.REPO_DATA = {",
    ("  generatedAt: {0}," -f (Convert-ToJsLiteral $generatedAt)),
    ("  rootPath: {0}," -f (Convert-ToJsLiteral $resolvedRoot)),
    ("  summary: {0}," -f (Convert-ToJsLiteral ([pscustomobject]$summary))),
    ("  folders: {0}," -f (Convert-ToJsLiteral $directories)),
    ("  files: {0}," -f (Convert-ToJsLiteral $files)),
    ("  treeLines: {0}," -f (Convert-ToJsLiteral $treeLines)),
    ("  quickLinks: {0}" -f (Convert-ToJsLiteral $quickLinks)),
    "};"
)

Set-Content -LiteralPath $markdownPath -Value ($markdown -join "`r`n") -Encoding UTF8
Set-Content -LiteralPath $manifestPath -Value ($jsManifest -join "`r`n") -Encoding UTF8

Write-Output ("Generated inventory at {0}" -f $markdownPath)
Write-Output ("Generated browser data at {0}" -f $manifestPath)
