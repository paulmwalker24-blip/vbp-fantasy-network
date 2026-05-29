param(
    [string]$LeagueRecordId = "BBU7",
    [string[]]$ManagerNames = @(),
    [int]$MinYards = 3,
    [int]$MaxYards = 8,
    [int]$MinSeconds = 2,
    [int]$MaxSeconds = 6,
    [ValidateSet("Normal", "Fast", "Faster", "Fastest")]
    [string]$Speed = "Fast",
    [switch]$PassThru
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    Split-Path -Parent $PSScriptRoot
}

function Read-LeagueRecord {
    param([string]$RecordId)

    $repoRoot = Get-RepoRoot
    $path = Join-Path $repoRoot "data\leagues.json"
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Could not find data\leagues.json."
    }

    $data = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    $league = @($data.leagues | Where-Object { $_.id -eq $RecordId })[0]
    if (-not $league) {
        throw "League record '$RecordId' was not found in data\leagues.json."
    }

    $league
}

function Invoke-SleeperJson {
    param([string]$Uri)

    Invoke-RestMethod -Uri $Uri -Method Get -TimeoutSec 20
}

function ConvertTo-FlatArray {
    param([object]$Value)

    if ($null -eq $Value) {
        return @()
    }

    $items = @($Value)
    if ($items.Count -eq 1 -and $items[0] -is [array]) {
        return @($items[0])
    }

    $items
}

function Get-DisplayNameForUser {
    param(
        [object]$User,
        [string]$Fallback
    )

    if ($User) {
        if ($User.metadata -and $User.metadata.team_name) {
            return [string]$User.metadata.team_name
        }
        if ($User.display_name) {
            return [string]$User.display_name
        }
        if ($User.username) {
            return [string]$User.username
        }
    }

    $Fallback
}

function Get-ManagersFromSleeper {
    param([object]$League)

    if (-not $League.sleeperLeagueId) {
        return @()
    }

    $leagueId = [string]$League.sleeperLeagueId
    $users = @(ConvertTo-FlatArray (Invoke-SleeperJson "https://api.sleeper.app/v1/league/$leagueId/users"))
    $rosters = @(ConvertTo-FlatArray (Invoke-SleeperJson "https://api.sleeper.app/v1/league/$leagueId/rosters"))
    $drafts = @(ConvertTo-FlatArray (Invoke-SleeperJson "https://api.sleeper.app/v1/league/$leagueId/drafts"))
    $userById = @{}

    foreach ($user in $users) {
        if ($user.user_id) {
            $userById[[string]$user.user_id] = $user
        }
    }

    $names = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    $draft = @($drafts | Sort-Object { if ($_.created) { -[int64]$_.created } else { 0 } })[0]

    if ($draft -and $draft.draft_order) {
        $draft.draft_order.PSObject.Properties |
            Sort-Object { [int]$_.Value } |
            ForEach-Object {
                $userId = [string]$_.Name
                if ($seen.ContainsKey($userId)) {
                    return
                }
                $displayName = Get-DisplayNameForUser -User $userById[$userId] -Fallback $userId
                if ($displayName) {
                    $names.Add($displayName)
                    $seen[$userId] = $true
                }
            }
    }

    foreach ($roster in ($rosters | Sort-Object roster_id)) {
        if (-not $roster.owner_id) {
            continue
        }
        $userId = [string]$roster.owner_id
        if ($seen.ContainsKey($userId)) {
            continue
        }
        $displayName = Get-DisplayNameForUser -User $userById[$userId] -Fallback $userId
        if ($displayName) {
            $names.Add($displayName)
            $seen[$userId] = $true
        }
    }

    @($names)
}

