import SwiftUI
import AppKit

struct HorizontalDayNavigation {
    var accumulated = 0.0
    mutating func reset(){accumulated = 0}
    mutating func consume(dx:Double,dy:Double,momentum:Bool)->Int? {
        guard !momentum,abs(dx) > abs(dy)*1.15,abs(dx) > 0.1 else{return nil}
        accumulated += dx
        guard abs(accumulated) >= 60 else{return nil}
        let steps = min(7,Int(abs(accumulated)/60));let direction = accumulated > 0 ? -1:1
        accumulated += Double(direction*steps)*60
        return direction*steps
    }
}
@MainActor final class SevenDayScrollView:NSView {
    var onMove:(Int)->Void = {_ in}
    var monitor:Any?
    var navigation = HorizontalDayNavigation()
    override func hitTest(_ point:NSPoint)->NSView? {nil}
    func install(){
        guard monitor == nil else{return}
        monitor = NSEvent.addLocalMonitorForEvents(matching:.scrollWheel){[weak self] event in
            var consumed = false
            MainActor.assumeIsolated {
                guard let self,let window = self.window,event.window === window,
                      self.bounds.contains(self.convert(event.locationInWindow,from:nil)),!self.isHiddenOrHasHiddenAncestor else{return}
                if event.phase.contains(.began) {self.navigation.reset()}
                let horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)*1.15 && abs(event.scrollingDeltaX) > 0.1
                if let steps = self.navigation.consume(dx:event.scrollingDeltaX,dy:event.scrollingDeltaY,momentum:!event.momentumPhase.isEmpty){self.onMove(steps)}
                if event.phase.contains(.ended) || event.phase.contains(.cancelled) {self.navigation.reset()}
                consumed = horizontal
            }
            return consumed ? nil:event
        }
    }
    func uninstall(){if let monitor {NSEvent.removeMonitor(monitor);self.monitor = nil}}
}
struct SevenDayScrollCapture:NSViewRepresentable {
    var onMove:(Int)->Void
    func makeNSView(context:Context)->SevenDayScrollView {let view = SevenDayScrollView();view.onMove = onMove;view.install();return view}
    func updateNSView(_ view:SevenDayScrollView,context:Context){view.onMove = onMove}
    static func dismantleNSView(_ view:SevenDayScrollView,coordinator:()){view.uninstall()}
}
