// Lens — layer overlay for the Dygma Defy
// Copyright (C) 2026 Gary Berger
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any later
// version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
// PARTICULAR PURPOSE.  See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with
// this program.  If not, see <https://www.gnu.org/licenses/>.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import Cocoa
import Darwin
import IOKit.hid

// ── Keymap data ───────────────────────────────────────────────────────────────
struct Layer { var labels: [String] = []; var shift: [String] = []; var hid: [Int] = [] }

/// One key as Bazecor places it: matrix index plus a rect in Defy's 1270x560 space.
struct KeyBox { var index: Int; var x, y, w, h: CGFloat; var led: Int
                var rot: CGFloat; var cx, cy: CGFloat }

struct Keymap {
    var layers: [Layer] = []
    var boxes: [KeyBox] = []
    var bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
    var palette: [NSColor] = []
    var colormap: [[Int]] = []
    var paths: [Int: NSBezierPath] = [:]
    var layerNames: [String] = []

    /// The LED colour this key shows on this layer.
    func led(_ box: KeyBox, layer: Int) -> NSColor? {
        guard colormap.indices.contains(layer),
              colormap[layer].indices.contains(box.led) else { return nil }
        let pi = colormap[layer][box.led]
        return palette.indices.contains(pi) ? palette[pi] : nil
    }

    static func load(_ path: String) -> Keymap {
        var k = Keymap()
        guard let d = FileManager.default.contents(atPath: path),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return k }
        for e in (j["layers"] as? [[String: Any]] ?? []) {
            let labels = e["labels"] as? [String] ?? []
            // An older layers.json has no "shift" array. Fall back to the plain
            // legends so the overlay still draws every key.
            k.layers.append(Layer(labels: labels,
                                  shift:  e["shift"]  as? [String] ?? labels,
                                  hid:    e["hid"]    as? [Int]    ?? []))
        }
        for g in (j["geom"] as? [[Double]] ?? []) where g.count >= 9 {
            k.boxes.append(KeyBox(index: Int(g[0]), x: g[1], y: g[2],
                                  w: g[3], h: g[4], led: Int(g[5]),
                                  rot: g[6], cx: g[7], cy: g[8]))
        }
        for c in (j["palette"] as? [[Double]] ?? []) where c.count == 3 {
            k.palette.append(NSColor(calibratedRed: c[0]/255, green: c[1]/255,
                                     blue: c[2]/255, alpha: 1))
        }
        k.colormap = j["colormap"] as? [[Int]] ?? []
        k.layerNames = j["layerNames"] as? [String] ?? []
        for (key, segs) in (j["paths"] as? [String: [[Any]]] ?? [:]) {
            guard let idx = Int(key) else { continue }
            let bp = NSBezierPath()
            for seg in segs {
                guard let op = seg.first as? String else { continue }
                let v = seg.dropFirst().compactMap { ($0 as? NSNumber)?.doubleValue }
                switch op {
                case "M" where v.count >= 2: bp.move(to: NSPoint(x: v[0], y: v[1]))
                case "L" where v.count >= 2: bp.line(to: NSPoint(x: v[0], y: v[1]))
                case "C" where v.count >= 6:
                    bp.curve(to: NSPoint(x: v[4], y: v[5]),
                             controlPoint1: NSPoint(x: v[0], y: v[1]),
                             controlPoint2: NSPoint(x: v[2], y: v[3]))
                case "Z": bp.close()
                default: break
                }
            }
            k.paths[idx] = bp
        }
        if let b = j["bounds"] as? [Double], b.count == 4 {
            k.bounds = CGRect(x: b[0], y: b[1], width: b[2] - b[0], height: b[3] - b[1])
        }
        return k
    }
}

// ── macOS virtual keycode → USB HID usage ─────────────────────────────────────
enum HID {
    static let table: [Int] = {
        var t = [Int](repeating: 0, count: 128)
        let pairs: [(Int, Int)] = [
            (0,4),(11,5),(8,6),(2,7),(14,8),(3,9),(5,10),(4,11),(34,12),(38,13),(40,14),
            (37,15),(46,16),(45,17),(31,18),(35,19),(12,20),(15,21),(1,22),(17,23),(32,24),
            (9,25),(13,26),(7,27),(16,28),(6,29),
            (18,30),(19,31),(20,32),(21,33),(23,34),(22,35),(26,36),(28,37),(25,38),(29,39),
            (36,40),(53,41),(51,42),(48,43),(49,44),(27,45),(24,46),(33,47),(30,48),(42,49),
            (41,51),(39,52),(50,53),(43,54),(47,55),(44,56),(57,57),
            (122,58),(120,59),(99,60),(118,61),(96,62),(97,63),(98,64),(100,65),
            (101,66),(109,67),(103,68),(111,69),
            (114,73),(115,74),(116,75),(117,76),(119,77),(121,78),
            (124,79),(123,80),(125,81),(126,82),
            (71,83),(75,84),(67,85),(78,86),(69,87),(76,88),
            (83,89),(84,90),(85,91),(86,92),(87,93),(88,94),(89,95),(91,96),(92,97),
            (82,98),(65,99),(81,103),(105,104),(107,105),(113,106),
            (106,107),(64,108),(79,109),(80,110),(90,111),
            (59,224),(56,225),(58,226),(55,227),(62,228),(60,229),(61,230),(54,231),
        ]
        for (vk, usage) in pairs where vk < 128 { t[vk] = usage }
        return t
    }()

    /// Modifier virtual keycodes and the flag each one raises.
    static let modifierFlag: [Int: CGEventFlags] = [
        59: .maskControl,   62: .maskControl,
        56: .maskShift,     60: .maskShift,
        58: .maskAlternate, 61: .maskAlternate,
        55: .maskCommand,   54: .maskCommand,
        57: .maskAlphaShift,
    ]
}

// ── Keyboard tap ──────────────────────────────────────────────────────────────
final class KeyTap {
    private var tap: CFMachPort?
    private(set) var down = Set<Int>()
    private(set) var flags: CGEventFlags = []
    var onChange: (() -> Void)?
    var onToggle: (() -> Void)?
    var toggleUsage: Int? = nil
    var debugKeys = false

    var isRunning: Bool { tap != nil }