function New-RaceReplay {
    param(
        [string[]]$Names,
        [int]$MinYards,
        [int]$MaxYards,
        [int]$MinSeconds,
        [int]$MaxSeconds,
        [string]$Speed
    )

    if ($Names.Count -lt 1) {
        throw "At least one manager name is required."
    }
    if ($MinYards -lt 1 -or $MaxYards -lt $MinYards) {
        throw "Invalid yard range: $MinYards-$MaxYards."
    }
    if ($MinSeconds -lt 1 -or $MaxSeconds -lt $MinSeconds) {
        throw "Invalid seconds range: $MinSeconds-$MaxSeconds."
    }

    $total = 100
    $players = @()
    $replays = @()

    for ($id = 0; $id -lt $Names.Count; $id++) {
        $progress = 0.0
        $elapsed = 0.0
        $yardsList = New-Object System.Collections.Generic.List[string]
        $timeList = New-Object System.Collections.Generic.List[string]

        while ($progress -lt $total) {
            $yards = Get-Random -Minimum $MinYards -Maximum ($MaxYards + 1)
            $time = Get-Random -Minimum ($MinSeconds * 1000) -Maximum (($MaxSeconds * 1000) + 1)
            $yardsList.Add([string]$yards)
            $timeList.Add([string]$time)

            $adjustedYards = [double]$yards
            $adjustedTime = [double]$time
            if ($Speed -eq "Fast") {
                $adjustedYards *= 2
            }
            elseif ($Speed -eq "Faster") {
                $adjustedYards *= 2
                $adjustedTime /= 2
            }
            elseif ($Speed -eq "Fastest") {
                $adjustedYards *= 3
                $adjustedTime /= 3
            }

            $previousProgress = $progress
            $nextProgress = $progress + $adjustedYards
            if ($nextProgress -ge $total) {
                $needed = $total - $previousProgress
                $fraction = $needed / $adjustedYards
                $elapsed = $elapsed + ($adjustedTime * $fraction) + ($id * 0.0001)
                $progress = $total
            }
            else {
                $progress = $nextProgress
                $elapsed = $elapsed + $adjustedTime
            }
        }

        $players += [pscustomobject]@{
            id = $id
            name = $Names[$id]
            finishMs = $elapsed
            yards = ($yardsList -join ",")
            time = ($timeList -join ",")
        }
    }

    $sorted = @($players | Sort-Object finishMs, id)
    $placeById = @{}
    for ($i = 0; $i -lt $sorted.Count; $i++) {
        $placeById[[int]$sorted[$i].id] = $i + 1
    }

    for ($id = 0; $id -lt $players.Count; $id++) {
        $player = $players[$id]
        $replays += ("{0}:{1}:{2}" -f $placeById[$id], $player.yards, $player.time)
    }

    $results = @(
        $sorted | ForEach-Object {
            [pscustomobject]@{
                place = $placeById[[int]$_.id]
                name = $_.name
                finishSeconds = [math]::Round(($_.finishMs / 1000), 3)
            }
        }
    )

    [pscustomobject]@{
        replay = ($replays -join "-")
        results = $results
    }
}

function Save-100YardRushReplay {
    param(
        [string[]]$Names,
        [string]$Replay,
        [int]$MinYards,
        [int]$MaxYards,
        [int]$MinSeconds,
        [int]$MaxSeconds,
        [string]$Speed
    )

    $characters = @(1..32 | Get-Random -Count $Names.Count)
    $animated = "true:" + (($characters | ForEach-Object { "$($_)-$(Get-Random -Minimum 1 -Maximum 3)" }) -join ",")
    $body = @{
        "save-settings" = "true"
        teams = [string]$Names.Count
        names = (($Names | ForEach-Object { [uri]::EscapeDataString($_) }) -join ",")
        settings = "$MinYards,$MaxYards,$MinSeconds,$MaxSeconds,$Speed"
        img = ""
        code = ""
        animated = $animated
        luck = ""
        date = [string]([DateTimeOffset]::Now.ToUnixTimeMilliseconds())
        replay = $Replay
        remote = ""
        link = ""
    }

    $code = Invoke-WebRequest -Uri "https://100yardrush.com/process/p-savesettings.php" -Method Post -Body $body -UseBasicParsing -TimeoutSec 20 |
        Select-Object -ExpandProperty Content

    "https://100yardrush.com/rush/v/$code"
}

function Normalize-ManagerNames {
    param([string[]]$InputNames)

    @(
        $InputNames |
            ForEach-Object { [string]$_ } |
            ForEach-Object { $_ -split "," } |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
    )
}

$league = Read-LeagueRecord -RecordId $LeagueRecordId
$names = @(Normalize-ManagerNames -InputNames $ManagerNames)
if ($names.Count -eq 0) {
    $names = @(Get-ManagersFromSleeper -League $league)
}

if ($names.Count -eq 0) {
    throw "No manager names were found. Pass -ManagerNames or make sure $LeagueRecordId has a Sleeper league ID."
}

$race = New-RaceReplay -Names $names -MinYards $MinYards -MaxYards $MaxYards -MinSeconds $MinSeconds -MaxSeconds $MaxSeconds -Speed $Speed
$url = Save-100YardRushReplay -Names $names -Replay $race.replay -MinYards $MinYards -MaxYards $MaxYards -MinSeconds $MinSeconds -MaxSeconds $MaxSeconds -Speed $Speed

$summary = [pscustomobject]@{
    leagueRecordId = $LeagueRecordId
    leagueName = $league.name
    managerCount = $names.Count
    settings = [pscustomobject]@{
        minYards = $MinYards
        maxYards = $MaxYards
        minSeconds = $MinSeconds
        maxSeconds = $MaxSeconds
        speed = $Speed
    }
    replayUrl = $url
    results = $race.results
}

if ($PassThru) {
    $summary
}
else {
    Write-Host "100 Yard Rush replay: $($summary.replayUrl)"
    Write-Host "Settings: $MinYards-$MaxYards yards, $MinSeconds-$MaxSeconds seconds, $Speed speed"
    Write-Host "Managers: $($names.Count)"
    Write-Host ""
    foreach ($result in $summary.results) {
        Write-Host ("{0}. {1} ({2:N3}s)" -f $result.place, $result.name, $result.finishSeconds)
    }
}
