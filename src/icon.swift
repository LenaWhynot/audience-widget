import AppKit
let image=NSImage(size:NSSize(width:1024,height:1024))
image.lockFocus()
NSColor(calibratedRed:0.07,green:0.08,blue:0.10,alpha:1).setFill()
NSBezierPath(roundedRect:NSRect(x:32,y:32,width:960,height:960),xRadius:210,yRadius:210).fill()
NSColor(calibratedRed:0.60,green:0.86,blue:0.68,alpha:1).setFill()
for (i,h) in [240.0,390.0,540.0].enumerated() {
 NSBezierPath(roundedRect:NSRect(x:245+Double(i)*190,y:235,width:135,height:h),xRadius:34,yRadius:34).fill()
}
image.unlockFocus()
let data=NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!
try data.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
