param(
    [string]$Port = "COM4",
    [int]$Baud = 115200,
    [switch]$AtOnly,
    [switch]$BrewOnly,
    [switch]$Deep,
    [switch]$ReadVersion,
    [int]$MaxEntries = 5,
    [string]$Directory = ""
)

$ErrorActionPreference = "Stop"

$BrewTerm = [byte]0x7e
$BrewCommandMode = [byte]0x59
$ErrorNames = @{
    4 = "access denied"
    6 = "no such file"
    7 = "directory exists"
    8 = "no such directory"
    11 = "file locked"
    13 = "name too long"
    22 = "filesystem full"
    26 = "bad pathname"
    28 = "no more entries"
}

function Format-HexBytes([byte[]]$Data) {
    if ($null -eq $Data -or $Data.Length -eq 0) { return "" }
    return (($Data | ForEach-Object { $_.ToString("x2") }) -join " ")
}

function Format-Printable([byte[]]$Data) {
    if ($null -eq $Data -or $Data.Length -eq 0) { return "" }
    $chars = foreach ($b in $Data) {
        if ($b -ge 32 -and $b -lt 127) { [char]$b } else { "." }
    }
    return -join $chars
}

function Add-Byte([System.Collections.Generic.List[byte]]$List, [int]$Value) {
    $List.Add([byte]($Value -band 0xff))
}

function Add-Bytes([System.Collections.Generic.List[byte]]$List, [byte[]]$Bytes) {
    foreach ($b in $Bytes) { $List.Add($b) }
}

function Get-BrewCrc([byte[]]$Data) {
    [int]$value = 0xffff
    foreach ($b in $Data) {
        $value = $value -bxor [int]$b
        for ($i = 0; $i -lt 8; $i++) {
            if (($value -band 1) -ne 0) {
                $value = (($value -shr 1) -bxor 0x8408) -band 0xffff
            } else {
                $value = ($value -shr 1) -band 0xffff
            }
        }
    }
    return ((-bnot $value) -band 0xffff)
}

function ConvertTo-PppEscaped([byte[]]$Data) {
    $out = [System.Collections.Generic.List[byte]]::new()
    foreach ($b in $Data) {
        if ($b -eq 0x7d) {
            Add-Byte $out 0x7d
            Add-Byte $out 0x5d
        } elseif ($b -eq 0x7e) {
            Add-Byte $out 0x7d
            Add-Byte $out 0x5e
        } else {
            $out.Add($b)
        }
    }
    return $out.ToArray()
}

function ConvertFrom-PppEscaped([byte[]]$Data) {
    $out = [System.Collections.Generic.List[byte]]::new()
    for ($i = 0; $i -lt $Data.Length; $i++) {
        $b = $Data[$i]
        if ($b -eq 0x7d -and ($i + 1) -lt $Data.Length) {
            $i++
            Add-Byte $out ([int]$Data[$i] -bxor 0x20)
        } else {
            $out.Add($b)
        }
    }
    return $out.ToArray()
}

function New-BrewFrame([byte[]]$Payload) {
    $out = [System.Collections.Generic.List[byte]]::new()
    Add-Bytes $out $Payload
    $crc = Get-BrewCrc $Payload
    Add-Byte $out ($crc -band 0xff)
    Add-Byte $out (($crc -shr 8) -band 0xff)
    $escaped = ConvertTo-PppEscaped $out.ToArray()
    $frame = [System.Collections.Generic.List[byte]]::new()
    Add-Bytes $frame $escaped
    Add-Byte $frame $BrewTerm
    return $frame.ToArray()
}

function New-PascalZString([string]$Text) {
    $rawText = [Text.Encoding]::ASCII.GetBytes($Text)
    $out = [System.Collections.Generic.List[byte]]::new()
    Add-Byte $out ($rawText.Length + 1)
    Add-Bytes $out $rawText
    Add-Byte $out 0
    return $out.ToArray()
}

function Read-PascalZString([byte[]]$Data, [int]$Offset) {
    if ($Offset -ge $Data.Length) { return "" }
    $length = [int]$Data[$Offset]
    $start = $Offset + 1
    $end = [Math]::Min($start + $length, $Data.Length)
    $bytes = $Data[$start..($end - 1)]
    if ($bytes.Length -gt 0 -and $bytes[$bytes.Length - 1] -eq 0) {
        if ($bytes.Length -eq 1) { return "" }
        $bytes = $bytes[0..($bytes.Length - 2)]
    }
    return [Text.Encoding]::GetEncoding("iso-8859-1").GetString($bytes)
}

