
###############################################################################

# MONITOR THE UPS THAT'S PROTECTING THE SERVER!

###############################################################################

function Set-PrtgResult {
    Param (
    [Parameter(mandatory=$True,Position=0)]
    [string]$Channel,
    
    [Parameter(mandatory=$True,Position=1)]
    [string]$Value,
    
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
    [alias('dm')]
    [ValidateSet("Auto","All")]
    [string]$DecimalMode,
    
    [Parameter(mandatory=$False)]
    [alias('w')]
    [switch]$Warning
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
    
    #<SpeedSize>
	if (!($Value -is [int])) { $Result += "    <float>1</float>`n" }
    if ($Mode)        { $Result += "    <mode>$Mode</mode>`n" }
    if ($MaxWarn)     { $Result += "    <limitmaxwarning>$MaxWarn</limitmaxwarning>`n"; $LimitMode = $true }
    if ($MaxError)    { $Result += "    <limitminwarning>$MinWarn</limitminwarning>`n"; $LimitMode = $true }
    if ($MaxError)    { $Result += "    <limitmaxerror>$MaxError</limitmaxerror>`n"; $LimitMode = $true }
    if ($WarnMsg)     { $Result += "    <limitwarningmsg>$WarnMsg</limitwarningmsg>`n"; $LimitMode = $true }
    if ($ErrorMsg)    { $Result += "    <limiterrormsg>$ErrorMsg</limiterrormsg>`n"; $LimitMode = $true }
    if ($LimitMode)   { $Result += "    <limitmode>1</limitmode>`n" }
    if ($SpeedSize)   { $Result += "    <speedsize>$SpeedSize</speedsize>`n" }
    if ($DecimalMode) { $Result += "    <decimalmode>$DecimalMode</decimalmode>`n" }
    if ($Warning)     { $Result += "    <warning>1</warning>`n" }
    
    if (!($ShowChart)) { $Result += "    <showchart>0</showchart>`n" }
    
    $Result += "  </result>`n"
    
    return $Result
}

###############################################################################
	
# http://www.powershellcookbook.com/recipe/vODQ/script-a-web-application-session

# get a session from the server, set the form fields, then submit them
$LoginForm = "http://hostname-or-ip-of-ppbe:3052/agent/index"
$LoginObject = Invoke-WebRequest $LoginForm -SessionVariable ups
$FormObject = $LoginObject.Forms[0]
$FormObject.Fields["value(username)"] = "admin"
$FormObject.Fields["value(password)"] = "admin"
$FormObject.Fields["value(action)"] = "Login"
$FormObject.Fields["value(persistentCookie)"] = "true"
$FormObject.Fields["value(button)"] = "Login"
$null = Invoke-WebRequest $LoginForm -WebSession $ups -Body $FormObject.Fields -Method Post

# take the session that you've created and request the data

$RawStatusData = Invoke-WebRequest "http://hostname-or-ip-of-ppbe:3052/agent/ppbe.xml"  -WebSession $ups -Method Post -Body '<?xml version="1.0" encoding="UTF-8" ?><ppbe><target><command>battery.backup.status</command></target><inquire /></ppbe>'

$RawStatusData = [xml]$RawStatusData.Content

$InputVoltage = $RawStatusData.ppbe.reply.status.utility.voltage
$OutputVoltage = $RawStatusData.ppbe.reply.status.output.voltage
$OutputWattage = $RawStatusData.ppbe.reply.status.output.watt
$OutputPercentLoad = $RawStatusData.ppbe.reply.status.output.load
$BatteryVoltage = $RawStatusData.ppbe.reply.status.battery.voltage
$BatteryCapacity = $RawStatusData.ppbe.reply.status.battery.capacity
$BatteryRuntime = New-TimeSpan -Hours $RawStatusData.ppbe.reply.status.battery.runtimeHour -Minutes $RawStatusData.ppbe.reply.status.battery.runtimeMinute

###############################################################################

$XmlOutput  = "<prtg>`n"
$XmlOutput += Set-PrtgResult "Input Voltage" $InputVoltage "volts"
$XmlOutput += Set-PrtgResult "Output Voltage" $OutputVoltage "volts"
$XmlOutput += Set-PrtgResult "Output Wattage" $OutputWattage "watts" -ShowChart
$XmlOutput += Set-PrtgResult "Output Load" $OutputPercentLoad "%" -ShowChart
$XmlOutput += Set-PrtgResult "Battery Voltage" $BatteryVoltage "volts"
$XmlOutput += Set-PrtgResult "Battery Capacity" $BatteryCapacity "%"
$XmlOutput += Set-PrtgResult "Battery Runtime" $BatteryRuntime.TotalMinutes "minutes"
$XmlOutput += "</prtg>"
$XmlOutput