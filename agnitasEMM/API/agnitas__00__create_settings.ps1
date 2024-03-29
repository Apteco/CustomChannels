
################################################
#
# INPUT
#
################################################


#-----------------------------------------------
# DEBUG SWITCH
#-----------------------------------------------

$debug = $true
$configMode = $true


################################################
#
# NOTES
#
################################################

<#

https://ws.agnitas.de/2.0/emmservices.wsdl
https://emm.agnitas.de/manual/de/pdf/webservice_pdf_de.pdf

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
# SETTINGS AND STARTUP
#
################################################

# General settings
$modulename = "EMMCREATESETTINGS"

# Load other generic settings like process id, startup timestamp, ...
. ".\bin\general_settings.ps1"

# Setup the network security like SSL and TLS
. ".\bin\load_networksettings.ps1"

# Load functions and assemblies
. ".\bin\load_functions.ps1"


################################################
#
# START
#
################################################


#-----------------------------------------------
# ASK FOR SETTINGSFILE
#-----------------------------------------------

# Default file
$settingsFileDefault = "$( $scriptPath )\settings.json"

# Ask for another path
$settingsFile = Read-Host -Prompt "Where do you want the settings file to be saved? Just press Enter for this default [$( $settingsFileDefault )]"

# ALTERNATIVE: The file dialog is not working from Visual Studio Code, but is working from PowerShell ISE or "normal" PowerShell Console
#$settingsFile = Set-FileName -initialDirectory "$( $scriptPath )" -filter "JSON files (*.json)|*.json"

# If prompt is empty, just use default path
if ( $settingsFile -eq "" -or $null -eq $settingsFile) {
    $settingsFile = $settingsFileDefault
}

# Check if filename is valid
if(Test-Path -LiteralPath $settingsFile -IsValid ) {
    Write-Host "SettingsFile '$( $settingsFile )' is valid"
} else {
    Write-Host "SettingsFile '$( $settingsFile )' contains invalid characters"
}


#-----------------------------------------------
# ASK FOR LOGFILE
#-----------------------------------------------

# Default file
$logfileDefault = "$( $scriptPath )\emm.log"

# Ask for another path
$logfile = Read-Host -Prompt "Where do you want the log file to be saved? Just press Enter for this default [$( $logfileDefault )]"

# ALTERNATIVE: The file dialog is not working from Visual Studio Code, but is working from PowerShell ISE or "normal" PowerShell Console
#$settingsFile = Set-FileName -initialDirectory "$( $scriptPath )" -filter "JSON files (*.json)|*.json"

# If prompt is empty, just use default path
if ( $logfile -eq "" -or $null -eq $logfile) {
    $logfile = $logfileDefault
}

# Check if filename is valid
if(Test-Path -LiteralPath $logfile -IsValid ) {
    Write-Host "Logfile '$( $logfile )' is valid"
} else {
    Write-Host "Logfile '$( $logfile )' contains invalid characters"
}


#-----------------------------------------------
# LOAD LOGGING MODULE NOW
#-----------------------------------------------

$settings = @{
    "logfile" = $logfile
}

# Setup the log and do the initial logging e.g. for input parameters
. ".\bin\startup_logging.ps1"


#-----------------------------------------------
# LOG THE NEW SETTINGS CREATION
#-----------------------------------------------

Write-Log -message "Creating a new settings file" -severity ( [Logseverity]::WARNING )


################################################
#
# SETTINGS
#
################################################

#-----------------------------------------------
# LOGIN DATA AGNITAS
#-----------------------------------------------

# Entering the username and password
# $base = Read-Host "Please enter account sessionId"
$username = Read-Host "Please enter the username for Agnitas REST API"
$password = Read-Host -AsSecureString "Please enter the password for Agnitas REST API"

# Combining username and password; making it ready for BasicAuth
$credentials = "$($username):$(( New-Object PSCredential "dummy",$password).GetNetworkCredential().Password)"

# Encoding to Base64
$BytesCredentials = [System.Text.Encoding]::ASCII.GetBytes($credentials)
$EncodedCredentials = [Convert]::ToBase64String($BytesCredentials)

# Authorization header value 
$auth = "Basic $( $EncodedCredentials )"

# Encrypting Authorization header
$credentialsEncrypted = Get-PlaintextToSecure $auth

$login = @{
    "authenticationHeader" = $credentialsEncrypted
}
<#
# Soap Password
$soapUsername = Read-Host "Please enter the username for Agnitas SOAP API"
$soapPassword = Read-Host -AsSecureString "Please enter the password for Agnitas SOAP API"
$soapPasswordEncrypted = Get-PlaintextToSecure "$(( New-Object PSCredential "dummy",$soapPassword).GetNetworkCredential().Password)"

