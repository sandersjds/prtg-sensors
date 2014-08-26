###############################################################################
#
# Lockstep - SNMP Device - Interesting Ports.ps1
#
# Indexes ports from a network device and creates SNMP traffic Sensors based on
# provided switches.  This sensor should probably be run sparingly, I typically
# deploy it with a 24 hour interval.  You can run it manually if you're adding
# new labels and want them faster than that.
# 
# Default behavior (no switches) only adds labeled ports.
#
# -All adds all valid ports (ports that have snmp traffic OID).  This differs
# from PRTG's default behavior, which add ports with a traffic counter greater
# than 0.
#
# -Sort also sorts ports, currently on every run. Custom sorting can be added
# after the PARAMETERS section
#
# Q3 2014 brian.addicks@lockstepgroup.com
#
###############################################################################

###############################################################################
#                                 REQUIREMENTS
#
# SharpSnmp powershell module
# PowerAlto2 is required for subinterface support
# Set placeholders as environment variables must be set
# SNMP v2 only
# Set snmpcommunity
# Set your linuxuser/linuxpassword as user/hash for prtg api calls
#
###############################################################################

###############################################################################
#                                     TODO
#
# Pause sensors with removed aliases (prtgshell doesn't support pause yet)
# Requires a -PauseOnly switch
#
# Verify if sort is needed, need Josh's help
#
# Sort directly to desired location, need Josh's help/prtgshell update
#
# Set Error for port down status?
# -ErrorOnDown
#
# Make -Log switch actually do something, idea is to log sensor change details
# to eventviewer.
#
# Probably more error handling :-(
# Figure out why primary channel isn't being set
# Upgrade to PrtgShell2!
#
###############################################################################

###############################################################################
# Script Parameters
[CmdletBinding()]
Param (
    [Parameter(mandatory=$False)]
    [decimal]$Timeout = 3000,

    [Parameter(mandatory=$False)]
    [switch]$Log,

    [Parameter(mandatory=$False)]
    [switch]$All,

    [Parameter(mandatory=$False)]
    [switch]$Sort
)

###############################################################################
# Sorting Regex/Expressions, Add custom entries here

$SortTable  = @()

$SortEx = @{expression={[int]$SortRx.Match($_.Name).Groups[1].Value}},
          @{expression={[int]$SortRx.Match($_.Name).Groups[2].Value}}
$SortTable += @{Make="Palo Alto Networks";SortRx='\w+(\d+)\/(\d+)';SortEx=$SortEx}

$SortEx = @{expression={[int]$SortRx.Match($_.Name).Groups[2].Value}},
          @{expression={$SortRx.Match($_.Name).Groups[1].Value}},
          @{expression={[int]$SortRx.Match($_.Name).Groups[3].Value}}
$SortTable += @{Make="Enterasys Networks";SortRx='(\w+)\.(\d+)\.(\d+)';SortEx=$SortEx}

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
# Import sharpsnmp

$Modules = @("sharpsnmp")

foreach ($m in $Modules) {
    if ($Debug) { "...importing $m" }
    $Import = Test-ModuleImport $m
    if (!($Import)) {
    return Set-PrtgError "$m module not loaded: ensure the module is visible for 32-bit PowerShell."
    }
}

###############################################################################
# Test for sharpsnmp dll loaded into the gac (possibly load it too? need to ask josh)

if (!([Reflection.Assembly]::LoadWithPartialName("SharpSnmpLib")).GlobalAssemblyCache ) {
    return Set-PrtgError "SharpSnmp Assembly not loaded: please ensure assembly is installed to GAC."
}

###############################################################################
# Connect to Prtg Server and get the current sensors with the tag netapplun

$PrtgConnection = Get-PrtgServer $PrtgHost $PrtgUser $PrtgHash

$UniqueTag      = "snmptrafficsensor"
$CurrentSensors = Get-PrtgTableData sensors $DeviceId -FilterTags $UniqueTag

###############################################################################
# Get all port aliases and names.

$AliasOid   = ".1.3.6.1.2.1.31.1.1.1.18"
$NameOid    = ".1.3.6.1.2.1.31.1.1.1.1"
$TrafficOid = ".1.3.6.1.2.1.2.2.1.10"

try   {
    $Aliases = Invoke-SnmpWalk $Device $Community $AliasOid -Timeout $Timeout
} catch {
    return Set-PrtgError "Couldn't retrieve aliases $Error[0]"
}

try   {
    $Names   = Invoke-SnmpWalk $Device $Community $NameOid -Timeout $Timeout
} catch {
    return Set-PrtgError "Couldn't retrieve names $Error[0]"
}

try   {
    $Traffic = Invoke-SnmpWalk $Device $Community $TrafficOid -Timeout $Timeout
} catch {
    return Set-PrtgError "Couldn't retrieve Traffic $Error[0]"
}

$SplitNameRx  = [regex] '(.+?)\ -\ (.+)'
$IndexRx      = [regex] "\d+$"
$ValidPorts = @()
$ExcludePorts = @('ha1'
                  'host')