    func start() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue)
                 | (1 << CGEventType.keyUp.rawValue)
                 | (1 << CGEventType.flagsChanged.rawValue)
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap,
                options: .listenOnly,                 // never swallows a keystroke
                eventsOfInterest: CGEventMask(mask),
                callback: { _, type, event, ctx in
                    guard let ctx else { return Unmanaged.passUnretained(event) }
                    Unmanaged<KeyTap>.fromOpaque(ctx).takeUnretainedValue().handle(type, event)
                    return Unmanaged.passUnretained(event)
                },
                userInfo: me) else { return false }
        tap = t
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return
        }
        let vk = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard vk >= 0, vk < 128 else { return }
        let usage = HID.table[vk]
        if debugKeys, type == .keyDown {
            print("key: vk=\(vk) usage=\(usage) toggleUsage=\(toggleUsage.map(String.init) ?? "nil")")
        }
        guard usage != 0 else { return }
        if let t = toggleUsage, usage == t {          // the summon key, never a normal press
            if type == .keyDown { DispatchQueue.main.async { self.onToggle?() } }
            return
        }
        let before = down
        let beforeFlags = flags
        flags = event.flags
        switch type {
        case .keyDown: down.insert(usage)
        case .keyUp:   down.remove(usage)
        case .flagsChanged:
            if let f = HID.modifierFlag[vk] {
                if event.flags.contains(f) { down.insert(usage) } else { down.remove(usage) }
            }
        default: return
        }
        if down != before || flags != beforeFlags {
            DispatchQueue.main.async { self.onChange?() }
        }
    }
}

extension CGEventFlags {
    /// The held modifiers, named, so a drag combination can be given on the command line.
    var grabBits: Set<String> {
        var s = Set<String>()
        if contains(.maskControl)   { s.insert("control") }
        if contains(.maskAlternate) { s.insert("alt") }
        if contains(.maskShift)     { s.insert("shift") }
        if contains(.maskCommand)   { s.insert("cmd") }
        return s
    }
}

// ── Serial link to the Neuron ─────────────────────────────────────────────────
final class Focus {
    private var fd: Int32 = -1
    let port: String
    init(port: String) { self.port = port }
    var isOpen: Bool { fd >= 0 }

    @discardableResult func open() -> Bool {
        if fd >= 0 { return true }
        let f = Darwin.open(port, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard f >= 0 else { return false }
        var t = termios()
        tcgetattr(f, &t)
        cfmakeraw(&t)
        cfsetspeed(&t, speed_t(B115200))       // never 1200: that is the DFU trigger
        t.c_cflag |= tcflag_t(CS8 | CREAD | CLOCAL)
        t.c_cflag &= ~tcflag_t(HUPCL)      // do not drop DTR on close; that resets the Neuron
        tcsetattr(f, TCSANOW, &t)
        tcflush(f, TCIOFLUSH)
        fd = f
        return true
    }

    func close() { if fd >= 0 { Darwin.close(fd); fd = -1 } }

    func ask(_ cmd: String, timeout: Double = 0.08) -> String? {
        guard fd >= 0 else { return nil }
        let line = cmd + "\n"
        guard line.withCString({ Darwin.write(fd, $0, strlen($0)) }) > 0 else { close(); return nil }
        var out = "", buf = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let n = Darwin.read(fd, &buf, buf.count)
            if n > 0 {
                out += String(decoding: buf[0..<n], as: UTF8.self)
                if out.contains(".\r\n") || out.contains(".\n") { break }
            } else if n < 0 && errno != EAGAIN {
                close(); return nil
            } else { usleep(700) }
        }
        return out.isEmpty ? nil : out
    }

    /// Charge of each half, as a percentage.
    func battery() -> (Int, Int)? {
        func pct(_ cmd: String) -> Int? {
            guard let r = ask(cmd) else { return nil }
            return r.split(whereSeparator: { " \r\n\t.".contains($0) })
                    .compactMap { Int($0) }.first
        }
        guard let l = pct("wireless.battery.left.level"),
              let r = pct("wireless.battery.right.level") else { return nil }
        return (l, r)
    }

    func activeLayer() -> Int? {
        guard let r = ask("layer.state") else { return nil }
        let nums = r.split(whereSeparator: { " \r\n\t".contains($0) })
                    .map(String.init).compactMap { Int($0) }
        guard !nums.isEmpty else { return nil }
        if nums.count >= 8 && nums.allSatisfy({ $0 == 0 || $0 == 1 }) {
            return nums.lastIndex(of: 1) ?? 0
        }
        return nums.last
    }
}

// ── Typing drill ──────────────────────────────────────────────────────────────
/// One target: a key on a layer, and what we have learned about reaching it.
struct Score: Codable { var n = 0; var errs = 0; var avgMs = 0.0 }

final class Drill {
    var active = false
    var target: (layer: Int, pos: Int)? = nil
    var started = Date()
    var hits = 0, misses = 0
    var lastResult: String = ""
    var includeBase = false
    var countMisses = true
    private(set) var scores: [String: Score] = [:]
    private let path = NSHomeDirectory() + "/Dygma/lens/drill.json"

    init() {
        if let d = FileManager.default.contents(atPath: path),
           let j = try? JSONDecoder().decode([String: Score].self, from: d) { scores = j }
    }
    private func save() {
        if let d = try? JSONEncoder().encode(scores) {
            try? d.write(to: URL(fileURLWithPath: path))
        }
    }
    private func key(_ l: Int, _ p: Int) -> String { "\(l):\(p)" }

    /// Every key worth drilling: it sends something, and above the base layer it
    /// must differ from the base, since repeating it teaches nothing new.
    func candidates(_ km: Keymap, skip: Int) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        for l in (includeBase ? 0 : 1)..<km.layers.count {
            for b in km.boxes {
                let h = km.layers[l].hid[safe: b.index] ?? 0
                guard h != 0, h != skip else { continue }
                if l > 0, (km.layers[0].hid[safe: b.index] ?? -1) == h { continue }
                out.append((l, b.index))
            }
        }
        return out
    }

    /// Prefer what you are slow at, what you get wrong, and what you have not seen.
    func pick(_ km: Keymap, skip: Int) {
        let c = candidates(km, skip: skip)
        guard !c.isEmpty else { target = nil; return }
        var best: (Double, (Int, Int))? = nil
        for _ in 0..<12 {
            let cand = c.randomElement()!
            let sc = scores[key(cand.0, cand.1)]
            let weight = (sc.map { $0.avgMs + Double($0.errs) * 900 } ?? 4000)
                       * Double.random(in: 0.75...1.25)
            if best == nil || weight > best!.0 { best = (weight, cand) }
        }
        target = best.map { $0.1 }
        started = Date()
    }

    func record(correct: Bool) {
        guard let t = target else { return }
        let k = key(t.layer, t.pos)
        var sc = scores[k] ?? Score()
        if correct {
            let ms = Date().timeIntervalSince(started) * 1000
            sc.avgMs = sc.n == 0 ? ms : (sc.avgMs * Double(sc.n) + ms) / Double(sc.n + 1)
            sc.n += 1; hits += 1
            lastResult = String(format: "%.1fs", ms / 1000)
        } else {
            guard countMisses else { return }
            sc.errs += 1; misses += 1
            lastResult = "miss"
        }
        scores[k] = sc
        save()
    }
}

