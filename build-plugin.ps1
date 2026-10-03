<#
.SYNOPSIS
    Impacchetta il plugin "Vyra Theme" in uno ZIP installabile (senza Gradle).
.PARAMETER Version
    Versione del plugin (default 1.0.0). Aggiorna anche <version> in plugin.xml.
.PARAMETER RefreshScheme
    Ricopia l'Impoo color scheme da IntelliJ dentro themes/Vyra.xml prima del build.
.PARAMETER Scheme
    Percorso esplicito dell'.icls sorgente (usato con -RefreshScheme).
.EXAMPLE
    .\build-plugin.ps1 -RefreshScheme
#>
[CmdletBinding()]
param(
    [string] $Version = '1.0.0',
    [string] $Scheme,
    [switch] $RefreshScheme
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$res = Join-Path $root 'src\main\resources'
$dist = Join-Path $root 'dist'
$themeJson = Join-Path $res 'themes\Vyra.theme.json'
$schemeXml = Join-Path $res 'themes\Vyra.xml'
$pluginXml = Join-Path $res 'META-INF\plugin.xml'
$utf8 = New-Object System.Text.UTF8Encoding($false)

if ($RefreshScheme) {
    if (-not $Scheme) {
        $Scheme = Get-ChildItem (Join-Path $env:APPDATA 'JetBrains\*\colors\Impoo color scheme.icls') -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $Scheme -or -not (Test-Path -LiteralPath $Scheme)) { throw "Impoo color scheme non trovato. Passa -Scheme <percorso .icls>." }
    $text = [System.IO.File]::ReadAllText($Scheme)
    # Rinominato perche' non collida con l'"Impoo color scheme" gia' installato a mano.
    $text = $text -replace '<scheme name="[^"]*"', '<scheme name="Vyra"'
    [System.IO.File]::WriteAllText($schemeXml, $text, $utf8)
    Write-Host "Editor scheme aggiornato da $Scheme" -ForegroundColor Cyan
}

foreach ($f in @($themeJson, $schemeXml, $pluginXml)) {
    if (-not (Test-Path -LiteralPath $f)) { throw "File mancante: $f" }
}

Write-Host ''
Write-Host 'Validazione' -ForegroundColor Cyan

$t = Get-Content -LiteralPath $themeJson -Raw | ConvertFrom-Json
if ($t.name -ne 'Vyra Theme') { throw "Il campo 'name' del descriptor deve essere 'Vyra Theme'. Trovato: $($t.name)" }
if ($t.dark -ne $true) { throw "'dark' deve essere true." }
if ($t.editorScheme -ne '/themes/Vyra.xml') { throw "editorScheme deve essere /themes/Vyra.xml. Trovato: $($t.editorScheme)" }

$named = @($t.colors.PSObject.Properties.Name)
$missing = New-Object System.Collections.Generic.List[string]
function Walk($node, $path) {
    foreach ($p in $node.PSObject.Properties) {
        $v = $p.Value
        if ($v -is [string]) {
            if ($v -match '^[A-Za-z_][A-Za-z0-9_]*$' -and $named -notcontains $v) { $missing.Add("$path.$($p.Name) -> $v") | Out-Null }
        }
        elseif ($v -is [System.Management.Automation.PSCustomObject]) { Walk $v "$path.$($p.Name)" }
    }
}
Walk $t.ui 'ui'
Walk $t.icons 'icons'
if ($missing.Count) { throw "Colori nominati non definiti in 'colors':`n  $($missing -join "`n  ")" }
Write-Host '  tutti i colori nominati sono definiti' -ForegroundColor Green

$bad = [regex]::Matches((Get-Content -LiteralPath $themeJson -Raw), '#[0-9A-Za-z]+') | ForEach-Object { $_.Value } |
    Where-Object { $_ -notmatch '^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$' } | Sort-Object -Unique
if ($bad) { throw "Hex non validi: $($bad -join ', ')" }
Write-Host '  tutti gli hex sono validi' -ForegroundColor Green

$xml = [xml](Get-Content -LiteralPath $schemeXml -Raw)
if ($xml.scheme.name -ne 'Vyra') { throw "Lo scheme XML deve chiamarsi 'Vyra'. Trovato: $($xml.scheme.name)" }
Write-Host "  editor scheme valido: $(@($xml.SelectNodes('//option')).Count) option" -ForegroundColor Green

$px = [xml](Get-Content -LiteralPath $pluginXml -Raw)
$tp = $px.SelectSingleNode('//themeProvider')
if (-not $tp -or $tp.path -ne '/themes/Vyra.theme.json') { throw 'plugin.xml: themeProvider mancante o path errato.' }
Write-Host "  plugin.xml valido: id=$($px.'idea-plugin'.id)" -ForegroundColor Green

$pluginXmlText = [System.IO.File]::ReadAllText($pluginXml)
if ($pluginXmlText -notmatch "<version>$([regex]::Escape($Version))</version>") {
    $pluginXmlText = $pluginXmlText -replace '<version>[^<]*</version>', "<version>$Version</version>"
    [System.IO.File]::WriteAllText($pluginXml, $pluginXmlText, $utf8)
    Write-Host "  <version> aggiornata a $Version" -ForegroundColor DarkGray
}

# IntelliJ si aspetta lib/<nome>.jar dentro lo ZIP: il jar contiene META-INF/plugin.xml e i temi.
# Le voci vanno scritte con '/' perche' Compress-Archive di PS 5.1 usa '\' e IntelliJ non le legge.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function New-Zip([string] $path, [hashtable] $entries) {
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Create)
    try {
        $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($name in ($entries.Keys | Sort-Object)) {
                $e = $zip.CreateEntry($name, [System.IO.Compression.CompressionLevel]::Optimal)
                $s = $e.Open()
                try { $bytes = [System.IO.File]::ReadAllBytes($entries[$name]); $s.Write($bytes, 0, $bytes.Length) } finally { $s.Dispose() }
            }
        } finally { $zip.Dispose() }
    } finally { $fs.Dispose() }
}

New-Item -ItemType Directory -Force -Path $dist | Out-Null
$baseDir = (Resolve-Path -LiteralPath $res).Path.TrimEnd('\') + '\'
$jarEntries = @{}
foreach ($f in Get-ChildItem -LiteralPath $res -Recurse -File) {
    $jarEntries[$f.FullName.Substring($baseDir.Length).Replace('\', '/')] = $f.FullName
}
$jar = Join-Path $dist "vyra-theme-$Version.jar"
New-Zip $jar $jarEntries

$zipPath = Join-Path $dist "vyra-theme-$Version.zip"
New-Zip $zipPath @{ "vyra-theme/lib/vyra-theme-$Version.jar" = $jar }
Remove-Item -LiteralPath $jar -Force

$z = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $inner = $z.Entries[0]
    $ms = New-Object System.IO.MemoryStream
    $st = $inner.Open(); $st.CopyTo($ms); $st.Dispose()
    $j = New-Object System.IO.Compression.ZipArchive($ms, [System.IO.Compression.ZipArchiveMode]::Read)
    $names = @($j.Entries | ForEach-Object { $_.FullName })
    foreach ($req in 'META-INF/plugin.xml', 'META-INF/pluginIcon.svg', 'themes/Vyra.theme.json', 'themes/Vyra.xml') {
        if ($names -notcontains $req) { throw "Voce mancante nel jar: $req" }
    }
    Write-Host ''
    Write-Host "Contenuto di $zipPath" -ForegroundColor Cyan
    Write-Host "  $($inner.FullName)"
    $names | ForEach-Object { Write-Host "    $_" }
} finally { $z.Dispose() }

Write-Host ''
Write-Host "Plugin pronto: $zipPath" -ForegroundColor Green
Write-Host 'Installa: Settings | Plugins | ingranaggio | Install Plugin from Disk...' -ForegroundColor Cyan
Write-Host 'Attiva:   Settings | Appearance & Behavior | Appearance | Theme | Vyra Theme' -ForegroundColor Cyan