function Read-Available($Serial, [double]$TimeoutSeconds = 1.2) {
    $out = [System.Collections.Generic.List[byte]]::new()
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        while ($Serial.BytesToRead -gt 0) {
            $count = $Serial.BytesToRead
            $buffer = New-Object byte[] $count
            [void]$Serial.Read($buffer, 0, $count)
            Add-Bytes $out $buffer
            $deadline = (Get-Date).AddMilliseconds(150)
        }
        Start-Sleep -Milliseconds 20
    } while ((Get-Date) -lt $deadline)
    return $out.ToArray()
}

function Read-UntilTerm($Serial, [double]$TimeoutSeconds = 2.0) {
    $out = [System.Collections.Generic.List[byte]]::new()
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        while ($Serial.BytesToRead -gt 0) {
            $count = $Serial.BytesToRead
            $buffer = New-Object byte[] $count
            [void]$Serial.Read($buffer, 0, $count)
            foreach ($b in $buffer) {
                $out.Add($b)
                if ($b -eq $BrewTerm) { return $out.ToArray() }
            }
        }
        Start-Sleep -Milliseconds 20
    } while ((Get-Date) -lt $deadline)
    return $out.ToArray()
}

function Send-At($Serial, [string]$Command, [string]$LineEnding = "`r") {
    $bytes = [Text.Encoding]::ASCII.GetBytes("AT$Command$LineEnding")
    $Serial.Write($bytes, 0, $bytes.Length)
    return Read-Available $Serial 1.2
}

function Decode-BrewPacket([byte[]]$Raw, [string]$Label) {
    if ($null -eq $Raw -or $Raw.Length -eq 0) {
        throw "$Label`: no response"
    }
    $parts = @()
    $current = [System.Collections.Generic.List[byte]]::new()
    foreach ($b in $Raw) {
        if ($b -eq $BrewTerm) {
            if ($current.Count -gt 0) { $parts += ,($current.ToArray()) }
            $current = [System.Collections.Generic.List[byte]]::new()
        } else {
            $current.Add($b)
        }
    }
    if ($parts.Count -eq 0) {
        throw "$Label`: no complete BREW packet in $(Format-HexBytes $Raw)"
    }
    $decoded = ConvertFrom-PppEscaped $parts[$parts.Count - 1]
    if ($decoded.Length -lt 3) {
        throw "$Label`: response too short: $(Format-HexBytes $decoded)"
    }
    $payloadLength = $decoded.Length - 2
    $payload = $decoded[0..($payloadLength - 1)]
    $got = [int]$decoded[$payloadLength] -bor ([int]$decoded[$payloadLength + 1] -shl 8)
    $want = Get-BrewCrc $payload
    if ($got -ne $want) {
        throw "$Label`: bad CRC got $($got.ToString("x4")), expected $($want.ToString("x4")); payload $(Format-HexBytes $payload)"
    }
    if ($payload.Length -ge 3 -and $payload[0] -eq $BrewCommandMode -and $payload[2] -ne 0) {
        $code = [int]$payload[2]
        $name = if ($ErrorNames.ContainsKey($code)) { $ErrorNames[$code] } else { "unknown" }
        throw "$Label`: BREW error $code ($name)"
    }
    return $payload
}

function Send-Brew($Serial, [byte[]]$Payload, [string]$Label) {
    $frame = New-BrewFrame $Payload
    $Serial.Write($frame, 0, $frame.Length)
    $raw = Read-UntilTerm $Serial 2.0
    return Decode-BrewPacket $raw $Label
}

function Parse-MemoryConfig([byte[]]$Payload) {
    if ($Payload.Length -ge 7 -and $Payload[0] -eq $BrewCommandMode) {
        return [BitConverter]::ToUInt32($Payload, 3)
    }
    return $null
}

function Parse-DirResponse([byte[]]$Payload) {
    if ($Payload.Length -lt 24) { return $null }
    $offset = 24
    if ($offset -lt $Payload.Length -and $Payload[$offset] -eq 0) { $offset++ }
    return Read-PascalZString $Payload $offset
}

function Parse-FileResponse([byte[]]$Payload) {
    if ($Payload.Length -lt 26) { return $null }
    $size = [BitConverter]::ToUInt32($Payload, 15)
    $offset = 23
    if ($offset -lt $Payload.Length -and $Payload[$offset] -eq 0) { $offset++ }
    $offset++ # directory-name length byte
    if ($offset -lt $Payload.Length -and $Payload[$offset] -eq 0) { $offset++ }
    $name = Read-PascalZString $Payload $offset
    return @{ Name = $name; Size = $size }
}

