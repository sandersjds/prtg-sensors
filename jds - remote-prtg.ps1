###############################################################################
# 
# PRTG remote monitoring monitoring sensor sensor
# September 8, 2014
# jsanders@lockstepgroup.com
#
###############################################################################
#
# Monitors basic status of a remote PRTG instance.
#



###############################################################################
# script parameters

#Param (
#	[Parameter(Position=0)]
#	[string[]]$ExceptionList
#)


# param validation the hard way because powershell errors don't speak PRTG.
function Set-PrtgError {
	Param (
		[Parameter(Position=0)]
		[string]$PrtgErrorText
	)
	
	@"
<prtg>
  <error>1</error>
  <text>$PrtgErrorText</text>
</prtg>
"@

	exit
}


###############################################################################
#
# from PrtgShell (v1)

function Set-PrtgResult {
    Param (
    [Parameter(mandatory=$True,Position=0)]
    [string]$Channel,
    
    [Parameter(mandatory=$True,Position=1)]
    $Value,
    
    [Parameter(mandatory=$True,Position=2)]
    [string]$Unit,

    [Parameter(mandatory=$False)]
    [alias('mw')]
    [string]$MaxWarn,

    [Parameter(mandatory=$False)]
    [alias('minw')]
    [string]$MinWarn,
    
    [Parameter(mandatory=$False)]
    [alias('me')]
    [string]$MaxError,
    
    [Parameter(mandatory=$False)]
    [alias('wm')]
    [string]$WarnMsg,
    
    [Parameter(mandatory=$False)]
    [alias('em')]
    [string]$ErrorMsg,
    
    [Parameter(mandatory=$False)]
    [alias('mo')]
    [string]$Mode,
    
    [Parameter(mandatory=$False)]
    [alias('sc')]
    [switch]$ShowChart,
    
    [Parameter(mandatory=$False)]
    [alias('ss')]
    [ValidateSet("One","Kilo","Mega","Giga","Tera","Byte","KiloByte","MegaByte","GigaByte","TeraByte","Bit","KiloBit","MegaBit","GigaBit","TeraBit")]
    [string]$SpeedSize,

	[Parameter(mandatory=$False)]
    [ValidateSet("One","Kilo","Mega","Giga","Tera","Byte","KiloByte","MegaByte","GigaByte","TeraByte","Bit","KiloBit","MegaBit","GigaBit","TeraBit")]
    [string]$VolumeSize,
    
    [Parameter(mandatory=$False)]
    [alias('dm')]
    [ValidateSet("Auto","All")]
    [string]$DecimalMode,
    
    [Parameter(mandatory=$False)]
    [alias('w')]
    [switch]$Warning,
    
    [Parameter(mandatory=$False)]
    [string]$ValueLookup
    )
    
    $StandardUnits = @("BytesBandwidth","BytesMemory","BytesDisk","Temperature","Percent","TimeResponse","TimeSeconds","Custom","Count","CPU","BytesFile","SpeedDisk","SpeedNet","TimeHours")
    $LimitMode = $false
    
    $Result  = "  <result>`n"
    $Result += "    <channel>$Channel</channel>`n"
    $Result += "    <value>$Value</value>`n"
    
    if ($StandardUnits -contains $Unit) {
        $Result += "    <unit>$Unit</unit>`n"
    } elseif ($Unit) {
        $Result += "    <unit>custom</unit>`n"
        $Result += "    <customunit>$Unit</customunit>`n"
    }
    
	if (!( ($Value -is [int]) -or ($Value -is [int64]) )) { $Result += "    <float>1</float>`n" }
    if ($Mode)        { $Result += "    <mode>$Mode</mode>`n" }
    if ($MaxWarn)     { $Result += "    <limitmaxwarning>$MaxWarn</limitmaxwarning>`n"; $LimitMode = $true }
    if ($MaxError)    { $Result += "    <limitminwarning>$MinWarn</limitminwarning>`n"; $LimitMode = $true }
    if ($MaxError)    { $Result += "    <limitmaxerror>$MaxError</limitmaxerror>`n"; $LimitMode = $true }
    if ($WarnMsg)     { $Result += "    <limitwarningmsg>$WarnMsg</limitwarningmsg>`n"; $LimitMode = $true }
    if ($ErrorMsg)    { $Result += "    <limiterrormsg>$ErrorMsg</limiterrormsg>`n"; $LimitMode = $true }
    if ($LimitMode)   { $Result += "    <limitmode>1</limitmode>`n" }
    if ($SpeedSize)   { $Result += "    <speedsize>$SpeedSize</speedsize>`n" }
    if ($VolumeSize)  { $Result += "    <volumesize>$VolumeSize</volumesize>`n" }
    if ($DecimalMode) { $Result += "    <decimalmode>$DecimalMode</decimalmode>`n" }
    if ($Warning)     { $Result += "    <warning>1</warning>`n" }
    if ($ValueLookup) { $Result += "    <ValueLookup>$ValueLookup</ValueLookup>`n" }
    
    if (!($ShowChart)) { $Result += "    <showchart>0</showchart>`n" }
    
    $Result += "  </result>`n"
    
    return $Result
}


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
	return Set-PrtgError "prtgshell module not loaded: ensure the module is visible for 32-bit PowerShell"
}

