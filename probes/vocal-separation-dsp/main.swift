import Foundation

struct ProbeFailure: Error {let message:String}
@main struct Probe {
    static func require(_ condition:Bool,_ message:String) throws {
        if !condition {throw ProbeFailure(message:message)}
    }
    static func reject(_ operation:() throws -> Void) throws {
        var rejected=false
        do {try operation()} catch {rejected=true}
        try require(rejected,"Expected rejection")
    }
    static func read(_ name:String,maximum:Int) throws -> [Float] {
        let url=URL(fileURLWithPath:name)
        let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? -1
        guard size>=0,size<=maximum*4,size%4==0 else {throw ProbeFailure(message:"Input bounds")}
        let bytes=try Data(contentsOf:url)
        return bytes.withUnsafeBytes {raw in
            (0..<(bytes.count/4)).map {Float(bitPattern:UInt32(littleEndian:raw.loadUnaligned(fromByteOffset:$0*4,as:UInt32.self)))}
        }
    }
    static func write(_ values:[Float],_ name:String) throws {
        var data=Data(capacity:values.count*4)
        for value in values {var bits=value.bitPattern.littleEndian;withUnsafeBytes(of:&bits){data.append(contentsOf:$0)}}
        try data.write(to:URL(fileURLWithPath:name),options:.withoutOverwriting)
    }
    static func checks() throws {
        try reject {_ = try VocalSeparationDSP.prepare(left:[],right:[])}
        try reject {_ = try VocalSeparationDSP.prepare(left:[0],right:[])}
        try reject {_ = try VocalSeparationDSP.prepare(left:[.nan],right:[0])}
        try reject {_ = try VocalSeparationDSP.prepare(left:[2],right:[0])}
        try reject {_ = try VocalSeparationDSP.prepare(left:[Float](repeating:0,count:441001),right:[Float](repeating:0,count:441001))}
        let p=try VocalSeparationDSP.prepare(left:[1,0,-1],right:[0,1,0])
        let prediction=[Float](repeating:0,count:VocalSeparationDSP.tensorCount)
        try reject {_ = try VocalSeparationDSP.reconstruct(prepared:p,vocals:[],accompaniment:prediction)}
        var invalid=prediction;invalid[0] = .nan
        try reject {_ = try VocalSeparationDSP.reconstruct(prepared:p,vocals:invalid,accompaniment:prediction)}
        invalid[0] = -1
        try reject {_ = try VocalSeparationDSP.reconstruct(prepared:p,vocals:invalid,accompaniment:prediction)}
        let silence=try VocalSeparationDSP.prepare(left:[0],right:[0])
        let stems=try VocalSeparationDSP.reconstruct(prepared:silence,vocals:prediction,accompaniment:prediction)
        try require(stems.vocalsLeft == [0] && stems.accompanimentRight == [0],"Silence changed")
        withUnsafeCurrentTask {$0?.cancel()}
        try reject {_ = try VocalSeparationDSP.prepare(left:[0],right:[0])}
        try reject {_ = try VocalSeparationDSP.reconstruct(prepared:p,vocals:prediction,accompaniment:prediction)}
    }
    static func main() async {
        do {
            let args=CommandLine.arguments
            if args.count==2,args[1]=="checks" {try checks();print("DSP_CHECKS_PASSED");return}
            guard args.count>=6 else {throw ProbeFailure(message:"Arguments")}
            let p=try VocalSeparationDSP.prepare(left:read(args[2],maximum:441000),right:read(args[3],maximum:441000))
            if args[1]=="prepare",args.count==6 {
                try write(p.magnitudes,args[4])
                let metadata=["originalFrames":p.originalFrames,"frameCount":p.frameCount,"sampleRate":44100]
                try JSONEncoder().encode(metadata).write(to:URL(fileURLWithPath:args[5]),options:.withoutOverwriting)
            } else if args[1]=="reconstruct",args.count==7 {
                let stems=try VocalSeparationDSP.reconstruct(prepared:p,
                    vocals:read(args[4],maximum:VocalSeparationDSP.tensorCount),accompaniment:read(args[5],maximum:VocalSeparationDSP.tensorCount))
                for (name,data) in [("vocals-left",stems.vocalsLeft),("vocals-right",stems.vocalsRight),
                                    ("accompaniment-left",stems.accompanimentLeft),("accompaniment-right",stems.accompanimentRight)] {
                    try write(data,args[6]+"-"+name+".f32")
                }
            } else {throw ProbeFailure(message:"Unknown operation")}
            print("DSP_OPERATION_PASSED")
        } catch {FileHandle.standardError.write(Data("DSP_FAILED \(error)\n".utf8));exit(1)}
    }
}
