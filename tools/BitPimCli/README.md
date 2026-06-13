# BitPim CLI Notes

The downloaded BitPim source is vendored at:

```text
third_party/bitpim-source
```

I did not turn the full BitPim GUI into a modern macOS app. The source explicitly requires:

```text
Python 2.5
wxPython 2.8.8.1 Unicode
pySerial 2.4
```

Modern macOS does not provide that stack, and macOS still only exposes the Rumor2 modem interface, not the LG diagnostic interface. Rebuilding the GUI would not by itself make the missing `DIAGInterface` appear.

The useful part is BitPim's existing command-line filesystem mode in `src/bp_cli.py`. It can run filesystem commands without wxPython, as long as you have Python 2 plus pySerial and an actual LG diagnostic COM port.

## Try On Windows With Python 2

From this repository folder on a Windows machine that exposes the Rumor2 diagnostic port:

```bat
tools\BitPimCli\bitpim-cli-ls-vx10000-com4.bat
```

If your diagnostic port is not `COM4`, edit the batch file and change `COM4`.

The batch file runs this:

```bat
python bp.py -p COM4 -f "LG-VX10000 (Voyager)" "ls phone:/"
```

The HowardForums thread said the `LG-VX10000 (Voyager)` profile worked for one LG265/Rumour2 user. You can also try the older Rumor profile:

```bat
python bp.py -p COM4 -f "LG-LX260 (Rumor)" "ls phone:/"
```

## Why This Helps

This uses BitPim's own protocol code instead of my PowerShell reimplementation. If it can list the phone filesystem, we can inspect `/brew`, `/brew/ams`, `/download`, and existing app folders. That is the likely path to replacing a demo app with a tiny Hello World MIDlet.

Stay read-only until the filesystem listing works.
