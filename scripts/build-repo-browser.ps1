param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [ValidateSet("absolute", "relative")]
    [string]$FileUrlMode = "absolute",
    [switch]$SkipSourceArchive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoInventoryPath = "docs/repo/repository-inventory.md"
$ManifestPath = "site/repo-data.js"
$TextExtensions = @(".md", ".txt", ".ps1", ".js", ".html", ".json", ".css")
$ImageExtensions = @(".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".svg")
$PreviewableArchiveExtensions = @(".pdf", ".md", ".png", ".jpg", ".jpeg", ".gif", ".webp", ".txt")
$SelfGeneratedPaths = @($ManifestPath)
$MaxEmbeddedTextBytes = 350000

function Get-RelativePathFromBase {
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

function Get-AbsoluteFileUrl {
    param([string]$FullPath)

    return ([System.Uri]$FullPath).AbsoluteUri
}

function Get-RelativeFileUrl {
    param(
        [string]$BasePath,
        [string]$FullPath
    )

    $relativePath = Get-RelativePathFromBase -BasePath $BasePath -TargetPath $FullPath
    $segments = $relativePath -split "/"
    $encodedSegments = $segments | ForEach-Object { [System.Uri]::EscapeDataString($_) }
    return ($encodedSegments -join "/")
}

function Get-FileUrl {
    param(
        [string]$BasePath,
        [string]$FullPath
    )

    if ($FileUrlMode -eq "relative") {
        return Get-RelativeFileUrl -BasePath $BasePath -FullPath $FullPath
    }

    return Get-AbsoluteFileUrl -FullPath $FullPath
}

function Read-TextFileContent {
    param([string]$FullPath)

    $utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)

    try {
        return [System.IO.File]::ReadAllText($FullPath, $utf8Strict)
    }
    catch {
        try {
            return [System.IO.File]::ReadAllText($FullPath, [System.Text.Encoding]::Unicode)
        }
        catch {
            return [System.IO.File]::ReadAllText($FullPath)
        }
    }
}

function Get-FileTypeLabel {
    param([string]$Extension)

    switch ($Extension.ToLowerInvariant()) {
        ".md" { return "Markdown" }
        ".html" { return "HTML" }
        ".js" { return "JavaScript" }
        ".ps1" { return "PowerShell" }
        ".pdf" { return "PDF" }
        ".png" { return "PNG" }
        ".jpg" { return "JPG" }
        ".jpeg" { return "JPEG" }
        ".txt" { return "Text" }
        default {
            if ([string]::IsNullOrWhiteSpace($Extension)) {
                return "File"
            }

            return $Extension.TrimStart(".").ToUpperInvariant()
        }
    }
}

function Get-RenderMode {
    param([string]$Extension)

    $normalized = $Extension.ToLowerInvariant()
    if ($normalized -eq ".md") { return "markdown" }
    if ($TextExtensions -contains $normalized) { return "code" }
    if ($normalized -eq ".pdf") { return "pdf" }
    if ($ImageExtensions -contains $normalized) { return "image" }
    return "download"
}

function Get-LogicalGroup {
    param(
        [string]$RelativePath,
        [string]$Extension,
        [string]$SourceKey,
        [bool]$IsDirectory
    )

    if ($IsDirectory) {
        if ($RelativePath -eq "docs") { return "Documentation" }
        if ($RelativePath -like "docs/*") { return "Documentation" }
        if ($RelativePath -eq "scripts") { return "Automation" }
        if ($RelativePath -like "scripts/*") { return "Automation" }
        if ($RelativePath -eq "site") { return "Reader Data" }
        if ($RelativePath -like "site/*") { return "Reader Data" }
        return "Folders"
    }

    $normalized = $Extension.ToLowerInvariant()

    if ($SourceKey -eq "archive") {
        switch -Wildcard ($RelativePath) {
            "Checkpoints/*" { return "Archive Checkpoints" }
            "Level 1 character sheets X 3/*" { return "Archive Character Sheets" }
            "Level 2 character sheets/*" { return "Archive Character Sheets" }
            "Level 3 character sheets/*" { return "Archive Character Sheets" }
            default {
                if ($normalized -eq ".pdf") { return "Archive Reference PDFs" }
                if ($ImageExtensions -contains $normalized) { return "Archive Images" }
                return "Archive Files"
            }
        }
    }

    switch -Wildcard ($RelativePath) {
        "4 versions of index/*" { return "Reader Snapshots" }
        "chatGPT/*" { return "Backups and Exports" }
        "index.html" { return "Reader App" }
        "docs/character/*" { return "Character Canon" }
        "docs/Checkpoints/*" { return "Campaign Checkpoints" }
        "docs/Level 1 character sheets X 3/*" { return "Character Sheets" }
        "docs/Level 2 character sheets/*" { return "Character Sheets" }
        "docs/Level 3 character sheets/*" { return "Character Sheets" }
        "docs/Level_3_Coalition_Statblocks_and_Dossiers_Contrast_Fixed.pdf" { return "Reference PDFs" }
        "docs/Nightstone_Tactical_Dossier.pdf" { return "Reference PDFs" }
        "docs/_Storm_Kings_Thunder_Dubbo_Session_0_Table_Packet.pdf" { return "Reference PDFs" }
        "docs/__Storm King_s Thunder (1-10).pdf" { return "Reference PDFs" }
        "docs/repo/*" { return "Repository Audit" }
        "gemeni/*" { return "Workspace Files" }
        "scripts/*" { return "Automation" }
        "site/*" { return "Reader Data" }
        "Alfie*Campaign*Thunder.pdf" { return "Reader Snapshots" }
        "*handover*" { return "Campaign Handovers" }
        "*inventory*" { return "Campaign Inventories" }
        default {
            if ($normalized -eq ".zip") { return "Backups and Exports" }
            if ($normalized -eq ".pdf") { return "Local PDFs" }
            if ($ImageExtensions -contains $normalized) { return "Local Images" }
            return "Workspace Files"
        }
    }
}

function Get-Description {
    param(
        [string]$RelativePath,
        [string]$Name,
        [string]$Group,
        [string]$SourceLabel
    )

    switch -Wildcard ($RelativePath) {
        "4 versions of index/*" { return "Saved PDF snapshot of a previous browser design." }
        "Alfie*Campaign*Thunder.pdf" { return "Saved PDF export of the current campaign dashboard." }
        "chatGPT/*" { return "Exported or backed-up workspace material." }
        "index.html" { return "Local vault reader with in-page document viewing." }
        "docs/character/*" { return "Canonical character-facing reference document." }
        "docs/Checkpoints/*" { return "Checkpoint document stored inside the repo." }
        "docs/Level 1 character sheets X 3/*" { return "Level 1 character sheet PDF stored inside the repo." }
        "docs/Level 2 character sheets/*" { return "Level 2 character sheet PDF stored inside the repo." }
        "docs/Level 3 character sheets/*" { return "Level 3 character sheet or dossier PDF stored inside the repo." }
        "docs/Level_3_Coalition_Statblocks_and_Dossiers_Contrast_Fixed.pdf" { return "Coalition dossier PDF stored directly inside the repo." }
        "docs/Nightstone_Tactical_Dossier.pdf" { return "Nightstone tactical dossier PDF stored directly inside the repo." }
        "docs/_Storm_Kings_Thunder_Dubbo_Session_0_Table_Packet.pdf" { return "Session 0 table packet PDF stored directly inside the repo." }
        "docs/__Storm King_s Thunder (1-10).pdf" { return "Storm King's Thunder reference PDF stored directly inside the repo." }
        "docs/repo/*" { return "Generated audit of the repo structure and contents." }
        "scripts/*" { return "Utility script for rebuilding the reader data." }
        "site/*" { return "Generated data file consumed by the local reader UI." }
        "*handover*" { return "Campaign continuity handover note." }
        "*inventory*" { return "Inventory and equipment tracking document." }
        default {
            if ($Group -eq "Archive Character Sheets") { return "Character sheet from the linked source archive." }
            if ($Group -eq "Archive Checkpoints") { return "Checkpoint file from the linked source archive." }
            if ($Group -eq "Archive Reference PDFs") { return "Reference PDF from the linked source archive." }
            if ($Group -eq "Archive Images") { return "Image asset from the linked source archive." }
            if ($Group -eq "Local PDFs") { return "PDF stored directly inside this repo." }
            if ($Group -eq "Local Images") { return "Image stored directly inside this repo." }
            return "$SourceLabel file."
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

    if ($Value -is [string]) {
        return Escape-JavaScriptString ([string]$Value)
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

function Find-SourceArchiveRoot {
    $downloads = "C:\Users\joshua.parris\Downloads"
    if (-not (Test-Path -LiteralPath $downloads)) {
        return $null
    }

    $archiveRoot = Get-ChildItem -LiteralPath $downloads -Directory -Filter "Alphie Wizard - Storm kings*" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -eq $archiveRoot) {
        return $null
    }

    $innerRoot = Join-Path $archiveRoot.FullName "Alphie Wizard - Storm kings"
    if (Test-Path -LiteralPath $innerRoot) {
        return $innerRoot
    }

    return $archiveRoot.FullName
}

function New-FileRecord {
    param(
        [System.IO.FileInfo]$Item,
        [string]$BasePath,
        [string]$SourceKey,
        [string]$SourceLabel
    )

    $relativePath = Get-RelativePathFromBase -BasePath $BasePath -TargetPath $Item.FullName
    $extension = $Item.Extension.ToLowerInvariant()
    $renderMode = Get-RenderMode -Extension $extension
    $isRepoInventory = $SourceKey -eq "repo" -and $relativePath -eq $RepoInventoryPath
    $isSelfGenerated = $SourceKey -eq "repo" -and ($SelfGeneratedPaths -contains $relativePath)
    $dynamicMetadata = $isSelfGenerated

    $textContent = $null
    if (-not $isSelfGenerated -and -not $isRepoInventory -and ($TextExtensions -contains $extension) -and $Item.Length -le $MaxEmbeddedTextBytes) {
        $textContent = [string](Read-TextFileContent -FullPath $Item.FullName)
    }

    [pscustomobject]@{
        id = "${SourceKey}:$relativePath"
        path = $relativePath
        displayPath = if ($SourceKey -eq "repo") { $relativePath } else { "Source Archive/$relativePath" }
        name = $Item.Name
        folder = ((Split-Path -Parent $relativePath) -replace "\\", "/")
        extension = $extension
        type = Get-FileTypeLabel -Extension $extension
        renderMode = $renderMode
        sizeBytes = if ($dynamicMetadata) { $null } else { [int64]$Item.Length }
        sizeKB = if ($dynamicMetadata) { $null } else { [math]::Round($Item.Length / 1KB, 2) }
        group = Get-LogicalGroup -RelativePath $relativePath -Extension $extension -SourceKey $SourceKey -IsDirectory $false
        lastModified = if ($dynamicMetadata) { $null } else { $Item.LastWriteTime }
        dynamicMetadata = $dynamicMetadata
        source = $SourceLabel
        sourceKey = $SourceKey
        fileUrl = [string](Get-FileUrl -BasePath $BasePath -FullPath $Item.FullName)
        description = $null
        textContent = $textContent
    }
}

function Get-PdfLocationRecords {
    param(
        [object[]]$Files,
        [string]$SourceLabel
    )

    return @($Files |
        Where-Object { $_.extension -eq ".pdf" } |
        Group-Object folder |
        Sort-Object Name |
        ForEach-Object {
            $folder = if ([string]::IsNullOrWhiteSpace($_.Name)) { "." } else { $_.Name }
            [pscustomobject]@{
                source = $SourceLabel
                folder = $folder
                count = $_.Count
            }
        })
}

$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$generatedAt = Get-Date

$directories = @(Get-ChildItem -LiteralPath $resolvedRoot -Directory -Force -Recurse |
    Sort-Object FullName |
    ForEach-Object {
        $relativePath = Get-RelativePathFromBase -BasePath $resolvedRoot -TargetPath $_.FullName
        [pscustomobject]@{
            path = $relativePath
            name = $_.Name
            parent = (Split-Path -Parent $relativePath) -replace "\\", "/"
            depth = ($relativePath.Split("/").Count)
            group = Get-LogicalGroup -RelativePath $relativePath -Extension "" -SourceKey "repo" -IsDirectory $true
            lastModified = $_.LastWriteTime
        }
    })

$repoFiles = @(Get-ChildItem -LiteralPath $resolvedRoot -File -Force -Recurse |
    Sort-Object FullName |
    ForEach-Object {
        New-FileRecord -Item $_ -BasePath $resolvedRoot -SourceKey "repo" -SourceLabel "Repository"
    })

foreach ($record in $repoFiles) {
    $record.description = Get-Description -RelativePath $record.path -Name $record.name -Group $record.group -SourceLabel $record.source
}

$sourceArchiveRoot = if ($SkipSourceArchive) { $null } else { Find-SourceArchiveRoot }
$archiveFiles = @()
if ($null -ne $sourceArchiveRoot) {
    $archiveFiles = @(Get-ChildItem -LiteralPath $sourceArchiveRoot -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $PreviewableArchiveExtensions -contains $_.Extension.ToLowerInvariant() } |
        Sort-Object FullName |
        ForEach-Object {
            New-FileRecord -Item $_ -BasePath $sourceArchiveRoot -SourceKey "archive" -SourceLabel "Source Archive"
        })

    foreach ($record in $archiveFiles) {
        $record.description = Get-Description -RelativePath $record.path -Name $record.name -Group $record.group -SourceLabel $record.source
    }
}

$repoSummary = [ordered]@{
    repoFileCount = @($repoFiles).Count
    repoFolderCount = @($directories).Count
    markdownCount = @($repoFiles | Where-Object { $_.extension -eq ".md" }).Count
    pdfCount = @($repoFiles | Where-Object { $_.extension -eq ".pdf" }).Count
    imageCount = @($repoFiles | Where-Object { $ImageExtensions -contains $_.extension }).Count
    scriptCount = @($repoFiles | Where-Object { $_.extension -eq ".ps1" -or $_.extension -eq ".js" }).Count
    archiveFileCount = @($archiveFiles).Count
    archivePdfCount = @($archiveFiles | Where-Object { $_.extension -eq ".pdf" }).Count
}

$repoPdfLocations = Get-PdfLocationRecords -Files $repoFiles -SourceLabel "Repository"
$archivePdfLocations = Get-PdfLocationRecords -Files $archiveFiles -SourceLabel "Source Archive"

$quickLinkIds = New-Object System.Collections.Generic.List[string]
foreach ($id in @(
    "repo:docs/character/alfie-current-inventory.md",
    "repo:docs/repo/repository-inventory.md",
    "repo:index.html",
    "repo:Alphie_Complete_Inventory.md"
)) {
    $quickLinkIds.Add($id)
}

foreach ($id in @(
    "repo:ChatGPThandover27042026.md",
    "repo:ClaudeHandover27042026.md",
    "repo:GemeniHandover27042026.md",
    "repo:docs/Checkpoints/SKT_Dubbo_Resume_Checkpoint_4_Handover.md",
    "repo:docs/Level 3 character sheets/SKT_Dubbo_Resume_Checkpoint_4_Handover.md"
)) {
    $match = $repoFiles | Where-Object { $_.id -eq $id } | Select-Object -First 1
    if ($null -ne $match -and -not $quickLinkIds.Contains($id)) {
        $quickLinkIds.Add($id)
    }
}

foreach ($archivePreferredPath in @(
    "__Storm King_s Thunder (1-10).pdf",
    "Nightstone_Tactical_Dossier.pdf",
    "Checkpoints/SKT_Dubbo_Resume_Checkpoint_4_Handover.pdf",
    "Checkpoints/SKT_Dubbo_Resume_Checkpoint_4_Handover.md"
)) {
    $match = $archiveFiles | Where-Object { $_.path -eq $archivePreferredPath } | Select-Object -First 1
    if ($null -ne $match -and -not $quickLinkIds.Contains($match.id)) {
        $quickLinkIds.Add($match.id)
    }
}

$allFiles = @()
$allFiles += $repoFiles
$allFiles += $archiveFiles

$quickLinks = New-Object System.Collections.Generic.List[object]
foreach ($id in $quickLinkIds) {
    $match = $allFiles | Where-Object { $_.id -eq $id } | Select-Object -First 1
    if ($null -ne $match) {
        $quickLinks.Add([pscustomobject]@{
            id = $match.id
            title = $match.name
            subtitle = $match.description
            path = $match.displayPath
            group = $match.group
            source = $match.source
            type = $match.type
        })
    }
}

$treeLines = Get-TreeLines -BasePath $resolvedRoot

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
$markdown.Add(("| Files in repo | {0} |" -f $repoSummary.repoFileCount))
$markdown.Add(("| Folders in repo | {0} |" -f $repoSummary.repoFolderCount))
$markdown.Add(("| Markdown files in repo | {0} |" -f $repoSummary.markdownCount))
$markdown.Add(("| PDF files in repo | {0} |" -f $repoSummary.pdfCount))
$markdown.Add(("| Image files in repo | {0} |" -f $repoSummary.imageCount))
$markdown.Add(("| Script/data files in repo | {0} |" -f $repoSummary.scriptCount))
if ($null -ne $sourceArchiveRoot) {
    $markdown.Add(("| Linked source archive files | {0} |" -f $repoSummary.archiveFileCount))
    $markdown.Add(("| Linked source archive PDFs | {0} |" -f $repoSummary.archivePdfCount))
}
$markdown.Add("")
$markdown.Add("Note: `site/repo-data.js` is generated by this script, so its size and modified-time fields are marked as `Generated at refresh` to avoid false self-referential metadata.")
$markdown.Add("")

$markdown.Add("## PDF Locations")
$markdown.Add("")
$markdown.Add("| Source | Folder | PDF Count |")
$markdown.Add("|---|---|---:|")
foreach ($pdfLocation in $repoPdfLocations) {
    $markdown.Add(('| {0} | `{1}` | {2} |' -f $pdfLocation.source, $pdfLocation.folder, $pdfLocation.count))
}
foreach ($pdfLocation in $archivePdfLocations) {
    $markdown.Add(('| {0} | `{1}` | {2} |' -f $pdfLocation.source, $pdfLocation.folder, $pdfLocation.count))
}
$markdown.Add("")

if ($null -ne $sourceArchiveRoot) {
    $markdown.Add("## Linked Source Archive")
    $markdown.Add("")
    $markdown.Add(('Archive root: `{0}`' -f $sourceArchiveRoot))
    $markdown.Add("")
    $markdown.Add("These files are not stored inside the repo, but the reader can open them in-place as a linked library.")
    $markdown.Add("")
}

$markdown.Add("## Quick Links")
$markdown.Add("")
$markdown.Add("| File | Source | Group | Type |")
$markdown.Add("|---|---|---|---|")
foreach ($item in $quickLinks) {
    $markdown.Add(('| `{0}` | {1} | {2} | {3} |' -f $item.path, $item.source, $item.group, $item.type))
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
$markdown.Add("## Files In Repo")
$markdown.Add("")
$markdown.Add("| File | Folder | Group | Type | Size (bytes) | Last Modified |")
$markdown.Add("|---|---|---|---|---:|---|")
foreach ($file in $repoFiles) {
    $folderLabel = if ([string]::IsNullOrWhiteSpace($file.folder)) { "." } else { $file.folder }
    $sizeLabel = if ($file.dynamicMetadata) { "Generated at refresh" } else { [string]$file.sizeBytes }
    $modifiedLabel = if ($file.dynamicMetadata) { "Generated at refresh" } else { $file.lastModified.ToString("yyyy-MM-dd HH:mm:ss") }
    $markdown.Add(('| `{0}` | `{1}` | {2} | {3} | {4} | {5} |' -f $file.path, $folderLabel, $file.group, $file.type, $sizeLabel, $modifiedLabel))
}

if ($null -ne $sourceArchiveRoot) {
    $markdown.Add("")
    $markdown.Add("## Linked Source Archive Files")
    $markdown.Add("")
    $markdown.Add("| File | Group | Type |")
    $markdown.Add("|---|---|---|")
    foreach ($file in $archiveFiles) {
        $markdown.Add(('| `{0}` | {1} | {2} |' -f $file.path, $file.group, $file.type))
    }
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

$markdownText = $markdown -join "`r`n"

$repoInventoryRecord = $repoFiles | Where-Object { $_.path -eq $RepoInventoryPath } | Select-Object -First 1
if ($null -ne $repoInventoryRecord) {
    $repoInventoryRecord.textContent = [string]$markdownText
}

$manifestRecord = $repoFiles | Where-Object { $_.path -eq $ManifestPath } | Select-Object -First 1
if ($null -ne $manifestRecord) {
    $manifestRecord.textContent = [string]"Generated reader data file. Re-run scripts/build-repo-browser.ps1 to refresh this manifest."
}

$manifestObject = [ordered]@{
    generatedAt = $generatedAt
    rootPath = [string]$resolvedRoot
    summary = [pscustomobject]$repoSummary
    sourceArchive = [pscustomobject]@{
        found = ($null -ne $sourceArchiveRoot)
        rootPath = if ($null -ne $sourceArchiveRoot) { [string]$sourceArchiveRoot } else { $null }
        fileCount = @($archiveFiles).Count
        pdfCount = @($archiveFiles | Where-Object { $_.extension -eq ".pdf" }).Count
    }
    pdfLocations = [pscustomobject]@{
        repo = $repoPdfLocations
        archive = $archivePdfLocations
    }
    folders = $directories
    files = $allFiles
    treeLines = $treeLines
    quickLinks = $quickLinks
}

$jsManifest = @(
    "window.REPO_DATA = {",
    ("  generatedAt: {0}," -f (Convert-ToJsLiteral $manifestObject.generatedAt)),
    ("  rootPath: {0}," -f (Convert-ToJsLiteral $manifestObject.rootPath)),
    ("  summary: {0}," -f (Convert-ToJsLiteral $manifestObject.summary)),
    ("  sourceArchive: {0}," -f (Convert-ToJsLiteral $manifestObject.sourceArchive)),
    ("  pdfLocations: {0}," -f (Convert-ToJsLiteral $manifestObject.pdfLocations)),
    ("  folders: {0}," -f (Convert-ToJsLiteral $manifestObject.folders)),
    ("  files: {0}," -f (Convert-ToJsLiteral $manifestObject.files)),
    ("  treeLines: {0}," -f (Convert-ToJsLiteral $manifestObject.treeLines)),
    ("  quickLinks: {0}" -f (Convert-ToJsLiteral $manifestObject.quickLinks)),
    "};"
)

Set-Content -LiteralPath (Join-Path $resolvedRoot $RepoInventoryPath) -Value $markdownText -Encoding UTF8
Set-Content -LiteralPath (Join-Path $resolvedRoot $ManifestPath) -Value ($jsManifest -join "`r`n") -Encoding UTF8

Write-Output ("Generated inventory at {0}" -f (Join-Path $resolvedRoot $RepoInventoryPath))
Write-Output ("Generated browser data at {0}" -f (Join-Path $resolvedRoot $ManifestPath))
