import Foundation

struct RVCPreviewState {
    enum Kind {case assetImport,audioImport,conversion}
    enum Phase {case idle,working,cancelling,succeeded,cancelled,failed}
    enum Outcome {case succeeded,cancelled,failed}
    enum Failure:Error {case busy}
    struct Event:Identifiable {let id=UUID();let date=Date();let message:String}
    private(set) var phase:Phase = .idle
    private(set) var kind:Kind?
    private(set) var percent:Int?
    private(set) var ticket:UUID?
    private(set) var events:[Event]=[]
    var busy:Bool {phase == .working || phase == .cancelling}
    func mayStart(assets:Bool,input:Bool,foreground:Bool,audioAvailable:Bool)->Bool {
        !busy && assets && input && foreground && audioAvailable
    }
    mutating func begin(_ kind:Kind) throws -> UUID {
        guard !busy else {throw Failure.busy}
        let next=UUID();ticket=next;self.kind=kind;phase = .working;percent=kind == .conversion ? 0 : nil
        return next
    }
    mutating func progress(_ fraction:Double,ticket:UUID) {
        guard self.ticket==ticket,phase == .working,kind == .conversion,fraction.isFinite else {return}
        percent=max(percent ?? 0,min(99,max(0,Int((min(1,max(0,fraction))*100).rounded()))))
    }
    mutating func requestCancel() {if phase == .working {phase = .cancelling}}
    mutating func finish(_ outcome:Outcome,ticket:UUID) {
        guard self.ticket==ticket,busy else {return}
        if phase == .cancelling {phase = .cancelled;return}
        switch outcome {
        case .succeeded:phase = .succeeded;if kind == .conversion {percent=100}
        case .cancelled:phase = .cancelled
        case .failed:phase = .failed
        }
    }
    mutating func append(_ text:String) {
        events.append(Event(message:String(text.prefix(512))))
        if events.count>100 {events.removeFirst(events.count-100)}
    }
    static func validPackFolder(_ value:String)->Bool {
        value.hasPrefix("rvc-") && UUID(uuidString:String(value.dropFirst(4))) != nil
    }
}
