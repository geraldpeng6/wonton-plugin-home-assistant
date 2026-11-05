"""Refuse port collisions before HA can fall back to another HTTP configuration."""

import errno
import os
import socket
import sys

try:
    with socket.socket() as listener:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(("127.0.0.1", 8123))
except OSError as error:
    if error.errno == errno.EADDRINUSE:
        sys.exit("Home Assistant 启动失败：宿主 127.0.0.1:8123 已被占用，请先停用占用它的服务。")
    raise

os.execv("/init", ["/init"])
