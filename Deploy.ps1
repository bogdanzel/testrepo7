. .\UHelper.ps1

#Read config file
[xml]$configFile = Get-Content  "DeployParameters.xml"

$deployConfig = $configFile.application

# -------------------------------------
# -------      SCRIPT BODY      -------
# -------------------------------------
$packageName = FindPackageName("Package")

$CMD = "Package\${packageName}.deploy.cmd /Y"
$paramXML = "Package\${packageName}.SetParameters.xml"

if ($deployConfig.globalDeploy -eq 1){
  $CMD = "${packageName}\$CMD"
  $paramXML = "${packageName}\$paramXML"
}

# Modify Parameters
ModifyXmlParameters $paramXML $deployConfig.websitename $deployConfig.webSitePhysicalPath  $deployConfig.virtualDirName  $deployConfig.appPoolName 

# Run MsDeploy
cmd /c $CMD

# Event source
if ($deployConfig.eventSourceName -ne $null)
{
	CreateEventSource $deployConfig.eventSourceName
}  
# Real work
# Unprotect configs
if ($deployConfig.webConfigProtectedSections -ne $null)  
{
	foreach ($entry in $deployConfig.webConfigProtectedSections.entry)
	{
		UnprotectConfig $deployConfig.websitename $deployConfig.virtualDirName  $entry.path
	}
}

$webConfig = "$($($deployConfig).webSitePhysicalPath)\$($($deployConfig).virtualDirName)\Web.config"
if (Test-Path $webConfig)
{
	[xml]$doc = Get-Content $webConfig
	$root = $doc.get_DocumentElement()

	if($deployConfig.modifyServiceAddress.entry -ne $null)
	{
		foreach ($entry in $deployConfig.modifyServiceAddress.entry)
		{
			if($entry.GetType().FullName -eq 'System.String')
			{
				ModifyServiceAddresses $entry $entry.serviceName 
			}
			else
			{
				ModifyServiceAddresses $entry.InnerText $entry.serviceName 
			}
		}
	}
	
	if(($deployConfig.impersonatedUser -ne $null) -and ($deployConfig.impersonatedUserPassword -ne $null))
	{
		ModifyImpersonation $deployConfig.impersonatedUser $deployConfig.impersonatedUserPassword
	}

	if ($deployConfig.useSSL -ne $null)
	{
		if ($deployConfig.useSSL -eq 'yes')
		{
			SetUpSSL $deployConfig.useSSL.name
			SetHttpGetModeForServiceBehavior "httpsGetEnabled" "httpGetEnabled"
		} 
		else 
		{
			DisableSSL $deployConfig.useSSL.name
			SetHttpGetModeForServiceBehavior "httpGetEnabled" "httpsGetEnabled"
		}
	}

	if($deployConfig.webConfigRewrites.entry -ne $null)
	{	
		ModifyConfigEntries $doc $deployConfig.webConfigRewrites
	}

	if($deployConfig.setUpUrlRewrites.entry -ne $null)
	{
		foreach ($entry in $deployConfig.setUpUrlRewrites.entry)
		{
			SetUpRewriteUrls $root $entry.ruleName $entry.InnerText
		}
	}
	
	if($deployConfig.aonBenfieldDistanceToLine -ne $null)
	{
	ModifyAonBenfieldDistanceToLine $deployConfig.aonBenfieldDistanceToLine
	}
	
	#ConnectionStrings - use internal config
	if(($deployConfig.connectionsStrings.connectionsString -ne $null) -and ($deployConfig.connectionsStrings.useExternalConfig -eq "false"))
	{
			if($deployConfig.connectionsStrings.useRoot -eq "true")
			{
				$useRoot = $true
			}
			else
			{
				$useRoot = $false
			}
			foreach ($connectionsString in $deployConfig.connectionsStrings.connectionsString)
			{
				ModifyConnectionStrings $connectionsString.name $deployConfig.connectionsStrings.sqlServer $connectionsString.catalog '' '' $deployConfig.connectionsStrings.applicationName $useRoot
			}
		
	}
	
	$doc.Save($webConfig)
}


#ConnectionStrings - use external config
if(($deployConfig.connectionsStrings.connectionsString -ne $null) -and ($deployConfig.connectionsStrings.useExternalConfig -eq "true"))
{
	$sqlConfig = "$($($deployConfig).webSitePhysicalPath)\$($($deployConfig).virtualDirName)\ConnectionStrings.RELEASE.config"
	if (Test-Path $sqlConfig)
	{
	  $doc = new-object System.Xml.XmlDocument
	  $doc.Load($sqlConfig)
	  $root = $doc.get_DocumentElement()

			foreach ($connectionsString in $deployConfig.connectionsStrings.connectionsString)
			{
				if($deployConfig.connectionsStrings.useRoot -eq "true")
				{
					$useRoot = $true
				}
				else
				{
					$useRoot = $false
				}
				ModifyConnectionStrings $connectionsString.name $deployConfig.connectionsStrings.sqlServer $connectionsString.catalog '' '' $deployConfig.connectionsStrings.applicationName $useRoot
			}
		
	  $doc.Save($sqlConfig)
	}
}


ConfigureApplicationPool $deployConfig.appPoolName  $deployConfig.appPoolNumerOfWorkers
RestartApplicationPool $deployConfig.appPoolName 

# Protect configs
if ($deployConfig.webConfigProtectedSections -ne $null)  
{
	foreach ($entry in $deployConfig.webConfigProtectedSections.entry)
	{
		ProtectConfig $deployConfig.websitename $deployConfig.virtualDirName  $entry.path
	}
}

if ($deployConfig.requiresRestPermissions -ne $null)
{
	foreach ($entry in $deployConfig.requiresRestPermissions.entry)
	{
		SetFrontRESTPermissions "$($($deployConfig).webSitePhysicalPath)\$($($deployConfig).virtualDirName)\$($($entry).fileName)"
	}
}
