# PSLogPurger v1.0

PSLogPurger is a tool designed to maintain the log directories of target servers in a Windows-based
infrastructure. It practically does two things:

1. Archives (ZIPs) logs older than a specified number of days
2. Deletes these log archives older than a specified number old days.

A list of servers and log paths (directories) are
fed to the program and the program recurs through them until completion. This tool is designed
to be a centralized log maintenance utility, such that it only needs to be configured in one server
and this server does the maintenance on the other target servers.

## Features

1. Archives (ZIPs) logs based on specified file age (default 30 days) using 7zip
2. Deletes archived logs based on specified file age (default 60 days)
3. Ability to specify log file extensions, thus filtering other files which may just happen to be in
the log directory.
4. The tool can be extended to be used for files other than logs. For instance, it can be used to
maintain a backup directory for SQL Server databases (*.bak).
5. Multiple server targets – which makes the tool a centralized log maintenance utility.
6. Customizable threshold parameters to determine how old the logs and log archives have to
be to archive or delete them respectively.
7. Support for email notification once the program completes execution
8. Configuration-file based approach in customizing the program behavior, making the
program flexible and adaptable to needs.

## Prerequisites

SOFTWARE: The following software must be installed in the host server where this program
will be executed. Running the program in an environment with the specified software not
installed, or in a lower version, will cause the program to crash.

  * PowerShell 2.0+ (native in Windows Server 2008 R2)
  * NET Framework 2.0+

This program uses remote WMI executions to perform its tasks. This is done for backward compatibility with older Windows servers where WinRM is not enabled by default. It also uses standard SMB/CIFS to do some of the cleanups. Please make sure these are not blocked by a firewall.

Make sure that the account used to run this program has appropriate administrative credentials on the target servers. For organizations that require only kerberos authentication, a Domain Admin is most likely required. For those that allow fallback to NTLM, local administrator credentials could be passed (assuming servers share a common administrative credential). For best approach to security, it is recommended to use a standard domain user account that is a member of the target servers' administrators group.

## How do you use this?

1. Make sure that the confguration file *config.ini* is properly filled in based on your requirements. This part is self explanatory. Take note that you can define more than 1 configuration file and the program will iterate through them. The only requirement is that a configuration file must be named with *config* and *ini* in the filename.
2. You can either run the *PSLogPurger.exe* file or the Powerhell script under *\Res\Script*.
3. If you want to schedule the log purge, use Task Scheduler. In the *Add arguments* section of the action, make sure to supply *Silent*. If you are running the PowerShell script, use *[program_path]\Res\Scripts\PSLogPurger.ps1 -Silent* as the argument ot powershell.

That's it, it's that easy!
