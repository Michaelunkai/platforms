<#
.SYNOPSIS
    maxpower
#>
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c; powercfg /change monitor-timeout-ac 0; powercfg /change monitor-timeout-dc 0; powercfg /change standby-timeout-ac 0; powercfg /change standby-timeout-dc 0; powercfg /change hibernate-timeout-ac 0; powercfg /change hibernate-timeout-dc 0; powercfg /change processor-state-min 100
