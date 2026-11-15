import Foundation
@main struct Checks {
    static func main() {
        func frame(_ speech:Double,_ music:Double=0.01,_ singing:Double=0.01)->LocalSoundQualityPolicy.Frame { .init(start:0,end:3,speech:speech,music:music,singing:singing) }
        precondition(!LocalSoundQualityPolicy.evaluate([frame(0.99,0.3)],duration:3).admitted)
        precondition(!LocalSoundQualityPolicy.evaluate([frame(0.99,0.01,0.3)],duration:3).admitted)
        precondition(LocalSoundQualityPolicy.evaluate([frame(0.9)],duration:3).admitted)
        precondition(!LocalSoundQualityPolicy.evaluate([frame(0.01)],duration:3).admitted)
        precondition(!LocalSoundQualityPolicy.evaluate([frame(.nan)],duration:3).admitted)
        precondition(!LocalSoundQualityPolicy.evaluate([],duration:3).admitted)
        let partial=LocalSoundQualityPolicy.Frame(start:0,end:1,speech:0.9,music:0,singing:0)
        precondition(!LocalSoundQualityPolicy.evaluate([partial,partial],duration:3).admitted)
        // Real Apple SoundAnalysis result on the pinned 1.98-second human clip.
        let rounded=LocalSoundQualityPolicy.Frame(start:-0.00025,end:1.97975,speech:0.9765845537185669,music:0.06453053653240204,singing:0.0034785051830112934)
        let short=LocalSoundQualityPolicy.evaluate([rounded],duration:1.98)
        precondition(short.admitted,"Submillisecond classifier clock rounding rejected real speech")
        precondition(abs(short.analyzedCoverage - 1.97975/1.98)<1e-12,"Negative timestamps must not inflate coverage")
        let invalid=LocalSoundQualityPolicy.Frame(start:-0.01,end:1.98,speech:0.99,music:0,singing:0)
        precondition(!LocalSoundQualityPolicy.evaluate([invalid],duration:1.98).admitted)
        let beforeSource=LocalSoundQualityPolicy.Frame(start:-0.0005,end:-0.0001,speech:0.99,music:0,singing:0)
        precondition(!LocalSoundQualityPolicy.evaluate([beforeSource],duration:1.98).admitted)
        print("Independent-score and temporal-coverage policy passed; not classifier accuracy evidence.")
    }
}