function Find-AtMode($Serial) {
    $baudList = if ($Deep) { @($Baud, 115200, 38400, 19200, 9600, 230400) | Select-Object -Unique } else { @($Baud) }
    $lineEndings = if ($Deep) {
        @(
            @{ Name = "CR"; Value = "`r" },
            @{ Name = "CRLF"; Value = "`r`n" },
            @{ Name = "LF"; Value = "`n" }
        )
    } else {
        @(@{ Name = "CR"; Value = "`r" })
    }
    $lineStates = if ($Deep) {
        @(
            @{ Name = "DTR off / RTS off"; Dtr = $false; Rts = $false },
            @{ Name = "DTR on / RTS off"; Dtr = $true; Rts = $false },
            @{ Name = "DTR off / RTS on"; Dtr = $false; Rts = $true },
            @{ Name = "DTR on / RTS on"; Dtr = $true; Rts = $true }
        )
    } else {
        @(@{ Name = "DTR off / RTS off"; Dtr = $false; Rts = $false })
    }

    foreach ($b in $baudList) {
        $Serial.BaudRate = $b
        foreach ($state in $lineStates) {
            $Serial.DtrEnable = $state.Dtr
            $Serial.RtsEnable = $state.Rts
            Start-Sleep -Milliseconds 120
            $null = Read-Available $Serial 0.2
            foreach ($ending in $lineEndings) {
                try {
                    $response = Send-At $Serial "" $ending.Value
                    if ($response.Length -gt 0) {
                        Write-Host "  AT discovery: $b baud / $($ending.Name) / $($state.Name) -> $(Format-Printable $response)"
                        Write-Host "      hex $(Format-HexBytes $response)"
                        return @{ Baud = $b; LineEnding = $ending.Value; LineEndingName = $ending.Name; Dtr = $state.Dtr; Rts = $state.Rts; LineStateName = $state.Name }
                    }
                    Write-Host "  AT discovery: $b baud / $($ending.Name) / $($state.Name) -> no response"
                } catch {
                    Write-Host "  AT discovery: $b baud / $($ending.Name) / $($state.Name) failed: $($_.Exception.Message)"
                }
            }
        }
    }
    return $null
}

function Run-AtProbe($Serial) {
    Write-Host ""
    Write-Host "AT probe"
    $mode = Find-AtMode $Serial
    if ($null -eq $mode) {
        Write-Host "  No AT response found."
        Write-Host "  Try -Deep, close BitPim, unplug/replug the phone, or install the LG USB modem driver."
        return $null
    }

    $Serial.BaudRate = $mode.Baud
    $Serial.DtrEnable = $mode.Dtr
    $Serial.RtsEnable = $mode.Rts
    Write-Host "  Using AT mode: $($mode.Baud) baud / $($mode.LineEndingName) / $($mode.LineStateName)"
    foreach ($cmd in @("", "E0", "+GMM", "+GMI", "+CGMM", "`$QCDMG", "`$LGDMGO")) {
        $response = Send-At $Serial $cmd $mode.LineEnding
        $label = "AT$cmd"
        if ($response.Length -gt 0) {
            Write-Host "  $label -> $(Format-Printable $response)"
            Write-Host "      hex $(Format-HexBytes $response)"
        } else {
            Write-Host "  $label -> no response"
        }
    }
    return $mode
}

function Try-MemoryConfig($Serial, [string]$Prefix) {
    try {
        $payload = Send-Brew $Serial ([byte[]]@($BrewCommandMode, 0x0c)) "memory config"
        $amount = Parse-MemoryConfig $payload
        if ($null -eq $amount) {
            Write-Host "  $Prefix memory response $(Format-HexBytes $payload)"
        } else {
            Write-Host "  $Prefix memory config $amount bytes"
        }
        return $true
    } catch {
        Write-Host "  $Prefix failed: $($_.Exception.Message)"
        return $false
    }
}

function Get-LineStates {
    if ($Deep) {
        return @(
            @{ Name = "DTR off / RTS off"; Dtr = $false; Rts = $false },
            @{ Name = "DTR on / RTS off"; Dtr = $true; Rts = $false },
            @{ Name = "DTR off / RTS on"; Dtr = $false; Rts = $true },
            @{ Name = "DTR on / RTS on"; Dtr = $true; Rts = $true }
        )
    }
    return @(@{ Name = "DTR off / RTS off"; Dtr = $false; Rts = $false })
}

