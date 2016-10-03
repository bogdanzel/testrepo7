# -------------------------------------
# -------       FUNCTIONS       -------
# ------------------------------

function ModifyXmlParameters([string]$xmlPath, [string] $site, [string] $physPath, [string] $vdir, [string] $appPool){
  $params = new-object System.Xml.XmlDocument
  $params.Load($xmlPath)
  $parameters = $params.get_DocumentElement()

  $iisParam = $parameters.SelectSingleNode("setParameter[@name='IIS Web Application Name']")
  if ($iisParam){
    $iisParam.value = "$site/$vdir"
  }
  
  $vdirParam = $parameters.SelectSingleNode("setParameter[@name='IisVirtualDirectoryPhysicalPath']")
  if ($vdirParam){
    $vdirParam.value = "$physPath\$vdir"
  }
  
  if ($appPool -ne ""){
    $poolParam = $parameters.SelectSingleNode("setParameter[@name='IIS Web Application Pool Name']")
    if ($poolParam){
      $poolParam.value = "$appPool"
    }
  }

  $params.Save($xmlPath)
}

function CopyFrom([string] $srcFolder, [string] $destFolder){
  if (!(Test-Path -path $destFolder)) { New-Item $destFolder -Type Directory }
  Copy-Item -Path $srcFolder\*.* -Destination $destFolder -Force
  return $LastExitCode
}

function RestartApplicationPool([string]$appPoolName)
{
  "* Stopping ""$appPoolName"" application pool"
  cmd /c "%systemroot%\system32\inetsrv\APPCMD STOP APPPOOL ""$appPoolName"""
  
  Start-Sleep -s 2
  
  "* Starting ""$appPoolName"" application pool"
  cmd /c "%systemroot%\system32\inetsrv\APPCMD START APPPOOL ""$appPoolName"""
}

function AddToPath([string] $item){
  if (!$item) { return 'Add item to path: nothing specified'; }
  if (!(TEST-PATH $item)) { return 'Add item to path: specified item not exists'; }

  $OldPath=(Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH).Path;
  if ($OldPath | Select-String -SimpleMatch $item) { return ''; }
  $NewPath="$OldPath;$item"
  Set-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH –Value $NewPath
  return $LastExitCode
}

function CreateEventSource([string] $sourceName){
  if (![System.Diagnostics.EventLog]::SourceExists($sourceName)){
    [System.Diagnostics.EventLog]::CreateEventSource($sourceName, "Application");
  }
}

function WriteInformationEvent([string] $sourceName, [string] $message){
  Write-Eventlog -logname "Application" -source $sourceName -eventID 3001 -entrytype Information -message $message
}

function SetUpSSL($bindingName) {
  $serviceModel = $root."system.serviceModel"
  
  if (!$serviceModel){
    return;
  }
  
  if ($serviceModel.bindings){
    $bindings = $serviceModel.bindings.SelectNodes("*")
    foreach ($binding in $bindings){
      if ($binding.Name -eq $bindingName){
          continue;
      }
      $bindingBindings = $binding.SelectNodes("*")
      foreach ($bindingBinding in $bindingBindings){
        $security = $bindingBinding.security
        if ($security){
          $security.mode = "Transport"
        }
      }
    }
  }
}

function SetHttpGetModeForServiceBehavior($allowAttribute, $denyAttribute)
{
  $serviceModel = $root."system.serviceModel"
  if ($serviceModel.behaviors.serviceBehaviors -and $serviceModel.behaviors.serviceBehaviors)
  {
    $behaviours = $serviceModel.behaviors.serviceBehaviors.SelectNodes("*")
    foreach ($behaviour in $behaviours){
      $metaData = $behaviour.serviceMetadata
      if ($metaData.HasAttribute($denyAttribute)){
        $metaData.RemoveAttribute($denyAttribute)
      }
      $metaData.SetAttribute($allowAttribute, "true")
    }
  }  
}

function RemoveExceptionDetailsInFaults {
  $serviceModel = $doc."system.serviceModel"
  
  if (!$serviceModel){
    return;
  }
  
  if ($serviceModel.behaviors.serviceBehaviors -and $serviceModel.behaviors.serviceBehaviors){
    $behaviours = $serviceModel.behaviors.serviceBehaviors.SelectNodes("*")
    foreach ($behaviour in $behaviours) {
      $serviceDebug = $behaviour.serviceDebug
      $serviceDebug.SetAttribute("includeExceptionDetailInFaults", "false")
    }
  }
}