foreach ($t in $Traffic) {
    $Index       = $IndexRx.Match($t.Oid).Value
    $AliasLookup = $Aliases | ? { $_.Oid -match "\.$Index$" }
    $NameLookup  = $Names   | ? { $_.Oid -match "\.$Index$" }

    $PortObject        = "" | Select Index,Name,Alias

    $PortObject.Index  = $Index
    $PortObject.Name   = $NameLookup.Data
    $PortObject.Alias  = $AliasLookup.Data
    
    if ($ExcludePorts -notcontains $PortObject.Name) {
        $ValidPorts     += $PortObject
        Write-Verbose $PortObject
    }
}


###############################################################################
# Remove sensors who's aliases have been removed.
# Rename sensors who's aliases have changed.

$Renamed = 0
$Removed = 0

Write-Verbose "-------- Checking for Rename/Removal --------"

foreach ($c in ($CurrentSensors | ? { $_.objid })) {
    $SplitNameMatch = $SplitNameRx.Match($c.sensor)

    if ($SplitNameMatch.Success) {
        $NameString  = $SplitNameMatch.Groups[1].Value
        $AliasString = $SplitNameMatch.Groups[2].Value
    } else {
        $NameString  = $c.sensor
        $AliasString = ""
    }

    Write-Verbose "CurrentSensor: $($c.sensor)"
    Write-Verbose "Name: $NameString`."
    Write-Verbose "Alias: $AliasString`."

    $Lookup = $ValidPorts | ? { $_.Name -eq $NameString }
    
    if (!($Lookup.Alias) -and !($All)) {

        $RemovePort   = Remove-PrtgObject $c.objid
        $LogContents += "Removed sensor $($c.objid): $($c.sensor)`n"
        $Removed++
        Write-Verbose "Removed"

    } elseif ($Lookup.Alias -ne $AliasString) {
        if ($Lookup.Alias) {
            $c.sensor = "$($Lookup.Name) - $($Lookup.Alias)"
        } else {
            $c.sensor = $Lookup.Name
        }
        
        $RenamePort   = Rename-PrtgObject $c.objid $c.sensor
        $LogContents += "Renamed sensor $($c.objid): $($c.sensor)`n"
        $Renamed++
        Write-Verbose "Renamed"
    }
    
}


###############################################################################
# Create missing sensors

$Created = 0

if ($All) {
    $CreatePorts = $ValidPorts
} else {
    $CreatePorts = $ValidPorts | ? { $_.Alias }
}

foreach ($c in $CreatePorts) {
    if ($c.Alias) {
        $NewSensorName = "$($c.Name) - $($c.Alias)"
    } else {
        $NewSensorName = "$($c.Name)"
    }

    $Lookup = $CurrentSensors | ? { $_.Sensor -eq $NewSensorName }

    if (!($Lookup)) {
        $CreateSensor = New-PrtgSnmpTrafficSensor $NewSensorName $c.Index $DeviceId -ShowErrors -ShowDiscards
        $LogContents += "Created sensor $NewSensorname"
        $Created++
        Write-Verbose "Creating $NewSensorName"
    }
}

$Sorted = @()
if ($Sort) {
    
    $MakeOid = ".1.3.6.1.2.1.1.1.0"
    try {
        $DeviceMake = (Invoke-SnmpGet $Device $Community $MakeOid).Data
        Write-Verbose "DeviceMake: $DeviceMake"
            
        $UseSort = $SortTable | ? { $DeviceMake -match $_.Make }
    } catch {
        return Set-PrtgError "Couldn't retrieve Make/Model $Error[0]"
    }

    
    $CurrentSensors = Get-PrtgTableData sensors $DeviceId -FilterTags $UniqueTag

    foreach ($c in $CurrentSensors) {
        $SplitNameMatch = $SplitNameRx.Match($c.sensor)

        if ($SplitNameMatch.Success) {
            $NameString  = $SplitNameMatch.Groups[1].Value
        } else {
            $NameString  = $c.sensor
        }

        $SensorInfo       = "" | Select objid,Name
        $SensorInfo.objid = $c.objid
        $SensorInfo.Name  = $NameString

        $Sorted += $SensorInfo
    }

    $SortRx = [regex]$UseSort.SortRx
    Write-Verbose $UseSort.SortRx


    $Sorted = $Sorted | sort $UseSort.SortEx

    foreach ($s in $Sorted) {
        $MoveObject = Move-PrtgObject $s.objid bottom
        Write-Verbose "Moving $($s.objid) $($s.Name) to bottom"
    }
}


$XmlOutput  = "<prtg>`n"

$XmlOutput += Set-PrtgResult "Total"   $AliasedPorts.Count sensors
$XmlOutput += Set-PrtgResult "Created" $Created sensors
$XmlOutput += Set-PrtgResult "Removed" $Removed sensors
$XmlOutput += Set-PrtgResult "Renamed" $Renamed sensors

$XmlOutput += "</prtg>"

$XmlOutput
