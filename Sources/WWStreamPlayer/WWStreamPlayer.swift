//
//  WWStreamPlayer.swift
//  WWStreamPlayer
//
//  Created by William.Weng on 2026/3/27.
//

import ObjectiveC
import FFmpegWrapper

open class WWStreamPlayer: NSObject {

    public static let shared = WWStreamPlayer()
    
    private override init() {
        super.init()
    }
}

// MARK: - 公開函式 (本地端)
public extension WWStreamPlayer {
    
    /// 使用的FFMpeg編譯版本
    /// - Returns: String
    func ffmpegVersion() -> String {
        return FFmpegWrapper.shared().version()
    }
    
    /// 取得本地端影片長度
    /// - Parameter url: URL
    /// - Returns: Result<TimeInterval, Error>
    func duration(at url: URL) -> Result<TimeInterval, Error> {
        
        var error: NSError? = nil
        let duration = FFmpegWrapper.shared().duration(at: url, error: &error)
        
        if let error = error { return .failure(error) }
        return .success(duration)
    }
    
    /// 取得本地端影音該時段的畫面
    /// - Parameters:
    ///   - url: NSURL
    ///   - second: NSTimeInterval
    func frame(at url: URL, second: TimeInterval) -> UIImage {
        return FFmpegWrapper.shared().frame(at: url, second: second)
    }
    
    /// 產生本地端影音縮圖 (平均時間)
    /// - Parameters:
    ///   - url: NSURL
    ///   - count: 縮圖張數
    func thumbnails(at url: URL, count: Int32) -> [UIImage] {
        return FFmpegWrapper.shared().thumbnails(at: url, count: count)
    }
}

// MARK: - 公開函式 (遠端串流)
public extension WWStreamPlayer {
    
    /// 播放RTSP串流 (使用frame圖片)
    /// - Parameters:
    ///   - url: NSURL
    ///   - frameCallback: 返回畫面
    ///   - failureCallback: 返回錯誤
    ///   - completionCallback: 播放完成
    func play(at url: URL, frame frameCallback: @escaping ((UIImage) -> Void), failure failureCallback: ((Error) -> Void)? = nil, completion completionCallback: ((Bool) -> Void)? = nil) {
        
        FFmpegWrapper.shared().playRTSP(with: url) { frame in
            frameCallback(frame)
        } error: { error in
            failureCallback?(error)
        } completion: { isFinished in
            completionCallback?(isFinished)
        }
    }
    
    /// 播放RTSP串流 (使用AVSampleBufferDisplayLayer)
    /// - Parameters:
    ///   - url: NSURL
    ///   - displayLayer: AVSampleBufferDisplayLayer
    ///   - failureCallback: 返回錯誤
    ///   - completionCallback: 播放完成
    func play(at url: URL, displayLayer: AVSampleBufferDisplayLayer, failure failureCallback: ((Error) -> Void)? = nil, completion completionCallback: ((Bool) -> Void)? = nil) {
        
        FFmpegWrapper.shared().playRTSP(with: url, displayLayer: displayLayer) { error in
            failureCallback?(error)
        } completion: { isFinished in
            completionCallback?(isFinished)
        }
    }
    
    /// 播放RTSP串流 (使用CVPixelBuffer for MetalKit)
    /// - Parameters:
    ///   - url: NSURL
    ///   - pixelBufferCallback: 返回CVPixelBufferRef
    ///   - errorCallback: 返回錯誤
    ///   - completionCallback: 播放完成
    func play(at url: URL, pixelBuffer: @escaping FFmpegPixelBufferCallback, failure failureCallback: ((Error) -> Void)? = nil, completion completionCallback: ((Bool) -> Void)? = nil) {
        
        FFmpegWrapper.shared().playRTSP(with: url, pixelBuffer: pixelBuffer) { error in
            failureCallback?(error)
        } completion: { isFinished in
            completionCallback?(isFinished)
        }
    }
    
    /// 停止播放
    /// - Parameter type: 播放類型
    func stop(for type: PlayerType) {
        switch type {
        case .image: FFmpegWrapper.shared().stopRTSPPlay()
        case .displayLayer: FFmpegWrapper.shared().stopRTSPPlayOnDisplayLayer()
        case .pixelBuffer: FFmpegWrapper.shared().stopRTSPPlayWithPixelBuffer()
        }
    }
}
