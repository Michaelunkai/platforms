<#
.SYNOPSIS
    keyubu
#>
ssh-keygen -t rsa -b 2048; cat ~/.ssh/id_rsa.pub | ssh ubuntu@192.168.1.193 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys'