function ProhibitServiceMetadata {
  $serviceModel = $doc."system.serviceModel"
  
  if (!$serviceModel) {
    return;
  }
  
  if ($serviceModel.behaviors.serviceBehaviors -and $serviceModel.behaviors.serviceBehaviors){
    $behaviours = $serviceModel.behaviors.serviceBehaviors.SelectNodes("*")
    foreach ($behaviour in $behaviours) {
      $metaData = $behaviour.serviceMetadata
      $metaData.SetAttribute("httpGetEnabled", "false")
      $metaData.SetAttribute("httpsGetEnabled", "false")
    }
  }
}

function DisableSSL($bindingName){
  $serviceModel = $root."system.serviceModel"
  
  if (!$serviceModel){
    return;
  }
  
  if ($serviceModel.bindings){
    $bindings = $serviceModel.bindings.SelectNodes("*")
    foreach ($binding in $bindings){
      if ($binding.Name -eq $bindingName){
          continue;
      }
      $bindingBindings = $binding.SelectNodes("*")
      foreach ($bindingBinding in $bindingBindings){
        $security = $bindingBinding.security
        if ($security){
          $security.mode = "TransportCredentialOnly"
        }
      }
    }
  }
}

function GetConnectionString([string] $server, [string] $database, [string] $user, [string] $pass, [string] $application){
  $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
  $builder["Data Source"] = $server
  $builder["Initial Catalog"] = $database
  $builder["Application Name"] = $application
  $builder["PersistSecurityInfo"] = $true
  if ($user -ne "" -and $pass -ne ""){
    $builder["User Id"] = $user
    $builder["Password"] = $pass
    $builder["Integrated Security"] = $false
  } else{
    $builder["Integrated Security"] = $true  
  }
  
  return $builder.ToString()
}

<#
function ModifyConnectionStrings([string] $configName, [string] $server, [string] $database, [string] $user, [string] $pass, [string] $application){
  $settings = $root.connectionStrings.SelectNodes("*")
  foreach ($setting in $settings){
    if ($setting.name -eq $configName){
      $connString = GetConnectionString $server $database $user $pass $application
      $setting.connectionString = "$connString"
    }
  }  
}
#>

function ModifyConnectionStrings([string] $configName, [string] $server, [string] $database, [string] $user, [string] $pass, [string] $application, [bool] $useRoot){
  if ($useRoot) {
  	$settings = $root.SelectNodes("*")
  } else {
  	$settings = $root.connectionStrings.SelectNodes("*")
  }
  foreach ($setting in $settings){
    if ($setting.name -eq $configName){
      $connString = GetConnectionString $server $database $user $pass $application
      $setting.connectionString = "$connString"
    }
  }  
}

function ModifyImpersonation([string] $user, [string] $password){
  $web = $root."system.web"
  $identity = $web.identity
  
  if ($user -ne '' -and $password -ne ''){
    $identity.SetAttribute("impersonate", "true")
    $identity.SetAttribute("userName", $user)
    $identity.SetAttribute("password", $password)
  } else {
    $identity.SetAttribute("impersonate", "false")
  }
}

function ProtectConfig ([string] $site, [string] $vdir, [string] $section){
  Add-Type -AssemblyName System.Web
  $config = [Web.Configuration.WebConfigurationManager]::OpenWebConfiguration("/" + $vdir, $site)
  if (!$config){
    return
  }	
  $sectionToProtect = $config.GetSection($section)
  
  if (!$sectionToProtect -or $sectionToProtect.SectionInformation.IsProtected){
    return
  }
  
  $sectionToProtect.SectionInformation.ProtectSection("DataProtectionConfigurationProvider");
  
  $config.Save()
}

function UnprotectConfig ([string] $vdir, [string] $section){
  Add-Type -AssemblyName System.Web
  $config = [Web.Configuration.WebConfigurationManager]::OpenWebConfiguration("/" + $vdir, $site)
  if (!$config){
    return
  }

  $sectionToProtect = $config.GetSection($section)
  
  if (!$sectionToProtect -or !$sectionToProtect.SectionInformation.IsProtected){
    return
  }
  
  $sectionToProtect.SectionInformation.UnprotectSection();
  
  $config.Save()
}

function SetFormsAuthSSL([bool] $requireSSL){
  $forms = $doc."system.web"."authentication"."forms"
  if ($requireSSL) {
  	$forms.requireSSL = "true"
  } else {
  	$forms.requireSSL = "false"
  }
}