// ── The HUD ───────────────────────────────────────────────────────────────────
final class LensView: NSView {
    var keymap = Keymap()
    var layerIndex = 0
    var status: String? = nil
    var hint: String? = nil
    var pressed = Set<Int>()
    var shifted = false      // Shift is held: draw the shifted legends
    var grabbable = false
    var showColors = true
    var rotateLabels = true
    var glass = false
    var battery: (Int, Int)? = nil
    var pill = false          // text-only strip
    var lastKey = ""
    var drill: Drill? = nil
    var onMoved: (() -> Void)?
    private var grip: NSPoint?

    var targetWidth: CGFloat = 760
    var pad: CGFloat { targetWidth < 520 ? 9 : 14 }
    var header: CGFloat { targetWidth < 520 ? 19 : 26 }
    var footer: CGFloat { targetWidth < 520 ? 11 : 14 }

    private var scale: CGFloat { (targetWidth - pad*2) / max(keymap.bounds.width, 1) }

    var idealSize: NSSize {
        pill ? NSSize(width: 276, height: 48)
             : NSSize(width: targetWidth,
                      height: pad*2 + header + footer + keymap.bounds.height * scale)
    }

    /// The colour most of this layer's keys are lit with — the layer's "mood".
    private func dominantColour() -> NSColor {
        var tally: [Int: Int] = [:]
        for b in keymap.boxes where keymap.colormap.indices.contains(layerIndex) {
            guard keymap.colormap[layerIndex].indices.contains(b.led) else { continue }
            tally[keymap.colormap[layerIndex][b.led], default: 0] += 1
        }
        guard let pi = tally.max(by: { $0.value < $1.value })?.key,
              keymap.palette.indices.contains(pi) else { return .systemBlue }
        return keymap.palette[pi]
    }

    private func drawMini() {
        let name = keymap.layerNames[safe: layerIndex] ?? "Layer \(layerIndex + 1)"
        let dot = NSBezierPath(ovalIn: NSRect(x: 16, y: bounds.midY - 6, width: 12, height: 12))
        dominantColour().setFill(); dot.fill()

        draw(name, in: NSRect(x: 36, y: bounds.midY - 11, width: 90, height: 22),
             size: 16, weight: .semibold, color: .white, align: .left)

        if !lastKey.isEmpty {
            draw(lastKey, in: NSRect(x: 126, y: bounds.midY - 9, width: 76, height: 18),
                 size: 12.5, weight: .medium,
                 color: NSColor(calibratedWhite: 1, alpha: 0.62), align: .left)
        }
        if let (l, r) = battery {
            draw("L \(l)%  R \(r)%",
                 in: NSRect(x: bounds.width - 116, y: bounds.midY - 8, width: 100, height: 16),
                 size: 10.5, weight: .medium,
                 color: NSColor(calibratedWhite: 1, alpha: min(l, r) < 20 ? 0.95 : 0.42),
                 align: .right)
        }
    }

    override var isFlipped: Bool { true }

    /// Defy space → view space.
    private func rect(_ b: KeyBox) -> NSRect {
        NSRect(x: pad + (b.x - keymap.bounds.minX) * scale,
               y: pad + header + (b.y - keymap.bounds.minY) * scale,
               width: b.w * scale - 2, height: b.h * scale - 2)
    }

