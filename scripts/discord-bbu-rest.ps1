function Invoke-BbuDiscordRequest {
  param(
    [string]$Uri,
    [hashtable]$Headers,
    [string]$UserAgent,
    [ValidateSet('Get','Patch','Post')][string]$Method = 'Get',
    [byte[]]$Body
  )
  foreach ($attempt in 1..5) {
    try {
      $request = @{ Uri=$Uri; Headers=$Headers; UserAgent=$UserAgent; Method=$Method; TimeoutSec=30 }
      if ($null -ne $Body) { $request.Body=$Body; $request.ContentType='application/json; charset=utf-8' }
      return Invoke-RestMethod @request
    } catch {
      # GET and PATCH can safely retry a rate limit. Never retry a POST automatically.
      if ($Method -eq 'Post' -or $attempt -eq 5 -or $null -eq $_.Exception.Response -or [int]$_.Exception.Response.StatusCode -ne 429) { throw }
      $delay = 1.0
      try { $limit=$_.ErrorDetails.Message | ConvertFrom-Json; $delay=[Math]::Max(1.0,[double]$limit.retry_after) } catch { }
      Start-Sleep -Milliseconds ([int][Math]::Ceiling(1000 * $delay))
    }
  }
}
