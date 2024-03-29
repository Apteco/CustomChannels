﻿################################################
#
# INPUT
#
################################################

Param(
    [hashtable] $params
)

#-----------------------------------------------
# DEBUG SWITCH
#-----------------------------------------------

$debug = $false

#-----------------------------------------------
# INPUT PARAMETERS, IF DEBUG IS TRUE
#-----------------------------------------------

if ( $debug ) {
    $params = [hashtable]@{
	    Password= "def"
	    scriptPath= "C:\FastStats\scripts\episervercampaign"
	    abc= "def"
	    Username= "abc"
    }
}


################################################
#
# NOTES
#
################################################

<#

https://world.optimizely.com/documentation/developer-guides/campaign/SOAP-API/introduction-to-the-soap-api/basic-usage/
WSDL: https://api.campaign.episerver.net/soap11/RpcSession?wsdl

#>

################################################
#
# SCRIPT ROOT
#
################################################

if ( $debug ) {
    # Load scriptpath
    if ($MyInvocation.MyCommand.CommandType -eq "ExternalScript") {
        $scriptPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
    } else {
        $scriptPath = Split-Path -Parent -Path ([Environment]::GetCommandLineArgs()[0])
    }
} else {
    $scriptPath = "$( $params.scriptPath )" 
}
Set-Location -Path $scriptPath


################################################
#
# SETTINGS
#
################################################

# General settings
$functionsSubfolder = "functions"
$settingsFilename = "settings.json"
$moduleName = "GETMAILINGS"
$processId = [guid]::NewGuid()

# Load settings
$settings = Get-Content -Path "$( $scriptPath )\$( $settingsFilename )" -Encoding UTF8 -Raw | ConvertFrom-Json

# Allow only newer security protocols
# hints: https://www.frankysweb.de/powershell-es-konnte-kein-geschuetzter-ssltls-kanal-erstellt-werden/
if ( $settings.changeTLS ) {
    $AllProtocols = @(    
        [System.Net.SecurityProtocolType]::Tls12
        #[System.Net.SecurityProtocolType]::Tls13,
        ,[System.Net.SecurityProtocolType]::Ssl3
    )
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols
}

# TODO [ ] change campaign type

# more settings
$logfile = $settings.logfile
#$guid = ([guid]::NewGuid()).Guid
$campaignType = $settings.campaignType

# append a suffix, if in debug mode
if ( $debug ) {
    $logfile = "$( $logfile ).debug"
}


################################################
#
# FUNCTIONS
#
################################################

Get-ChildItem -Path ".\$( $functionsSubfolder )" | ForEach {
    . $_.FullName
}

################################################
#
# LOG INPUT PARAMETERS
#
################################################

# Start the log
Write-Log -message "----------------------------------------------------"
Write-Log -message "$( $modulename )"
Write-Log -message "Got a file with these arguments: $( [Environment]::GetCommandLineArgs() )"

# Check if params object exists
if (Get-Variable "params" -Scope Global -ErrorAction SilentlyContinue) {
    $paramsExisting = $true
} else {
    $paramsExisting = $false
}

# Log the params, if existing
if ( $paramsExisting ) {
    $params.Keys | ForEach-Object {
        $param = $_
        Write-Log -message "    $( $param ): $( $params[$param] )"
    }
}



################################################
#
# PROGRAM
#
################################################


#-----------------------------------------------
# GET CURRENT SESSION OR CREATE A NEW ONE
#-----------------------------------------------

Write-Log -message "Opening a new session in EpiServer valid for $( $settings.ttl )"

Get-EpiSession


#-----------------------------------------------
# GET MAILINGS / CAMPAIGNS
#-----------------------------------------------
<#
switch ( $campaignType ) {

    "classic" {

        $campaigns = Invoke-Epi -webservice "Mailing" -method "getIdsInStatus" -param @("regular", "NEW") -useSessionId $true
        
    }

    # smart campaigns are the default value
    default {

        # get all mailings in smart campaigns
        $mailings = Invoke-Epi -webservice "Mailing" -method "getIdsInStatus" -param @("campaign", "ACTIVATION_REQUIRED") -useSessionId $true

        # get all compound elements for the mailings => campaign
        $campaigns = @()
        $mailings | Select -Unique | ForEach {
            $mailingId = $_
            $campaigns += Invoke-Epi -webservice "SplitMailing" -method "getSplitMasterId" -param @(@{value=$mailingId;datatype="long"}) -useSessionId $true   
        }
        
    }

}
#>

$campaigns = Get-EpiCampaigns -campaignType $campaignType

Write-Log -message "Got back $( $campaigns.count ) campaigns/mailings"


#-----------------------------------------------
# GET MAILINGS / CAMPAIGNS DETAILS
#-----------------------------------------------

$campaignDetails = @()
$campaigns | Select -Unique | ForEach {

    $campaignId = $_

    # create new object
    $campaign = New-Object PSCustomObject
    $campaign | Add-Member -MemberType NoteProperty -Name "ID" -Value $campaignId

    # ask for name
    $campaignName = Invoke-Epi -webservice "Mailing" -method "getName" -param @(@{value=$campaignId;datatype="long"}) -useSessionId $true
    $campaign | Add-Member -MemberType NoteProperty -Name "Name" -Value $campaignName

    $campaignDetails += $campaign

}


#-----------------------------------------------
# GET MAILINGS / CAMPAIGNS DETAILS
#-----------------------------------------------

$messages = $campaignDetails | Select @{name="id";expression={ $_.ID }}, @{name="name";expression={ "$( $_.ID )$( $settings.nameConcatChar )$( $_.Name )" }}


################################################
#
# RETURN
#
################################################

# real messages
return $messages

