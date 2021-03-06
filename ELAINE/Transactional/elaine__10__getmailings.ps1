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
	    scriptPath= "C:\Users\Florian\Documents\GitHub\AptecoCustomChannels\ELAINE\Transactional"
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
$libSubfolder = "lib"
$settingsFilename = "settings.json"
$moduleName = "ELNMAILINGS"
$processId = [guid]::NewGuid()

# Load settings
$settings = Get-Content -Path "$( $scriptPath )\$( $settingsFilename )" -Encoding UTF8 -Raw | ConvertFrom-Json

# Allow only newer security protocols
# hints: https://www.frankysweb.de/powershell-es-konnte-kein-geschuetzter-ssltls-kanal-erstellt-werden/
if ( $settings.changeTLS ) {
    $AllProtocols = @(    
        [System.Net.SecurityProtocolType]::Tls12
    )
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols
}

# more settings
$logfile = $settings.logfile
#$guid = ([guid]::NewGuid()).Guid # TODO [ ] use this guid for a specific identifier of this job in the logfiles

# append a suffix, if in debug mode
if ( $debug ) {
    $logfile = "$( $logfile ).debug"
}


################################################
#
# FUNCTIONS
#
################################################

# Load all PowerShell Code
"Loading..."
Get-ChildItem -Path ".\$( $functionsSubfolder )" -Recurse -Include @("*.ps1") | ForEach {
    . $_.FullName
    "... $( $_.FullName )"
}
<#
# Load all exe files in subfolder
$libExecutables = Get-ChildItem -Path ".\$( $libSubfolder )" -Recurse -Include @("*.exe") 
$libExecutables | ForEach {
    "... $( $_.FullName )"
    
}

# Load dll files in subfolder
$libExecutables = Get-ChildItem -Path ".\$( $libSubfolder )" -Recurse -Include @("*.dll") 
$libExecutables | ForEach {
    "Loading $( $_.FullName )"
    [Reflection.Assembly]::LoadFile($_.FullName) 
}
#>


################################################
#
# LOG INPUT PARAMETERS
#
################################################

# Start the log
Write-Log -message "----------------------------------------------------"
Write-Log -message "$( $modulename )"
Write-Log -message "Got a file with these arguments:"
[Environment]::GetCommandLineArgs() | ForEach {
    Write-Log -message "    $( $_ -replace "`r|`n",'' )"
}
# Check if params object exists
if (Get-Variable "params" -Scope Global -ErrorAction SilentlyContinue) {
    $paramsExisting = $true
} else {
    $paramsExisting = $false
}

# Log the params, if existing
if ( $paramsExisting ) {
    Write-Log -message "Got these params object:"
    $params.Keys | ForEach-Object {
        $param = $_
        Write-Log -message "    ""$( $param )"" = ""$( $params[$param] )"""
    }
}


################################################
#
# PROGRAM
#
################################################


#-----------------------------------------------
# PREPARE CALLING ELAINE
#-----------------------------------------------

Create-ELAINE-Parameters


#-----------------------------------------------
# ELAINE VERSION
#-----------------------------------------------
<#
This call should be made at the beginning of every script to be sure the version is filled (and the connection could be made)
#>

if ( $settings.checkVersion ) { 

    $elaineVersion = Invoke-ELAINE -function "api_getElaineVersion"
    # or like this to get it back as number
    #$elaineVersion = Invoke-ELAINE -function "api_getElaineVersion" -method "Post" -parameters @($true)

    Write-Log -message "Using ELAINE version '$( $elaineVersion )'"

    # Use this function to check if a mininum version is needed to call the function
    #Check-ELAINE-Version -minVersion "6.2.2"

}


#-----------------------------------------------
# LOAD THE TRANSACTIONAL MAILINGS
#-----------------------------------------------

switch ( $settings.mailings.loadMailingsMethod ) {

    1 {

        #-----------------------------------------------
        # MAILINGS BY STATUS - METHOD 1
        #-----------------------------------------------
        <#
        This one returns the nl_id, nl_name and nl_status
        Transactional Mailings and Automation Mails (subscribe, unsubscribe, etc.) have the status "actionmail", the normal mailings have "ready"
        #>

        $jsonInput = @(
            ""              # message_name : string
            "actionmail"    # message_status : on_hold|actionmail|ready|clearing|not_started|finished|processing|paused|aborted|failed|queued|scheduled|pending|sampling|deleted -> an empty string means all status
        ) 
        $templates = Invoke-ELAINE -function "api_getMessageInfo" -parameters $jsonInput
        
    }

    2 {

        #-----------------------------------------------
        # MAILINGS BY STATUS - METHOD 2 - SINCE 5.12.0 
        #-----------------------------------------------

        $check = Check-ELAINE-Version -minVersion "5.12.2"

        if ( $check ) {
            $jsonInput = @(
                ""      # message_name : string
            ) 
            $templates = Invoke-ELAINE -function "api_getActionmails" -parameters $jsonInput
        } else {
            throw [System.IO.InvalidDataException] "You need version 5.12.2 to run this function."
        }

    }

    Default {

        
        #-----------------------------------------------
        # MAILINGS BY STATUS - METHOD 3
        #-----------------------------------------------
        <#
        This one returns nl_id,nl_status,nl_failure_code,nl_start_time,nl_finish_time,nl_nr_of_mails,nl_sent_mails,nl_mails_failed,nl_send_limit
        Possible status
        on_hold|actionmail|ready|clearing|not_started|finished|processing|paused|aborted|failed|queued|scheduled|pending|sampling|deleted -> leerer string ist auch möglich für alle
        #>

        $function = "api_getMailingsByStatus"
        $jsonInput = @(
            "actionmail" # message_status : on_hold|actionmail|ready|clearing|not_started|finished|processing|paused|aborted|failed|queued|scheduled|pending|sampling|deleted -> an empty string means all status
        ) 
        $mailingsByStatus = Invoke-ELAINE -function "api_getMailingsByStatus" -parameters $jsonInput


        #-----------------------------------------------
        # GET ALL MAILINGS DETAILS VIA SINGLE CALLS
        #-----------------------------------------------

        $templates = [System.Collections.ArrayList]@()
        $mailingsByStatus | ForEach-Object {

            $nl = $_
            $jsonInput = @(
                "Mailing"               # objectType : Datafield|Mailing|Group|Segment
                "$( $nl.nl_id )"        # objectID
            ) 
            $res = Invoke-ELAINE -function "api_getDetails" -parameters $jsonInput
            [void]$templates.Add(@($res))
            
        }

    }

}


#-----------------------------------------------
# BUILD MAILING OBJECTS
#-----------------------------------------------

$mailings = [System.Collections.ArrayList]@()
$templates | foreach {

    # Load data
    $template = $_

    # Create mailing objects
    [void]$mailings.Add([Mailing]@{
        mailingId=$template.nl_id
        mailingName=$template.nl_name
    })

}

$messages = $mailings | Select @{name="id";expression={ $_.mailingId }}, @{name="name";expression={ $_.toString() }}


################################################
#
# RETURN
#
################################################

# real messages
return $messages


