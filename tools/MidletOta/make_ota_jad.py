#!/usr/bin/env python3
"""Generate an OTA-style Java ME JAD from a JAR manifest."""

import argparse
import os
import shutil
import sys
import zipfile


SKIP_KEYS = {
    "midlet-jar-url",
    "midlet-jar-size",
}


def unfold_manifest(text):
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    logical = []
    current = ""
    for line in text.split("\n"):
        if line.startswith(" "):
            current += line[1:]
        else:
            if current:
                logical.append(current)
            current = line
    if current:
        logical.append(current)
    return logical


def read_manifest(jar_path):
    with zipfile.ZipFile(jar_path, "r") as jar:
        with jar.open("META-INF/MANIFEST.MF") as manifest:
            return manifest.read().decode("utf-8", "replace")


def parse_attrs(lines):
    attrs = []
    for line in lines:
        if not line.strip() or ":" not in line:
            continue
        key, value = line.split(":", 1)
        attrs.append((key.strip(), value.strip()))
    return attrs


def find_attr(attrs, wanted):
    wanted = wanted.lower()
    for key, value in attrs:
        if key.lower() == wanted:
            return value
    return None


def jad_for(jar_path, jar_url):
    attrs = parse_attrs(unfold_manifest(read_manifest(jar_path)))
    output = [
        ("MIDlet-Jar-URL", jar_url),
        ("MIDlet-Jar-Size", str(os.path.getsize(jar_path))),
    ]

    seen = set()
    for key, value in attrs:
        lower = key.lower()
        if lower in SKIP_KEYS:
            continue
        if lower.startswith("midlet-") or lower.startswith("microedition-"):
            output.append((key, value))
            seen.add(lower)

    midlet_1 = find_attr(attrs, "MIDlet-1")
    if midlet_1 and "midlet-name" not in seen:
        output.append(("MIDlet-Name", midlet_1.split(",", 1)[0].strip()))

    if "microedition-configuration" not in seen:
        output.append(("MicroEdition-Configuration", "CLDC-1.1"))

    if "microedition-profile" not in seen:
        output.append(("MicroEdition-Profile", "MIDP-2.0"))

    return "\n".join("%s: %s" % item for item in output) + "\n"


def main(argv):
    parser = argparse.ArgumentParser(description="Generate an OTA-style JAD from a Java ME JAR")
    parser.add_argument("jar", help="input JAR")
    parser.add_argument("--base-url", required=True, help="public base URL where the JAR will be hosted")
    parser.add_argument("--out", default="dist", help="output directory")
    parser.add_argument("--name", help="output basename without extension")
    args = parser.parse_args(argv)

    jar_path = os.path.abspath(args.jar)
    if not os.path.isfile(jar_path):
        parser.error("JAR not found: %s" % jar_path)

    name = args.name or os.path.splitext(os.path.basename(jar_path))[0]
    os.makedirs(args.out, exist_ok=True)

    out_jar = os.path.join(args.out, name + ".jar")
    out_jad = os.path.join(args.out, name + ".jad")
    shutil.copyfile(jar_path, out_jar)

    base_url = args.base_url.rstrip("/")
    jar_url = "%s/%s.jar" % (base_url, name)
    with open(out_jad, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(jad_for(out_jar, jar_url))

    print("Wrote %s" % out_jar)
    print("Wrote %s" % out_jad)
    print("JAD points to %s" % jar_url)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
