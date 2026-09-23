"""Bounded, descriptor-safe reader for the plugin's config.json.

Service.qml used to read config.json through Quickshell's FileView, which
follows symlinks and reads until EOF: a FIFO swapped in for the config file
would stall the shell's IO thread and an oversized file would exhaust memory.
This helper lstats first and only reads a regular file owned by the current
user, capped at a byte limit passed as argv[2], opened with O_NOFOLLOW.

Prints the file content base64-encoded on stdout (exit 0). Prints nothing and
exits 1 on any rejection: missing file, wrong type, wrong owner, over the cap.
Base64 keeps the transport newline-free so the QML side can use SplitParser.
"""

import base64
import os
import stat
import sys


def main() -> int:
    path, limit = sys.argv[1], int(sys.argv[2])
    try:
        st = os.lstat(path)
        if (
            not stat.S_ISREG(st.st_mode)
            or st.st_uid != os.geteuid()
            or st.st_size > limit
        ):
            return 1
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        try:
            chunks = []
            total = 0
            while True:
                chunk = os.read(fd, 65536)
                if not chunk:
                    break
                total += len(chunk)
                if total > limit:
                    return 1
                chunks.append(chunk)
            data = b"".join(chunks)
        finally:
            os.close(fd)
    except (OSError, ValueError):
        return 1
    sys.stdout.write(base64.b64encode(data).decode())
    return 0


if __name__ == "__main__":
    sys.exit(main())
