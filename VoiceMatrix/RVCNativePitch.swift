import Foundation

/// Independent experimental window-corrected autocorrelation with temporal tracking.
/// 16 kHz, 60 ms Hann windows, 10 ms grid, 50...1100 Hz. No Praat source bundled.
/// The comparison reference is not ground truth; device and listening unverified.
enum RVCNativePitch {
 enum Failure:Error {case input}
 static func experimentalAutocorrelation(_ audio:[Float],refinePeaks:Bool = false) throws -> [Double] {
  guard (960...147680).contains(audio.count),audio.allSatisfy({$0.isFinite && abs($0)<=1}) else {throw Failure.input}
  struct Candidate {let hz:Double;let cost:Double}
  // At most 918 analysis frames, 923 output frames and 15 candidates/frame.
  // Center only full windows; retain explicit zero padding on the RVC frame grid.
  let count=(audio.count-960)/160+1
  let outputCount=audio.count/160
  let left=(outputCount-count+1)/2
  var output=[Double](repeating:0,count:outputCount)
  let globalPeak=Double(audio.map{abs($0)}.max()!)
  if globalPeak==0 {return output}
  let window=(0..<960).map{0.5-0.5*cos(2*Double.pi*(Double($0)+0.5)/960)}
  let maximumLag=refinePeaks ? 353 : 321
  var windowCorrelation=[Double](repeating:0,count:maximumLag+1)
  for lag in 0...maximumLag {for i in 0..<(960-lag) {windowCorrelation[lag] += window[i]*window[i+lag]}}
  var candidates=[[Candidate]]();candidates.reserveCapacity(count)
  for frame in 0..<count {
   try Task.checkCancellation()
   let center=Double(audio.count-(count-1)*160)/2-0.5+Double(frame*160)
   let start=Int(floor(center-479.5))
   var samples=(0..<960).map{Double(audio[start+$0])}
   let mean=samples.reduce(0,+)/960
   for i in 0..<960 {samples[i]=(samples[i]-mean)*window[i]}
   // Soft silence preference (Boersma 1993, equation 23), with local
   // windowed peak. Preserve pinned 0.03 silence / 0.6 voicing settings.
   let intensity=samples.map{abs($0)}.max()!/globalPeak
   let unvoicedCost=1-(0.6+max(0,2-intensity/(0.03/1.6)))
   var correlation=[Double](repeating:0,count:maximumLag+1)
   let energy=samples.reduce(0){$0+$1*$1}
   if energy<=1e-20 {candidates.append([Candidate(hz:0,cost:0)]);continue}
   for lag in 0...maximumLag {
    var sum=0.0
    for i in 0..<(960-lag) {sum += samples[i]*samples[i+lag]}
    correlation[lag]=sum/energy*windowCorrelation[0]/windowCorrelation[lag]
   }
   var voiced=[Candidate]()
   for k in 15...320 where correlation[k]>0.2 && correlation[k]>=correlation[k-1] && correlation[k]>correlation[k+1] {
    let a=correlation[k-1],b=correlation[k],c=correlation[k+1]
    let denominator=a-2*b+c
    let shift=denominator != 0 ? max(-1,min(1,0.5*(a-c)/denominator)) : 0
    var hz=16000/(Double(k)+shift)
    if refinePeaks {
    // Experimental 32-sample Hann-sinc peak refinement (Boersma 1993,
    // equation 22). Fixed search work; correlation is even at negative lags.
    // Keep parabolic strength/path costs unchanged to isolate frequency error.
    func interpolated(_ x:Double)->Double {
     let low=Int(floor(x)),fraction=x-Double(low)
     if fraction<1e-12 {return correlation[abs(low)]}
     var sum=0.0
     for j in 1...32 {
      let dl=fraction+Double(j-1),dr=1-fraction+Double(j-1)
      let wl=sin(Double.pi*dl)/(Double.pi*dl)*(0.5+0.5*cos(Double.pi*dl/(fraction+32)))
      let wr=sin(Double.pi*dr)/(Double.pi*dr)*(0.5+0.5*cos(Double.pi*dr/(33-fraction)))
      sum += correlation[abs(low+1-j)]*wl+correlation[abs(low+j)]*wr
     }
     return sum
    }
    var lo=Double(k)-0.75,hi=Double(k)+0.75
    let ratio=(sqrt(5.0)-1)/2
    var l=hi-ratio*(hi-lo),r=lo+ratio*(hi-lo)
    var vl=interpolated(l),vr=interpolated(r)
    for _ in 0..<32 {
     if vl<vr {lo=l;l=r;vl=vr;r=lo+ratio*(hi-lo);vr=interpolated(r)}
     else {hi=r;r=l;vr=vl;l=hi-ratio*(hi-lo);vl=interpolated(l)}
    }
    hz=16000/((lo+hi)/2)
    }
    let strength=min(1,b-0.25*(a-c)*shift)
    if hz>=50 && hz<=1100 {voiced.append(Candidate(hz:hz,cost:1-strength+0.01*log2(1100/hz)))}
   }
   voiced.sort{$0.cost == $1.cost ? $0.hz > $1.hz : $0.cost < $1.cost}
   candidates.append([Candidate(hz:0,cost:unvoicedCost)]+voiced.prefix(14))
  }
  var scores=candidates[0].map{$0.cost}
  var back=[[Int]](repeating:[],count:count)
  if count>1 {
   for frame in 1..<count {
    try Task.checkCancellation()
    var next=[Double](repeating:.infinity,count:candidates[frame].count)
    var previous=[Int](repeating:0,count:next.count)
    for j in candidates[frame].indices {
     let current=candidates[frame][j]
     for k in candidates[frame-1].indices {
      let old=candidates[frame-1][k]
      let transition:Double
      if old.hz==0 && current.hz==0 {transition=0}
      else if old.hz==0 || current.hz==0 {transition=0.14}
      else {transition=0.35*abs(log2(current.hz/old.hz))}
      let score=scores[k]+transition+current.cost
      if score<next[j] {next[j]=score;previous[j]=k}
     }
    }
    back[frame]=previous;scores=next
   }
  }
  var selected=scores.indices.min{scores[$0]<scores[$1]}!
  for frame in stride(from:count-1,through:0,by:-1) {
   output[left+frame]=candidates[frame][selected].hz
   if frame>0 {selected=back[frame][selected]}
  }
  return output
 }
}
