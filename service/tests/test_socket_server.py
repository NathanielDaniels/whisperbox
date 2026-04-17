import asyncio
import json
import os
import tempfile
import pytest
from socket_server import SocketServer


@pytest.fixture
def sock_path():
    # tmp_path on macOS can exceed the 104-char AF_UNIX limit; use /tmp directly
    with tempfile.TemporaryDirectory(dir="/tmp") as d:
        yield os.path.join(d, "test.sock")


@pytest.mark.asyncio
async def test_server_starts_and_accepts_connection(sock_path):
    """Server should bind to socket and accept a client."""
    server = SocketServer(sock_path)
    received = []
    server.on_command = lambda cmd: received.append(cmd)

    task = asyncio.create_task(server.start())
    await asyncio.sleep(0.1)

    reader, writer = await asyncio.open_unix_connection(sock_path)
    writer.write(json.dumps({"cmd": "start_recording"}).encode() + b"\n")
    await writer.drain()
    await asyncio.sleep(0.1)

    assert len(received) == 1
    assert received[0]["cmd"] == "start_recording"

    writer.close()
    await writer.wait_closed()
    server.stop()
    await task


@pytest.mark.asyncio
async def test_server_sends_event(sock_path):
    """Server should send newline-delimited JSON events to clients."""
    server = SocketServer(sock_path)
    task = asyncio.create_task(server.start())
    await asyncio.sleep(0.1)

    reader, writer = await asyncio.open_unix_connection(sock_path)
    await asyncio.sleep(0.05)  # let _handle_client run and store _writer
    await server.send_event({"event": "model_loaded"})
    await asyncio.sleep(0.1)

    line = await asyncio.wait_for(reader.readline(), timeout=1.0)
    msg = json.loads(line)
    assert msg["event"] == "model_loaded"

    writer.close()
    await writer.wait_closed()
    server.stop()
    await task


@pytest.mark.asyncio
async def test_server_removes_stale_socket(sock_path):
    """If a stale .sock file exists, server should remove it and bind."""
    # Create a stale socket file
    with open(sock_path, "w") as f:
        f.write("stale")

    server = SocketServer(sock_path)
    task = asyncio.create_task(server.start())
    await asyncio.sleep(0.1)

    # Should be able to connect
    reader, writer = await asyncio.open_unix_connection(sock_path)
    writer.close()
    await writer.wait_closed()
    server.stop()
    await task
