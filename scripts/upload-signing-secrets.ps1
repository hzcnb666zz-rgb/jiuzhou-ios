param([Parameter(Mandatory=$true)][string]$Archive)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($Archive)
try {
    foreach ($mapping in @(@('*.p12','IOS_P12_BASE64'), @('*.mobileprovision','IOS_PROFILE_BASE64'), @('*.txt','IOS_P12_PASSWORD'))) {
        $entry = @($zip.Entries | Where-Object FullName -like $mapping[0])
        if ($entry.Count -ne 1) { throw "Expected one signing entry matching $($mapping[0])" }
        $stream = $entry[0].Open()
        $memory = [IO.MemoryStream]::new()
        try {
            $stream.CopyTo($memory)
            if ($mapping[1] -eq 'IOS_P12_PASSWORD') {
                $secret = [Text.Encoding]::UTF8.GetString($memory.ToArray()).Trim([char]0xFEFF).Trim()
                # The vendor text contains a password label before the actual value.
                if ($secret.Contains(':')) { $secret = $secret.Split(':')[-1].Trim() }
                if ($secret.Contains([char]0xFF1A)) { $secret = $secret.Split([char]0xFF1A)[-1].Trim() }
            } else { $secret = [Convert]::ToBase64String($memory.ToArray()) }
            $secret | gh secret set $mapping[1] --repo hzcnb666zz-rgb/jiuzhou-ios
            if ($LASTEXITCODE -ne 0) { throw 'Secret upload failed' }
        } finally { $stream.Dispose(); $memory.Dispose(); $secret = $null }
    }
} finally { $zip.Dispose() }
Write-Output 'Signing secrets uploaded without printing their values.'
