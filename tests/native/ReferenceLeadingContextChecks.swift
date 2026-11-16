import Foundation
@main struct ReferenceLeadingContextChecks {
 static func main() {
  for rate in [16000.0,24000.0,44100.0,48000.0] {
   precondition(BundledASRPolicy.referenceLeadingFrameCount(frames:Int(rate),sampleRate:rate)==Int((rate*0.25).rounded()))
   precondition(BundledASRPolicy.referenceLeadingFrameCount(frames:Int(rate*30),sampleRate:rate)==nil)
  }
  for rate in [Double.nan,Double.infinity,0,15999,48001] { precondition(BundledASRPolicy.referenceLeadingFrameCount(frames:16000,sampleRate:rate)==nil) }
  for n in [-1,0,1,1440001] { precondition(BundledASRPolicy.referenceLeadingFrameCount(frames:n,sampleRate:48000)==nil) }
  precondition(BundledASRPolicy.referenceLeadingFrameCount(frames:476000,sampleRate:16000)==4000)
  precondition(BundledASRPolicy.referenceLeadingFrameCount(frames:476001,sampleRate:16000)==nil)
 }
}