    override func draw(_ dirty: NSRect) {
        let radius: CGFloat = pill ? bounds.height/2 : 16
        let bg = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        // Over frosted glass a faint scrim is enough; on its own the panel needs
        // to supply its own darkness.
        NSColor(calibratedWhite: glass ? 0.0 : 0.07,
                alpha: glass ? 0.22 : 0.92).setFill()
        bg.fill()
        if grabbable {
            NSColor.systemBlue.setStroke(); bg.lineWidth = 3
        } else {
            NSColor(calibratedWhite: 1.0, alpha: 0.10).setStroke(); bg.lineWidth = 1
        }
        bg.stroke()

        if pill { drawMini(); return }

        // wordmark, left
        let mark = NSMutableAttributedString(string: "LENS", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .heavy),
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.42),
            .kern: 2.6])
        mark.draw(in: NSRect(x: pad + 2, y: pad + 1, width: 90, height: 16))
        NSColor(calibratedWhite: 1, alpha: 0.13).setFill()
        NSRect(x: pad + 2, y: pad + 17, width: 46, height: 1).fill()

        // layer name, centre
        let name = keymap.layerNames[safe: layerIndex] ?? "Layer \(layerIndex + 1)"
        draw(name, in: NSRect(x: pad, y: pad - 2, width: bounds.width - pad*2, height: 20),
             size: 15, weight: .semibold, color: .white, align: .center)

        // One corner, one message, or they draw over each other. A status is rare
        // and it matters, so it wins; then the drill while it runs; then the
        // batteries, which are only ever a glance.
        if let st = status {
            draw(st, in: NSRect(x: bounds.width - pad - 260, y: pad + 2,
                                width: 260, height: 16),
                 size: 10.5, weight: .medium, color: NSColor.systemOrange, align: .right)
        } else if let d = drill, d.active {
            let total = d.hits + d.misses
            let acc = total == 0 ? 100 : Int(Double(d.hits) / Double(total) * 100)
            draw("\(d.hits) hit · \(acc)% · \(d.lastResult)",
                 in: NSRect(x: bounds.width - pad - 190, y: pad + 2, width: 190, height: 16),
                 size: 10.5, weight: .medium,
                 color: NSColor(calibratedWhite: 1, alpha: 0.75), align: .right)
        } else if let (l, r) = battery {
            let txt = "L \(l)%   R \(r)%"
            draw(txt, in: NSRect(x: bounds.width - pad - 150, y: pad + 2,
                                 width: 150, height: 16),
                 size: 10.5, weight: .medium,
                 color: NSColor(calibratedWhite: 1, alpha: min(l, r) < 20 ? 0.95 : 0.45),
                 align: .right)
        }
        if let h = hint {
            draw(h, in: NSRect(x: pad, y: bounds.height - pad - 12,
                               width: bounds.width - pad*2, height: 14),
                 size: 10, weight: .regular,
                 color: NSColor(calibratedWhite: 1, alpha: 0.45), align: .center)
        }
        guard keymap.layers.indices.contains(layerIndex) else { return }
        let lay = keymap.layers[layerIndex]

        let vers = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                   as? String ?? "?"
        draw("Lens \(vers)",
             in: NSRect(x: bounds.width - pad - 120, y: bounds.height - pad - footer + 1,
                        width: 120, height: footer),
             size: targetWidth < 520 ? 8 : 9, weight: .regular,
             color: NSColor(calibratedWhite: 1, alpha: 0.30), align: .right)

        for b in keymap.boxes {
            let label = (shifted ? lay.shift[safe: b.index] : nil)
                     ?? lay.labels[safe: b.index] ?? ""
            let usage = lay.hid[safe: b.index] ?? 0
            let hot = usage != 0 && pressed.contains(usage)
            let empty = label.isEmpty

            // local shape -> placed on the panel, turned about its own centre
            let shape = (keymap.paths[b.index]?.copy() as? NSBezierPath)
                ?? NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: b.w, height: b.h),
                                xRadius: 7, yRadius: 7)
            let t = NSAffineTransform()
            t.translateX(by: pad + (b.x - keymap.bounds.minX) * scale,
                         yBy:  pad + header + (b.y - keymap.bounds.minY) * scale)
            t.scaleX(by: scale, yBy: scale)
            shape.transform(using: t as AffineTransform)   // no rotation: the
            // silhouette already encodes the angle of the cap

            var text = NSColor.white
            let lit = showColors ? keymap.led(b, layer: layerIndex) : nil
            if let c = lit, c.brightnessComponent > 0.04 {
                let k: CGFloat = hot ? 1.0 : (empty ? 0.30 : 0.62)
                let fill = NSColor(calibratedRed: c.redComponent*k, green: c.greenComponent*k,
                                   blue: c.blueComponent*k, alpha: 1)
                fill.setFill(); shape.fill()
                let lum = 0.2126*fill.redComponent + 0.7152*fill.greenComponent
                        + 0.0722*fill.blueComponent
                text = lum > 0.55 ? .black : .white
            } else {
                NSColor(calibratedWhite: empty ? 0.12 : 0.20,
                        alpha: empty ? 0.5 : 1.0).setFill()
                shape.fill()
            }
            if let d = drill, d.active, let t = d.target,
               t.layer == layerIndex, t.pos == b.index {
                NSColor.systemGreen.withAlphaComponent(0.85).setFill(); shape.fill()
                NSColor.white.setStroke(); shape.lineWidth = 3; shape.stroke()
                text = .black
            } else if hot {
                NSColor.white.setStroke(); shape.lineWidth = 2.5; shape.stroke()
            }

            guard !empty, label != "▽" else { continue }
            let centre = (t as AffineTransform).transform(NSPoint(x: b.cx, y: b.cy))
            let fs: CGFloat = label.count >= 6 ? 9 : (label.count >= 4 ? 10.5 : 13)
            let box = NSRect(x: centre.x - 26, y: centre.y - fs*0.78, width: 52, height: fs*1.6)
            if b.rot != 0, rotateLabels, let ctx = NSGraphicsContext.current?.cgContext {
                ctx.saveGState()
                ctx.translateBy(x: centre.x, y: centre.y)
                ctx.rotate(by: b.rot * .pi / 180)
                ctx.translateBy(x: -centre.x, y: -centre.y)
                draw(label, in: box, size: fs, weight: hot ? .bold : .medium,
                     color: text, align: .center)
                ctx.restoreGState()
            } else {
                draw(label, in: box, size: fs, weight: hot ? .bold : .medium,
                     color: text, align: .center)
            }
        }
    }

    // ── Dragging ──────────────────────────────────────────────────────────────
    override func mouseDown(with e: NSEvent) { grip = e.locationInWindow }

    override func mouseDragged(with e: NSEvent) {
        guard let g = grip, let w = window else { return }
        let p = w.convertPoint(toScreen: e.locationInWindow)
        w.setFrameOrigin(NSPoint(x: p.x - g.x, y: p.y - g.y))
    }

    override func mouseUp(with e: NSEvent) { grip = nil; onMoved?() }

    private func draw(_ s: String, in r: NSRect, size: CGFloat, weight: NSFont.Weight,
                      color: NSColor, align: NSTextAlignment) {
        let ps = NSMutableParagraphStyle(); ps.alignment = align; ps.lineBreakMode = .byClipping
        (s as NSString).draw(in: r, withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color, .paragraphStyle: ps])
    }
}

extension Array { subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil } }

// ── Controller ────────────────────────────────────────────────────────────────
final class LensPanel: NSPanel {
    var placing = false
    override var canBecomeKey: Bool { placing }
    override var canBecomeMain: Bool { placing }
}

enum Anchor: String {
    case topLeft = "top-left", top, topRight = "top-right"
    case left, center, right
    case bottomLeft = "bottom-left", bottom, bottomRight = "bottom-right"

    func origin(for size: NSSize, in vf: NSRect, inset: CGFloat = 24) -> NSPoint {
        let x: CGFloat, y: CGFloat
        switch self {
        case .topLeft, .left, .bottomLeft:       x = vf.minX + inset
        case .top, .center, .bottom:             x = vf.midX - size.width/2
        case .topRight, .right, .bottomRight:    x = vf.maxX - size.width - inset
        }
        switch self {
        case .topLeft, .top, .topRight:          y = vf.maxY - size.height - inset
        case .left, .center, .right:             y = vf.midY - size.height/2
        case .bottomLeft, .bottom, .bottomRight: y = vf.minY + inset
        }
        return NSPoint(x: x, y: y)
    }
}

