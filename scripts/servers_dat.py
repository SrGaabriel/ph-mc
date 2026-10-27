"""Write an uncompressed NBT servers.dat listing the club server.

Usage: python3 scripts/servers_dat.py <out-path> <name> <address>
"""
import struct, sys


def string(s):
    b = s.encode()
    return struct.pack(">H", len(b)) + b


def tag(kind, name, payload):
    return bytes([kind]) + string(name) + payload


def main():
    out, name, address = sys.argv[1:4]
    server = tag(8, "name", string(name)) + tag(8, "ip", string(address)) + b"\x00"
    servers = bytes([10]) + struct.pack(">i", 1) + server  # TAG_List of 1 TAG_Compound
    root = tag(10, "", tag(9, "servers", servers) + b"\x00")
    with open(out, "wb") as f:
        f.write(root)


if __name__ == "__main__":
    main()
