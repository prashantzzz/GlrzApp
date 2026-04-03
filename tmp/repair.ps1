$root = "C:\Users\Prashant\Documents\Prashant_coder\NoCodeApps\GlrzApp_aves\android\app\src\main\kotlin\com\galleryze\app"
Get-ChildItem -Path $root -Filter *.kt -Recurse | ForEach-Object {
    $content = Get-Content $_.FullName -Raw
    $newContent = $content -replace 'deckers\.thibault\.aves', 'com.galleryze.app'
    if ($content -ne $newContent) {
        $newContent | Set-Content $_.FullName
        Write-Host "Updated: $($_.FullName)"
    }
}
