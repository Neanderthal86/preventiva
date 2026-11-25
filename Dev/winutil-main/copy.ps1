Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '..\..\Dist\Modules') -Filter '*.psm1' | ForEach-Object {
    $dest = Join-Path $PSScriptRoot "functions\private\$($_.BaseName).ps1"
    $lines = Get-Content -LiteralPath $_.FullName -Encoding UTF8 | Where-Object { $_ -notmatch '^\s*Export-ModuleMember\b' }
    Set-Content -LiteralPath $dest -Value $lines -Encoding UTF8
}
