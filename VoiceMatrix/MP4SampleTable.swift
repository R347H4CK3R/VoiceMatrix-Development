import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Deliberately narrow ISO-BMFF demuxer. Reads original packet bytes, never asks
/// AVFoundation to retime, group or trim samples. Unsupported structures fail closed.
final class MP4SampleTable {
    enum Failure: Error { case unsupported, bounds, changed }
    struct Sample {
        let offset: Int64; let size: Int; let timestamp: Double; let duration: Double; let key: Bool
        let discardPaddingNanoseconds: UInt64
        init(offset: Int64, size: Int, timestamp: Double, duration: Double, key: Bool, discardPaddingNanoseconds: UInt64 = 0) {
            self.offset=offset;self.size=size;self.timestamp=timestamp;self.duration=duration;self.key=key
            self.discardPaddingNanoseconds=discardPaddingNanoseconds
        }
    }
    struct Track { let configuration: Data; let width: Int; let height: Int; let sampleRate: Double; let channels: Int; let samples: [Sample]; let seekPreRoll: Double }
    let video: Track
    let audio: Track
    let duration: Double
    private let reader: Reader
    private static let maximumSamples = 300_000
    private struct Box { let type: String; let data: Data }

    init(url: URL) throws {
        let r = try Reader(url)
        let deadline=Date().addingTimeInterval(180)
        var cursor: Int64 = 0, moov: Data?, media: [Range<Int64>] = []
        var fileType = false, boxCount = 0
        while cursor < r.size {
            try Task.checkCancellation()
            boxCount += 1; guard boxCount <= 4096, r.size-cursor >= 8 else { throw Failure.bounds }
            let h = try r.read(offset:cursor,count:Int(min(16,r.size-cursor)))
            let short = try Self.u32(h,0), type = try Self.text(h,4)
            let header: Int64 = short == 1 ? 16 : 8
            let size: Int64
            if short == 1 { let large = try Self.u64(h,8); guard large <= UInt64(Int64.max) else { throw Failure.bounds };size=Int64(large) }
            else if short == 0 { size = r.size-cursor }
            else { size = Int64(short) }
            guard size >= header, size <= r.size-cursor else { throw Failure.bounds }
            let body = (cursor+header)..<(cursor+size)
            switch type {
            case "ftyp": guard !fileType, body.count >= 8, body.count <= 4096 else { throw Failure.unsupported };fileType=true
            case "moov": guard moov == nil, body.count <= 16_777_216 else { throw Failure.bounds }; moov=try r.read(offset:body.lowerBound,count:Int(body.count))
            case "mdat": guard body.count > 0, media.count < 16 else { throw Failure.bounds }; media.append(body)
            case "free", "skip", "wide": break
            default: throw Failure.unsupported
            }
            cursor += size
        }
        guard fileType, let moov, !media.isEmpty else { throw Failure.unsupported }
        let children = try Self.boxes(moov)
        guard !children.contains(where: { ["mvex","cmov"].contains($0.type) }) else { throw Failure.unsupported }
        let movie = try Self.one(children,"mvhd").data
        let movieVersion = try Self.u8(movie,0)
        guard movieVersion <= 1 else { throw Failure.unsupported }
        let movieScale = try Self.u32(movie,movieVersion == 0 ? 12:20)
        guard movieScale > 0, try Self.u32(movie,movieVersion == 0 ? 20:32)==0x00010000 else { throw Failure.unsupported }
        let traks = children.filter { $0.type == "trak" }
        guard traks.count == 2 else { throw Failure.unsupported }
        var v: Track?, a: Track?
        for trak in traks {
            let parsed = try Self.parseTrack(trak.data,media:media,movieScale:movieScale,deadline:deadline)
            if parsed.0 == "vide" { guard v == nil else { throw Failure.unsupported };v=parsed.1 }
            else { guard a == nil else { throw Failure.unsupported };a=parsed.1 }
        }
        guard let v, let a, v.samples.count+a.samples.count <= Self.maximumSamples else { throw Failure.bounds }
        let all = (v.samples+a.samples).sorted { $0.offset < $1.offset }
        var lastEnd: Int64 = 0
        for sample in all { guard sample.offset >= lastEnd else { throw Failure.unsupported };lastEnd=sample.offset+Int64(sample.size) }
        let vd = v.samples.last.map { $0.timestamp+$0.duration } ?? 0
        let ad = a.samples.last.map { $0.timestamp+$0.duration } ?? 0
        let length = max(vd,ad)
        guard length.isFinite, (3...1800).contains(length), abs(vd-ad)<=0.25 else { throw Failure.unsupported }
        try r.verify()
        reader=r;video=v;audio=a;duration=length
    }
    func read(_ sample: Sample) throws -> Data { try reader.read(offset:sample.offset,count:sample.size) }
    func verifyUnchanged() throws { try reader.verify() }

