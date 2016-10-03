<#
Autodeploy Dashboard on FrontEnd and BackEnd environments
	- ppws1
	- ppws2
	- imas1
	- imas2
#>
Param(
	[Parameter(Mandatory=$True)]
	[string]$Type,
	[string]$userName,
	[string]$password,
	[string]$packagesPath,
	[string]$configPath,
	[string]$shareFolder,
	[string]$FrontEnd,
	[string]$BackEnd,
	$secureParameters
)

#FUNCTIONS
function FindBuildNumber([string]$packagesPath)
{
	$latestVersion = Get-ChildItem $packagesPath |  Where-Object {($_.Mode -match "d--") -and ($_.name -match "[0-9]+\.[0-9]+(?:\.[0-9]+)")} | Sort-Object Name | Select-Object -Last 1
	[string]$buildNumber = $latestVersion.Name
	return $buildNumber
}

function ModifySecureConfigFile($config, $secureParameters)
{
	if(Test-Path -Path "$config") 
	{
		write-host "Adding secure parameters in config file"
		$secureParameters.Keys | % { 
		$keyHash = $_ 
		(Get-Content "$config") | Foreach-Object {$_ -replace "@@$keyHash@@", $secureParameters.Item($keyHash)} | Set-Content "$config"
		}
	}
	
	if ($Error[0].Exception -ne $null)
	{
		write-host "Error adding secure parameters to config file ($config) !" 
		write-host  "Error: $Error[0].Exception" 
		[System.Environment]::Exit(1)
	}
}

function CreateConfigFile($configFile, $node)
{
	write-host "Create config file $configFile"
	if(test-path -path $configFile)
	{
		Remove-Item $configFile -Force 
	}
	$doc = new-object System.Xml.XmlDocument
	$doc.LoadXml($node.OuterXml)
	$doc.Save($configFile)
	
	if ($Error[0].Exception -ne $null)
	{
		write-host "Error creating config file ($configFile)!" 
		write-host "Error: $Error[0].Exception" 
		[System.Environment]::Exit(1)
	}
}

function DeployPackages($servers, $buildNumber, $packagesPath, $configPath, $Type, $shareFolder, $userName, $password, $environment, $secureParameters, $envParameters)
{
	foreach($server in $servers)
	{
		if (test-connection $server -quiet)
		{
			foreach($node in $envParameters)
			{
				$error.clear()
				#Create config file
				CreateConfigFile "$configPath\$Type\DeployParameters.xml" $node
				
				#copy packages
				Write-Host "Clear share folder ${shareFolder}"
				Remove-Item "\\$server\${shareFolder}\*" -Recurse -Force
				write-host "Copy package $Type $buildNumber to ($server)"
				copy "$packagesPath\$buildNumber\${Type}_${buildNumber}\${environment}\Package"  "\\$server\${shareFolder}\${Type}_${buildNumber}\Package" -Force -Recurse
				copy "$configPath\*.ps1"  "\\$server\${shareFolder}\${Type}_${buildNumber}" -Force -Recurse
				copy "$configPath\Deploy.cmd"  "\\$server\${shareFolder}\${Type}_${buildNumber}" -Force -Recurse
				copy "$configPath\$Type\DeployParameters.xml"  "\\$server\${shareFolder}\${Type}_${buildNumber}\DeployParameters.xml" -Force -Recurse
				
				if ($Error[0].Exception -ne $null)
				{
					write-host "Error copying files to the server $server !" 
					write-host  "Error: $Error[0].Exception" 
					[System.Environment]::Exit(1)
				}
				
				#Adding secure parameters in config file
				ModifySecureConfigFile "\\$server\${shareFolder}\${Type}_${buildNumber}\DeployParameters.xml" $secureParameters

				$deployFolder="${shareFolder}\${Type}_${buildNumber}"
				# Conect to remote host
				winrm s winrm/config/client '@{TrustedHosts="' $server '"}'
				$pass = convertto-securestring "$password" -asplaintext -force
				$mycred = new-object -typename System.Management.Automation.PSCredential -argumentlist "$userName",$pass
				invoke-command -ComputerName $server -ScriptBlock {
				param($deployFolder)
				Invoke-Expression -Command "c:\$deployFolder\Deploy.cmd"
				} -credential $mycred -Arg $deployFolder
				
				if ($Error[0].Exception -ne $null)
				{
					write-host "Error run deploy scripts on the server $server !" 
					write-host "Error: $Error[0].Exception" 
					[System.Environment]::Exit(1)
				}
			}
		}
		else
		{
			write-host "Ping request could not find host $server"
			write-host "The connection is not established!"
			[System.Environment]::Exit(1)
		}
	}
}

#Main
#Read XML file
if (test-path -path "$configPath\$Type\DeployParametersAll.xml")
{
	$xml = [xml](Get-Content "$configPath\$Type\DeployParametersAll.xml")
	$frontEndEnvParameters = $xml.parameters.applications.application | where {$_.layer -eq "FrontEnd"}
	$backEndEnvParameters = $xml.parameters.applications.application | where {$_.layer -eq "BackEnd"}
}
else
{
	write-host "Config file $configPath\$Type\DeployParametersAll.xml does not exist!"
	[System.Environment]::Exit(1)
}

#Find latest version
$buildNumber = FindBuildNumber $packagesPath
if(($buildNumber -eq $null) -or ($buildNumber -eq ""))
{
	write-host "Please check your folder of packages: $packagesPath !"
	write-host "Packages not found!"
	[System.Environment]::Exit(1)
}

#Deploy FrontEnd
if(($FrontEnd -ne $null) -and ($FrontEnd -ne ""))
{
	$serversFront=$FrontEnd.Split(',')
	DeployPackages $serversFront $buildNumber $packagesPath $configPath $Type $shareFolder $userName $password "FrontEnd" $secureParameters $frontEndEnvParameters
}

#Deploy BackEnd
if(($BackEnd -ne $null) -and ($BackEnd -ne ""))
{
	$serversBack=$BackEnd.Split(',')
	DeployPackages $serversBack $buildNumber $packagesPath $configPath $Type $shareFolder $userName $password "BackEnd" $secureParameters $backEndEnvParameters
}

if($error.Count -gt 0)
{
	write-host "An error occurred during deploy!"
	[System.Environment]::Exit(1)
}

