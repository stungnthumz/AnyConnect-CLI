<#
.SYNOPSIS
    Provides a simple CLI to Cisco AnyConnect to clean reconnect VPN session.
.PARAMETER VpnMode
    The mode of operation. Can be 'connect', 'disconnect', 'reconnect'.
.PARAMETER VpnHost
    The ip or fqdn addres of VPN host to connect. Used in 'connect' and 'reconnect' mode only.
.PARAMETER VpnUser
    The name of VPN user. Used in 'connect' and 'reconnect' mode only.
.PARAMETER VpnPassword
    The password for VPN user. Used in 'connect' and 'reconnect' mode only.
.PARAMETER AnyConnectPath
    The path to AnyConnect executables
.NOTES
    Author: stungnthumz@dwemereth.net
#>
[CmdletBinding()]
param (
    [string] $AnyConnectPath = 'C:\Program Files (x86)\Cisco\Cisco AnyConnect Secure Mobility Client',
    
    [ValidateSet('connect', 'disconnect', 'reconnect')]
    [string]$VpnMode = 'reconnect',
    
    [string] $VpnHost,
    [string] $VpnUser,
    [string] $VpnPassword
)

function Get-ScriptMutex {

    $mutexName = $PSCommandPath -replace '[\s:\./\\]', '_'

    [bool] $isCreated = $false
    $mutex = New-Object System.Threading.Mutex($false, $mutexName, [ref] $isCreated)

    Add-Member -InputObject $mutex -NotePropertyName 'Created' -NotePropertyValue $isCreated
    return $mutex;
}

function Lock-Script {
    param (
        [Parameter(Mandatory)] $context
    )

    $mutex = $context.Mutex
    return [bool] $mutex.WaitOne(0)
}

function Unlock-Script {
    param (
        [Parameter(Mandatory)] $context
    )

    $mutex = $context.Mutex
    $mutex.ReleaseMutex()
    
}

function Get-ScriptContext {
    
    $mutex = Get-ScriptMutex
    if (!$mutex.Created) {
        Write-Error 'Mutex not created'
        return $null
    }

    $context = @{
        VpnCli = "$AnyConnectPath\vpncli.exe"
        VpnUi = "$AnyConnectPath\vpnui.exe"
        Mode = $VpnMode
        Host = $VpnHost
        User = $VpnUser
        Pass = $VpnPassword
    } 

    Add-Member -InputObject $context -NotePropertyName 'Mutex' -NotePropertyValue $mutex
    return $context
}


function Connect {
    param (
        [Parameter(Mandatory)] $context
    )

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo.FileName = $context.VpnCli
    $proc.StartInfo.Arguments = '-s'
    $proc.StartInfo.UseShellExecute = $false
    $proc.StartInfo.RedirectStandardInput = $true
    $proc.Start() | Out-Null

    $proc.StandardInput.WriteLine("connect $($context.Host)")
    $proc.StandardInput.WriteLine("$($context.User)")
    $proc.StandardInput.WriteLine("$($context.Pass)")
    $proc.StandardInput.WriteLine('exit')
    $proc.StandardInput.WriteLine('')
    $proc.StandardInput.Close()

    $proc.WaitForExit()

    Start-Process -FilePath $context.VpnUi

}

function Disconnect {
    param (
        [Parameter(Mandatory)] $context
    )
    
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo.FileName = $context.VpnCli
    $proc.StartInfo.Arguments = 'disconnect'
    $proc.StartInfo.UseShellExecute = $false
    $proc.Start() | Out-Null
    $proc.WaitForExit()

    Get-Process | Where-Object {$_.Path -eq "$($context.VpnUi)"} | Stop-Process 

    # We are locked, let other script instances check it and go down
    Start-Sleep -Seconds 2
}

<#
    Main Script
#>

$context = Get-ScriptContext
if ($context -eq $null) {
    Write-Error 'Error creating context'
    exit 1
}
    
$isLocked = Lock-Script $context
if (!$isLocked) {
    Write-Error 'Other script instance is active'
    exit 2
}

switch($context.Mode) { 

    'connect' {
        Connect $context
    } 

    'disconnect' {
        Disconnect $context
    }

    'reconnect' {
        Disconnect $context
        Connect $context
    }
}

Unlock-Script $context
exit 0

