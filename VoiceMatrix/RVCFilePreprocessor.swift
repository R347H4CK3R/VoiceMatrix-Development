import Foundation

enum RVCFileError: Error { case format, bounds, destination, nonfinite }

enum RVCFileIO {
    static func create(_ url:URL) throws -> FileHandle {
        try Data().write(to:url,options:.withoutOverwriting)
        return try FileHandle(forWritingTo:url)
    }
    static func write<T>(_ values:[T], to handle:FileHandle) throws {
        try values.withUnsafeBytes {try handle.write(contentsOf:Data($0))}
    }
}

/// Restricted, bounded PCM16 mono WAV reader. Other formats require explicit decoding.
final class RVCPCMReader {
    let handle:FileHandle
    let samples:Int
    let rate:Int
    let offset:UInt64
    private var cache:[Int:[Float]]=[:]
    init(_ url:URL) throws {
        let attrs=try FileManager.default.attributesOfItem(atPath:url.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular,
              let number=attrs[.size] as? NSNumber, number.int64Value <= 800_000_000 else {throw RVCFileError.format}
        handle=try FileHandle(forReadingFrom:url)
        let h=try handle.read(upToCount:12) ?? Data()
        func u32(_ d:Data,_ at:Int)->Int {Int(d.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:at,as:UInt32.self)}.littleEndian)}
        func u16(_ d:Data,_ at:Int)->Int {Int(d.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:at,as:UInt16.self)}.littleEndian)}
        guard h.count==12, String(data:h.prefix(4),encoding:.ascii)=="RIFF",
              String(data:h.suffix(4),encoding:.ascii)=="WAVE" else {throw RVCFileError.format}
        let end=u32(h,4)+8
        guard end <= number.intValue, end>=44 else {throw RVCFileError.format}
        var position=12;var foundRate:Int?;var foundData:(UInt64,Int)?
        var chunks=0
        while position+8<=end {
            chunks += 1;guard chunks<=128 else {throw RVCFileError.format}
            try handle.seek(toOffset:UInt64(position))
            let header=try handle.read(upToCount:8) ?? Data()
            guard header.count==8 else {throw RVCFileError.format}
            let size=u32(header,4);let name=String(data:header.prefix(4),encoding:.ascii)
            guard size<=end-position-8 else {throw RVCFileError.format}
            if name=="fmt " {
                guard foundRate==nil, size>=16, size<=64 else {throw RVCFileError.format}
                let fmt=try handle.read(upToCount:16) ?? Data()
                guard fmt.count==16 else {throw RVCFileError.format}
                let r=u32(fmt,4)
                guard u16(fmt,0)==1,u16(fmt,2)==1,u16(fmt,14)==16,u16(fmt,12)==2,
                      [16000,24000,44100,48000].contains(r),u32(fmt,8)==r*2 else {throw RVCFileError.format}
                foundRate=r
            } else if name=="data" {
                guard foundData==nil,size%2==0 else {throw RVCFileError.format}
                foundData=(UInt64(position+8),size/2)
            }
            position += 8+size+(size%2)
        }
        guard let r=foundRate,let data=foundData,data.1>=1,data.1<=r*7200 else {throw RVCFileError.bounds}
        rate=r;offset=data.0;samples=data.1
    }
    deinit {try? handle.close()}
    func sample(_ index:Int) throws -> Double {
        if index<0 || index>=samples {return 0}
        let block=index/16384
        if cache[block]==nil {
            try handle.seek(toOffset:offset+UInt64(block*16384*2))
            let count=min(16384,samples-block*16384)
            let bytes=try handle.read(upToCount:count*2) ?? Data()
            guard bytes.count==count*2 else {throw RVCFileError.format}
            let values=bytes.withUnsafeBytes {raw in (0..<count).map{Float(Int16(littleEndian:raw.loadUnaligned(fromByteOffset:$0*2,as:Int16.self)))/32768}}
            if cache.count>=2 {cache.removeValue(forKey:cache.keys.min()!)}
            cache[block]=values
        }
        return Double(cache[block]![index%16384])
    }
}