final class Controller: NSObject {
    let panel: LensPanel
    let view = LensView()
    let focus: Focus
    let tap = KeyTap()
    let drill = Drill()
    let alwaysOn: Bool, placing: Bool, posPath: String
    let toggleUsage: Int?
    let useSerial: Bool
    var alwaysGrab = false
    var dragMods: Set<String> = ["control", "alt"]
    private var hideWork: DispatchWorkItem?
    private var lastLayer = -1
    private var pinned = false
    private var stashed = false
    private var warnedPort = false
    /// The Neuron answers in ~1 ms; 20 Hz is imperceptible and far gentler on it.
    private let pollGap = 0.05
    private var statusItem: NSStatusItem?
    let mapPath: String
    var glass: Bool
    var opacity: CGFloat
    private var tick = 0
    /// Each size remembers its own spot.
    private var posKey: String { pill ? "pill" : (view.targetWidth < 520 ? "small" : "big") }
    var pill: Bool
    /// Bazecor opens the Neuron exclusively. While it is up, we must not hold the port.
    private var bazecorUp = false
    private var watchdog: Timer?
    private let q = DispatchQueue(label: "lens.serial")

    init(port: String, mapPath: String, posPath: String, width: CGFloat,
         forcedLayer: Int?, toggleUsage: Int?, useSerial: Bool,
         showColors: Bool, rotateLabels: Bool, glass: Bool, opacity: CGFloat,
         pill: Bool, drillBase: Bool, drillMisses: Bool,
         alwaysOn: Bool, placing: Bool, grab: Bool,
         dragMods: Set<String>, anchor: Anchor?) {
        let alwaysGrabInit = grab
        self.focus = Focus(port: port)
        self.alwaysOn = alwaysOn || placing
        self.placing = placing
        self.posPath = posPath
        self.toggleUsage = toggleUsage
        self.useSerial = useSerial
        self.mapPath = mapPath
        self.glass = glass
        self.opacity = opacity
        self.pill = pill
        view.keymap = Keymap.load(mapPath)
        view.targetWidth = width
        view.showColors = showColors
        view.rotateLabels = rotateLabels
        view.glass = glass
        view.pill = pill
        view.drill = drill
        drill.includeBase = drillBase
        drill.countMisses = drillMisses
        if let f = forcedLayer { view.layerIndex = f; lastLayer = f; pinned = true }
        if placing { view.hint = "drag me   ·   ⌘Q saves and quits" }
        let size = view.idealSize
        panel = LensPanel(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: placing ? [.borderless] : [.nonactivatingPanel, .borderless],
                          backing: .buffered, defer: false)
        super.init()
        self.alwaysGrab = alwaysGrabInit
        self.dragMods = dragMods
        panel.placing = placing
        view.frame = NSRect(origin: .zero, size: size)
        if glass {
            let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
            blur.material = .hudWindow
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.wantsLayer = true
            blur.layer?.cornerRadius = pill ? size.height/2 : 16
            blur.layer?.masksToBounds = true
            blur.autoresizingMask = [.width, .height]
            view.autoresizingMask = [.width, .height]
            blur.addSubview(view)
            panel.contentView = blur
        } else {
            panel.contentView = view
        }
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = !placing && !alwaysGrabInit
        panel.isMovableByWindowBackground = placing
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                    .fullScreenAuxiliary, .ignoresCycle]
        place(size: size, anchor: anchor)
        panel.alphaValue = (placing || self.alwaysOn) ? opacity : 0   // show it, do not just stop the fade
        panel.orderFrontRegardless()
        if placing {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            NotificationCenter.default.addObserver(
                self, selector: #selector(moved), name: NSWindow.didMoveNotification, object: panel)
        }
        startTap()
        buildMenu()
        watchBazecor()
        if useSerial { poll() }
    }

    private func startTap() {
        view.onMoved = { [weak self] in self?.moved() }
        tap.toggleUsage = toggleUsage
        tap.debugKeys = CommandLine.arguments.contains("--debug-keys")
        tap.onToggle = { [weak self] in
            guard let self else { return }
            print("toggle: overlay -> \(self.stashed ? "shown" : "hidden")")
            self.stashed.toggle()
            if self.stashed {
                self.hideWork?.cancel()
                NSAnimationContext.runAnimationGroup { c in
                    c.duration = 0.15; self.panel.animator().alphaValue = 0
                }
            } else {
                self.show(fade: !self.alwaysOn)
            }
        }
        tap.onChange = { [weak self] in
            guard let self else { return }
            if self.drill.active, let u = self.tap.down.first,
               let t = self.drill.target {
                let want = self.view.keymap.layers[safe: t.layer]?.hid[safe: t.pos] ?? 0
                if u == want {
                    self.drill.record(correct: true)
                    self.drill.pick(self.view.keymap, skip: self.toggleUsage ?? 0)
                    self.view.layerIndex = self.drill.target?.layer ?? 0
                } else if u != (self.toggleUsage ?? -1) {
                    self.drill.record(correct: false)
                }
                self.view.needsDisplay = true
            }
            self.view.pressed = self.tap.down
            self.view.shifted = self.tap.flags.contains(.maskShift)
            if let u = self.tap.down.first,
               let lay = self.view.keymap.layers[safe: self.view.layerIndex],
               let pos = lay.hid.firstIndex(of: u) {
                self.view.lastKey = lay.labels[safe: pos] ?? ""
            }
            let grab = self.alwaysGrab || self.dragMods.isSubset(of: self.tap.flags.grabBits)
            if grab != self.view.grabbable {
                self.view.grabbable = grab
                self.panel.ignoresMouseEvents = !grab
                if grab { self.show(fade: false) } else { self.show(fade: true) }
            }
            self.view.needsDisplay = true
            if !self.tap.down.isEmpty { self.show(fade: true) }
        }
        // tapCreate can succeed and still deliver nothing, so ask TCC directly.
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        let granted = access == kIOHIDAccessTypeGranted
        if !granted {
            print("Input Monitoring: NOT granted (\(access.rawValue)) — asking now")
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            view.hint = "allow Input Monitoring for Lens, then reopen it"
            view.needsDisplay = true
        }
        let started = tap.start()          // call once; two calls means two taps
        if started && granted {
            print("key tap: running — highlighting is live")
        } else if !started {
            print("key tap: tapCreate refused")
        }
        setvbuf(stdout, nil, _IOLBF, 0)
    }

    // MARK: menu bar

    private func item(_ title: String, _ sel: Selector, on: Bool? = nil,
                      key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        if let on { i.state = on ? .on : .off }
        return i
    }

