$root = "c:\Users\Prashant\Documents\Prashant_coder\NoCodeApps\GlrzApp_aves\android\app\src\main\kotlin\com\galleryze\app"
$files = Get-ChildItem -Path $root -Filter "*.kt" -Recurse

foreach ($file in $files) {
    $content = Get-Content -Path $file.FullName
    $newContent = @()
    $modified = $false
    
    foreach ($line in $content) {
        if ($line -match "deckers\.thibault\.aves") {
            $newLine = $line -replace "deckers\.thibault\.aves", "com.galleryze.app"
            $newContent += $newLine
            $modified = $true
        } else {
            $newContent += $line
        }
    }
    
    if ($modified) {
        Set-Content -Path $file.FullName -Value $newContent -Encoding UTF8
        Write-Host "Repaired: $($file.FullName)"
    }
}
