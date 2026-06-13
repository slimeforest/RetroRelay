#!/usr/bin/env python3
"""
Read-only LG Rumor2 / LX265 macOS USB probe.

This is intentionally tiny and dependency-free. It talks to /dev/cu.* devices
using POSIX termios directly so a modern Mac does not need pySerial, Python 2,
wxPython, BitPim, or a VM just to test the connection.
"""

import argparse
import glob
import os
import select
import struct
import sys
import termios
import time


TERM = 0x7E
COMMAND_MODE = 0x59

ERROR_NAMES = {
    4: "access denied",
    6: "no such file",
    7: "directory exists",
    8: "no such directory",
    11: "file locked",
    13: "name too long",
    22: "filesystem full",
    26: "bad pathname",
    28: "no more entries",
}

BAUDS = {
    9600: termios.B9600,
    19200: termios.B19200,
    38400: termios.B38400,
    57600: termios.B57600,
    115200: termios.B115200,
    230400: getattr(termios, "B230400", termios.B115200),
}


class BrewError(Exception):
    def __init__(self, code, message):
        Exception.__init__(self, message)
        self.code = code


def hex_bytes(data):
    return " ".join("%02x" % b for b in data)


def printable(data):
    return "".join(chr(b) if 32 <= b < 127 else "." for b in data)


def pascal_z(text):
    raw = text.encode("ascii", "replace")
    if len(raw) > 254:
        raw = raw[:254]
    return bytes([len(raw) + 1]) + raw + b"\x00"


def read_pascal_z(data, offset):
    if offset >= len(data):
        return ""
    length = data[offset]
    start = offset + 1
    end = min(start + length, len(data))
    raw = data[start:end]
    if raw.endswith(b"\x00"):
        raw = raw[:-1]
    return raw.decode("iso-8859-1", "replace")


def crc16_brew(data):
    value = 0xFFFF
    for b in data:
        value ^= b
        for _ in range(8):
            if value & 1:
                value = ((value >> 1) ^ 0x8408) & 0xFFFF
            else:
                value = (value >> 1) & 0xFFFF
    return (~value) & 0xFFFF


def ppp_escape(data):
    out = bytearray()
    for b in data:
        if b == 0x7D:
            out.extend((0x7D, 0x5D))
        elif b == 0x7E:
            out.extend((0x7D, 0x5E))
        else:
            out.append(b)
    return bytes(out)


def ppp_unescape(data):
    out = bytearray()
    i = 0
    while i < len(data):
        b = data[i]
        if b == 0x7D and i + 1 < len(data):
            i += 1
            out.append(data[i] ^ 0x20)
        else:
            out.append(b)
        i += 1
    return bytes(out)


def brew_frame(payload):
    crc = crc16_brew(payload)
    return ppp_escape(payload + struct.pack("<H", crc)) + bytes([TERM])


def decode_brew(raw, label):
    if not raw:
        raise RuntimeError("%s: no response" % label)

    packets = []
    current = bytearray()
    for b in raw:
        if b == TERM:
            if current:
                packets.append(bytes(current))
            current = bytearray()
        else:
            current.append(b)

    if not packets:
        raise RuntimeError("%s: no complete BREW packet in %s" % (label, hex_bytes(raw)))

    decoded = ppp_unescape(packets[-1])
    if len(decoded) < 3:
        raise RuntimeError("%s: short BREW packet %s" % (label, hex_bytes(decoded)))

    payload = decoded[:-2]
    got = struct.unpack("<H", decoded[-2:])[0]
    want = crc16_brew(payload)
    if got != want:
        raise RuntimeError(
            "%s: bad CRC got %04x expected %04x payload %s"
            % (label, got, want, hex_bytes(payload))
        )

    if len(payload) >= 3 and payload[0] == COMMAND_MODE and payload[2] != 0:
        code = payload[2]
        name = ERROR_NAMES.get(code, "unknown")
        raise BrewError(code, "%s: BREW error %d (%s)" % (label, code, name))

    return payload