    /// A small Defy thumb cap, drawn as a template image for the menu bar.
    static func menuMark() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18))
        img.lockFocus()
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 3.0, y: 4.0))
        p.line(to: NSPoint(x: 13.5, y: 2.2))
        p.curve(to: NSPoint(x: 15.4, y: 4.4),
                controlPoint1: NSPoint(x: 14.7, y: 2.4), controlPoint2: NSPoint(x: 15.4, y: 3.3))
        p.line(to: NSPoint(x: 14.2, y: 13.6))
        p.curve(to: NSPoint(x: 12.0, y: 15.6),
                controlPoint1: NSPoint(x: 14.1, y: 14.7), controlPoint2: NSPoint(x: 13.1, y: 15.6))
        p.line(to: NSPoint(x: 4.2, y: 15.6))
        p.curve(to: NSPoint(x: 2.4, y: 13.4),
                controlPoint1: NSPoint(x: 3.1, y: 15.6), controlPoint2: NSPoint(x: 2.4, y: 14.6))
        p.close()
        NSColor.black.setStroke(); p.lineWidth = 1.6; p.stroke()
        NSColor.black.withAlphaComponent(0.30).setFill(); p.fill()
        img.unlockFocus()
        return img
    }

    private func buildMenu() {
        let si = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        si.button?.image = Self.menuMark()
        si.button?.image?.isTemplate = true
        let m = NSMenu()
        m.addItem(item("Refresh keymap from Bazecor backup", #selector(doRefresh), key: "r"))
        m.addItem(.separator())
        m.addItem(sliderItem("Size", 360, 1100, Double(view.targetWidth),
                             #selector(setWidth(_:))))
        m.addItem(item("Layer strip only", #selector(togglePill), on: pill))
        m.addItem(.separator())
        m.addItem(item("Layer drill", #selector(toggleDrill), on: drill.active, key: "d"))
        m.addItem(item("  include layer 1", #selector(toggleBase), on: drill.includeBase))
        m.addItem(item("  count mistakes", #selector(toggleMisses), on: drill.countMisses))
        m.addItem(item("Drill report", #selector(drillReport)))
        m.addItem(item("Frosted background", #selector(toggleGlass), on: glass))
        m.addItem(item("LED colours", #selector(toggleColors), on: view.showColors))
        m.addItem(item("Turn thumb legends", #selector(toggleRotate), on: view.rotateLabels))
        m.addItem(item("Always draggable", #selector(toggleGrab), on: alwaysGrab))
        m.addItem(.separator())
        m.addItem(sliderItem("Opacity", 0.25, 1.0, Double(opacity),
                             #selector(setOpacity(_:))))
        m.addItem(.separator())
        m.addItem(item("Reveal folder", #selector(reveal)))
        m.addItem(NSMenuItem(title: "Quit Lens",
                             action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        si.menu = m
        statusItem = si
    }

    /// A labelled slider as a menu row. Custom-view rows are tall, so these go last.
    private func sliderItem(_ title: String, _ lo: Double, _ hi: Double,
                            _ value: Double, _ action: Selector) -> NSMenuItem {
        let it = NSMenuItem()
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 244, height: 28))
        box.autoresizingMask = [.width]
        let lab = NSTextField(labelWithString: title)
        lab.frame = NSRect(x: 14, y: 6, width: 62, height: 16)
        lab.font = .menuFont(ofSize: 13)
        lab.textColor = .labelColor
        let sl = NSSlider(value: value, minValue: lo, maxValue: hi,
                          target: self, action: action)
        sl.frame = NSRect(x: 82, y: 3, width: 148, height: 22)
        sl.autoresizingMask = [.width]
        sl.isContinuous = true
        box.addSubview(lab); box.addSubview(sl)
        it.view = box
        return it
    }

    @objc private func setOpacity(_ sl: NSSlider) {
        opacity = CGFloat(sl.doubleValue)
        if !stashed { panel.alphaValue = opacity }
        save("opacity", Double(round(opacity * 100) / 100))
    }

    /// Persist one setting so it survives the next relaunch.
    private func save(_ key: String, _ value: Any) {
        let path = NSHomeDirectory() + "/Dygma/lens/config.json"
        var cfg = (try? JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: path)))) as? [String: Any] ?? [:]
        cfg[key] = value
        if let d = try? JSONSerialization.data(withJSONObject: cfg,
                                               options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: URL(fileURLWithPath: path))
        }
    }

    @objc private func doRefresh(_ sender: NSMenuItem) {
        let dir = NSHomeDirectory() + "/Dygma/lens/decode"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["python3", dir + "/export_layers.py"]
        p.currentDirectoryURL = URL(fileURLWithPath: dir)
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { print("refresh: \(error)"); return }
        p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        print("refresh (exit \(p.terminationStatus)):\n" + out.trimmingCharacters(in: .newlines))
        guard p.terminationStatus == 0 else {
            view.status = "keymap refresh failed — see lens.log"; view.needsDisplay = true; return
        }
        view.keymap = Keymap.load(mapPath)
        view.status = nil
        resize(to: view.idealSize)
    }

    /// Resize the window, then make the drawing match its content view exactly.
    /// Setting the drawing's frame first lets the autoresize mask shrink it twice.
    private func resize(to size: NSSize, anchor: Anchor? = nil) {
        let here = panel.frame.origin        // stay put unless this size
        place(size: size, anchor: anchor, fallback: here)   // has its own spot
        panel.setContentSize(size)
        if let cv = panel.contentView {
            cv.frame = NSRect(origin: .zero, size: size)
            (cv as? NSVisualEffectView)?.layer?.cornerRadius = pill ? size.height/2 : 16
            view.frame = cv.bounds
        }
        view.needsDisplay = true
    }

    @objc private func setWidth(_ sl: NSSlider) {
        view.pill = false; pill = false
        view.targetWidth = CGFloat(sl.doubleValue)
        save("pill", false); save("width", Double(round(sl.doubleValue)))
        resize(to: view.idealSize)
    }

    @objc private func toggleDrill(_ s: NSMenuItem) {
        drill.active.toggle(); s.state = drill.active ? .on : .off
        if drill.active {
            drill.hits = 0; drill.misses = 0; drill.lastResult = ""
            drill.pick(view.keymap, skip: toggleUsage ?? 0)
            pinned = true                        // show the target layer, not the live one
            view.layerIndex = drill.target?.layer ?? 0
        } else {
            pinned = false
        }
        view.needsDisplay = true
    }

    @objc private func toggleBase(_ s: NSMenuItem) {
        drill.includeBase.toggle(); s.state = drill.includeBase ? .on : .off
        save("drillBase", drill.includeBase)
        if drill.active {
            drill.pick(view.keymap, skip: toggleUsage ?? 0)
            view.layerIndex = drill.target?.layer ?? 0
            view.needsDisplay = true
        }
    }

    @objc private func toggleMisses(_ s: NSMenuItem) {
        drill.countMisses.toggle(); s.state = drill.countMisses ? .on : .off
        save("drillMisses", drill.countMisses)
    }

    /// Write what you are worst at to a file and open it.
    @objc private func drillReport() {
        let names = view.keymap.layerNames
        var rows: [(Double, String)] = []
        for (k, sc) in drill.scores {
            let p = k.split(separator: ":").compactMap { Int($0) }
            guard p.count == 2, let lay = view.keymap.layers[safe: p[0]] else { continue }
            let label = lay.labels[safe: p[1]] ?? "?"
            let cost = sc.avgMs + Double(sc.errs) * 900
            // pad in Swift: %s takes a C string, and handing it a Swift String
            // makes strlen walk an object pointer. That crashes.
            func col(_ t: String, _ n: Int) -> String {
                t.count >= n ? String(t.prefix(n))
                             : t + String(repeating: " ", count: n - t.count)
            }
            let line = col(names[safe: p[0]] ?? "L\(p[0]+1)", 6) + " "
                     + col(label, 10) + " "
                     + String(format: "%5.0f ms  %3d tries  %3d missed",
                              sc.avgMs, sc.n, sc.errs)
            rows.append((cost, line))
        }
        rows.sort { $0.0 > $1.0 }
        let text = "Lens drill — slowest first\n\n"
                 + rows.map { $0.1 }.joined(separator: "\n") + "\n"
        let out = NSHomeDirectory() + "/Dygma/lens/drill-report.txt"
        try? text.write(toFile: out, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(URL(fileURLWithPath: out))
    }

    @objc private func togglePill(_ s: NSMenuItem) {
        view.pill.toggle(); pill = view.pill
        s.state = pill ? .on : .off
        save("pill", pill)
        resize(to: view.idealSize)
    }

    @objc private func toggleGlass(_ s: NSMenuItem) {
        glass.toggle(); s.state = glass ? .on : .off
        view.glass = glass
        save("glass", glass)
        view.status = "restart Lens to change the background"
        view.needsDisplay = true
    }
    @objc private func toggleColors(_ s: NSMenuItem) {
        view.showColors.toggle(); s.state = view.showColors ? .on : .off
        save("colors", view.showColors); view.needsDisplay = true
    }
    @objc private func toggleRotate(_ s: NSMenuItem) {
        view.rotateLabels.toggle(); s.state = view.rotateLabels ? .on : .off
        save("rotateLabels", view.rotateLabels); view.needsDisplay = true
    }
    @objc private func toggleGrab(_ s: NSMenuItem) {
        alwaysGrab.toggle(); s.state = alwaysGrab ? .on : .off
        panel.ignoresMouseEvents = !alwaysGrab
        view.grabbable = alwaysGrab
        save("grab", alwaysGrab); view.needsDisplay = true
    }
    @objc private func reveal() {
        NSWorkspace.shared.selectFile(NSHomeDirectory() + "/Dygma/lens/config.json",
                                      inFileViewerRootedAtPath: NSHomeDirectory() + "/Dygma/lens")
    }

    private func watchBazecor() {
        let check = { [weak self] in
            guard let self else { return }
            let up = !NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.dygmalab.bazecor").isEmpty
            if up != self.bazecorUp {
                self.bazecorUp = up
                self.view.status = up ? "Bazecor has the keyboard" : nil
                self.view.needsDisplay = true
            }
        }
        check()
        watchdog = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in check() }
    }

    private func place(size: NSSize, anchor: Anchor?, fallback: NSPoint? = nil) {
        let vf = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        var origin = fallback ?? Anchor.bottom.origin(for: size, in: vf, inset: 60)
        if let a = anchor {
            origin = a.origin(for: size, in: vf)
        } else if let d = FileManager.default.contents(atPath: posPath),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Double],
                  let x = j[posKey + "X"], let y = j[posKey + "Y"] {
            let p = NSPoint(x: x, y: y)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(NSRect(origin: p, size: size)) }) {
                origin = p
            }
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    @objc private func moved() {
        let o = panel.frame.origin
        var j = (try? JSONSerialization.jsonObject(
            with: (try? Data(contentsOf: URL(fileURLWithPath: posPath))) ?? Data()))
            as? [String: Double] ?? [:]
        j[posKey + "X"] = Double(o.x)
        j[posKey + "Y"] = Double(o.y)
        if let d = try? JSONSerialization.data(withJSONObject: j) {
            try? d.write(to: URL(fileURLWithPath: posPath))
        }
    }

    private func show(fade: Bool) {
        hideWork?.cancel()
        if stashed { panel.alphaValue = 0; return }
        panel.alphaValue = opacity
        guard fade, !alwaysOn else { return }
        let w = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup { c in
                c.duration = 0.45; self?.panel.animator().alphaValue = 0
            }
        }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: w)
    }

    private func poll() {
        q.asyncAfter(deadline: .now() + pollGap) { [weak self] in
            guard let self else { return }
            if self.bazecorUp {                       // hand the Neuron back, at once
                if self.focus.isOpen { self.focus.close() }
                self.q.asyncAfter(deadline: .now() + 1.0) { self.poll() }
                return
            }
            if !self.focus.isOpen, !self.focus.open() {
                if !self.warnedPort {
                    self.warnedPort = true
                    print("serial: cannot open \(self.focus.port) — retrying")
                }
                DispatchQueue.main.async {
                    self.view.status = "no Neuron on \(self.focus.port)"
                    self.view.needsDisplay = true
                }
                self.q.asyncAfter(deadline: .now() + 1.5) { self.poll() }
                return
            }
            if self.warnedPort { print("serial: open ok"); self.warnedPort = false }
            self.tick += 1
            if self.tick % 160 == 1, let b = self.focus.battery() {
                DispatchQueue.main.async { self.view.battery = b; self.view.needsDisplay = true }
            }
            let n = self.focus.activeLayer()
            DispatchQueue.main.async {
                if let n, n != self.lastLayer, !self.pinned {
                    self.lastLayer = n
                    self.view.status = nil
                    self.view.layerIndex = n
                    self.view.needsDisplay = true
                    self.show(fade: true)
                } else if n != nil, self.view.status != nil {
                    self.view.status = nil; self.view.needsDisplay = true
                }
            }
            self.poll()
        }
    }
}

// ── main ──────────────────────────────────────────────────────────────────────
let args = CommandLine.arguments
func opt(_ name: String, _ fallback: String) -> String {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return fallback }
    return args[i + 1]
}
if args.contains("--check") {
    let a = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
    let names = [0: "GRANTED", 1: "DENIED", 2: "not yet asked"]
    print("Input Monitoring : \(names[Int(a.rawValue)] ?? "\(a.rawValue)")")
    print("Accessibility    : \(AXIsProcessTrusted() ? "granted" : "not granted")")
    print("bundle           : \(Bundle.main.bundleIdentifier ?? "none (bare binary)")")
    print("path             : \(Bundle.main.bundlePath)")
    exit(0)
}
if args.contains("--help") {
    print("""
    lens — layer overlay for the Dygma Defy

      --at <spot>   top-left top top-right left center right
                    bottom-left bottom bottom-right
      --place       drag it where you want, ⌘Q saves and quits
      --grab        always draggable (gives up click-through)
      --drag-mods   hold these to grab it, default cmd,shift
      --fade        hide again 1.6 s after a change (default: stay visible)
      --always      kept for compatibility; visible is now the default
      --replace     take over from a copy that is already running
      --no-colors   plain keys instead of your LED colours
      --upright-labels  do not turn the thumb legends with the caps
      --width <px>  overlay width, default 760
      --serial      read the live layer from the Neuron (opt-in; the port is
                    exclusive, so this competes with Bazecor)
      --pill        layer strip only, instead of the whole board
      --layer <n>   pin a layer instead of reading the keyboard
      --toggle <k>  key that shows/hides the overlay: f13..f24 or none
                    (default f13 — assign F13 to a key in Bazecor)
      --port <dev>  default /dev/cu.usbmodem1101
      --map <file>  default ~/Dygma/lens/layers.json

    Settings persist in ~/Dygma/lens/config.json; flags override it.
    """)
    exit(0)
}
let home = FileManager.default.homeDirectoryForCurrentUser.path

// Launched from Finder or `open`, stdout goes nowhere. Keep a log we can read.
freopen(home + "/Dygma/lens/lens.log", "a", stdout)
freopen(home + "/Dygma/lens/lens.log", "a", stderr)
setvbuf(stdout, nil, _IOLBF, 0)
print("\n=== lens started \(Date()) ===")

// One instance only.
let lockPath = home + "/Dygma/lens/.lock"
let lockFD = Darwin.open(lockPath, O_CREAT | O_RDWR, 0o644)
func err(_ m: String) { FileHandle.standardError.write(Data((m + "\n").utf8)) }
if flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    let other = (try? String(contentsOfFile: lockPath, encoding: .utf8))
                .flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    if args.contains("--replace"), let pid = other, pid > 0 {
        kill(pid, SIGTERM)
        var took = false
        for _ in 0..<40 { usleep(50_000); if flock(lockFD, LOCK_EX | LOCK_NB) == 0 { took = true; break } }
        if !took { err("lens: the running copy (pid \(pid)) would not quit"); exit(1) }
    } else {
        err("lens is already running\(other.map { " (pid \($0))" } ?? ""). Use --replace to take over.")
        exit(1)
    }
}
ftruncate(lockFD, 0)
_ = String(getpid()).withCString { Darwin.write(lockFD, $0, strlen($0)) }

/// "f13".."f24", a bare HID usage number, or "none".
func parseToggle(_ v: String) -> Int? {
    let t = v.lowercased()
    if t == "none" || t.isEmpty { return nil }
    if t.hasPrefix("f"), let n = Int(t.dropFirst()), (13...24).contains(n) { return 104 + (n - 13) }
    if let n = Int(t), (4...231).contains(n) { return n }
    err("lens: cannot read --toggle \(v); use f13..f24, a HID number, or none")
    return nil
}

// Settings live in a file, because a relaunch (Finder, or macOS restarting the
// app after a permission change) throws command-line arguments away.
var cfg: [String: Any] = [:]
if let d = FileManager.default.contents(atPath: home + "/Dygma/lens/config.json"),
   let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { cfg = j }

func flag(_ name: String, _ key: String, _ def: Bool) -> Bool {
    if args.contains("--" + name) { return true }
    if args.contains("--no-" + name) { return false }
    return cfg[key] as? Bool ?? def
}
func setting(_ name: String, _ key: String, _ def: String) -> String {
    let v = opt("--" + name, "")
    if !v.isEmpty { return v }
    if let c = cfg[key] as? String { return c }
    if let n = cfg[key] as? NSNumber { return n.stringValue }
    return def
}

let placing = args.contains("--place")
let app = NSApplication.shared
app.setActivationPolicy(placing ? .regular : .accessory)
/// The Neuron's node number changes between replugs, so look for it.
func findPort() -> String {
    let given = opt("--port", "")
    if !given.isEmpty { return given }
    let found = (try? FileManager.default.contentsOfDirectory(atPath: "/dev"))?
        .filter { $0.hasPrefix("cu.usbmodem") }.sorted() ?? []
    return "/dev/" + (found.first ?? "cu.usbmodem1101")
}

let c = Controller(port: findPort(),
                   mapPath: setting("map", "map", home + "/Dygma/lens/layers.json"),
                   posPath: home + "/Dygma/lens/position.json",
                   width: CGFloat(Double(setting("width", "width", "760")) ?? 760),
                   forcedLayer: Int(opt("--layer", "")).map { $0 - 1 },
                   toggleUsage: parseToggle(setting("toggle", "toggle", "f13")),
                   useSerial: flag("serial", "serial", true),
                   showColors: flag("colors", "colors", true),
                   rotateLabels: flag("rotate-labels", "rotateLabels", true),
                   glass: flag("glass", "glass", true),
                   opacity: CGFloat(Double(setting("opacity", "opacity", "1")) ?? 1),
                   pill: flag("pill", "pill", false),
                   drillBase: flag("drill-base", "drillBase", true),
                   drillMisses: flag("drill-misses", "drillMisses", true),
                   alwaysOn: !flag("fade", "fade", false),
                   placing: placing,
                   grab: flag("grab", "grab", false),
                   dragMods: Set(setting("drag-mods", "dragMods", "cmd,shift")
                                 .split(separator: ",").map { String($0) }),
                   anchor: Anchor(rawValue: opt("--at", "")))
_ = c
app.run()