function AddAppSettings([hashtable] $settings) {
    $appSettings = $doc.SelectSingleNode("//configuration/appSettings")
    if ($appSettings -eq $null)
    {
        $appSettings = $doc.CreateNode('element',"appSettings","")    
        $doc.configuration.AppendChild($appSettings)
        $appSettings = $doc.SelectSingleNode("//configuration/appSettings")
    }
    
    foreach ($setting in $settings.GETENUMERATOR()) {
        $key = $setting.key
        $existing = $doc.SelectSingleNode("//configuration/appSettings/add[@key='$key']")
        if ($existing -ne $null) {
            $existing.SetAttribute("value", $setting.value)
        } else {
            $newSetting = $doc.CreateNode('element',"add","")    
            $newSetting.SetAttribute("key", $setting.key)
            $newSetting.SetAttribute("value", $setting.value)
            $appSettings.AppendChild($newSetting)
        }
    }
}

function ModifyAppSettings([hashtable] $settings){
  $appSettings = $doc.SelectNodes("appSettings/*")
  foreach ($setting in $appSettings){
    if ($settings.ContainsKey($setting.key)){
      $setting.value = $settings[$setting.key]
    }
  }
}

function ModifyEndpointAddresses([string] $servicesBase, $serviceName){
  $endpoints = $root.SelectNodes("system.serviceModel/client/*")
  foreach ($enpoint in $endpoints){
    try{      
      $uri = New-Object System.Uri($enpoint.address)
	  $len = $uri.Segments.Length
	  $service = $uri.Segments[$len - 1]
	  if(($service -eq $serviceName) -or ($serviceName -eq $null))
	  {
		$enpoint.address = "$servicesBase/$service"
	  }
    }
    catch [System.Exception]{
	  #skip endpoint
    }
  }
}

function UpdateOption([string] $server, [string] $database, [string] $application, [string] $optionKey, [string] $optionValue){
  $updateSQL = "UPDATE [$database].[dbo].[Options] SET Value='$optionValue' WHERE OptionKey='$optionKey';"
  
  $connection = New-Object System.Data.SQLClient.SQLConnection
  $connString = GetConnectionString $server $database $application
  $connection.ConnectionString = "$connString"
  $connected = $false
  try{
    $connection.Open()
    $connected = $true
  }
  catch [System.Exception]{
    write-host "Could not connect to database. ConnectionString = $connString"
  }
  
  if ($connected){
    try{
      $command = New-Object System.Data.SQLClient.SQLCommand
      $command.Connection = $connection
      $command.CommandText = $updateSQL  
      $command.ExecuteNonQuery()
    }
    catch [System.Exception]{
      write-host "Error occurred during update options in database. Please set '$optionKey' option(s) in database manually."
    }  
    $connection.Close()
  }
}

function GetValueFromFile([string] $filePath) {
  $fileContent = get-content $filePath
  try {
    $secureValue = $fileContent | convertto-securestring
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureValue)
    $value = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    return $value
  }
  catch [System.Exception] {
    return $fileContent
  } 
}

