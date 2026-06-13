# Rumor2MacProbe

Mac-native read-only probe for the LG Rumor2 / LX265.

This does not try to rebuild the full BitPim GUI. BitPim's GUI is old Python 2 plus wxPython 2.8-era software, and modern macOS does not provide that stack. More importantly, the Mac must expose the right USB serial interface before any BitPim-style filesystem access can work.

This probe uses only Python 3 and macOS `/dev/cu.*` serial devices. It has no external dependencies.

## Run

Double-click:

```text
Rumor2MacProbe.command
```

Or run from Terminal:

```sh
python3 tools/Rumor2MacProbe/rumor2_mac_probe.py --deep
```

To list ports only:

```sh
python3 tools/Rumor2MacProbe/rumor2_mac_probe.py --list-ports
```

To force a port:

```sh
python3 tools/Rumor2MacProbe/rumor2_mac_probe.py --port /dev/cu.usbmodem21101 --deep
```

## What Success Looks Like

Good first sign:

```text
AT+GMM -> ...LG-LX265...
```

Better sign:

```text
memory config -> ...
```

Best sign:

```text
dir[0] brew
```

or a successful read of:

```text
brew/version.txt
ams/version.txt
```

If AT works but BREW/diagnostic commands do not, macOS is probably exposing only the modem interface, not the LG diagnostic interface. In that case, a Mac-native app cannot install Hello World until we find a Mac driver/path that exposes the diagnostic interface.

## Safety

This probe is read-only. It sends AT identification commands, attempts diagnostic mode switches, and tries filesystem listings/version-file reads. It does not create, delete, or overwrite files on the phone.
