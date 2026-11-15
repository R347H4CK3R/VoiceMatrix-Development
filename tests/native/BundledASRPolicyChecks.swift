import Foundation
@main struct BundledASRPolicyChecks {
    static func main() {
        precondition(BundledASRPolicy.admittedTokenMean([]) == nil)
        precondition(BundledASRPolicy.admittedTokenMean([.nan]) == nil)
        precondition(BundledASRPolicy.admittedTokenMean([.infinity]) == nil)
        precondition(BundledASRPolicy.admittedTokenMean([-0.1]) == nil)
        precondition(BundledASRPolicy.admittedTokenMean([1.1]) == nil)
        precondition(BundledASRPolicy.admittedTokenMean([0.34]) == nil)
        precondition(BundledASRPolicy.admittedTokenMean([0.35]) == 0.35)
        precondition(BundledASRPolicy.admittedTokenMean([0.4,0.8])! > 0.59)
        precondition(BundledASRPolicy.admittedTokenMean(Array(repeating:1,count:4097)) == nil)
        let voiced=Array(repeating:Float(0.05),count:32000)
        precondition(BundledASRPolicy.recoveryTailFrameCount(text:"'",samples:voiced,sampleRate:16000)==2560)
        precondition(BundledASRPolicy.recoveryTailFrameCount(text:"",samples:voiced,sampleRate:16000)==2560)
        precondition(BundledASRPolicy.recoveryTailFrameCount(text:"Please close the window",samples:voiced,sampleRate:16000)==nil)
        precondition(BundledASRPolicy.recoveryTailFrameCount(text:"a",samples:voiced,sampleRate:16000)==nil)
        precondition(BundledASRPolicy.recoveryTailFrameCount(text:"'",samples:Array(repeating:0,count:32000),sampleRate:16000)==nil)
        precondition(BundledASRPolicy.recoveryTailFrameCount(text:"'",samples:[.nan],sampleRate:16000)==nil)
        precondition(BundledASRPolicy.recoveryTailFrameCount(text:"'",samples:voiced,sampleRate:.nan)==nil)
        precondition(BundledASRPolicy.recoveryTailFrameCount(text:"'",samples:Array(repeating:0.05,count:480000),sampleRate:16000)==nil)
        precondition(BundledASRPolicy.admittedRecoveryTokenMean([0.69])==nil)
        precondition(BundledASRPolicy.admittedRecoveryTokenMean([0.7])==0.7)
        print("Bundled ASR policy checks passed")
    }
}