class SerialPort:
    def __init__(self, path, baud):
        self.path = path
        self.baud = baud
        self.fd = None
        self.old_attrs = None

    def open(self):
        self.fd = os.open(self.path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        self.old_attrs = termios.tcgetattr(self.fd)
        self.set_baud(self.baud)
        termios.tcflush(self.fd, termios.TCIOFLUSH)

    def close(self):
        if self.fd is not None:
            if self.old_attrs is not None:
                try:
                    termios.tcsetattr(self.fd, termios.TCSANOW, self.old_attrs)
                except termios.error:
                    pass
            os.close(self.fd)
            self.fd = None

    def set_baud(self, baud):
        if baud not in BAUDS:
            raise ValueError("unsupported baud %s" % baud)
        attrs = termios.tcgetattr(self.fd)
        attrs[0] = termios.IGNPAR
        attrs[1] = 0
        attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
        attrs[3] = 0
        attrs[4] = BAUDS[baud]
        attrs[5] = BAUDS[baud]
        attrs[6][termios.VMIN] = 0
        attrs[6][termios.VTIME] = 0
        termios.tcsetattr(self.fd, termios.TCSANOW, attrs)
        self.baud = baud
        termios.tcflush(self.fd, termios.TCIOFLUSH)

    def write(self, data):
        os.write(self.fd, data)

    def read_available(self, timeout=1.2, settle=0.12):
        out = bytearray()
        deadline = time.time() + timeout
        while time.time() < deadline:
            remaining = max(0.0, deadline - time.time())
            readable, _, _ = select.select([self.fd], [], [], min(0.05, remaining))
            if readable:
                try:
                    chunk = os.read(self.fd, 4096)
                except BlockingIOError:
                    chunk = b""
                if chunk:
                    out.extend(chunk)
                    deadline = time.time() + settle
        return bytes(out)

    def read_until_term(self, timeout=2.0):
        out = bytearray()
        deadline = time.time() + timeout
        while time.time() < deadline:
            remaining = max(0.0, deadline - time.time())
            readable, _, _ = select.select([self.fd], [], [], min(0.05, remaining))
            if readable:
                try:
                    chunk = os.read(self.fd, 4096)
                except BlockingIOError:
                    chunk = b""
                for b in chunk:
                    out.append(b)
                    if b == TERM:
                        return bytes(out)
        return bytes(out)


def list_ports():
    ports = sorted(glob.glob("/dev/cu.*"))
    preferred = [p for p in ports if "Bluetooth" not in p and "debug-console" not in p]
    return preferred + [p for p in ports if p not in preferred]


def send_at(port, command, line_ending="\r"):
    data = ("AT%s%s" % (command, line_ending)).encode("ascii")
    port.write(data)
    return port.read_available(1.2)


def brew_command(port, payload, label):
    port.write(brew_frame(payload))
    raw = port.read_until_term(2.0)
    return decode_brew(raw, label)


def req_memory_config():
    return bytes([COMMAND_MODE, 0x00])


def req_firmware():
    return bytes([COMMAND_MODE, 0x01])


def req_list_dir(dirname, entry):
    return bytes([COMMAND_MODE, 0x0A]) + struct.pack("<I", entry) + pascal_z(dirname)


def req_list_file(dirname, entry):
    return bytes([COMMAND_MODE, 0x0B]) + struct.pack("<I", entry) + pascal_z(dirname)


def req_read_file(filename):
    return bytes([COMMAND_MODE, 0x04, 0x00]) + pascal_z(filename)


def parse_firmware(payload):
    if len(payload) <= 3:
        return ""
    return printable(payload[3:]).strip(".\x00 ")


def parse_file_response(payload):
    if len(payload) < 13:
        return b""
    size = struct.unpack("<I", payload[7:11])[0]
    data_size = struct.unpack("<H", payload[11:13])[0]
    data = payload[13:13 + data_size]
    if size and len(data) > size:
        return data[:size]
    return data


def parse_dir_name(payload):
    if len(payload) < 8:
        return ""
    offset = 7
    if offset < len(payload) and payload[offset] == 0:
        offset += 1
    return read_pascal_z(payload, offset)


def parse_file_name(payload):
    if len(payload) < 24:
        return None
    entry = struct.unpack("<I", payload[3:7])[0]
    size = struct.unpack("<I", payload[15:19])[0]
    offset = 23
    if offset < len(payload) and payload[offset] == 0:
        offset += 1
    if offset < len(payload):
        dirname_len = payload[offset]
        offset += 1 + dirname_len
    if offset < len(payload) and payload[offset] == 0:
        offset += 1
    name = read_pascal_z(payload, offset)
    return entry, name, size


def run_at_probe(port):
    print("\nAT probe")
    for cmd in ("", "E0", "+GMM", "+GMI", "+CGMM", "$QCDMG", "$LGDMGO"):
        response = send_at(port, cmd)
        label = "AT%s" % cmd
        if response:
            print("  %-9s -> %s" % (label, printable(response)))
            print("             hex %s" % hex_bytes(response))
        else:
            print("  %-9s -> no response" % label)


def try_brew_mode(port, deep):
    print("\nBREW/diagnostic probe")

    def memory_check(label):
        payload = brew_command(port, req_memory_config(), label)
        print("  %s -> %s" % (label, hex_bytes(payload)))
        return True

    try:
        memory_check("memory config")
        return True
    except Exception as exc:
        print("  memory config -> %s" % exc)

    bauds = [port.baud, 115200, 38400, 19200, 230400] if deep else [port.baud]
    seen = []
    for baud in bauds:
        if baud in seen or baud not in BAUDS:
            continue
        seen.append(baud)
        try:
            port.set_baud(baud)
        except Exception as exc:
            print("  baud %s skipped: %s" % (baud, exc))
            continue

        for cmd in ("$QCDMG", "$LGDMGO"):
            response = send_at(port, cmd, "\r\n")
            if response:
                print("  AT%s at %s -> %s" % (cmd, baud, printable(response)))
            else:
                print("  AT%s at %s -> no response" % (cmd, baud))
            try:
                memory_check("memory config after AT%s at %s" % (cmd, baud))
                return True
            except Exception as exc:
                print("  after AT%s -> %s" % (cmd, exc))

    return False


def list_root(port, max_entries):
    print("\nRoot directory probe")
    for i in range(max_entries):
        try:
            payload = brew_command(port, req_list_dir("", i), "list directory %d" % i)
            name = parse_dir_name(payload)
            print("  dir[%d] %s" % (i, name or "(empty)"))
        except BrewError as exc:
            print("  dir[%d] %s" % (i, exc))
            if exc.code == 28:
                break
        except Exception as exc:
            print("  dir[%d] %s" % (i, exc))
            break

    for i in range(max_entries):
        try:
            payload = brew_command(port, req_list_file("", i), "list file %d" % i)
            parsed = parse_file_name(payload)
            if parsed:
                _, name, size = parsed
                print("  file[%d] %s (%d bytes)" % (i, name or "(empty)", size))
            else:
                print("  file[%d] raw %s" % (i, hex_bytes(payload)))
        except BrewError as exc:
            print("  file[%d] %s" % (i, exc))
            if exc.code == 28:
                break
        except Exception as exc:
            print("  file[%d] %s" % (i, exc))
            break


def read_version_files(port):
    print("\nSafe version-file probe")
    for filename in ("brew/version.txt", "ams/version.txt"):
        try:
            payload = brew_command(port, req_read_file(filename), "read %s" % filename)
            data = parse_file_response(payload)
            print("  %s -> %s" % (filename, printable(data)))
            print("             hex %s" % hex_bytes(data))
        except Exception as exc:
            print("  %s -> %s" % (filename, exc))


def run_for_port(path, baud, deep, max_entries):
    print("Rumor2MacProbe read-only connection test")
    print("Using port: %s at %s baud" % (path, baud))
    print("Keep the phone out of USB mass-storage mode so serial ports stay visible.")

    port = SerialPort(path, baud)
    try:
        port.open()
        port.read_available(0.2)
        run_at_probe(port)
        if try_brew_mode(port, deep):
            try:
                payload = brew_command(port, req_firmware(), "firmware")
                print("\nFirmware probe")
                print("  firmware -> %s" % parse_firmware(payload))
            except Exception as exc:
                print("\nFirmware probe")
                print("  firmware -> %s" % exc)
            list_root(port, max_entries)
            read_version_files(port)
        else:
            print("\nCould not enter or detect BREW/diagnostic mode on this Mac port.")
            print("If only a modem port appears, macOS may not expose the LG diagnostic interface.")
    finally:
        port.close()


def main(argv):
    parser = argparse.ArgumentParser(description="Read-only LG Rumor2 macOS USB probe")
    parser.add_argument("--list-ports", action="store_true", help="list /dev/cu.* ports and exit")
    parser.add_argument("--port", help="serial port, for example /dev/cu.usbmodem21101")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--deep", action="store_true", help="try multiple baud rates")
    parser.add_argument("--max-entries", type=int, default=5)
    args = parser.parse_args(argv)

    ports = list_ports()
    if args.list_ports:
        print("Available serial ports:")
        for port in ports:
            print("  %s" % port)
        return 0

    path = args.port
    if not path:
        candidates = [p for p in ports if "usbmodem" in p.lower()]
        path = candidates[0] if candidates else (ports[0] if ports else None)

    print("Available serial ports:")
    for port in ports:
        marker = " *" if port == path else "  "
        print("%s%s" % (marker, port))

    if not path:
        print("\nNo serial ports found.")
        return 2

    print("")
    run_for_port(path, args.baud, args.deep, args.max_entries)
    print("\nDone. This probe did not write files to the phone.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
