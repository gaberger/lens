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

// The mark is a real Defy thumb cap, taken from the overlay's own geometry.
let home = FileManager.default.homeDirectoryForCurrentUser.path
let j = try! JSONSerialization.jsonObject(
    with: Data(contentsOf: URL(fileURLWithPath: home + "/Dygma/lens/layers.json"))) as! [String: Any]
let segs = (j["paths"] as! [String: [[Any]]])["67"]!     // defy-t4, the angled cap
let palette = (j["palette"] as! [[Double]]).map {
    NSColor(calibratedRed: $0[0]/255, green: $0[1]/255, blue: $0[2]/255, alpha: 1) }

let cap = NSBezierPath()
for s in segs {
    let op = s.first as! String
    let v = s.dropFirst().compactMap { ($0 as? NSNumber)?.doubleValue }
    switch op {
    case "M": cap.move(to: NSPoint(x: v[0], y: v[1]))
    case "L": cap.line(to: NSPoint(x: v[0], y: v[1]))
    case "C": cap.curve(to: NSPoint(x: v[4], y: v[5]),
                        controlPoint1: NSPoint(x: v[0], y: v[1]),
                        controlPoint2: NSPoint(x: v[2], y: v[3]))
    case "Z": cap.close()
    default: break
    }
}
let capBounds = cap.bounds

func icon(_ px: Int) -> Data {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext

    // ground: rounded square, near-black with a cool tint
    let r = NSBezierPath(roundedRect: NSRect(x: s*0.06, y: s*0.06, width: s*0.88, height: s*0.88),
                         xRadius: s*0.22, yRadius: s*0.22)
    NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 1).setFill()
    r.fill()

    // a soft band of the user's own palette across the lower third
    ctx.saveGState(); r.addClip()
    let band = NSGradient(colors: [palette[4], palette[1], palette[0]].map { $0.withAlphaComponent(0.55) })!
    band.draw(in: NSRect(x: 0, y: s*0.06, width: s, height: s*0.42), angle: 0)
    ctx.restoreGState()

    // the cap, centred and scaled to fit
    ctx.saveGState()
    let fit = s * 0.52 / max(capBounds.width, capBounds.height)
    ctx.translateBy(x: s/2, y: s/2 + s*0.03)
    ctx.scaleBy(x: fit, y: -fit)
    ctx.translateBy(x: -capBounds.midX, y: -capBounds.midY)
    let shape = cap.copy() as! NSBezierPath
    NSColor(calibratedWhite: 1, alpha: 0.96).setFill(); shape.fill()
    ctx.restoreGState()

    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

let set = home + "/Dygma/lens/Lens.iconset"
try? FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32),
                   ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256),
                   ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512),
                   ("icon_512x512@2x", 1024)] {
    try! icon(px).write(to: URL(fileURLWithPath: "\(set)/\(name).png"))
}
print("wrote \(set)")