function InstallWinService([string] $dotNetRuntimeDir, [string] $serviceName, [string] $exeName, [string] $destDir, [string] $userName, [string] $password, [bool] $log){
  if((Test-Path $dotNetRuntimeDir) -eq 0)
  { 
    $dotNetRuntimeDir = [System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()
  }

  $installUtil_exe = [System.IO.Path]::Combine($dotNetRuntimeDir, "InstallUtil.exe")
  
  "Installing service..."
  if ($log){
    & $InstallUtil_exe /Account=User /Username=$userName /Password=$password /LogFile=InstallLog.log /ServiceName=$serviceName /i $destDir
  }
  else
  {
    & $InstallUtil_exe /Account=User /Username=$userName /Password=$password /ServiceName=$serviceName /i $destDir
  }
	
  Start-Sleep -s 5
  "Done `n"
}

function UninstallWinService([string] $dotNetRuntimeDir, [string] $serviceName, [string] $exeName, [string] $destDir, [bool] $log){
  if((Test-Path $dotNetRuntimeDir) -eq 0)
  { 
    $dotNetRuntimeDir = [System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()
  }

  $installUtil_exe = [System.IO.Path]::Combine($dotNetRuntimeDir, "InstallUtil.exe")
  
  "Uninstalling service..."
  if ($log){
    & $InstallUtil_exe /LogFile=UninstallLog.log /ServiceName=$serviceName /u $destDir
  }
  else
  {
    & $InstallUtil_exe /ServiceName=$serviceName /u $destDir
  }
	
  Start-Sleep -s 5
  "Done `n"
}

function StartWinService([string] $serviceName){
  "Starting service..."
  Start-Service $serviceName
  Start-Sleep -s 10
  $serviceAfter = Get-Service $serviceName
  "$serviceName is now " + $serviceAfter.status
}

function StopWinService([string] $serviceName){
  "Stopping service..."
  if ((Get-Service $serviceName).Status -eq 'Running')
  {
    Stop-Service $serviceName -Force
    Write-Host $serviceName'...' -NoNewLine
    Start-Sleep -s 10
    $service = Get-Service $serviceName
    While($service | Where-Object {$_.Status -eq 'Running'})
    { 
       Write-Host '.'-NoNewLine 
       Start-Sleep 3 
    }
    "`n"+ $serviceName + " is now " + (Get-Service $serviceName).status
  }
  "Done `n"
}

# Devops adding

function ModifyConfigEntries($doc, $settings) {
    $config = $doc.DocumentElement
    foreach ($setting in $settings.entry) {
        ModifyConfigEntry $config $setting.path $setting.keyName $setting.keyValue $setting.parameter $setting.InnerText
    }
}

function ModifyConfigEntry($config, [string]$nodepath, [string]$locateParameterName, [string]$locateParameterValue, [string]$parameterName, [string]$parameterValue)
{
	$existingNodes = $config.SelectNodes($nodepath) | where {$_.GetAttribute("$($locateParameterName)") -eq $locateParameterValue}

	if(!$existingNodes)
	{
		$currentNode = $config
		$pathFragments = $nodepath.Split('/')
		for($i = 0; $i -lt $pathFragments.Count; $i++)
		{
            $query = $pathFragments[$i]
			if($i -eq $pathFragments.Count - 1)
			{
				if($locateParameterName)
				{
				 $query = "$query[@$locateParameterName='$locateParameterValue']"
				}
			}
			$nextNode = $currentNode.SelectSingleNode($query)
			if($nextNode -ne $null)
			{
				$currentNode = $nextNode
			}
			else
			{
                $currentNodeNew = $currentNode.OwnerDocument.CreateNode('element',$pathFragments[$i],"")
	            $currentNode.AppendChild($currentNodeNew)
                $currentNode = $currentNodeNew

				if($locateParameterName -and ($i -eq $pathFragments.Count - 1))
				{
					$currentNode.SetAttribute($locateParameterName, $locateParameterValue)
				}
			}
		}
	}
    else
    {
        $currentNode = $existingNodes
    }
    $currentNode.SetAttribute($parameterName, $parameterValue)
}

function FindPackageName([string] $folder)
{
	$findNamePackage = Get-ChildItem "$folder" -Recurse | where {$_.Name -like "*.zip"} 
	$NamePackage = $findNamePackage| %{ $_.Name }

    $arrayNames = $NamePackage.Split('.')

    $name=$arrayNames[0]+"."+$arrayNames[1]

  return $name
 }
 
function TrimSlashInTheEnd($url)
{
  if ($url.EndsWith("/")){
    $url = $url -replace "/$", ""
  }
  return "$url"
}
 
function ModifyServiceAddresses($serviceUrl, $serviceName)
{
  $servicesBase = TrimSlashInTheEnd $serviceUrl
  ModifyEndpointAddresses $servicesBase $serviceName
}

function ConfigureApplicationPool([string]$appPoolName, [int]$workerProcesses)
{
  cmd /c "%systemroot%\system32\inetsrv\appcmd set apppool /apppool.name:""$appPoolName"" /enable32BitAppOnWin64:false /managedPipelineMode:Integrated /processModel.identityType:ApplicationPoolIdentity /processModel.loadUserProfile:false /processModel.maxProcesses:$workerProcesses"
}

function SetUpRewriteUrls($configRoot, $ruleName, $serviceUrl)
{
  $servicesBase = TrimSlashInTheEnd $serviceUrl
  
  $rewrite = $configRoot."system.webServer"."rewrite"
  $rules = $rewrite.SelectNodes("rules/*")
  foreach ($rule in $rules) {
    if ($rule.name -eq "$ruleName"){
      $rule.action.url = "$servicesBase"
    }
  }
}

function SetRESTPermissions([string]$path, [string]$user){
  $acl = Get-Acl $path
  $ar = New-Object System.Security.AccessControl.FileSystemAccessRule($user,"Write","Allow")
  
  $acl.AddAccessRule($ar)
  Set-Acl $path $acl
}

function ModifyAonBenfieldDistanceToLine ([string]$url) {
  $servicesBase = TrimSlashInTheEnd $url

  $endpoints = $root.SelectNodes("system.serviceModel/client/*")
  foreach ($enpoint in $endpoints){
  
	  if ($enpoint.name -eq "AonBenfieldDistanceToLine"){
		$enpoint.address = "$servicesBase"
	  } 
  }
}

function SetFrontRESTPermissions([string]$dir) {
  $files = [System.IO.Directory]::GetFiles($dir, "*.svc", [System.IO.SearchOption]::TopDirectoryOnly)
  foreach ($f in $files) {
    SetRESTPermissions $f "IIS_IUSRS"
  }
}
