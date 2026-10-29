import AppKit
let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
NSColor.clear.setFill(); NSRect(x:0,y:0,width:size,height:size).fill()
NSColor(calibratedRed: 0.965, green: 0.965, blue: 0.947, alpha:1).setFill()
NSBezierPath(roundedRect:NSRect(x:40,y:40,width:944,height:944), xRadius:215,yRadius:215).fill()
NSColor(calibratedWhite:0.09,alpha:1).setFill()
for (x,y) in [(240,545),(545,545),(240,240)] {
    NSBezierPath(roundedRect:NSRect(x:x,y:y,width:239,height:239),xRadius:52,yRadius:52).fill()
}
NSColor(calibratedRed:0.30,green:0.46,blue:0.37,alpha:1).setFill()
NSBezierPath(roundedRect:NSRect(x:545,y:240,width:239,height:239),xRadius:52,yRadius:52).fill()
let tick = NSBezierPath(); tick.move(to: NSPoint(x:602,y:356)); tick.line(to:NSPoint(x:648,y:309));tick.line(to:NSPoint(x:728,y:405));tick.lineWidth=21;tick.lineCapStyle = .round;tick.lineJoinStyle = .round;NSColor.white.setStroke();tick.stroke()
image.unlockFocus()
let rep = NSBitmapImageRep(data:image.tiffRepresentation!)!
try rep.representation(using:.png, properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
