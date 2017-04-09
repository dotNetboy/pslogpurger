########################################################################
# Program Name: PSLogPurger
# Description: This script automates the log maintenance process from multiple target servers
# Author: dotNetboy 
# Version: 1.0
########################################################################

# Switch to enable silent mode
param([switch]$Silent=$false) 

# Script path when executed from a PowerShell console
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition

# Use he following instead if compiling to EXE (using ps2exe)
# ps2exe: https://ps2exe.codeplex.com/
<#
param([string]$SilentPassed="") 
$Silent = $false
if ($SilentPassed -eq "Silent")
{
    $Silent = $true
}
# Script path when compiled as an EXE (using ps2exe)
$scriptpath = pwd | Select-Object -ExpandProperty Path
##
#>

########################## Main program definition
function Main-Program
{
    $configFiles = @()
    $programRootItems = Get-ChildItem $scriptPath | Select-Object -ExpandProperty Name
    foreach ($item in $programRootItems)
    {
        if ($item -like "*config*" -and $item -like "*.ini*")
        {
            $configFiles += $item
        }
    }
    #Recurse through defined configuration files
    foreach ($config in $configFiles)
    {
        # Initialize variables
        $programStartTime = date
        $Continue = $True
        Init-Vars
        #Load configuration data
        try
        {
            Output-Message "Loading configuration from $config"
            $loadResult = Load-Settings -configFile "$config"
            if ($loadResult -eq $True)
            {
                Output-Message "Configuration parameters loaded successfully`n" -Green
                Output-Message "Log Maintenance Utility is now commencing..."
            }
            else
            {
                Output-Message "Error obtained while reading from configuration file $config" -Red
                Output-Message "[ERROR]: $loadResult`n" -Red
                $Continue = $false
            }
        }
        catch [System.Exception]
        {
            Output-Message "Error encountered while reading from configuration file $config. Please ensure configuration syntax is correct"
            Output-Message "[ERROR]: $_"
            $Continue = $false
        }
        # Transfer 7zip binaries to log paths for local archiving
        if ($Continue -eq $True)
        {
            # Create temporary directory
            if (Test-Path "$scriptPath\Temp")
            {
                Remove-Item -Path "$scriptPath\Temp" -Force -Recurse -ErrorAction SilentlyContinue > $null
            }
            New-Item -Path "$scriptPath\Temp" -ItemType Directory -Force -ErrorAction Stop > $null
            ##
            foreach ($logObjInstance in $global:logPaths)
            {
                try
                {
                    # declare variables
                    $logServerInstance = $logObjInstance.Server
                    $logPathInstance = $logObjInstance.logPath
                    $subContinue = $false
                    ##
                    Output-Message "Log Maintenance Utility is processing $logPathInstance of $logServerInstance"
                    Output-Message "Transferring 7z binaries for local archiving in $logPathInstance"
                    $scriptparams = @{'Server'=$logServerInstance;
                                      '7zPath'=$global:7zPath;
                                      'destLocation'=$logPathInstance;
                                     }
                    $transfer7zresult = Transfer-7z @scriptparams
                    if ($transfer7zresult -eq $True)
                    {
                        Output-Message "7z binaries have been transferred to $logPathInstance" 
                        $subContinue = $True
                    }
                    else
                    {
                        Output-Message "Unable to transfer 7z binaries to $logServerInstance" -Red
                        Output-Message "[ERROR]: $transfer7zresult`n" -Red
                        $logObjInstance.Status = 'Failed'
                        $subContinue = $false
                        $global:errorExists = $True
                    }
                    if ($subContinue -eq $True)
                    {
                        $subContinue = $false
                        Output-Message "Identifying logs older than $global:logThreshold days for archiving"
                        $scriptparams = @{'Server'=$logServerInstance;
                                          'logSource'=$logPathInstance;
                                          'logSourceTemp'=$logPathInstance + '\Temp';
                                         }
                        $identifyResult = Get-OldLogs @scriptparams
                        if ($identifyResult -eq $True)
                        {
                            Output-Message "Logs older than $global:logThreshold  days in $logPathInstance have been set for archiving" 
                            $subContinue = $True
                        }
                        else
                        {
                            Output-Message "Unable to identify files to archive in $logPathInstance" -Red
                            Output-Message "[ERROR]: $identifyResult`n" -Red
                            $logObjInstance.Status = 'Failed'
                            $subContinue = $false
                            $global:errorExists = $True
                        }
                    }
                    if ($subContinue -eq $True)
                    {
                        #declare variables
                        $subContinue = $false
                        $datestamp = date -F {yyyyMMddHHmmss}
                        $archiveName = "Log_Backup_" + $datestamp + ".zip"
                        ##
                        Output-Message "Archiving identified logs in $logPathInstance"
                        $scriptparams = @{'Server'=$logServerInstance;
                                          'archiveLocation'=$logPathInstance;
                                          'archiveName'=$archiveName;
                                          'logPath'=$logPathInstance + '\Temp';
                                          'resultFilePath'=$logPathInstance + '\ResultFile.txt';
                                         }
                        $archiveResult = Archive-OldLogs @scriptparams
                        if ($archiveResult -eq $True)
                        {
                            Output-Message "Logs older than $global:logThreshold days in $logPathInstance have been successfully archived`n" -Green 
                            $subContinue = $True
                        }
                        else
                        {
                            Output-Message "Unable to archive logs in $logPathInstance" -Red
                            Output-Message "[ERROR]: $archiveResult`n" -Red
                            $logObjInstance.Status = 'Failed'
                            $subContinue = $false
                            $global:errorExists = $True
                        }
                    }
                    if ($subContinue -eq $True)
                    {
                        $subContinue = $false
                        Output-Message "Removing old log archives older than $global:archiveThreshold  days in $logPathInstance"
                        $scriptparams = @{'Server'=$logServerInstance;
                                          'archiveSource'=$logPathInstance;
                                         }
                        $removeResult = Remove-OldArchives @scriptparams
                        if ($removeResult -eq $True)
                        {
                            Output-Message "Log archives older than $global:archiveThreshold days in $logPathInstance have been successfully removed`n" -Green 
                            $subContinue = $True
                            $logObjInstance.Status = 'Success'
                        }
                        else
                        {
                            Output-Message "Unable to remove log archives in $logPathInstance" -Red
                            Output-Message "[ERROR]: $removeResult`n" -Red
                            $logObjInstance.Status = 'Failed'
                            $subContinue = $false
                            $global:errorExists = $True
                        }
                    }
                    # Clean Temporary Files
                    $cleanupResult = Clean-TempFiles -Server $logServerInstance -logPath $logPathInstance
                    if ($cleanupResult -ne $True)
                    {
                        Output-Message "[WARNING]: Cleanup of temporary files in $logPathInstance of $logServerInstance failed" -Yellow
                    }
                }
                catch [System.Exception]
                {
                    Output-Message "An error has been encountered while processing $logPathInstance in $logServerInstance" -Red
                    Output-Message "[ERROR]: $_`n" -Red 
                    $global:errorExists = $True
                    $cleanupResult = Clean-TempFiles -Server $logServerInstance -logPath $logPathInstance
                    if ($cleanupResult -ne $True)
                    {
                        Output-Message "[WARNING]: Cleanup of temporary files in $logPathInstance of $logServerInstance failed" -Yellow
                    }
                }
            }
            #Get Execution Duration
            $programStopTime = date
            $rawDuration = $programStopTime - $programStartTime
            if ($rawDuration.hours -ne 0)
            {
                $global:duration = $rawDuration.hours.tostring() + " Hours "
            }
            if ($rawDuration.minutes -ne 0)
            {
                $global:duration += $rawDuration.minutes.tostring() + " Minutes " 
            }
            if ($rawDuration.seconds -ne 0)
            {
                $global:duration += $rawDuration.seconds.tostring() + " Seconds"
            }
            ##
            
            # Send email notification
            Output-Message "Sending email notification"
            try
            {
                if ($global:errorExists -eq $True)
                {
                    Email-Result -Error
                    Output-Message "Email notification sent"
                }
                else
                {
                    Email-Result
                    Output-Message "Email notification sent"
                }
            }
            catch [System.Exception]
            {
                Output-Message "[WARNING]: Unable to send email notification" -Yellow
                Output-Message "$_"
            }
            ## 

            # Cleanup Task
            Output-Message "Performing cleanup of temporary files and old program logs"
            try
            {
                Clean-TempFiles -Server $env:COMPUTERNAME -logPath $scriptPath
                Clean-OldLogs -History $global:logHistory
                Output-Message "Cleanup task completed`n"
            }
            catch
            {
                Output-Message "[WARNING]: Program failed to remove old log files in \Log`n" -Yellow
            }
            ##

            if ($global:errorExists -eq $True)
            {
                Output-Message "[WARNING]: Errors were encountered during the program execution" -Yellow
                Output-Message "Please review the log file for details" -Yellow 
            }
            else
            {
                Output-Message "[SUCCESS]: All logs older than $global:logThreshold days have been archived without errors" -Green
                Output-Message "[SUCCESS]: All log archives older than $global:archiveThreshold days have been removed without errors" -Green
            }
        }
    }
    if ($Silent -eq $true)
    {
        exit 0
    }
    else
    {
        Write-Host -ForegroundColor Yellow "`n[Press any key to EXIT]`n"
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        exit 0
    }
}
# Refer to supporting functions below to understand program mechanics

