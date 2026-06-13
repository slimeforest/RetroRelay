# Rumor2Probe

This folder contains only the current LG Rumor2 Windows diagnostic-port test.

The target port is:

```text
LGE Mobile USB Serial Port (COM4)
USB\VID_1004&PID_6000_DIAGInterface
```

Ignore `COM5` for this test. It is the LG GPS/NMEA interface.

## Files

```text
rumor2probe_windows.ps1
Run-Rumor2Probe-Windows-COM4-DIAG.bat
Run-Rumor2Probe-Windows-COM4-DIAG-Deep.bat
README.md
```

## Run

Keep the phone out of mass-storage mode so `COM4` stays visible.

First try:

```bat
Run-Rumor2Probe-Windows-COM4-DIAG.bat
```

If that fails or gives no BREW response, try:

```bat
Run-Rumor2Probe-Windows-COM4-DIAG-Deep.bat
```

PowerShell equivalents:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\rumor2probe_windows.ps1 -Port COM4 -BrewOnly -ReadVersion
powershell.exe -ExecutionPolicy Bypass -File .\rumor2probe_windows.ps1 -Port COM4 -BrewOnly -ReadVersion -Deep
```

The probe is read-only. It does not write, delete, move, or rename files on the phone.

## Success

Any response from these is useful:

```text
AT
AT+GMM
AT$QCDMG
AT$LGDMGO
memory config
firmware
brew/version.txt
root directory listing
```

The best result is a response from `brew/version.txt` or a root directory listing. That means the diagnostic/BREW filesystem path is reachable.
