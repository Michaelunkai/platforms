<#
.SYNOPSIS
    fixwim
#>
& "C:\Program Files\7-Zip\7z.exe" e "F:\isos\Win11_24H2_English_x64.iso" -o"F:\Downloads\" sources/install.wim -r; New-Item -ItemType Directory -Path "C:\mount" -Force; & dism /mount-image /imagefile:"F:\Downloads\install.wim" /index:1 /mountdir:"C:\mount" /readonly; Copy-Item "C:\mount\Windows\System32\Recovery\winre.wim" "C:\Windows\System32\Recovery\"; & dism /unmount-image /mountdir:"C:\mount" /discard; & reagentc /enable
