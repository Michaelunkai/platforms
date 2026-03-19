<#
.SYNOPSIS
    getollama - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
winget install Ollama.Ollama --location "F:\backup\ollama" --override "/DIR=F:\backup\ollama /S"; Stop-Process -Name "ollama*" -Force -ErrorAction SilentlyContinue; [System.Environment]::SetEnvironmentVariable("OLLAMA_MODELS", "F:\backup\ollama\models", "Machine"); [System.Environment]::SetEnvironmentVariable("OLLAMA_HOME", "F:\backup\ollama", "Machine"); $env:OLLAMA_MODELS="F:\backup\ollama\models"; $env:OLLAMA_HOME="F:\backup\ollama"