    private static func parseTrack(_ data: Data, media: [Range<Int64>], movieScale: UInt32, deadline:Date) throws -> (String,Track) {
        let track = try boxes(data), tkhd = try one(track,"tkhd").data
        let version = try u8(tkhd,0); guard version <= 1 else { throw Failure.unsupported }
        let matrix = version == 0 ? 40:52
        let identity: [UInt32] = [0x10000,0,0,0,0x10000,0,0,0,0x40000000]
        for i in 0..<9 { guard try u32(tkhd,matrix+i*4) == identity[i] else { throw Failure.unsupported } }
        let trackWidth = try u32(tkhd,matrix+36), trackHeight = try u32(tkhd,matrix+40)
        let mdia = try boxes(one(track,"mdia").data)
        let mdhd = try one(mdia,"mdhd").data, mv = try u8(mdhd,0)
        guard mv <= 1 else { throw Failure.unsupported }
        let scale = try u32(mdhd,mv == 0 ? 12:20)
        let mediaDuration = mv == 0 ? UInt64(try u32(mdhd,16)) : try u64(mdhd,24)
        guard scale > 0, mediaDuration > 0, Double(mediaDuration)/Double(scale)<=1800 else { throw Failure.bounds }
        let kind = try text(one(mdia,"hdlr").data,8)
        guard kind == "vide" || kind == "soun" else { throw Failure.unsupported }
        if let edit = try optional(track,"edts") {
            let elst = try one(boxes(edit.data),"elst").data
            // One identity edit only. Trimming/offsets/empty edits need a different mapping.
            guard try u32(elst,0) == 0, try u32(elst,4) == 1, elst.count == 20,
                  try u32(elst,12) == 0, try u32(elst,16) == 0x00010000 else { throw Failure.unsupported }
            let editDuration = try u32(elst,8)
            guard abs(Double(editDuration)/Double(movieScale)-Double(mediaDuration)/Double(scale)) <= 1/Double(movieScale) else { throw Failure.unsupported }
        }
        let minf = try boxes(one(mdia,"minf").data)
        let dref = try one(boxes(one(minf,"dinf").data),"dref").data
        guard try u32(dref,0)==0, try u32(dref,4)==1 else { throw Failure.unsupported }
        let references=try boxes(Data(dref.dropFirst(8)))
        guard references.count==1, references[0].type=="url ", references[0].data.count==4,
              try u32(references[0].data,0)==1 else { throw Failure.unsupported }
        let stbl = try boxes(one(minf,"stbl").data)
        let allowed: Set<String> = ["stsd","stts","stsc","stsz","stco","co64","stss","ctts","sgpd","sbgp","free"]
        guard stbl.allSatisfy({ allowed.contains($0.type) }) else { throw Failure.unsupported }
        let stsd = try one(stbl,"stsd").data
        guard try u32(stsd,0)==0, try u32(stsd,4)==1 else { throw Failure.unsupported }
        let entries = try boxes(Data(stsd.dropFirst(8)))
        guard entries.count==1 else { throw Failure.unsupported }
        let entry=entries[0], e=entry.data
        guard try u16(e,6)==1 else { throw Failure.unsupported }
        let config: Data, width: Int, height: Int, rate: Double, channels: Int
        if kind=="vide" {
            guard entry.type=="avc1", e.count>=78 else { throw Failure.unsupported }
            width=Int(try u16(e,24));height=Int(try u16(e,26));rate=0;channels=0
            guard (1...1280).contains(width),(1...720).contains(height),trackWidth==UInt32(width)<<16,trackHeight==UInt32(height)<<16 else { throw Failure.unsupported }
            let atoms=try boxes(Data(e.dropFirst(78)))
            guard atoms.allSatisfy({ ["avcC","pasp","btrt"].contains($0.type) }) else { throw Failure.unsupported }
            if let pasp=try optional(atoms,"pasp") { guard pasp.data.count==8,try u32(pasp.data,0)>0,try u32(pasp.data,0)==u32(pasp.data,4) else { throw Failure.unsupported } }
            config=try one(atoms,"avcC").data
            guard config.count>=7,config.count<=65536,config[0]==1,(config[4]&3)==3 else { throw Failure.unsupported }
        } else {
            guard entry.type=="mp4a",e.count>=28,try u16(e,8)==0,trackWidth==0,trackHeight==0 else { throw Failure.unsupported }
            width=0;height=0;let entryChannels=Int(try u16(e,16));rate=Double(try u32(e,24))/65536
            guard (1...2).contains(entryChannels), rate>=7350,rate<=96000,try u16(e,18)==16 else { throw Failure.unsupported }
            let atoms=try boxes(Data(e.dropFirst(28)))
            guard atoms.allSatisfy({ ["esds","btrt"].contains($0.type) }) else { throw Failure.unsupported }
            config=try aacConfig(one(atoms,"esds").data)
            channels=Int((config[1]>>3)&15)
            guard (1...2).contains(channels),entryChannels==channels || entryChannels==2 else { throw Failure.unsupported }
            let rates:[Double]=[96000,88200,64000,48000,44100,32000,24000,22050,16000,12000,11025,8000,7350]
            guard let ri=rates.firstIndex(of:rate) else { throw Failure.unsupported }
            let bits=UInt16((2<<11)|(ri<<7)|(channels<<3)), expected=Data([UInt8(bits>>8),UInt8(bits&255)])
            guard config==expected || config==expected+Data([0x56,0xe5,0x00]) else { throw Failure.unsupported }
        }
        let sizes=try one(stbl,"stsz").data
        guard try u32(sizes,0)==0 else { throw Failure.unsupported }
        let defaultSize=try u32(sizes,4), count=Int(try u32(sizes,8))
        guard count>0,count<=maximumSamples,sizes.count==12+(defaultSize==0 ? count*4:0) else { throw Failure.bounds }
        var seekPreRoll:Double=0
        let groupDescription=try optional(stbl,"sgpd"), groupMapping=try optional(stbl,"sbgp")
        if groupDescription != nil || groupMapping != nil {
            guard kind=="soun",let sgpd=groupDescription?.data,let sbgp=groupMapping?.data,
                  sgpd.count==18,try u32(sgpd,0)==0x01000000,try text(sgpd,4)=="roll",
                  try u32(sgpd,8)==2,try u32(sgpd,12)==1,try u16(sgpd,16)==0xffff,
                  sbgp.count==20,try u32(sbgp,0)==0,try text(sbgp,4)=="roll",try u32(sbgp,8)==1,
                  try u32(sbgp,12)==UInt32(count),try u32(sbgp,16)==1 else { throw Failure.unsupported }
            // Exact AAC-LC roll recovery of one 1024-sample packet, not a timeline trim.
            seekPreRoll=1024/rate
        }
        var sampleSizes:[Int]=[];sampleSizes.reserveCapacity(count)
        for i in 0..<count { let size=Int(defaultSize==0 ? try u32(sizes,12+i*4):defaultSize);guard size>0,size<=16_777_216 else { throw Failure.bounds };sampleSizes.append(size) }
        let times=try rows(one(stbl,"stts").data,width:8)
        var durations:[UInt32]=[];durations.reserveCapacity(count);var total:UInt64=0
        for row in times { let n=Int(try u32(row,0)), delta=try u32(row,4);guard n>0,n<=count-durations.count,delta>0 else { throw Failure.bounds };durations += Array(repeating:delta,count:n);total += UInt64(n)*UInt64(delta) }
        guard durations.count==count,total==mediaDuration else { throw Failure.unsupported }
        var finalPaddingNanoseconds:UInt64=0
        if kind=="soun" {
            // Supported ASC is AAC-LC with frameLengthFlag=0: each coded packet
            // decodes to 1024 frames. Only the final stts entry may shorten output.
            // Keep all compressed bytes; the muxer represents the tail as DiscardPadding.
            let integerRate=UInt64(rate)
            for (i,delta) in durations.enumerated() {
                if i % 1024 == 0 { try Task.checkCancellation();guard Date()<deadline else { throw Failure.bounds } }
                let numerator=UInt64(delta)*integerRate
                guard numerator % UInt64(scale)==0 else { throw Failure.unsupported }
                let frames=numerator/UInt64(scale)
                guard frames>0,frames<=1024,i==count-1 || frames==1024 else { throw Failure.unsupported }
                if i==count-1 {
                    // Integer nearest-nanosecond rounding; products are bounded by1023e9.
                    finalPaddingNanoseconds=((1024-frames)*1_000_000_000+integerRate/2)/integerRate
                }
            }
        }
        if let ctts=try optional(stbl,"ctts") { var covered=0;for row in try rows(ctts.data,width:8) { let n=Int(try u32(row,0));guard n>0,n<=count-covered,try u32(row,4)==0 else { throw Failure.unsupported };covered += n };guard covered==count else { throw Failure.unsupported } }
        var sync=Set<Int>()
        if let stss=try optional(stbl,"stss") { var prev=0;for row in try rows(stss.data,width:4) { let n=Int(try u32(row,0));guard n>prev,n<=count else { throw Failure.unsupported };sync.insert(n-1);prev=n };guard kind=="vide",sync.contains(0) else { throw Failure.unsupported } }
        else { sync=Set(0..<count) }
        let offsets32=try optional(stbl,"stco"), offsets64=try optional(stbl,"co64")
        guard (offsets32==nil) != (offsets64==nil) else { throw Failure.unsupported }
        let offsets=try rows((offsets32 ?? offsets64!).data,width:offsets32==nil ? 8:4).map { row -> Int64 in
            let n=offsets32==nil ? try u64(row,0):UInt64(try u32(row,0));guard n<=536_870_912 else { throw Failure.bounds };return Int64(n)
        }
        guard !offsets.isEmpty,offsets.count<=count else { throw Failure.bounds }
        let chunks=try rows(one(stbl,"stsc").data,width:12)
        guard !chunks.isEmpty,try u32(chunks[0],0)==1 else { throw Failure.unsupported }
        var mappings:[(Int,Int)]=[];var last=0
        for row in chunks { let first=Int(try u32(row,0)),n=Int(try u32(row,4));guard first>last,first<=offsets.count,n>0,n<=count,try u32(row,8)==1 else { throw Failure.unsupported };mappings.append((first,n));last=first }
        var result:[Sample]=[];result.reserveCapacity(count);var run=0,clock:UInt64=0
        for chunk in 1...offsets.count {
            try Task.checkCancellation()
            if run+1<mappings.count,chunk==mappings[run+1].0 { run += 1 }
            let n=mappings[run].1;guard n<=count-result.count else { throw Failure.unsupported }
            var offset=offsets[chunk-1]
            for _ in 0..<n { let i=result.count,size=sampleSizes[i];if i % 1024 == 0 { try Task.checkCancellation();guard Date()<deadline else { throw Failure.bounds } };guard media.contains(where: { offset >= $0.lowerBound && offset <= $0.upperBound-Int64(size) }) else { throw Failure.bounds }
                result.append(Sample(offset:offset,size:size,timestamp:Double(clock)/Double(scale),duration:Double(durations[i])/Double(scale),key:sync.contains(i),discardPaddingNanoseconds:i==count-1 ? finalPaddingNanoseconds:0))
                offset += Int64(size);clock += UInt64(durations[i])
            }
        }
        guard result.count==count else { throw Failure.unsupported }
        return (kind,Track(configuration:config,width:width,height:height,sampleRate:rate,channels:channels,samples:result,seekPreRoll:seekPreRoll))
    }
    private static func one(_ boxes: [Box], _ type: String) throws -> Box { guard let value=try optional(boxes,type) else { throw Failure.unsupported };return value }
    private static func optional(_ boxes: [Box], _ type: String) throws -> Box? { let values=boxes.filter{$0.type==type};guard values.count<=1 else { throw Failure.unsupported };return values.first }
    private static func boxes(_ data: Data) throws -> [Box] {
        var result:[Box]=[],p=0
        while p<data.count {
            try Task.checkCancellation()
            guard data.count-p>=8,result.count<4096 else { throw Failure.bounds }
            let n=try u32(data,p), type=try text(data,p+4);var header=8
            let length:Int
            if n==1 { header=16;let value=try u64(data,p+8);guard value<=UInt64(data.count-p) else { throw Failure.bounds };length=Int(value) }
            else { guard n>=8 else { throw Failure.unsupported };length=Int(n) }
            guard length>=header,length<=data.count-p else { throw Failure.bounds }
            result.append(Box(type:type,data:Data(data[(p+header)..<(p+length)])));p += length
        }
        return result
    }
    private static func rows(_ data:Data,width:Int) throws -> [Data] {
        guard try u32(data,0)==0 else { throw Failure.unsupported }
        let n=Int(try u32(data,4));guard n>0,n<=maximumSamples,data.count==8+n*width else { throw Failure.bounds }
        return (0..<n).map { Data(data[(8+$0*width)..<(8+($0+1)*width)]) }
    }
    private static func u8(_ data:Data,_ p:Int) throws -> UInt8 { guard p>=0,p<data.count else { throw Failure.bounds };return data[p] }
    private static func u16(_ data:Data,_ p:Int) throws -> UInt16 { UInt16(try u8(data,p))<<8 | UInt16(try u8(data,p+1)) }
    private static func u32(_ data:Data,_ p:Int) throws -> UInt32 { UInt32(try u16(data,p))<<16 | UInt32(try u16(data,p+2)) }
    private static func u64(_ data:Data,_ p:Int) throws -> UInt64 { UInt64(try u32(data,p))<<32 | UInt64(try u32(data,p+4)) }
    private static func text(_ data:Data,_ p:Int) throws -> String { guard p>=0,p<=data.count-4,let text=String(data:data[p..<(p+4)],encoding:.ascii) else { throw Failure.bounds };return text }
    private static func aacConfig(_ data:Data) throws -> Data {
        func descriptor(_ offset:Int,_ end:Int) throws -> (UInt8,Int,Int) {
            guard offset<end else { throw Failure.unsupported };let tag=try u8(data,offset);var p=offset+1,n=0,done=false
            for _ in 0..<4 { guard p<end else { throw Failure.unsupported };let b=try u8(data,p);p += 1;n=(n<<7)|Int(b&127);if b&128==0 {done=true;break} }
            guard done,n<=end-p else { throw Failure.bounds };return(tag,p,p+n)
        }
        guard try u32(data,0)==0 else { throw Failure.unsupported }
        let es=try descriptor(4,data.count);guard es.0==3,es.2-es.1>=3,try u8(data,es.1+2)==0 else { throw Failure.unsupported }
        let decoder=try descriptor(es.1+3,es.2);guard decoder.0==4,decoder.2-decoder.1>=13,try u8(data,decoder.1)==0x40 else { throw Failure.unsupported }
        let config=try descriptor(decoder.1+13,decoder.2);guard config.0==5,(2...5).contains(config.2-config.1) else { throw Failure.unsupported }
        return Data(data[config.1..<config.2])
    }
    private final class Reader {
        let size:Int64
        let handle:FileHandle
        let url:URL
        let original:stat
        private let deadline=Date().addingTimeInterval(180)
        init(_ url:URL) throws {
            guard url.isFileURL else { throw Failure.unsupported }
            let fd=open(url.path,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC)
            guard fd>=0 else { throw Failure.changed }
            let h=FileHandle(fileDescriptor:fd,closeOnDealloc:true)
            var info=stat()
            guard fstat(fd,&info)==0,info.st_mode & mode_t(S_IFMT)==mode_t(S_IFREG),info.st_size>0,info.st_size<=536_870_912 else { try? h.close();throw Failure.bounds }
            self.url=url;handle=h;original=info;size=Int64(info.st_size)
            try verify()
        }
        deinit { try? handle.close() }
        func read(offset:Int64,count:Int) throws -> Data {
            try Task.checkCancellation();try verify()
            guard count>0,count<=16_777_216,offset>=0,offset<=size-Int64(count) else { throw Failure.bounds }
            try handle.seek(toOffset:UInt64(offset))
            guard let data=try handle.read(upToCount:count),data.count==count else { throw Failure.changed }
            try verify();return data
        }
        func verify() throws {
            try Task.checkCancellation()
            guard Date()<deadline else { throw Failure.bounds }
            var current=stat(),named=stat()
            guard fstat(handle.fileDescriptor,&current)==0,lstat(url.path,&named)==0,
                  named.st_mode & mode_t(S_IFMT)==mode_t(S_IFREG),
                  current.st_dev==original.st_dev,current.st_ino==original.st_ino,current.st_size==original.st_size,
                  named.st_dev==original.st_dev,named.st_ino==original.st_ino,named.st_size==original.st_size,
                  Self.sameTimes(original,current),Self.sameTimes(original,named) else { throw Failure.changed }
        }
        private static func sameTimes(_ a:stat,_ b:stat)->Bool {
#if canImport(Darwin)
            return a.st_mtimespec.tv_sec==b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec==b.st_mtimespec.tv_nsec && a.st_ctimespec.tv_sec==b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec==b.st_ctimespec.tv_nsec
#else
            return a.st_mtim.tv_sec==b.st_mtim.tv_sec && a.st_mtim.tv_nsec==b.st_mtim.tv_nsec && a.st_ctim.tv_sec==b.st_ctim.tv_sec && a.st_ctim.tv_nsec==b.st_ctim.tv_nsec
#endif
        }
    }
}