$soapAuth =@{
    username = $soapUsername
    password = $soapPasswordEncrypted
}
#>

#-----------------------------------------------
# ASK IF THERE IS A PROXY USED
#-----------------------------------------------

# ask for credentials if e.g. a proxy is used (normally without the prefixed domain)
#$cred = Get-Credential
#$proxyUrl = "http://proxy:8080"

# TODO [ ] sometimes the proxy wants an additional content type or header -> do if this comes up

# More useful links
# https://stackoverflow.com/questions/13552227/using-proxy-automatic-configuration-from-ie-settings-in-net
# https://stackoverflow.com/questions/20471486/how-can-i-make-invoke-restmethod-use-the-default-web-proxy/20472024  

$proxyDecision = $Host.UI.PromptForChoice("Proxy usage", "Do you use a proxy for network authentication?", @('&Yes'; '&No'), 1)

If ( $proxyDecision -eq "0" ) {

    # Means yes and proceed

    # Try a figure out the uri
    $proxyUriSuggest = [System.Net.WebRequest]::GetSystemWebProxy().GetProxy("http://www.apteco.de")

    # Ask for the uri
    $proxyUriDecision = $Host.UI.PromptForChoice("Proxy uri", "I have figured out the url '$( $proxyUriSuggest.ToString() )'. Is that correct?", @('&Yes'; '&No'), 1)
    If ( $proxyUriDecision -eq "0" ) {

        # yes, correct
        $proxyUri = $proxyUriSuggest.toString()

    } else {

        # no, not correct
        $proxyUri = Read-Host "Please enter the proxy url like 'http://proxyurl:8080'"

    }

    # Next step, figure out credentials
    $proxyCredentialsDecision = $Host.UI.PromptForChoice("Proxy credentials", "Remember the FastStats Service is normally running with another windows user. So do you want to use the current account user login?", @('&Yes'; '&No'), 1)
    If ( $proxyCredentialsDecision -eq "0" ) {
        
        # yes, use default credentials
        $proxyUseDefaultCredentials = $true
        $proxyCredentials = @{}

    } else {

        # no, use other credentials
        $proxyUseDefaultCredentials = $false

        # Soap Password
        $proxyUsername = Read-Host "Please enter the username for proxy authentication"
        $proxyPassword = Read-Host -AsSecureString "Please enter the password for proxy authentication"
        $proxyPasswordEncrypted = Get-PlaintextToSecure "$(( New-Object PSCredential "dummy",$proxyPassword).GetNetworkCredential().Password)"

        $proxyCredentials = @{
            "username" = $proxyUsername
            "password" = $proxyPasswordEncrypted
        }

    }

    $proxy = @{
        "proxyUrl" = $proxyUri # ""|"http://proxyurl:8080"
        #"useDefaultCredentials" = $false   # Do this by default if a proxy is used
        "proxyUseDefaultCredentials" = $proxyUseDefaultCredentials
        "credentials" = $proxyCredentials
    }

} else {
    
    # Leave the process here
    
    $proxy = @{}

}

#-----------------------------------------------
# LOGIN DATA SFTP
#-----------------------------------------------

# ask for sftp sessions
$sftpHostname = Read-Host "Please enter the hostname for sftp"
$sftpUsername = Read-Host "Please enter the username for sftp"
$sftpPassword = Read-Host -AsSecureString "Please enter the password for sftp"
$sftpKeyfingerprint = Read-Host "Please enter the Ssh Host Key Fingerprint, something like ssh-ed25519 255 yrt1ZYQO/YULXZ/IXS..."
$sftpPasswordEncrypted = Get-PlaintextToSecure "$(( New-Object PSCredential "dummy",$sftpPassword).GetNetworkCredential().Password)"

# bring sftp settings together
$sftpSettings = @{
    "HostName" = $sftpHostname
    "Username" = $sftpUsername
    "Password" = $sftpPasswordEncrypted
    "SshHostKeyFingerprint" = $sftpKeyfingerprint
    "Raw" = [Hashtable]@{}
}

