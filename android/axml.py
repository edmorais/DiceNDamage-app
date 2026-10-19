#!/usr/bin/env python3
"""axml.py -- read and rewrite a binary AndroidManifest.xml.

Only what this build needs: dump the tree so you can see what the stock LÖVE
shell declares, rewrite string-pool entries, and set typed integer attributes.

The string pool is rebuilt rather than patched in place, because the
replacement ids are not the same length as the originals. Order and count are
preserved: the resource-map chunk that follows is indexed by string position,
and every attribute in the tree refers to a string by index, so moving one
would silently rename something else.
"""
import struct
import sys

RES_STRING_POOL   = 0x0001
RES_XML           = 0x0003
RES_XML_START_NS  = 0x0100
RES_XML_END_NS    = 0x0101
RES_XML_START_ELE = 0x0102
RES_XML_END_ELE   = 0x0103
RES_XML_CDATA     = 0x0104
RES_XML_RES_MAP   = 0x0180

UTF8_FLAG = 1 << 8

TYPE_REFERENCE = 0x01
TYPE_STRING    = 0x03
TYPE_INT_DEC   = 0x10
TYPE_INT_HEX   = 0x11
TYPE_INT_BOOL  = 0x12


# ---------------------------------------------------------------- string pool

class StringPool:
    def __init__(self, blob):
        typ, hsize, csize = struct.unpack_from("<HHI", blob, 0)
        assert typ == RES_STRING_POOL, "not a string pool"
        (count, style_count, self.flags,
         strings_start, styles_start) = struct.unpack_from("<IIIII", blob, 8)

        self.utf8 = bool(self.flags & UTF8_FLAG)
        self.sorted = bool(self.flags & 1)
        offsets = struct.unpack_from("<%dI" % count, blob, hsize)
        self.strings = [self._read(blob, strings_start + o) for o in offsets]

        # Styles are carried through untouched; LÖVE's manifest has none, but
        # dropping them silently would be a trap for the next manifest.
        self.style_offsets = list(struct.unpack_from(
            "<%dI" % style_count, blob, hsize + 4 * count)) if style_count else []
        self.style_data = blob[styles_start:csize] if style_count else b""

    def _read(self, blob, pos):
        if self.utf8:
            n, pos = self._len8(blob, pos)     # characters
            n, pos = self._len8(blob, pos)     # bytes
            return blob[pos:pos + n].decode("utf-8", "replace")
        n, pos = self._len16(blob, pos)
        return blob[pos:pos + n * 2].decode("utf-16-le", "replace")

    @staticmethod
    def _len8(blob, pos):
        n = blob[pos]
        if n & 0x80:
            return ((n & 0x7F) << 8) | blob[pos + 1], pos + 2
        return n, pos + 1

    @staticmethod
    def _len16(blob, pos):
        n = struct.unpack_from("<H", blob, pos)[0]
        if n & 0x8000:
            hi = (n & 0x7FFF) << 16
            return hi | struct.unpack_from("<H", blob, pos + 2)[0], pos + 4
        return n, pos + 2

    def index(self, text):
        return self.strings.index(text)

    def replace(self, old, new):
        """Rewrite every entry equal to `old`. Returns how many changed."""
        hits = 0
        for i, s in enumerate(self.strings):
            if s == old:
                self.strings[i] = new
                hits += 1
        return hits

    def serialize(self):
        if self.sorted:
            # Rewriting a value can break the sort the flag promises, and
            # nothing here needs a sorted pool.
            self.flags &= ~1
        data, offsets = bytearray(), []
        for s in self.strings:
            offsets.append(len(data))
            if self.utf8:
                raw = s.encode("utf-8")
                data += self._put8(len(s)) + self._put8(len(raw)) + raw + b"\x00"
            else:
                raw = s.encode("utf-16-le")
                data += self._put16(len(s)) + raw + b"\x00\x00"
        while len(data) % 4:
            data += b"\x00"

        hsize = 28
        strings_start = hsize + 4 * len(offsets) + 4 * len(self.style_offsets)
        styles_start = (strings_start + len(data)) if self.style_offsets else 0
        csize = strings_start + len(data) + len(self.style_data)

        out = bytearray(struct.pack(
            "<HHIIIIII", RES_STRING_POOL, hsize, csize,
            len(offsets), len(self.style_offsets), self.flags,
            strings_start, styles_start))
        for o in offsets:
            out += struct.pack("<I", o)
        for o in self.style_offsets:
            out += struct.pack("<I", o)
        out += data + self.style_data
        return bytes(out)

    @staticmethod
    def _put8(n):
        if n > 0x7F:
            return bytes([0x80 | (n >> 8), n & 0xFF])
        return bytes([n])

    @staticmethod
    def _put16(n):
        if n > 0x7FFF:
            return struct.pack("<HH", 0x8000 | (n >> 16), n & 0xFFFF)
        return struct.pack("<H", n)


# ---------------------------------------------------------------- the file

