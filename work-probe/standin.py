"""Local stand-ins for what is outside the engine, all on 127.0.0.1 ports run.sh picked:

  origin  - an HTTPS server for one.google.com (a certificate from a probe CA, which the tunnel half
            is given as its upstream anchor). GET /ai?... answers gzip-encoded text/html bodies whose
            decoded size the "probe" query parameter picks (small, large, xl), each holding the
            Shadowrocket module's old product id near the start, in the middle and near the end;
            "many" is the large page holding it 3,000 times, so a rewrite grows it by 72,000 bytes,
            past the fix's 64 KiB allowance.
  reinject - what mihomo's listener does on the re-inject port for the engine: it answers the
            engine's SOCKS5 reachability check and HTTP CONNECT with the re-inject credentials the
            App published, and it connects every CONNECT to the local origin, never anywhere else.

Usage: standin.py --origin-port N --reinject-port N --cert PEM --key PEM --summary published.json
"""
import argparse
import asyncio
import base64
import gzip
import json
import random
import ssl
import sys
import time
import urllib.parse

OLD_ID = b"g1.ios.20tb.m.v2"
PAGES = {"small": (200_000, 3), "large": (1_500_000, 3), "xl": (10_700_000, 3), "many": (1_500_000, 3_000)}


def log(*parts):
    print(time.strftime("%H:%M:%S"), *parts, flush=True)


def page(size, count):
    """A text/html page of exactly `size` bytes holding OLD_ID `count` times: at the start, at the end,
    and evenly between."""
    marker = b'<script>var plan="' + OLD_ID + b'";</script>\n'
    head = b"<!doctype html><html><head><meta charset=utf-8><title>Google One</title>\n" + marker
    tail = marker + b"</body></html>\n"
    # pseudo-random words, so the page compresses about as much as real HTML (3-4x), not 30x
    words = [w.encode() for w in ("google one ai premium storage plan gemini family share photos drive gmail "
             "backup device member offer trial month year price region account settings manage cancel "
             "upgrade terms privacy help support download app web ios android").split()]
    rng = random.Random(size)
    room = size - len(head) - len(tail) - (count - 2) * len(marker)
    lines, n, total = [], 0, 0
    while total < room:
        text = b" ".join(rng.choice(words) for _ in range(12))
        lines.append(b'<p data-k="%08x">%s %d</p>\n' % (rng.getrandbits(32), text, n))
        total += len(lines[-1])
        n += 1
    body = b"".join(lines)[:room]
    pieces, step = [], len(body) // (count - 1)
    for i in range(count - 1):
        pieces.append(body[i * step:(i + 1) * step] if i < count - 2 else body[i * step:])
    out = head + marker.join(pieces) + tail
    assert len(out) == size and out.count(OLD_ID) == count, (len(out), out.count(OLD_ID))
    return out


async def read_head(reader):
    data = await reader.readuntil(b"\r\n\r\n")
    lines = data.decode("latin-1").split("\r\n")
    request = lines[0]
    headers = {}
    for line in lines[1:]:
        if ":" in line:
            k, v = line.split(":", 1)
            headers[k.strip().lower()] = v.strip()
    return request, headers


