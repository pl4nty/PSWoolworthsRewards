function Connect-WoolworthsRewards {
  param (
    [string]$BaseUri = "https://api.woolworthsrewards.com.au/wx",
    # defaultClientId, or wow[|Dev|Local|UAT|PT][Online|Mobile]ClientId in index.html footer script
    [string]$ClientId = "8h41mMOiDULmlLT28xKSv5ITpp3XBRvH"
  )

  $script:Session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
  $script:Session.Headers.client_id = $ClientId

  $script:BaseUri = $BaseUri
  $script:Auth = @{
    bearerExpiry = [DateTime]::MaxValue
    refreshExpiry = [DateTime]::MaxValue
  }

  $script:Creds = @{
    username = Read-Host 'Email or card number'
    password = Read-Host 'Password' -MaskInput
  } | ConvertTo-Json

  New-WRSession
  Write-Host 'Successfully authenticated to Woolworths Rewards'
}

function Disconnect-WoolworthsRewards {
  $body = @{'access_token' = $script:Auth.bearer} | ConvertTo-Json
  Invoke-WRRequest 'security/logout/rewards' 'POST' 'v2' -Body $body -ContentType 'application/json'
}

function New-WRSession {
  param (
    $option = 'basic'
  )
  
  $now = Get-Date # set before API call to avoid time desync with server
  $res = switch ($option) {
    'basic' { Invoke-WRRequest 'security/login/rewards' 'POST' 'v2' -Body $script:Creds -ContentType 'application/json' }
    'otp' {
      # TODO implement OTP initialisation
      Invoke-RestMethod 'https://accounts.woolworthsrewards.com.au/er-login/validate-user' -Method Post -Body @{
        otp = $script:Creds
        action = 'VALIDATE_OTP'
      } 
    }
  }
  Update-WRAuth $now $res
}

function Update-WRAuth {
  param (
    [Parameter(Mandatory = $true)]
    [DateTime]$SessionStart,

    [Parameter(Mandatory = $true)]
    $res

    # [Parameter(Mandatory = $true, ParameterSetName='bearer')]
    # [String]$Bearer,
    # [Parameter(Mandatory = $true, ParameterSetName='bearer')]
    # [String]$bearerExpiredInSeconds,

    # [Parameter(ParameterSetName='refresh')]
    # [String]$refresh,
    # [Parameter(ParameterSetName='refresh')]
    # [String]$refreshExpiredInSeconds
  )

  $script:Session.Headers.Authorization = "Bearer $($res.bearer)"

  $script:Auth.bearer = $res.bearer
  $script:Auth.bearerExpiry = $SessionStart.AddSeconds($res.bearerExpiredInSeconds)

  if ($res.refresh) {
    $script:Auth.refresh = $res.refresh
    $script:Auth.refreshExpiry = $SessionStart.AddSeconds($res.refreshExpiredInSeconds)
  }
}

function Invoke-WRRequest {
  param (
    [String]$path,

    [String]$method = 'GET',
    [String]$version = 'v1',

    [String]$uri = "$($script:BaseUri)/$version/$path"
  )
  
  $now = Get-Date
  if ($now -gt $script:Auth.bearerExpiry) {
    $script:Auth.bearerExpiry = [DateTime]::MaxValue

    if ($now -gt $script:Auth.refreshExpiry) {
      $script:Auth.refreshExpiry = [DateTime]::MaxValue
      New-WRSession
    } else {
      $res = Invoke-WRRequest 'security/refreshLogin' 'POST' 'v2' -Body (@{'refresh_token' = $script:Auth.refresh} | ConvertTo-Json)
      $script:Auth = Update-WRAuth $now $res
    }
  }
  
  "$method $uri", $script:Session.Headers | Out-String | write-host
  $res = Invoke-RestMethod -Uri $uri -Method $method -WebSession $script:Session @args
  return $res.data
}

function Get-WRTransactionPDF {
  param (
    [Parameter(Mandatory = $true)]
    [String]$downloadUrl
  )

  return Invoke-WRRequest 'rewards/member/ereceipts/transactions/details/download' 'POST' -Body (@{'downloadUrl' = $downloadUrl} | ConvertTo-Json)
}

function Get-WRTransactions {
  param (
    [Int]$Page = 1
  )

  Invoke-WRRequest "rewards/member/ereceipts/transactions/list?page=$Page"
}

function Get-WRTransactionDetails {
  param (
    [Parameter(Mandatory = $true)]
    [String]$ReceiptKey
  )

  Invoke-WRRequest 'rewards/member/ereceipts/transactions/details' 'POST' -Body (@{receiptKey = $ReceiptKey} | ConvertTo-Json)
}

function Get-WRProfile {
  $res = Invoke-WRRequest "member/profile"
  return $res.member
}

# Get transactions
# $res = @(1,2) | % { Get-WRTransactions $_ } | % { Get-WRTransactionDetails $_.receiptKey }

# Itemise
# $items = $res.receiptDetails.details | where __typename -eq 'ReceiptDetailsItems' | select -ExpandProperty items

# Set price for quantified items, ignoring sale lines
# for ($i=0; $i -lt $items.count; $i++) {
#   if ($items[$i].amount -eq '' -and $items[$i].description -notlike 'PRICE REDUCED*') {
#     $items[$i].amount = $items[$i+1].amount
#     $items[$i+1].amount = $null
#   }
# }

# Filter out quantities and sale lines
# $items | ? amount -notin @('',$null)

# $items | where description -like '*milk*' | measure-object -Sum amount | select Sum

# GET member/profile
# GET member/addresses
# GET member/contacts
# GET member/accounts/rewards/cards?addname=true loyalty card data
# GET member/preferences/security OTP prefs
# GET member/preferences/receipt
# GET member/preferences/redemption
# GET member/preferences/redemption/lock
# GET customerdatareport/request/rewards rewards?
# GET v2/security/hashcrn CRN hashes?
# GET v2/security/social/status?type=Facebook facebook link status
# POST secure/c2login-stepup resendOTP: false
# POST wx/api-otp/verifytoken otptoken
# GET wx/connect/v3/authetoken Apple card JWT?
# {
#   "crn": "330000000000#######",
#   "edr_card": "#############",
#   "wallet_type": "APPLE",
#   "jwt_version": "1",
#   "created": "DateTime",
#   "env": "PROD"
# }
# GET /wx/connect/android/$JWT uses the apple JWT??? returns an android JWT with tons of metadata