final class RVCFloatReader {
    let handle:FileHandle
    let samples:Int
    init(_ url:URL,samples:Int) throws {handle=try FileHandle(forReadingFrom:url);self.samples=samples}
    deinit {try? handle.close()}
    func read(_ start:Int,_ count:Int) throws -> [Float] {
        guard start>=0,count>=0,count<=147680,start+count<=samples else {throw RVCFileError.bounds}
        try handle.seek(toOffset:UInt64(start*4))
        let bytes=try handle.read(upToCount:count*4) ?? Data()
        guard bytes.count==count*4 else {throw RVCFileError.format}
        return bytes.withUnsafeBytes{raw in (0..<count).map{raw.loadUnaligned(fromByteOffset:$0*4,as:Float.self)}}
    }
    func window(plan:RVCChunkPlan,index:Int) throws -> [Float] {
        let ids=try (0..<147680).map{try plan.reflectedInputIndex(chunk:index,offset:$0)}
        let lo=ids.min()!,hi=ids.max()!
        let values=try read(lo,hi-lo+1)
        return ids.map{values[$0-lo]}
    }
}

enum RVCFilePreprocessor {
    struct Prepared {let url:URL;let samples:Int;let inputGain:Float;let peakBeforeGain:Float}
    private static func gcd(_ a:Int,_ b:Int)->Int {var x=a,y=b;while y != 0 {(x,y)=(y,x%y)};return x}
    private static func i0(_ x:Double)->Double {
        var term=1.0,sum=1.0
        for k in 1...40 {term *= x*x/(4*Double(k*k));sum += term;if term<sum*1e-16 {break}}
        return sum
    }
    static func prepare(input:URL,directory:URL) throws -> Prepared {
        let source=try RVCPCMReader(input)
        let g=gcd(source.rate,16000),up=16000/g,down=source.rate/g
        let count=(source.samples*up+down-1)/down
        _=try RVCChunkPlan(inputSamples:count)
        let resampled=directory.appendingPathComponent("resampled.f32")
        let writer=try RVCFileIO.create(resampled)
        defer {try? writer.close()}
        let maximum=max(up,down),half=10*maximum
        var kernel=[Double](repeating:0,count:2*half+1)
        if up != down {
            for i in kernel.indices {
                let x=Double(i-half),ratio=x/Double(half)
                let sinc=x==0 ? 1/Double(maximum) : sin(Double.pi*x/Double(maximum))/(Double.pi*x)
                kernel[i]=sinc*i0(5*sqrt(max(0,1-ratio*ratio)))/i0(5)
            }
            let sum=kernel.reduce(0,+)
            kernel=kernel.map{$0*Double(up)/sum}
        }
        var block:[Float]=[];block.reserveCapacity(16384)
        for k in 0..<count {
            if k%16384==0 {try Task.checkCancellation()}
            var value:Double=0
            if up==down {value=try source.sample(k)}
            else {
                let center=k*down+half
                let first=max(0,(center-2*half+up-1)/up)
                let last=min(source.samples-1,center/up)
                if first<=last {
                    for n in first...last {value += try source.sample(n)*kernel[center-n*up]}
                }
            }
            guard value.isFinite else {throw RVCFileError.nonfinite}
            block.append(Float(value))
            if block.count==16384 {try RVCFileIO.write(block,to:writer);block.removeAll(keepingCapacity:true)}
        }
        if !block.isEmpty {try RVCFileIO.write(block,to:writer)}
        try writer.synchronize()
        let raw=try RVCFloatReader(resampled,samples:count)
        let first=try raw.read(0,19),last=try raw.read(count-19,19)
        let forward=directory.appendingPathComponent("filter-forward.f64")
        let forwardWriter=try RVCFileIO.create(forward)
        defer {try? forwardWriter.close()}
        var filter=Filter(initial:2*Double(first[0])-Double(first[18]))
        var values:[Double]=[]
        for i in stride(from:18,through:1,by:-1) {values.append(filter.next(2*Double(first[0])-Double(first[i])))}
        try RVCFileIO.write(values,to:forwardWriter)
        for start in stride(from:0,to:count,by:16384) {
            try Task.checkCancellation()
            values=try raw.read(start,min(16384,count-start)).map{filter.next(Double($0))}
            try RVCFileIO.write(values,to:forwardWriter)
        }
        values=[]
        for i in stride(from:17,through:0,by:-1) {values.append(filter.next(2*Double(last[18])-Double(last[i])))}
        try RVCFileIO.write(values,to:forwardWriter);try forwardWriter.synchronize()
        let reverse=try FileHandle(forReadingFrom:forward)
        defer {try? reverse.close()}
        let output=directory.appendingPathComponent("prepared.f32")
        let outputWriter=try RVCFileIO.create(output)
        defer {try? outputWriter.close()}
        try reverse.seek(toOffset:UInt64((count+35)*8))
        let ending=try reverse.read(upToCount:8) ?? Data()
        guard ending.count==8 else {throw RVCFileError.format}
        filter=Filter(initial:ending.withUnsafeBytes{$0.loadUnaligned(as:Double.self)})
        var peak:Float=0
        var end=count+36
        while end>0 {
            try Task.checkCancellation()
            let begin=max(0,end-16384)
            try reverse.seek(toOffset:UInt64(begin*8))
            let data=try reverse.read(upToCount:(end-begin)*8) ?? Data()
            guard data.count==(end-begin)*8 else {throw RVCFileError.format}
            let inputValues=data.withUnsafeBytes{raw in (0..<(end-begin)).map{raw.loadUnaligned(fromByteOffset:$0*8,as:Double.self)}}
            var selected:[Float]=[]
            for local in inputValues.indices.reversed() {
                let value=filter.next(inputValues[local]),position=begin+local
                guard value.isFinite else {throw RVCFileError.nonfinite}
                if position>=18 && position<count+18 {
                    let sample=Float(value)
                    guard sample.isFinite else {throw RVCFileError.nonfinite}
                    peak=max(peak,abs(sample))
                    selected.append(sample)
                }
            }
            if !selected.isEmpty {
                try outputWriter.seek(toOffset:UInt64((max(begin,18)-18)*4))
                try RVCFileIO.write(Array(selected.reversed()),to:outputWriter)
            }
            end=begin
        }
        try outputWriter.synchronize()
        // Resampling/filtering can overshoot normalized PCM. Preserve shape with
        // one global attenuation, never per-block scaling or hard clipping.
        let inputGain:Float=peak>1 ? 0.99/peak : 1
        if inputGain<1 {
            let preparedReader=try RVCFloatReader(output,samples:count)
            for start in stride(from:0,to:count,by:16384) {
                try Task.checkCancellation()
                let scaled=try preparedReader.read(start,min(16384,count-start)).map{$0*inputGain}
                guard scaled.allSatisfy({$0.isFinite && abs($0)<=1}) else {throw RVCFileError.nonfinite}
                try outputWriter.seek(toOffset:UInt64(start*4))
                try RVCFileIO.write(scaled,to:outputWriter)
            }
            try outputWriter.synchronize()
        }
        return Prepared(url:output,samples:count,inputGain:inputGain,peakBeforeGain:peak)
    }
    /// SciPy butter(5,48,high,fs=16000), direct-form II transposed.
    private struct Filter {
        let b=[0.9699606451838447,-4.849803225919223,9.699606451838447,-9.699606451838447,4.849803225919223,-0.9699606451838447]
        let a=[1.0,-4.939001819168364,9.757863526739543,-9.639544849413458,4.761506797356209,-0.9408236532054606]
        var z:[Double]
        init(initial:Double) {z=[-0.9699604796995847,3.8798419288925783,-5.819762908173043,3.879841948472456,-0.9699604894923387].map{$0*initial}}
        mutating func next(_ x:Double)->Double {
            let y=b[0]*x+z[0]
            for i in 0..<4 {z[i]=z[i+1]+b[i+1]*x-a[i+1]*y}
            z[4]=b[5]*x-a[5]*y
            return y
        }
    }
}
