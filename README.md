# RetroRelay

Current focus: get a minimal Java ME `Hello World` MIDlet running on an LG Rumor2/LX265.

## What We Learned

- The Rumor2 can see `.jar` and `.jad` files on microSD, but trying to launch them from the file manager reports `invalid file`.
- A known third-party Java ME app also reports `invalid file` from microSD, so this is probably an install-path restriction, not just our packaging.
- macOS can see the phone as a USB modem and identify it as `LG-LX265`. The current make-or-break Mac test is whether that port can also enter BREW/diagnostic filesystem mode.
- Installing the LG USB driver on Windows exposes the more useful ports:
  - `COM4`: `USB\VID_1004&PID_6000_DIAGInterface`
  - `COM5`: `USB\VID_1004&PID_6000_GPSInterface`
- `COM4` is the interesting diagnostic port. `COM5` is not useful for Java app installation.

## Current Folder

```text
README.md
third_party/
  bitpim-source/
tools/
  Rumor2MacProbe/
    README.md
    Rumor2MacProbe.command
    rumor2_mac_probe.py
  BitPimCli/
    README.md
    bitpim-cli-ls-vx10000-com4.bat
    bitpim-cli-ls-lx260-com4.bat
  MidletOta/
    README.md
    make_ota_jad.py
    serve_midlets.py
  Rumor2Probe/
    README.md
    Run-Rumor2Probe-Windows-COM4-DIAG.bat
    Run-Rumor2Probe-Windows-COM4-DIAG-Deep.bat
    rumor2probe_windows.ps1
```

`Rumor2MacProbe` and `Rumor2Probe` are read-only. They do not write, delete, move, or rename phone files.

## Mac-Native Test

This is the preferred no-VM route now:

```sh
python3 tools/Rumor2MacProbe/rumor2_mac_probe.py --deep
```

Or double-click:

```text
tools/Rumor2MacProbe/Rumor2MacProbe.command
```

The Mac probe has no external dependencies. It opens `/dev/cu.*` directly, sends safe AT identification commands, then tries read-only BREW filesystem probes based on the old BitPim protocol.

Useful outcomes:

- `AT+GMM -> ...LG-LX265...`: macOS sees the phone's modem interface.
- `memory config -> ...`: the port is responding to BREW/diagnostic packets.
- `dir[0] ...` or `brew/version.txt -> ...`: we can probably continue toward Hello World from the Mac.

If AT works but every BREW probe gets `no response`, then the Mac is still only seeing the modem side of the phone. In that case, a Mac app cannot install Hello World yet because the needed internal filesystem interface is not exposed.

Current Mac result on June 2, 2026:

- Port found: `/dev/cu.usbmodem1101`
- `AT+GMM` returned `Model:LG-LX265`
- `AT+GMI` returned `LG Electronics Inc.`
- `AT$QCDMG` and `AT$LGDMGO` returned `ERROR`
- BREW memory-config probes returned `no response`
- IOKit reports the USB device as `LG CDMA USB Modem`, vendor `0x1004`, product `0x6000`

That means the Mac-native path can talk to the phone, but only through the modem personality so far.

`third_party/bitpim-source` is the downloaded BitPim source. The full GUI cannot be rebuilt on modern macOS without resurrecting Python 2.5 and wxPython 2.8.8.1. The useful piece for this project is BitPim's existing CLI filesystem mode, which does not need wxPython.

## OTA JAD Generator

`tools/MidletOta` recreates the useful part of the old Rumkin/Sprint-style MIDlet service without PHP. It reads a JAR manifest, writes an OTA-style JAD, and can serve JAD/JAR files with Java ME MIME types.

Generate:

```sh
python3 tools/MidletOta/make_ota_jad.py path/to/App.jar --base-url http://example.com/midlets --out dist
```

Serve:

```sh
python3 tools/MidletOta/serve_midlets.py dist --host 0.0.0.0 --port 8000
```

This is not signing. It is OTA install metadata. It may help if the Rumor2 browser can reach the JAD URL. It probably will not make memory-card file-manager launching work.

Try the BitPim CLI wrappers on a Windows machine that exposes the LG diagnostic COM port:

```bat
tools\BitPimCli\bitpim-cli-ls-vx10000-com4.bat
tools\BitPimCli\bitpim-cli-ls-lx260-com4.bat
```

These use BitPim's own protocol code and are read-only `ls phone:/` tests.

## Why Try BitPim In Windows XP

BitPim is old enough that Windows 11 has trouble running it, and the GUI fails on missing legacy wx/Python DLLs. The phone and driver stack are also from the Windows XP era.

An XP VM may help because:

- BitPim was designed for that generation of Windows.
- Old LG USB drivers are more likely to expose the phone interfaces the way BitPim expects.
- BitPim may be able to read the Rumor2 internal BREW filesystem over the diagnostic port.

If BitPim can browse the internal filesystem, then we can look for the phone's Java/BREW download folders and app index files. That is the likely route to installing a Hello World MIDlet, because launching `.jar/.jad` directly from microSD appears blocked.

## XP + BitPim Test

1. In UTM, pass the Rumor2 USB device through to Windows XP.
2. Keep the phone out of mass-storage mode.
3. Install the LG USB driver inside XP if XP does not expose LG COM ports.
4. In Device Manager, find the serial ports. Ignore GPS. Try the first serial port after the modem first.
5. Open BitPim.
6. Try phone profile `LG-VX10000 / Voyager` first.
7. Select the serial COM port manually.
8. Do not use `Get Phone Data` yet. Use BitPim's filesystem/file-view panel and right-click `Refresh filesystem`.

Success is seeing internal folders such as `brew`, `download`, `user`, or similar. Stop there and record the folder list before writing anything.

The HowardForums thread says BitPim 1.0.7.20080908 test worked for one LG265/Rumour2 user. The official 1.0.7 may still work, but the test build is worth trying if the official build cannot refresh the filesystem.

## Phone Menus To Inspect

These dialer codes were reported for the Rumour2/LG265. Use them for read-only inspection first.

```text
##123456#  service program menu
##3282#    3G menu
##2739#    AMS menu
##2769737# browser settings
##2342#    CDG2 menu
##7764726# programming menu
##786#     RTN phone info
```

The most interesting one for Hello World is probably `##2739#` because AMS usually means Application Management System. Look for anything like install source, Java apps, app manager, download manager, or security/policy settings. Do not change values yet; write down menu names/options.

## How This Gets To Hello World

If BitPim can read the internal filesystem, the next step is to find where downloaded Java apps live. Then we can create a tiny, properly packaged MIDP 2.0 Hello World app and place it where the phone's content manager expects installed/downloaded apps.

The rough path is:

```text
BitPim reads internal filesystem
-> identify Java app storage/index files
-> create tiny MIDP Hello World JAR/JAD
-> copy files into the expected internal folder
-> update any required app index/metadata
-> launch from My Stuff / Applications
```

Do not write files until we know the folder layout and index format.

Known filesystem clues from the thread:

- `_policy.txt` was found under `/brew/ams`.
- One user reported demo games could be replaced by overwriting existing `.jar` and `.jad` files.
- Reinstalling an app after replacing policy data mattered for permission changes.

Those point toward `/brew/ams` and existing demo-game app folders/indexes as the most promising places to inspect first.