class Origin:
    def __init__(self):
        self.bodies = {}
        for name, (size, count) in PAGES.items():
            raw = page(size, count)
            self.bodies[name] = (raw, gzip.compress(raw, 6))
            log(f"origin: page '{name}' {len(raw)} bytes decoded, {len(self.bodies[name][1])} gzip, "
                f"{raw.count(OLD_ID)}x {OLD_ID.decode()}")

    async def serve(self, reader, writer):
        peer = writer.get_extra_info("peername")
        alpn = writer.get_extra_info("ssl_object").selected_alpn_protocol()
        try:
            while True:
                try:
                    request, headers = await read_head(reader)
                except (asyncio.IncompleteReadError, ConnectionError):
                    return
                method, target, _ = request.split(" ", 2)
                url = urllib.parse.urlsplit(target)
                query = urllib.parse.parse_qs(url.query)
                which = query.get("probe", ["large"])[0]
                log(f"origin: {peer} {request!r} host={headers.get('host')} accept-encoding={headers.get('accept-encoding')} alpn={alpn}")
                if method != "GET" or url.path != "/ai" or which not in self.bodies:
                    writer.write(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n")
                    await writer.drain()
                    continue
                raw, packed = self.bodies[which]
                writer.write((
                    "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Encoding: gzip\r\n"
                    f"Content-Length: {len(packed)}\r\nCache-Control: no-store\r\n\r\n").encode())
                writer.write(packed)
                await writer.drain()
                log(f"origin: answered '{which}': {len(packed)} gzip bytes ({len(raw)} decoded)")
                if headers.get("connection", "").lower() == "close":
                    return
        finally:
            writer.close()


class Reinject:
    def __init__(self, origin_port, user, password):
        self.origin_port = origin_port
        self.user, self.password = user, password
        self.expected = "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode()

    async def serve(self, reader, writer):
        peer = writer.get_extra_info("peername")
        try:
            first = await reader.readexactly(1)
        except (asyncio.IncompleteReadError, ConnectionError):
            writer.close()
            return
        if first == b"\x05":
            await self.socks_check(reader, writer, peer)
            return
        rest, headers = await read_head_after(first, reader)
        method, target = rest.split(" ")[:2]
        if headers.get("proxy-authorization") != self.expected:
            log(f"reinject: {peer} {rest!r} refused 407 (Proxy-Authorization is not the published re-inject credentials)")
            writer.write(b"HTTP/1.1 407 Proxy Authentication Required\r\nProxy-Authenticate: Basic realm=\"mihomo\"\r\nContent-Length: 0\r\n\r\n")
            await writer.drain()
            writer.close()
            return
        host = target.rsplit(":", 1)[0]
        if method != "CONNECT" or host != "one.google.com":
            log(f"reinject: {peer} {rest!r} refused 403 (this stand-in only reaches the local one.google.com origin)")
            writer.write(b"HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n")
            await writer.drain()
            writer.close()
            return
        up_reader, up_writer = await asyncio.open_connection("127.0.0.1", self.origin_port)
        log(f"reinject: {peer} {rest!r} signed in -> 127.0.0.1:{self.origin_port} (local origin)")
        writer.write(b"HTTP/1.1 200 Connection established\r\n\r\n")
        await writer.drain()
        await asyncio.gather(pipe(reader, up_writer), pipe(up_reader, writer))

    async def socks_check(self, reader, writer, peer):
        # RFC 1928 greeting, then RFC 1929 sign-in when the engine offers it
        count = (await reader.readexactly(1))[0]
        methods = await reader.readexactly(count)
        if 2 in methods:
            writer.write(b"\x05\x02")
            await writer.drain()
            version, ulen = await reader.readexactly(2)
            user = (await reader.readexactly(ulen)).decode()
            plen = (await reader.readexactly(1))[0]
            password = (await reader.readexactly(plen)).decode()
            ok = (user, password) == (self.user, self.password)
            writer.write(b"\x01\x00" if ok else b"\x01\x01")
            log(f"reinject: {peer} SOCKS5 check, sign-in {'accepted' if ok else 'refused'}")
        else:
            writer.write(b"\x05\xff")
            log(f"reinject: {peer} SOCKS5 check without sign-in refused")
        await writer.drain()
        writer.close()


async def read_head_after(first, reader):
    data = first + await reader.readuntil(b"\r\n\r\n")
    lines = data.decode("latin-1").split("\r\n")
    headers = {}
    for line in lines[1:]:
        if ":" in line:
            k, v = line.split(":", 1)
            headers[k.strip().lower()] = v.strip()
    return lines[0], headers


async def pipe(reader, writer):
    try:
        while True:
            chunk = await reader.read(65536)
            if not chunk:
                break
            writer.write(chunk)
            await writer.drain()
    except (ConnectionError, asyncio.IncompleteReadError):
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def main():
    p = argparse.ArgumentParser()
    p.add_argument("--origin-port", type=int, required=True)
    p.add_argument("--reinject-port", type=int, required=True)
    p.add_argument("--cert", required=True)
    p.add_argument("--key", required=True)
    p.add_argument("--summary", required=True)
    a = p.parse_args()
    summary = json.load(open(a.summary))
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(a.cert, a.key)
    context.set_alpn_protocols(["http/1.1"])
    origin = Origin()
    reinject = Reinject(a.origin_port, summary["reinjectUser"], summary["reinjectPassword"])
    s1 = await asyncio.start_server(origin.serve, "127.0.0.1", a.origin_port, ssl=context)
    s2 = await asyncio.start_server(reinject.serve, "127.0.0.1", a.reinject_port)
    log(f"standin: origin https://127.0.0.1:{a.origin_port} (one.google.com), re-inject 127.0.0.1:{a.reinject_port}")
    async with s1, s2:
        await asyncio.gather(s1.serve_forever(), s2.serve_forever())


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        sys.exit(0)
