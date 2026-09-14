"""Flatten an SVG path to M / L / C / Z commands. Arcs become cubic beziers."""
import re, math

NUM = re.compile(r'[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?')
CMDS = set("MmLlHhVvCcSsQqTtAaZz")

def _tokens(d):
    out, i = [], 0
    while i < len(d):
        ch = d[i]
        if ch in CMDS:
            out.append(ch); i += 1
        elif ch in " ,\n\r\t":
            i += 1
        else:
            m = NUM.match(d, i)
            if not m or not m.group():
                i += 1; continue
            out.append(float(m.group())); i = m.end()
    return out

def _arc(x0, y0, rx, ry, phi, large, sweep, x, y):
    """Endpoint arc -> list of cubic bezier segments (x1,y1,x2,y2,x,y)."""
    if rx == 0 or ry == 0 or (x0 == x and y0 == y):
        return [("L", x, y)]
    rx, ry = abs(rx), abs(ry)
    p = math.radians(phi)
    cosp, sinp = math.cos(p), math.sin(p)
    dx2, dy2 = (x0 - x) / 2.0, (y0 - y) / 2.0
    x1 =  cosp*dx2 + sinp*dy2
    y1 = -sinp*dx2 + cosp*dy2
    lam = x1*x1/(rx*rx) + y1*y1/(ry*ry)
    if lam > 1:
        s = math.sqrt(lam); rx *= s; ry *= s
    num = rx*rx*ry*ry - rx*rx*y1*y1 - ry*ry*x1*x1
    den = rx*rx*y1*y1 + ry*ry*x1*x1
    co = math.sqrt(max(0.0, num/den)) * (-1 if large == sweep else 1)
    cx1 =  co * rx * y1 / ry
    cy1 = -co * ry * x1 / rx
    cx = cosp*cx1 - sinp*cy1 + (x0 + x)/2.0
    cy = sinp*cx1 + cosp*cy1 + (y0 + y)/2.0

    def ang(ux, uy, vx, vy):
        n = math.hypot(ux, uy) * math.hypot(vx, vy)
        if n == 0: return 0.0
        c = max(-1.0, min(1.0, (ux*vx + uy*vy) / n))
        a = math.acos(c)
        return -a if ux*vy - uy*vx < 0 else a

    th1 = ang(1, 0, (x1-cx1)/rx, (y1-cy1)/ry)
    dth = ang((x1-cx1)/rx, (y1-cy1)/ry, (-x1-cx1)/rx, (-y1-cy1)/ry)
    if not sweep and dth > 0: dth -= 2*math.pi
    elif sweep and dth < 0:   dth += 2*math.pi

    segs, n = [], max(1, int(math.ceil(abs(dth) / (math.pi/2))))
    delta = dth / n
    t = 4/3 * math.tan(delta/4)
    th = th1
    px, py = x0, y0
    for _ in range(n):
        th2 = th + delta
        c1, s1 = math.cos(th),  math.sin(th)
        c2, s2 = math.cos(th2), math.sin(th2)
        def pt(c, s):
            return (cx + rx*c*cosp - ry*s*sinp, cy + rx*c*sinp + ry*s*cosp)
        ex, ey = pt(c2, s2)
        d1x, d1y = (-rx*s1*cosp - ry*c1*sinp), (-rx*s1*sinp + ry*c1*cosp)
        d2x, d2y = (-rx*s2*cosp - ry*c2*sinp), (-rx*s2*sinp + ry*c2*cosp)
        segs.append(("C", px + t*d1x, py + t*d1y, ex - t*d2x, ey - t*d2y, ex, ey))
        px, py, th = ex, ey, th2
    return segs

class _Reader:
    """Streaming reader. Arc flags are single characters, not numbers, because
    SVG allows `a4 4 0 014-4` where `01` is two flags glued to the next value."""
    def __init__(self, d): self.d, self.i = d, 0
    def _skip(self):
        while self.i < len(self.d) and self.d[self.i] in " ,\n\r\t": self.i += 1
    def more(self):
        self._skip(); return self.i < len(self.d)
    def peek_cmd(self):
        self._skip()
        return self.d[self.i] if self.i < len(self.d) and self.d[self.i] in CMDS else None
    def cmd(self):
        c = self.peek_cmd(); self.i += 1; return c
    def num(self):
        self._skip()
        m = NUM.match(self.d, self.i)
        if not m: raise ValueError(f"no number at {self.i} in {self.d[:40]}")
        self.i = m.end(); return float(m.group())
    def flag(self):
        self._skip()
        ch = self.d[self.i]; self.i += 1
        return 1 if ch == "1" else 0

def flatten(d):
    r = _Reader(d)
    out = []
    cmd = None
    x = y = sx = sy = 0.0
    lcx = lcy = None            # last cubic control point, for S/s
    while r.more():
        if r.peek_cmd():
            cmd = r.cmd()
            if cmd in "Zz":
                out.append(("Z",)); x, y = sx, sy; lcx = lcy = None
                continue
        rel = cmd.islower()
        c = cmd.upper()
        def n(k): return [r.num() for _ in range(k)]
        if c == "M":
            a, b = n(2)
            x, y = (x+a, y+b) if rel else (a, b)
            out.append(("M", x, y)); sx, sy = x, y
            cmd = "l" if rel else "L"; lcx = lcy = None
        elif c == "L":
            a, b = n(2); x, y = (x+a, y+b) if rel else (a, b)
            out.append(("L", x, y)); lcx = lcy = None
        elif c == "H":
            a, = n(1); x = x+a if rel else a
            out.append(("L", x, y)); lcx = lcy = None
        elif c == "V":
            a, = n(1); y = y+a if rel else a
            out.append(("L", x, y)); lcx = lcy = None
        elif c == "C":
            a,b,cc,dd,e,f = n(6)
            if rel: a,b,cc,dd,e,f = x+a,y+b,x+cc,y+dd,x+e,y+f
            out.append(("C", a,b,cc,dd,e,f)); lcx, lcy = cc, dd; x, y = e, f
        elif c == "S":
            cc,dd,e,f = n(4)
            if rel: cc,dd,e,f = x+cc,y+dd,x+e,y+f
            a, b = (2*x-lcx, 2*y-lcy) if lcx is not None else (x, y)
            out.append(("C", a,b,cc,dd,e,f)); lcx, lcy = cc, dd; x, y = e, f
        elif c == "A":
            rx, ry, rot = n(3)
            la, sw = r.flag(), r.flag()
            e, f = n(2)
            if rel: e, f = x+e, y+f
            out.extend(_arc(x, y, rx, ry, rot, la, sw, e, f))
            x, y = e, f; lcx = lcy = None
        else:
            r.num()                                   # Q/T unused by these paths
    return out
