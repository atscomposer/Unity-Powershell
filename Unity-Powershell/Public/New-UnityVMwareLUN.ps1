Function New-UnityVMwareLUN {

  <#
      .SYNOPSIS
      Creates a Unity VMware block LUN.
      .DESCRIPTION
      Creates a Unity VMware block LUN.
      You need to have an active session with the array.
      .NOTES
      Written by Erwan Quelin under MIT licence - https://github.com/equelin/Unity-Powershell/blob/master/LICENSE
      .LINK
      https://github.com/equelin/Unity-Powershell
      .PARAMETER Session
      Specify an UnitySession Object.
      .PARAMETER Name
      Name of the VMware VMFS datastore unique to the system.
      .PARAMETER Pool
      Pool ID
      .PARAMETER Description
      Description of the VMware VMFS datastore.
      .PARAMETER Size
      LUN Size.
      .PARAMETER fastVPParameters
      FAST VP settings for the storage resource
      .PARAMETER isCompressionEnabled
      Indicates whether to enable inline compression for the LUN. Default is True on supported arrays
      .PARAMETER isThinEnabled
      Is Thin enabled? (Default is true)
      .PARAMETER host
      List of host to grant access to LUN.
      .PARAMETER accessMask
      Host access mask. Might be:
      - NoAccess: No access. 
      - Production: Access to production LUNs only. 
      - Snapshot: Access to LUN snapshots only. 
      - Both: Access to both production LUNs and their snapshots.
      .PARAMETER snapSchedule
      Snapshot schedule assigned to the storage resource
      .PARAMETER isSnapSchedulePaused
      Indicates whether the assigned snapshot schedule is paused.
      .EXAMPLE
      New-UnityVMwareLUN -Name 'DATASTORE01' -Pool 'pool_1' -Size 10GB -host 'Host_12' -accessMask 'Production'

      Create LUN named 'DATASTORE01' on pool 'pool_1' and with a size of '10GB', grant production access to 'Host_12'
      .EXAMPLE
      for($i=1; $i -le 10; $i++){New-UnityVMwareLUN -Name "DATASTORE0$i" -Size 2TB -Pool 'pool_1' -host (Get-UnityHost).id}

      Create 10 datastores on pool 'pool_1' and with a size of '2TB', grant production access to all existing hosts.
  #>

  [CmdletBinding(SupportsShouldProcess = $True,ConfirmImpact = 'High')]
  Param (
    [Parameter(Mandatory = $false,HelpMessage = 'EMC Unity Session')]
    $session = ($global:DefaultUnitySession | where-object {$_.IsConnected -eq $true}),
    [Parameter(Mandatory = $true,Position = 0,ValueFromPipeline=$True,ValueFromPipelinebyPropertyName=$True,HelpMessage = 'VMware LUN Name')]
    [String[]]$Name,
    [Parameter(Mandatory = $false,HelpMessage = 'VMware LUN Description')]
    [String]$Description,

    # lunParameters
    [Parameter(Mandatory = $true,HelpMessage = 'VMware LUN Pool ID')]
    [String]$Pool,
    [Parameter(Mandatory = $true,HelpMessage = 'VMware LUN Size in Bytes')]
    [uint64]$Size,
    [Parameter(Mandatory = $false,HelpMessage = 'Host to grant access to VMware LUN')]
    [String[]]$host,
    [Parameter(Mandatory = $false,HelpMessage = 'Host access mask')]
    [HostLUNAccessEnum]$accessMask = 'Production',
    [Parameter(Mandatory = $false,HelpMessage = 'Is Thin enabled on VMware LUN ? (Default is true)')]
    [bool]$isThinEnabled = $true,
    [Parameter(Mandatory = $false,HelpMessage = 'FAST VP settings for the storage resource')]
    [TieringPolicyEnum]$fastVPParameters,
    [Parameter(Mandatory = $false,HelpMessage = 'Indicates whether to enable inline compression for the LUN. Default is True')]
    [bool]$isCompressionEnabled,

    # snapScheduleParameters
    [Parameter(Mandatory = $false,HelpMessage = 'ID of a protection schedule to apply to the storage resource')]
    [String]$snapSchedule,
    [Parameter(Mandatory = $false,HelpMessage = 'Is assigned snapshot schedule is paused ? (Default is false)')]
    [bool]$isSnapSchedulePaused = $false
  )

  Begin {
    Write-Debug -Message "[$($MyInvocation.MyCommand)] Executing function"

    ## Variables
    $URI = '/api/types/storageResource/action/createVmwareLun'
    $Type = 'VMware LUN'
    $StatusCode = 200
  }

  Process {
    Foreach ($sess in $session) {

      Write-Debug -Message "Processing Session: $($sess.Server) with SessionId: $($sess.SessionId)"

      Foreach ($n in $Name) {

        # Creation of the body hash
        $body = @{}

        # Name parameter
        $body["name"] = "$($n)"

        # Domain parameter
        If ($Description) {
              $body["description"] = "$($Description)"
        }

        # lunParameters parameter
        $body["lunParameters"] = @{}
        $lunParameters = @{}
        $poolParameters = @{}

        $poolParameters["id"] = "$($Pool)"
        $lunParameters["pool"] = $poolParameters
        $lunParameters["size"] = $($Size)

        If ($PSBoundParameters.ContainsKey('fastVPParameters')) {
          $lunParameters["fastVPParameters"] = @{}
          $fastVPParam = @{}
          $fastVPParam['tieringPolicy'] = $fastVPParameters
          $lunParameters["fastVPParameters"] = $fastVPParam
        }

        If ($PSBoundParameters.ContainsKey('isCompressionEnabled')) {
          $lunParameters["isCompressionEnabled"] = $isCompressionEnabled
        } else {
          $lunParameters["isCompressionEnabled"] = Test-CompressionUnsupported -Session $Sess -Pool $Pool
        }

        If ($PSBoundParameters.ContainsKey('host')) {
        
          $lunParameters["hostAccess"] = @()
          $hostAccess = @()

          foreach ($h in $host) {
            $blockHostAccessParam = @{}
              $blockHostAccessParam['host'] = @{}
                $HostParam = @{}
                $HostParam['id'] = $h
              $blockHostAccessParam['host'] = $HostParam
              $blockHostAccessParam['accessMask'] = $accessMask
            $hostAccess += $blockHostAccessParam
          }

          $lunParameters["hostAccess"] = $hostAccess
    
        }

        $body["lunParameters"] = $lunParameters

        #snapScheduleParameters
        If ($snapSchedule) {
          $body["snapScheduleParameters"] = @{}
          $snapScheduleParameters = @{}
          $snapScheduleParam = @{}
          $snapScheduleParam["id"] ="$($snapSchedule)"
          $snapScheduleParameters["snapSchedule"] = $snapScheduleParam
          $snapScheduleParameters["isSnapSchedulePaused"]= "$($isSnapSchedulePaused)"
          $body["snapScheduleParameters"] = $snapScheduleParameters
        }

        # isThinEnabled
        If ($isThinEnabled) {
          $lunParameters["isThinEnabled"] = $isThinEnabled
        }

        ####### END BODY - Do not edit beyond this line

        #Show $body in verbose message
        $Json = $body | ConvertTo-Json -Depth 10
        Write-Verbose $Json  

        If ($Sess.TestConnection()) {

          ##Building the URL
          $URL = 'https://'+$sess.Server+$URI
          Write-Verbose "URL: $URL"

          #Sending the request
          If ($pscmdlet.ShouldProcess($Sess.Name,"Create $Type $n")) {
            $request = Send-UnityRequest -uri $URL -Session $Sess -Method 'POST' -Body $Body
          }

          Write-Verbose "Request status code: $($request.StatusCode)"

          If ($request.StatusCode -eq $StatusCode) {

            #Formating the result. Converting it from JSON to a Powershell object
            $results = ($request.content | ConvertFrom-Json).content

            $Storageresource = Get-UnityStorageResource -session $Sess -ID $results.storageResource.id

            Write-Verbose "$Type with the ID $($Storageresource.luns.id) has been created"

            Get-UnityVMwareLUN -Session $Sess -ID $Storageresource.luns.id
          } # End If ($request.StatusCode -eq $StatusCode)
        } # End If ($Sess.TestConnection()) 
      } # End Foreach
    } # End Foreach ($sess in $session)
  } # End Process
} # End Function