# Add sftp proxy settings
# https://winscp.net/eng/docs/rawsettings
$proxySFTPDecision = $Host.UI.PromptForChoice("Proxy usage", "Do you want to add the same proxy settings for SFTP?", @('&Yes'; '&No'), 1)
If ( $proxySFTPDecision -eq "0" ) {

    $sftpSettings.Raw.Add("ProxyMethod", "3") # 0 = None, 1 = SOCKS4, 2 = SOCKS5, 3 = HTTP, 4 = Telnet (SFTP/SCP protocols only), 5 = Local (SFTP/SCP), For additional options with FTP protocol, see FtpProxyLogonType
    $sftpSettings.Raw.Add("ProxyHost", $proxyUri)

    If ( $proxyCredentials ) {
        $sftpSettings.Raw.Add("ProxyUsername", $proxyCredentials.username)
        $sftpSettings.Raw.Add("ProxyPassword", $proxyCredentials.password)
    }
}


#-----------------------------------------------
# MESSAGE SETTINGS
#-----------------------------------------------

$messages = @{
    copyString = "#COPY#"
}


#-----------------------------------------------
# UPLOAD SETTINGS
#-----------------------------------------------

$autoImport = Read-Host "Please enter your Agnitas EMM Auto Import ID you have created to import files automatically, e.g. like 847" #847

$upload = @{
    rotatingTargetGroups = 15  # Number of targetGroups, that are re-used for Mailings sends
    targetGroupPrefix = "Apteco Campaign Target Group: "
    standardMailingList = 0
    autoImportId = $autoImport
    archiveImportFile = $true
    sleepTime = 20               # seconds to wait between the status checks of import
    maxSecondsWaiting = 900     # seconds to wait at maximum for the import
    archiveFolder = "/archive"
    uploadFolder = "/import"
}


#-----------------------------------------------
# BROADCAST SETTINGS
#-----------------------------------------------

$broadcast = @{
    lockfile = "$( $scriptPath )\sending.lock"     # file that is being used to make sure there is only one broadcast at a time
    maxLockfileAge = 600                            # max seconds to exist for a lockfile - after that it will be deleted and will proceed with the next broadcast
    lockfileRetries = 30                            # How often do you want to request the existence of the lockfile 
    lockfileDelayWhileWaiting = 10000               # Millieseconds delay between retries
    #sleepTime = 3                                   # seconds to wait between the status checks of import
    #maxSecondsWaiting = 240                         # seconds to wait at maximum for the import
}


#-----------------------------------------------
# RESPONSE / CLEANUP SETTINGS
#-----------------------------------------------

$response = @{
    cleanupMailings = $true                     # Should older mailings be automatically cleaned up
    maxAgeMailings = -14                        # Mailings will be automatically deleted after n days if the response job is running and cleanupMailings is true
    cleanupSFTPArchive = $true                  # Should older upload files automatically cleaned up
    maxAgeArchiveFiles = -7                     # Max age for files on the sftp archive folder
    exportFolder = "/export"                    # Remote export folder on sftp
    exportDirectory = "$( $scriptPath )\export" # Local folder for downloading export files from sftp
    triggerFerge = $true                        # Should FERGE be triggered to download response data
    bulkDirectory = "$( $scriptPath )\bulk"     # FERGE bulk folder - path needs to be reachable via SQLServer
    taskDefaultName = "Response Gathering for Agnitas EMM"
}


#-----------------------------------------------
# SETTINGS OBJECT
#-----------------------------------------------

# TODO [ ] check if some settings could be brought together

$settings = @{

    # General settings
    "base" = "https://emm.agnitas.de/restful"
    "encoding" = "utf8"
    "nameConcatChar" =   " | "
    "providername" = "agnitasEMM"                        # identifier for this custom integration, this is used for the response allocation
    "logfile" = $logfile
    "winscplogfile" = "$( $scriptPath )\winscp.log"
    "timestampFormat" = "yyyy-MM-dd--HH-mm-ss"
    "powershellExePath" = "powershell.exe"    # Define other powershell path, e.g if you want to use pwsh for powershell7

    # Network settings
    "changeTLS" = $true
    "proxy" = $proxy # Proxy settings, if needed - will be automatically used
    
    # SOAP settings
    # "soap" = @{
    #     "base" = "https://ws.agnitas.de/2.0/"
    #     "Username" = $soapUsername
    #     "Password" = $soapPasswordEncrypted
    #     "contentType" = "application/json;charset=utf-8"
    #     "authentication" = $soapAuth
    # }
    #"baseSOAP" = "https://ws.agnitas.de/2.0/"   # TODO [x] check which url is used

    # Detail settings
    "login" = $login
    "sftpSession" = $sftpSettings
    "messages" = $messages
    "upload" = $upload
    "broadcast" = $broadcast
    "response" = $response

}


################################################
#
# PACK TOGETHER SETTINGS AND SAVE AS JSON
#
################################################