########################## Supporting functions
function Transfer-7z
{
    [CmdletBinding()]
    param(
        [Parameter(Position=1)]
        [String]$Server = $global:logServer,
        [Parameter(Position=2)]
        [String]$7zPath = $global:7zPath,
        [Parameter(Position=3)]
        [String]$destLocation = $global:logSource
    )
    try
    {
        $7zFiles = $7zPath + "\*"
        $destLocationUNC = PPath-ToUNC -Server $Server -PPath $destLocation
        Copy-Item -Path $7zFiles -Destination $destLocationUNC -Force -ErrorAction Stop > $null
        return $true
    }
    catch [System.Exception]
    {
        return $_
    }
}

function Get-OldLogs
{
    [CmdletBinding()] 
    param(
        [Parameter(Position=1)]
        [String]$Server = $global:logServer,
        [Parameter(Position=2)]
        [String]$logSource = $global:logSource,
        [Parameter(Position=3)]
        [String]$logSourceTemp = $global:logSourceTemp
    )
    try
    {
        $logSourceUNC = PPath-ToUNC -Server $Server -PPath $logSource
        $logSourceTempUNC = PPath-ToUNC -Server $Server -PPath $logSourceTemp
        $Files = Get-ChildItem -Path $logSourceUNC
        # Remove Temp path if it exists and create an empty Temp folder
        if (Test-Path $logSourceTempUNC)
        {
            Remove-Item -Path $logSourceTempUNC -Force -Recurse -ErrorAction Stop > $null
        }
        New-Item -Path $logSourceTempUNC -ItemType Directory -ErrorAction Stop > $null

        #Move all old files to Temp folder
        foreach ($file in $Files)
        {
           foreach ($extension in $global:fileextensions)
           {
               if (($file.LastWriteTime -le ((date).AddDays(-$global:logthreshold))) -and $file.Name -notlike "*.zip" -and $file.Name -like "*.$extension")
               {
                    $filePath = $logSourceUNC + "\" + $file.Name
                    $fileName = $file.Name
                    $fileModifyDate = $file.LastWriteTime
                    $fileAge = ((date) - $fileModifyDate).Days
                    Output-Message "$fileName's last modify date is $fileAge days ago [ACTION: set for archiving]"
                    Copy-Item -Path $filePath -Destination $logSourceTempUNC -Force -ErrorAction Stop > $null
                    Remove-Item -Path $filePath -Force -ErrorAction Stop > $null
                    Output-Message "$fileName has been set for archiving"
               }
           }
        }
        return $true
    }
    catch [System.Exception]
    {
        return $_
    }
}