class Axml:
    def __init__(self, blob):
        typ, hsize, csize = struct.unpack_from("<HHI", blob, 0)
        assert typ == RES_XML, "not a binary XML file"
        self.header = blob[:hsize]
        self.chunks = []
        pos = hsize
        while pos < csize:
            ctyp, chsize, ccsize = struct.unpack_from("<HHI", blob, pos)
            self.chunks.append([ctyp, bytearray(blob[pos:pos + ccsize])])
            pos += ccsize
        self.pool = StringPool(self.chunks[0][1])
        assert self.chunks[0][0] == RES_STRING_POOL, "pool is not the first chunk"

    # -------------------------------------------------------- element walk

    def elements(self):
        """Yields (chunk, name, [(ns, name, attr_offset)]) per start element."""
        for ctyp, buf in self.chunks:
            if ctyp != RES_XML_START_ELE:
                continue
            ns, name, astart, asize, acount = struct.unpack_from("<IIHHH", buf, 16)
            attrs = []
            for i in range(acount):
                off = 16 + astart + i * asize
                a_ns, a_name, a_raw = struct.unpack_from("<III", buf, off)
                attrs.append((a_ns, a_name, off))
            yield buf, self.pool.strings[name], attrs

    def get_attr(self, element, attr):
        """Every (dataType, data) this attribute has on this element."""
        out = []
        for buf, name, attrs in self.elements():
            if name != element:
                continue
            for _, a_name, off in attrs:
                if self.pool.strings[a_name] == attr:
                    _, _, dtype, data = struct.unpack_from("<HBBI", buf, off + 12)
                    out.append((dtype, data))
        return out

    def set_int_attr(self, element, attr, value):
        """Set a typed integer attribute, e.g. screenOrientation. Returns hits.

        The trailing Res_value is `uint16 size, uint8 res0, uint8 dataType,
        uint32 data` -- eight bytes, and an attribute record is only twenty.
        Packing it as anything wider silently writes over the next attribute,
        which is exactly what aapt refused to read the first time round.
        """
        hits = 0
        for buf, name, attrs in self.elements():
            if name != element:
                continue
            for _, a_name, off in attrs:
                if self.pool.strings[a_name] != attr:
                    continue
                struct.pack_into("<HBBI", buf, off + 12, 8, 0,
                                 TYPE_INT_DEC, value)
                struct.pack_into("<I", buf, off + 8, 0xFFFFFFFF)  # no raw string
                hits += 1
        return hits

    def remove_elements(self, element, attr, values):
        """Drop whole elements whose `attr` is one of `values`.

        Removes the start chunk and its matching end chunk, tracking depth so
        a container would take its children with it. Pool entries for the
        removed names are left alone: unused strings cost nothing, and
        deleting one would renumber every index after it.
        """
        keep, drop, depth, removed = [], False, 0, []
        for ctyp, buf in self.chunks:
            if not drop and ctyp == RES_XML_START_ELE:
                ns, name, astart, asize, acount = struct.unpack_from("<IIHHH", buf, 16)
                if self.pool.strings[name] == element:
                    for i in range(acount):
                        off = 16 + astart + i * asize
                        _, a_name, a_raw = struct.unpack_from("<III", buf, off)
                        if (self.pool.strings[a_name] == attr
                                and a_raw != 0xFFFFFFFF
                                and self.pool.strings[a_raw] in values):
                            drop, depth = True, 0
                            removed.append(self.pool.strings[a_raw])
                            break
            if drop:
                if ctyp == RES_XML_START_ELE:
                    depth += 1
                elif ctyp == RES_XML_END_ELE:
                    depth -= 1
                    if depth == 0:
                        drop = False
                continue
            keep.append([ctyp, buf])
        self.chunks = keep
        return removed

    def dump(self):
        out, depth = [], 0
        for ctyp, buf in self.chunks:
            if ctyp == RES_XML_START_ELE:
                ns, name, astart, asize, acount = struct.unpack_from("<IIHHH", buf, 16)
                line = ["  " * depth + "<" + self.pool.strings[name]]
                for i in range(acount):
                    off = 16 + astart + i * asize
                    a_ns, a_name, a_raw = struct.unpack_from("<III", buf, off)
                    _, _, dtype, data = struct.unpack_from("<HBBI", buf, off + 12)
                    if dtype == TYPE_STRING and a_raw != 0xFFFFFFFF:
                        val = repr(self.pool.strings[a_raw])
                    elif dtype == TYPE_INT_BOOL:
                        val = "true" if data else "false"
                    elif dtype == TYPE_REFERENCE:
                        val = "@0x%08x" % data
                    else:
                        val = "%d (0x%x, type 0x%02x)" % (data, data, dtype)
                    line.append("  " * (depth + 1) + "  %s=%s"
                                % (self.pool.strings[a_name], val))
                out.append("\n".join(line))
                depth += 1
            elif ctyp == RES_XML_END_ELE:
                depth -= 1
        return "\n".join(out)

    def serialize(self):
        self.chunks[0][1] = bytearray(self.pool.serialize())
        body = b"".join(bytes(buf) for _, buf in self.chunks)
        size = len(self.header) + len(body)
        head = bytearray(self.header)
        struct.pack_into("<I", head, 4, size)
        return bytes(head) + body


if __name__ == "__main__":
    print(Axml(open(sys.argv[1], "rb").read()).dump())