# rename settings file if it already exists
If ( Test-Path -Path $settingsFile ) {
    $backupPath = "$( $settingsFile ).$( $timestamp.ToString("yyyyMMddHHmmss") )"
    Write-Log -message "Moving previous settings file to $( $backupPath )" -severity ( [Logseverity]::WARNING )
    Move-Item -Path $settingsFile -Destination $backupPath
} else {
    Write-Log -message "There was no settings file existing yet"
}

# create json object
$json = $settings | ConvertTo-Json -Depth 99 # -compress

# print settings to console
$json

# save settings to file
$json | Set-Content -path $settingsFile -Encoding UTF8


################################################
#
# CREATE FOLDERS IF NEEDED
#
################################################

# Creating the lib folder for the sqlite stuff
$libFolder = ".\$( $libSubfolder )"
if ( !(Test-Path -Path "$( $libFolder )") ) {
    Write-Log -message "lib folder '$( $libFolder )' does not exist. Creating the folder now!"
    New-Item -Path "$( $libFolder )" -ItemType Directory
}

# Export folder to put exported files from Agnitas
$exportDir = $settings.response.exportDirectory
if ( !(Test-Path -Path "$( $exportDir )") ) {
    Write-Log -message "export folder '$( $exportDir )' does not exist. Creating the folder now!"
    New-Item -Path "$( $exportDir )" -ItemType Directory
}

# Bulk folder for FERGE - needs to be reachable from SQLServer
$bulkDir = $settings.response.bulkDirectory
if ( !(Test-Path -Path "$( $bulkDir )") ) {
    Write-Log -message "bulk folder '$( $bulkDir )' does not exist. Creating the folder now! Make sure the path is reachable from SQLServer"
    New-Item -Path "$( $bulkDir )" -ItemType Directory
}

################################################
#
# RELOAD EVERYTHING
#
################################################

#-----------------------------------------------
# RELOAD SETTINGS
#-----------------------------------------------

# Load the settings from the local json file
. ".\bin\load_settings.ps1"

# Load functions and assemblies
. ".\bin\load_functions.ps1"

# Load the preparation file to prepare the connections
. ".\bin\preparation.ps1"


################################################
#
# DOWNLOAD AND INSTALL THE WINSCP PACKAGE
#
################################################

$winscpDll = "WinSCPnet.dll"

if ( $libDlls.Name -notcontains $winscpDll ) {

    Write-Log -message "A browser page is opening now. Please download the .NET assembly library zip file"
    Write-Log -message "Please unzip the file and put it into the lib folder"
        
    Start-Process "https://winscp.net/download/WinSCP-5.19.2-Automation.zip"
    
    # Wait for key
    Write-Host -NoNewLine 'Press any key if you have put the files there';
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');

    # Confirm you read the licence details
    $decision = $Host.UI.PromptForChoice("Confirmation", "Can you confirm you read 'license-dotnet.txt' and 'license-winscp.txt'", @('&Yes'; '&No'), 1)

    If ( $decision -eq "0" ) {

        # Means yes and proceed

    } else {
        
        # Leave the process here
        exit 0

    }

}


################################################
#
# DO SOME MORE SETTINGS DIRECTLY
#
################################################

#-----------------------------------------------
# CALCULATE FINGERPRINT FOR SFTP
#-----------------------------------------------

# TODO [ ] Fill this with code
<#
# Setup session options
$sessionOptions = [WinSCP.SessionOptions]::new()
-Property @{
    Protocol = [WinSCP.Protocol]::Sftp
    HostName = $settings.sftpSession.HostName
    UserName = $settings.sftpSession.Username
    #Password = $settings.sftpSession.Password
    #SshHostKeyFingerprint = "ssh-rsa 2048 xxxxxxxxxxx...="
}

$sessionOptions.Protocol = [WinSCP.Protocol]::Sftp
$sessionOptions.HostName = $settings.sftpSession.HostName
$sessionOptions.UserName = $settings.sftpSession.Username
$session = [WinSCP.Session]::new()

# This does not work on PS7 anymore
#$fingerprint = $session.ScanFingerprint($sessionOptions,"SHA-256") # Helper, to find out server fingerprint
$settings.sftpSession.Add("SshHostKeyFingerprint",$fingerprint)
#>


#-----------------------------------------------
# CHECK LOGIN FOR AGNITAS REST AND CHOOSE DEFAULT LIST
#-----------------------------------------------

# The default list will be used to load some receivers and to find out the valid fields