function Archive-OldLogs
{
    [CmdletBinding()]
    param(
        [Parameter(Position=1)]
        [String]$Server = $global:logServer,
        [Parameter(Position=2)]
        [String]$archiveLocation = $global:logSource,
        [Parameter(Position=3)]
        [String]$archiveName = $global:archiveName,
        [Parameter(Position=4)]
        [String]$logPath = $global:logSourceTemp,
        [Parameter(Position=5)]
        [String]$resultFilePath = $global:ResultFilePath
    )
    BEGIN {}
    PROCESS
    {
        try
        {
            # Setup variables
            $archivePath = $archiveLocation + "\" + $archiveName
            $logFiles = $logPath + "\*"
            $7zpath = $archiveLocation + "\7z.exe"
            Output-Message "Archiving logs to ZIP archive $archiveName"
            $processId = (Invoke-WmiMethod -Path "Win32_Process" -ComputerName $Server -Name Create -ArgumentList "cmd /c `"`"$7zpath`" a -tzip `"$archivePath`" `"$logFiles`" -y 1> `"$ResultFilePath`" 2>&1`"" -ErrorAction Stop).processId
            $LocalResultFilePath = ($resultFilePath -replace '.txt','') + "-copy.txt"
            $resultFilePathUNC = PPath-ToUNC -Server $Server -PPath $resultFilePath
            ##

            # Poll for program output
            if (Test-Path $LocalResultFilePath)
            {
                Remove-Item -Path $LocalResultFilePath -Force -ErrorAction SilentlyContinue > $null
            }
            New-Item -Path $LocalResultFilePath -ItemType File -Force -ErrorAction Stop > $null
            $timeoutCounter = 0
            while ((Get-WmiObject -class "win32_process" -Filter "ProcessID=$processId" -ComputerName $server) -ne $null -and $timeoutCounter -lt $global:timeoutvalue)
            {
                Write-Host -NoNewline "#"
                sleep -m 50
                $timeoutCounter++
            }
            Write-Host ""
            if ($timeoutCounter -ge $global:timeoutvalue)
            {
                Output-Message "Timeout has been reached while waiting for archiving operation to complete"
                return "TIMEOUT has been reached. The archiving (ZIP) process may have encountered an unknown error or the timeout value may be set too low"
            }
            ##

            # Parse result
            Copy-Item -Path $resultFilePathUNC -Destination $LocalResultFilePath -Force -ErrorAction Stop > $null
            $resultContents = Get-Content $LocalResultFilePath
            foreach ($line in $resultContents)
            {
                if ($line -like "*Everything is OK*")
                {
                    Output-Message "Archiving complete"
                    return $true
                }
            }
            return $resultContents
            ##
        }
        catch [System.Exception]
        {
            return $_
        }
    }
    END {}
}

function Remove-OldArchives
{
    [CmdletBinding()]
    param(
        [Parameter(Position=1)]
        [String]$Server = $global:logServer,
        [Parameter(Position=2)]
        [String]$archiveSource = $global:logSource
    )
    try
    {
        $archiveSourceUNC = PPath-ToUNC -Server $Server -PPath $archiveSource
        $Archives = Get-ChildItem -Path $archiveSourceUNC | Where-Object { $_.Name -like "*.zip"}
        #Remove old archives
        foreach ($archive in $Archives)
        {
            $archivePath = $archiveSourceUNC + "\" + $archive.Name
            $archiveName = $archive.Name
            $archiveModifyDate = $archive.LastWriteTime
            $archiveAge = ((date) - $archiveModifyDate).Days
            if ($archive.LastWriteTime -le ((date).AddDays(-$global:archivethreshold)))
            {
                Output-Message "$archiveName's last modify date is $archiveAge days ago [ACTION: remove]"
                Remove-Item -Path $archivePath -Force -ErrorAction Stop > $null
                Output-Message "Log archive $archiveName has been removed"
            } 
        }
        return $true
    }
    catch [System.Exception]
    {
        return $_
    }
}

function Load-Settings
{
    [CmdletBinding()]
    param(
    [parameter()]
    [string]$configFile
    )
    BEGIN {}
    PROCESS
    {
        $Settings = Get-Content "$scriptPath\$configFile"
        try
        {
            foreach ($line in $Settings)
            {
                if ($line -ne "" -and $line -notlike "#*")
                {
                    if ($line -like "*logserver*")
                    {
                        $global:logserver = $line.Split('=')[1]
                    }
                    if ($line -like "*logpath*")
                    {
                        $value = $line.Split('=')[1]
                        $logPathProps = @{'logPath'=$value.Split(',')[0];}
                        if ($value.Split(',').Count -gt 1)
                        {
                            $logPathProps.Add('Server',$value.Split(',')[1])
                        }
                        else
                        {
                            $logPathProps.Add('Server',$global:logserver)
                        }
                        $logPathProps.Add('Status','Pending')
                        $logPathObj = New-Object -TypeName PSObject -Property $logPathProps
                        $global:logPaths += $logPathObj
                    }
                    if ($line -like "*fileextensions*")
                    {
                        $value = $line.Split('=')[1]
                        foreach ($extension in $value.Split(','))
                        {
                            $global:fileextensions += $extension
                        }
                    }
                    if ($line -like "*logthreshold*")
                    {
                        $global:logthreshold = $line.Split('=')[1]
                    }
                    if ($line -like "*archivethreshold*")
                    {
                        $global:archivethreshold = $line.Split('=')[1]
                    }
                    if ($line -like "*loghistory*")
                    {
                        $global:loghistory = $line.Split('=')[1]
                    }
                    if ($line -like "*7zpath*")
                    {
                        $global:7zPath = $scriptPath + $line.Split('=')[1]
                    }
                    if ($line -like "*timeout*")
                    {
                        [int]$timeoutdata = [int]$line.Split('=')[1]
                        $global:timeoutvalue = ($timeoutdata * 50)
                    }
                    if ($line -like "*sendnotification*")
                    {
                        if ($line -like "*yes*")
                        {
                            $global:sendnotification = $true
                        }
                        if ($line -like "*no*")
                        {
                            $global:sendnotification = $false    
                        }
                    }
                    if ($line -like "*smtpserver*")
                    {
                        $global:smtpserver = $line.Split('=')[1]
                    }
                    if ($line -like "*smtpport*")
                    {
                        $global:smtpport = $line.Split('=')[1]
                    }
                    if ($line -like "*emailto*")
                    {
                        $global:emailto = $line.Split('=')[1]
                    }
                    if ($line -like "*emailcc*")
                    {
                        $global:emailcc = $line.Split('=')[1]
                    }
                    if ($line -like "*emailfrom*")
                    {
                        $global:emailfrom = $line.Split('=')[1]
                    }
                    if ($line -like "*emailsubject*")
                    {
                        $global:emailsubject = $line.Split('=')[1]
                    }
                    if ($line -like "*emailerrorsubject*")
                    {
                        $global:emailerrorsubject = ($line.Split('=')[1] -replace '<server_instance>',"$global:serverinstance")
                    }
                }
            }
        }
        catch [System.Exception]
        {
            return $_
        }
        return $true     
    }
    END {}
}

function Output-Message
{
    [CmdletBinding()]
    param(

    [Parameter(Position=1)]
    [String]$Message,

    [Parameter(Position=2)]
    [String]$Path = $global:LOGPATH,

    [Parameter(Position=3)]
    [switch]$Green,

    [Parameter(Position=4)]
    [switch]$Yellow,

    [Parameter(Position=5)]
    [switch]$Red,

    [Parameter(Position=6)]
    [switch]$Silent
    )

    if (($PSBoundParameters.ContainsKey('Silent')) -ne $true)
    {
        if ($PSBoundParameters.ContainsKey('Green')) { Write-Host -ForegroundColor Green $Message }
        elseif ($PSBoundParameters.ContainsKey('Yellow')) { Write-Host -ForegroundColor Yellow $Message }
        elseif ($PSBoundParameters.ContainsKey('Red')) { Write-Host -ForegroundColor Red $Message }
        else { Write-Host $Message }
    }
    $datedisplay = date -F {MM/dd/yyy hh:mm:ss:}
    [IO.File]::AppendAllText($Path,"$datedisplay $Message`r`n")
}

function PPath-ToUNC
{
    [CmdletBinding()]
    param(

    [Parameter(Position=1)]
    [String]$Server,

    [Parameter(Position=2)]
    [String]$PPath

    )
    $driveLetter = $PPath[0]
    $UNC = '\\' + $server + '\' + $driveLetter + '$' + ($PPath -replace "$driveLetter`:",'') 
    $UNC
}

function Clean-TempFiles
{
    [CmdletBinding()]
    param(
    [Parameter()]
    [string]$Server = $global:logServer,
    [Parameter()]
    [string]$logPath
    )
    $logPathUNC = PPath-ToUNC -Server $Server -PPath $logPath
    try
    {
        if (Test-Path "$logPathUNC\Temp")
        {
            Remove-Item -Path "$logPathUNC\Temp" -Force -Recurse -ErrorAction Stop > $null
        }
        if (Test-Path "$logPathUNC\7z.dll")
        {
            Remove-Item -Path "$logPathUNC\7z.dll" -Force -Recurse -ErrorAction Stop > $null
        }
        if (Test-Path "$logPathUNC\7z.exe")
        {
            Remove-Item -Path "$logPathUNC\7z.exe" -Force -Recurse -ErrorAction Stop > $null
        }
        if (Test-Path "$logPathUNC\ResultFile.txt")
        {
            Remove-Item -Path "$logPathUNC\ResultFile.txt" -Force -Recurse -ErrorAction Stop > $null
        }
        return $true
    }
    catch [System.Exception]
    {
        return $false
    }
}

function Clean-OldLogs
{
    [CmdletBinding()]
    param(

    [Parameter()]
    [string]$History = $global:logHistory
    )
    $logsList = get-childitem -Path "$scriptPath\Log" | Sort-Object -Property 'LastWriteTime' -Descending | Select-Object -ExpandProperty Name
    if ($logsList.Count -ge $History)
    {
        $logCounter = 1
        foreach ($log in $logsList)
        {
            if ($logCounter -gt $History)
            {
                Remove-Item -Path "$scriptPath\Log\$log" -Force > $null
            }
            $logCounter++
        }
    }
}

function Email-Result
{
    [CmdletBinding()]
    param(

    [Parameter(Position=1)]
    [string[]]$To = $global:emailto,

    [Parameter(Position=2)]
    [string]$CC = $global:emailcc,

    [Parameter(Position=3)]
    [string[]]$From = $global:emailfrom,

    [Parameter()]
    [string]$SMTPServer = $global:smtpserver,

    [Parameter()]
    [string]$SMTPPort = $global:smtpport,
       
    [Parameter()]
    [string]$Subject = $global:emailsubject,

    [Parameter()]
    [switch]$Error
    )
    BEGIN
    {
    }
    PROCESS
    {
        Output-Message "Creating email message"
        $SMTPmessage = New-Object Net.Mail.MailMessage($From,$To)
        foreach ($address in $CC.Split(','))
        {
            $SMTPmessage.CC.Add($address)    
        }
        $SMTPmessage.Subject = $Subject
        $SMTPmessage.IsBodyHtml = $false
        if ($PSBoundParameters.ContainsKey('Error'))
        {
            $SMTPmessage.Priority = [System.Net.Mail.MailPriority]::High
            $SMTPmessage.Subject = $global:emailerrorsubject
        }
        # Compose email body
        $EmailBody = "Task: Log Maintenance`n"
        $EmailBody += "Host Server: $env:COMPUTERNAME`n"
        $displaydate = date -F {MM/dd/yyyy HH:mm:ss}
        $EmailBody += "Execution Date: $displaydate`n"
        $EmailBody += "Execution Duration: $global:duration`n"
        if ($PSBoundParameters.ContainsKey('Error'))
        {
            $EmailBody += "Result: ERROR encountered (Refer to attached log file for details)`n"
        }
        else
        {
            $EmailBody += "Result: SUCCESS (Refer to attached log file for details)`n"
        }
        $EmailBody += "`nList of Log Paths:`n`n"
        foreach ($logObjInstance in $global:logPaths)
        {
            $logEntry = PPath-ToUNC -Server $logObjInstance.Server -PPath $logObjInstance.logPath
            $logEntryStatus = $logEntry + " [Result: " + $logObjInstance.Status + "]`n"
            $EmailBody += $logEntryStatus
        }
        ## End email body composition
        $SMTPmessage.Body = $EmailBody
        Output-Message "Email message created"
        Copy-Item -Path $global:LOGPATH -Destination $global:EMAILLOGPATH -Force -ErrorAction SilentlyContinue > $null
        $Attached_log = New-Object System.Net.Mail.Attachment($global:EMAILLOGPATH)
        $SMTPmessage.attachments.Add($Attached_log)
        $SMTPClient = New-Object Net.Mail.SmtpClient($SMTPServer,$SMTPPort)
        try
        {
            Output-Message "Sending email message..."
            $SMTPClient.Send($SMTPmessage)
            Output-Message "Email sent!"
        }
        catch [Exception]
        {
            Output-Message "Unable to send email. The error message is: $_" -Red
        }
    }
    END
    {
        $Attached_log.Dispose()
        $SMTPmessage.Dispose()
        Remove-Item -Path $global:EMAILLOGPATH -Force -ErrorAction SilentlyContinue > $null
    }
}

function Init-Vars
{
    # Global parameter declaration
    $global:LOGPATH = $scriptpath + "\Log\" + ("Log_Maintenance_Utility_" + $env:COMPUTERNAME + "_" + (date -Format "yyyyMMddhhmmss") + ".log")
    $global:EMAILLOGPATH = $scriptpath + "\Temp\" + ("Log_Maintenance_Utility_" + $env:COMPUTERNAME + "_" + (date -Format "yyyyMMddhhmmss") + ".log")
    $global:logServer = $env:COMPUTERNAME
    $global:logPaths = @()
    $global:fileextensions = @()
    $global:logSource = "C:\PowerShell\Logs"
    $global:logSourceTemp = $logSource + "\Temp"
    $global:7zPath = "$scriptpath\Res\7z"
    $global:archiveName = ""
    $global:ResultFilePath = "$scriptpath\Temp\resultFile.txt"
    $global:timeoutvalue = 1200
    $global:errorExists = $false
    $global:duration = ""
    $global:logHistory=20
    $global:smtpserver
    $global:smtpport=25
    $global:emailto=""
    $global:emailcc=""
    $global:emailfrom=""
    $global:emailsubject=""
    $global:emailerrorsubject=""
    ##
}

# Initialize variables
Init-Vars
##

# Run the program
Main-Program
##