function Enter-BrewMode($Serial) {
    Write-Host ""
    Write-Host "BREW mode setup"
    $directBauds = if ($Deep) { @($Baud, 38400, 115200, 19200, 230400) | Select-Object -Unique } else { @($Baud) }
    $modeBauds = if ($Deep) { @(115200, 19200, 38400, 230400) } else { @($Baud) }
    $lineStates = Get-LineStates

    foreach ($b in $directBauds) {
        $Serial.BaudRate = $b
        foreach ($state in $lineStates) {
            $Serial.DtrEnable = $state.Dtr
            $Serial.RtsEnable = $state.Rts
            Start-Sleep -Milliseconds 120
            $null = Read-Available $Serial 0.2
            if (Try-MemoryConfig $Serial "direct BREW at $b baud / $($state.Name)") { return $true }
        }
    }

    foreach ($modeCommand in @("`$QCDMG", "`$LGDMGO")) {
        foreach ($b in $modeBauds) {
            $Serial.BaudRate = $b
            $response = Send-At $Serial $modeCommand
            if ($response.Length -gt 0) {
                Write-Host "  AT$modeCommand at $b -> $(Format-Printable $response)"
                Write-Host "      hex $(Format-HexBytes $response)"
            } else {
                Write-Host "  AT$modeCommand at $b -> no response"
            }
            Start-Sleep -Milliseconds 250
            $probeBauds = if ($Deep) { @($b, 38400, 115200, 19200, 230400) | Select-Object -Unique } else { @($b) }
            foreach ($probeBaud in $probeBauds) {
                $Serial.BaudRate = $probeBaud
                foreach ($state in $lineStates) {
                    $Serial.DtrEnable = $state.Dtr
                    $Serial.RtsEnable = $state.Rts
                    Start-Sleep -Milliseconds 120
                    $null = Read-Available $Serial 0.2
                    if (Try-MemoryConfig $Serial "BREW after AT$modeCommand at $probeBaud baud / $($state.Name)") { return $true }
                }
            }
        }
    }

    return $false
}

function Run-BrewProbe($Serial) {
    Write-Host ""
    Write-Host "BREW probe"
    if (-not (Enter-BrewMode $Serial)) {
        Write-Host "  Could not enter BREW/diagnostic mode on $Port."
        Write-Host "  If Windows exposes another COM port after installing an LG driver, try that port."
        Write-Host "  For the full BitPim-style sweep, rerun with -Deep."
        return
    }

    try {
        $payload = Send-Brew $Serial ([byte[]]@(0x00)) "firmware"
        Write-Host "  firmware -> $(Format-Printable $payload)"
        Write-Host "      hex $(Format-HexBytes $payload)"
    } catch {
        Write-Host "  firmware failed: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-Host "Root listing probe for directory '$Directory'"
    for ($i = 0; $i -lt $MaxEntries; $i++) {
        try {
            $request = [System.Collections.Generic.List[byte]]::new()
            Add-Byte $request $BrewCommandMode
            Add-Byte $request 0x0a
            Add-Bytes $request ([BitConverter]::GetBytes([uint32]$i))
            Add-Bytes $request (New-PascalZString $Directory)
            $payload = Send-Brew $Serial $request.ToArray() "list directory $i"
            Write-Host "  dir[$i] $(Parse-DirResponse $payload)"
        } catch {
            Write-Host "  dir[$i] stopped: $($_.Exception.Message)"
            break
        }
    }

    for ($i = 0; $i -lt $MaxEntries; $i++) {
        try {
            $request = [System.Collections.Generic.List[byte]]::new()
            Add-Byte $request $BrewCommandMode
            Add-Byte $request 0x0b
            Add-Bytes $request ([BitConverter]::GetBytes([uint32]$i))
            Add-Bytes $request (New-PascalZString $Directory)
            $payload = Send-Brew $Serial $request.ToArray() "list file $i"
            $file = Parse-FileResponse $payload
            Write-Host "  file[$i] $($file.Name) ($($file.Size) bytes)"
        } catch {
            Write-Host "  file[$i] stopped: $($_.Exception.Message)"
            break
        }
    }

    if ($ReadVersion) {
        try {
            $request = [System.Collections.Generic.List[byte]]::new()
            Add-Byte $request $BrewCommandMode
            Add-Byte $request 0x04
            Add-Byte $request 0x00
            Add-Bytes $request (New-PascalZString "brew/version.txt")
            $payload = Send-Brew $Serial $request.ToArray() "read brew/version.txt"
            Write-Host "  brew/version.txt raw -> $(Format-Printable $payload)"
            Write-Host "      hex $(Format-HexBytes $payload)"
        } catch {
            Write-Host "  read brew/version.txt failed: $($_.Exception.Message)"
        }
    }
}

Write-Host "Rumor2Probe Windows read-only connection test"
Write-Host "Using port: $Port at $Baud baud"
Write-Host "Keep the phone out of mass-storage mode so the COM port stays visible."

$serial = New-Object System.IO.Ports.SerialPort $Port, $Baud, None, 8, one
$serial.ReadTimeout = 1000
$serial.WriteTimeout = 1000
$serial.DtrEnable = $false
$serial.RtsEnable = $false

try {
    $serial.Open()
    Start-Sleep -Milliseconds 250
    $null = Read-Available $serial 0.3
    if (-not $BrewOnly) { $null = Run-AtProbe $serial }
    if (-not $AtOnly) { Run-BrewProbe $serial }
} finally {
    if ($serial.IsOpen) { $serial.Close() }
}

Write-Host ""
Write-Host "Done. This probe did not write files to the phone."