# Load the data from Agnitas EMM
try {

    <#
    https://emm.agnitas.de/manual/en/pdf/EMM_Restful_Documentation.html#api-Mailing-getMailings
    #>
    $restParams = @{
        Method = "Get"
        Uri = "$( $apiRoot )/mailinglist"
        Headers = $header
        Verbose = $true
        ContentType = $contentType
    }
    Check-Proxy -invokeParams $restParams
    $mailinglists = Invoke-RestMethod @restParams
    Write-Log -message "Please choose your default import mailing list, that you are using in your auto import job"
    $standardMailingList = $mailinglists | Out-GridView -PassThru
    $settings.upload.standardMailingList = $standardMailingList.mailinglist_id

} catch {

    Write-Log -message "Got exception during REST connection test" -severity ( [LogSeverity]::ERROR )
    Write-Log -message "  StatusCode: $( $_.Exception.Response.StatusCode.value__ )" -severity ( [LogSeverity]::ERROR )
    Write-Log -message "  StatusDescription: $( $_.Exception.Response.StatusDescription )" -severity ( [LogSeverity]::ERROR )
    Write-Log -message "  Type: '$( $_.Exception.GetType().Name )'" -severity ( [LogSeverity]::ERROR )
    Write-Log -message "  Message: '$( $_.Exception.Message )'" -severity ( [LogSeverity]::ERROR )
    Write-Log -message "  Stacktrace: '$( $_.ScriptStackTrace )'" -severity ( [LogSeverity]::ERROR )

}


#-----------------------------------------------
# CHECK LOGIN FOR AGNITAS SOAP AND CREATE TARGETGROUPS
#-----------------------------------------------

# Load targetgroups as a test
try {

    . ".\bin\load_targetGroups.ps1"

    # If the targetgroups are not enough, create them
    If ( $aptecoTargetgroups.count -lt $settings.upload.rotatingTargetGroups ) {
        $targetgroupsToCreate = $settings.upload.rotatingTargetGroups - $aptecoTargetgroups.Count
        for ( $i = 0 ; $i -lt $targetgroupsToCreate ; $i++) {
            <#
            # Prepare parameters
            $param = @{
                name = [Hashtable]@{
                    type = "string"
                    value = "$( $settings.upload.targetGroupPrefix )$( $timestamp.toString( $settings.timestampFormat ) ) "
                }
                description = [Hashtable]@{
                    type = "string"
                    value = "Targetgroup for a rotating system so for each new mailing the oldest targetgroup will be recycled"
                }
                eql = [Hashtable]@{
                    type = "string"
                    value = "send_id = '$( [guid]::NewGuid() )'"
                }
            }

            # Create the target group now
            $newTargetgroup = Invoke-Agnitas -method "AddTargetGroup" -param $param -verboseCall -namespace "http://agnitas.com/ws/schemas" #-wsse $wsse #-verboseCall        
#>
            # Create the target group now
            $restParams = @{
                Method = "Post"
                Uri = "$( $apiRoot )/target"
                Headers = $header
                Verbose = $true
                ContentType = $contentType
                Body = @{
                    "name" = "$( $settings.upload.targetGroupPrefix )$( $timestamp.toString( $settings.timestampFormat ) ) #$( $i )" # Adding i because it does not accept multiple targetgroups with the same name
                    "description" = "Targetgroup for a rotating system so for each new mailing the oldest targetgroup will be recycled"
                    "eql" = "send_id = '$( [guid]::NewGuid().toString() )'"
                } | ConvertTo-Json -Depth 99 -Compress
            }
            Check-Proxy -invokeParams $restParams
            $newTargetgroup = Invoke-RestMethod @restParams

            Write-Log -message "Created new target group with ID '$( $newTargetgroup.target_id )'"

        }
    }

} catch {

    Write-Log -message "Got exception during target group creation" -severity ( [LogSeverity]::ERROR )
    Write-Log -message "  Type: '$( $_.Exception.GetType().Name )'" -severity ( [LogSeverity]::ERROR )
    Write-Log -message "  Message: '$( $_.Exception.Message )'" -severity ( [LogSeverity]::ERROR )
    Write-Log -message "  Stacktrace: '$( $_.ScriptStackTrace )'" -severity ( [LogSeverity]::ERROR )
    
    throw $_.exception

}


################################################
#
# PACK TOGETHER SETTINGS AND SAVE AS JSON
#
################################################

# create json object
$json = $settings | ConvertTo-Json -Depth 99 # -compress

# print settings to console
$json

# save settings to file
$json | Set-Content -path $settingsFile -Encoding UTF8


################################################
#
# WAIT FOR KEY
#
################################################

Write-Host -NoNewLine 'Press any key to continue...';
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');