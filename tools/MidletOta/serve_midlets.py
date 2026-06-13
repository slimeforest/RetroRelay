#!/usr/bin/env python3
"""Serve JAD/JAR files with Java ME OTA MIME types."""

import argparse
import functools
import http.server
import os
import sys


class MidletHandler(http.server.SimpleHTTPRequestHandler):
    def guess_type(self, path):
        lower = path.lower()
        if lower.endswith(".jad"):
            return "text/vnd.sun.j2me.app-descriptor"
        if lower.endswith(".jar"):
            return "application/java-archive"
        return http.server.SimpleHTTPRequestHandler.guess_type(self, path)


def main(argv):
    parser = argparse.ArgumentParser(description="Serve Java ME MIDlet files")
    parser.add_argument("directory", help="directory containing JAD/JAR files")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8000)
    args = parser.parse_args(argv)

    directory = os.path.abspath(args.directory)
    if not os.path.isdir(directory):
        parser.error("directory not found: %s" % directory)

    handler = functools.partial(MidletHandler, directory=directory)
    server = http.server.ThreadingHTTPServer((args.host, args.port), handler)
    print("Serving %s" % directory)
    print("URL root: http://%s:%d/" % (args.host, args.port))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("")
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
