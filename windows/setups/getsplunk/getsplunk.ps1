<#
.SYNOPSIS
    getsplunk - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
docker run -d --name splunk -p 8000:8000 -p 8088:8088 -p 8089:8089 -p 9997:9997 -e SPLUNK_START_ARGS="--accept-license" -e SPLUNK_PASSWORD="adminadmin" -v /home/micha/splunk-data:/opt/splunk/var splunk/splunk:latest;
    Start-Process chrome "http://localhost:8000"
