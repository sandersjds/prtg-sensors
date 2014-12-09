###############################################################################
#
# bma - CloudFlare - Dynamic Dns
#
# Create a device with the DNS record you want to update as the address.
# Set linux user/pass to your CloudFlare Email/API Token.
#
# Q4 2014 brian.addicks@lockstepgroup.com
#
###############################################################################

###############################################################################
#                              PLACEHOLDER USAGE
# prtg_sensorid ........................................................ UNUSED
# prtg_deviceid ........................................................ UNUSED
# prtg_groupid ......................................................... UNUSED
# prtg_probeid ......................................................... UNUSED
#
# prtg_host ........................................................... $Record
# prtg_device .......................................................... UNUSED
# prtg_group ........................................................... UNUSED
# prtg_probe ........................................................... UNUSED
# prtg_name ............................................................ UNUSED
#
# prtg_windowsdomain ................................................... UNUSED
# prtg_windowsuser ..................................................... UNUSED
# prtg_windowspassword ................................................. UNUSED
#
# prtg_linuxuser ...................................................... $CfUser
# prtg_linuxpassword ................................................. $CfToken
#
# prtg_snmpcommunity ................................................... UNUSED
#
# prtg_version ......................................................... UNUSED
# prtg_url ............................................................. UNUSED
# prtg_primarychannel .................................................. UNUSED
#
###############################################################################

###############################################################################
#                                 REQUIREMENTS
#
# PrtgShell
# Set placeholders as environment variables must be set
# Powershell 3+ (uses Invoke-RestMethod)
#
###############################################################################

###############################################################################
#                                     TODO
#
#
###############################################################################

###############################################################################
# Script Parameters
[CmdletBinding()]
Param (
    
)

$TimerStart = Get-Date
###############################################################################
# Function for PRTG friendly errors on module failure

function Test-ModuleImport ([string]$Module) {
    Import-Module $Module -ErrorAction SilentlyContinue
    if (!($?)) { return $false } `
        else   { return $true }
}

###############################################################################
# Import prtgshell

$Import = Test-ModuleImport prtgshell

if (!($Import)) {
return @"
<prtg>
  <error>1</error>
  <text>Prtgshell module not loaded: ensure the module is visible for 32-bit PowerShell</text>
</prtg>
"@
}

Write-Verbose "imported prtgshell"

###############################################################################
# Check for required Environment Variables

$NeededVars = @("prtg_host"
                "prtg_linuxuser"
                "prtg_Linuxpassword")

foreach ($n in $NeededVars) {
    $Test = Get-Item env:$n -ErrorAction silentlyContinue
    if (!($Test.Value)) {
        	return Set-PrtgError "$n not specified.  Verify it is configured and 'Set placeholders as environment values' is enabled."
    }
}

Write-Verbose "received environment variables"

###############################################################################
# Assign Environment Variables to friendlier names and setup some basic info

$Record      = "$($env:prtg_host)"
$CfUser      = "$($env:prtg_linuxuser)"
$CfToken     = "$($env:prtg_linuxpassword)"

$ZoneRx = [regex]'\w+\.\w+$'
$Zone   = $ZoneRx.Match($Record)

$CfUrl  = 'https://www.cloudflare.com/api_json.html?'

Write-Verbose "set friendly names"

###############################################################################
# Get DNS record's current info

$Action = 'rec_load_all'

$FullUrl  = $CfUrl
$FullUrl += 'a='      + $Action
$FullUrl += '&tkn='   + $CfToken
$FullUrl += '&email=' + $CfUser
$FullUrl += '&z='     + $Zone

$GetRecords    = Invoke-RestMethod -Uri $FullUrl
$DesiredRecord = ($GetRecords.response.recs.objs | ? { $_.name -eq $Record })

$RecordId      = $DesiredRecord.rec_id
Write-Verbose "Record Id: $RecordId"

$RecordContent = $DesiredRecord.content
Write-Verbose "Record Content: $RecordContent"

$CurrentIp = Invoke-RestMethod 'http://api.ipify.org'

if ($CurrentIp -eq $RecordContent) {
    $Message = "No update needed."
} else {
    $Message = "Record updated from $RecordContent to $CurrentIp"
    
    $Action = 'rec_edit'

    $FullUrl  = $CfUrl
    $FullUrl += 'a='             + $Action
    $FullUrl += '&tkn='          + $CfToken
    $FullUrl += '&id='           + $RecordId
    $FullUrl += '&email='        + $CfUser
    $FullUrl += '&z='            + $Zone
    $FullUrl += '&type='         + $DesiredRecord.type
    $FullUrl += '&name='         + $Record
    $FullUrl += '&ttl='          + $DesiredRecord.ttl
    $FullUrl += '&content='      + $CurrentIp
    $FullUrl += '&service_mode=' + $DesiredRecord.service_mode

    $UpdateIp = Invoke-RestMethod -Uri $FullUrl
}

###############################################################################
# Stop timer

$TimerStop            = Get-Date
$ExecutionTime        = $TimerStop - $TimerStart

###############################################################################
# Return results

$XmlOutput  = "<prtg>`n"

$XmlOutput += "  <text>$Message</text>`n"
$XMLOutput += Set-PrtgResult "Sensor Run Time" $ExecutionTime.TotalMilliseconds "ms"

$XmlOutput += "</prtg>"

$XmlOutput
