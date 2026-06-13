# MidletOta

Mac-native helper for the old Rumkin/Sprint-style Java ME install path.

The HowardForums thread points to a workflow where you upload a JAR to a service, the service generates a JAD, and the phone downloads the JAD through its browser. That is OTA installation. It is not the same as opening a copied `.jar` or `.jad` from the memory-card file manager.

This folder recreates the useful part without PHP:

- read `META-INF/MANIFEST.MF` from a JAR
- generate an OTA-style `.jad`
- add absolute `MIDlet-Jar-URL`
- add correct `MIDlet-Jar-Size`
- serve `.jad` and `.jar` with Java ME MIME types

It does not cryptographically sign MIDlets.

## Generate A JAD

```sh
python3 tools/MidletOta/make_ota_jad.py path/to/App.jar --base-url http://example.com/midlets --out dist
```

This writes:

```text
dist/App.jar
dist/App.jad
```

The JAD will point to:

```text
http://example.com/midlets/App.jar
```

## Serve Locally

```sh
python3 tools/MidletOta/serve_midlets.py dist --host 0.0.0.0 --port 8000
```

Then a phone would visit:

```text
http://YOUR_MAC_IP:8000/App.jad
```

The Rumor2 has no Wi-Fi, so a local LAN URL probably will not help unless the phone has a data path that can reach your Mac. Usually this requires a public URL or tunnel. The important test is whether the phone browser can download the JAD as an application install, not whether the memory card file manager can open it.

## Why Memory Card Launch Still May Fail

The Rumor2 file manager can show JAR/JAD files on microSD, but that does not mean it invokes the Java Application Manager installer. The old reports specifically describe downloading through a service so the phone receives the JAD over HTTP with the right content type.

If a generated OTA JAD still says `invalid file` from the memory card manager, that does not disprove the OTA path. It only means the memory-card launcher path is still blocked.
