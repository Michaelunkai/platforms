<#
.SYNOPSIS
    gstremio - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
$TAG = "stremio" ; docker run --rm -it -e TAG=$TAG -v /f/backup/windowsapps/installed:/f michadockermisha/backup:$TAG sh -c 'apk add --no-cache rsync ; rsync -av /home /f ; mv /f/home "/f/${TAG}"'
