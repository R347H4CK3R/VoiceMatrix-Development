import Foundation
@main struct Checks {
    struct Interval: Decodable { let group:Int; let start,end:Double }
    struct Case: Decodable { let durationSeconds:Double; let memberIntervals:[Interval] }
    struct Report: Decodable { let cases:[String:Case] }
    static func main() throws {
        let report=try JSONDecoder().decode(Report.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
        guard let fixture=report.cases["assembledABA"] else {fatalError("Missing real fixture")}
        let segments=fixture.memberIntervals.map {LocalSpeakerPolicy.Segment(speaker:"group_\($0.group)",start:$0.start,end:$0.end)}
        let selected=try LocalSpeakerPolicy.speakerWindows(segments,duration:fixture.durationSeconds)
        guard selected.count==2,selected.allSatisfy({!$0.windows.isEmpty}) else {fatalError("Lost a recovered speaker")}
        try JSONEncoder().encode(selected).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
    }
}
