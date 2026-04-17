"""Unix domain socket server for IPC with the Swift menu bar app.

Protocol: newline-delimited JSON. Each message is a single JSON object
terminated by \n. The server accepts one client at a time.
"""

import asyncio
import json
import os
from typing import Callable


class SocketServer:
    def __init__(self, sock_path: str):
        self.sock_path = sock_path
        self.on_command: Callable[[dict], None] | None = None
        self.on_client_connected: Callable[[], None] | None = None
        self._server: asyncio.AbstractServer | None = None
        self._writer: asyncio.StreamWriter | None = None
        self._running = False

    async def start(self):
        """Start listening on the Unix domain socket."""
        # Remove stale socket
        if os.path.exists(self.sock_path):
            os.unlink(self.sock_path)

        os.makedirs(os.path.dirname(self.sock_path), exist_ok=True)
        self._running = True
        self._server = await asyncio.start_unix_server(
            self._handle_client, path=self.sock_path
        )
        async with self._server:
            try:
                await self._server.serve_forever()
            except asyncio.CancelledError:
                pass

    def stop(self):
        """Stop the server."""
        self._running = False
        if self._server:
            self._server.close()
        if self._writer:
            self._writer.close()

    async def send_event(self, event: dict):
        """Send a JSON event to the connected client."""
        if self._writer and not self._writer.is_closing():
            line = json.dumps(event, ensure_ascii=False) + "\n"
            self._writer.write(line.encode("utf-8"))
            await self._writer.drain()

    async def _handle_client(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ):
        """Handle a single client connection."""
        self._writer = writer
        if self.on_client_connected:
            result = self.on_client_connected()
            if asyncio.iscoroutine(result):
                await result
        try:
            while self._running:
                line = await reader.readline()
                if not line:
                    break
                try:
                    msg = json.loads(line.decode("utf-8").strip())
                    if self.on_command:
                        result = self.on_command(msg)
                        if asyncio.iscoroutine(result):
                            await result
                except json.JSONDecodeError:
                    continue
        except (ConnectionResetError, BrokenPipeError):
            pass
        finally:
            self._writer = None
            writer.close()