Write-Verbose "imported prtgshell"

###############################################################################
# Check for required Environment Variables

$NeededVars = @("prtg_host"
                "prtg_snmpcommunity"
                "prtg_deviceid"
                "prtg_url"
                "prtg_linuxuser"
                "prtg_linuxpassword")

foreach ($n in $NeededVars) {
    $Test = Get-Item env:$n -ErrorAction silentlyContinue
    if (!($Test.Value)) {
        	return Set-PrtgError "$n not specified.  Verify it is configured and 'Set placeholders as environment values' is enabled."
    }
}

Write-Verbose "received environment variables"

###############################################################################
# Assign Environment Variables to friendlier names

$Device      = "$($env:prtg_host)"
$Community   = "$($env:prtg_snmpcommunity)"
$DeviceId    = [int]"$($env:prtg_deviceid)"

$PrtgUser    = "$($env:prtg_linuxuser)"
$PrtgHash    = "$($env:prtg_linuxpassword)"
$PrtgHost    = [System.Uri]"$($env:prtg_url)"
$PrtgHost    = $PrtgHost.Host

Write-Verbose "set friendly names"




###############################################################################
# remote prtg monitor monitor

$BasicDetails = Get-PrtgServer $Device $PrtgUser $PrtgHash
$SensorDetails = Get-PrtgTableData groups 0 -Count 1

$ReportString = "Remote PRTG Version: " + $BasicDetails.Version


if (!$SensorDetails.upsens) { 			$SensorDetails.upsens = 0 }
if (!$SensorDetails.downsens) { 		$SensorDetails.downsens = 0 }
if (!$SensorDetails.partialdownsens) {	$SensorDetails.partialdownsens = 0 }
if (!$SensorDetails.downacksens) {		$SensorDetails.downacksens = 0 }
if (!$SensorDetails.warnsens) { 		$SensorDetails.warnsens = 0 }
if (!$SensorDetails.pausedsens) { 		$SensorDetails.pausedsens = 0 }
if (!$SensorDetails.unusualsens) { 		$SensorDetails.unusualsens = 0 }
if (!$SensorDetails.undefinedsens) { 	$SensorDetails.undefinedsens = 0 }




###############################################################################
# generating output

$XMLOutput = "<prtg>`n"
$XMLOutput += "<text>$ReportString</text>`n"
$XMLOutput += Set-PrtgResult "Sensors Up" $SensorDetails.upsens "sensors" -ShowChart
$XMLOutput += Set-PrtgResult "Sensors Down" $SensorDetails.downsens "sensors" -ShowChart
$XMLOutput += Set-PrtgResult "Sensors Partial Down" $SensorDetails.partialdownsens "sensors" -ShowChart
$XMLOutput += Set-PrtgResult "Sensors Down (Acknowledged)" $SensorDetails.downacksens "sensors" -ShowChart
$XMLOutput += Set-PrtgResult "Sensors Warning" $SensorDetails.warnsens "sensors" -ShowChart
$XMLOutput += Set-PrtgResult "Sensors Paused" $SensorDetails.pausedsens "sensors" -ShowChart
$XMLOutput += Set-PrtgResult "Sensors Unusual" $SensorDetails.unusualsens "sensors" -ShowChart
$XMLOutput += Set-PrtgResult "Sensors Undefined" $SensorDetails.undefinedsens "sensors" -ShowChart
$XMLOutput += "</prtg>"

$XMLOutput
