//
//  WWStreamPlayer.swift
//  WWStreamPlayer
//
//  Created by William.Weng on 2026/3/27.
//

import ObjectiveC
import FFmpegWrapper

open class WWStreamPlayer: NSObject {
    
    let ffmpegWrapper = FFmpegWrapper()
    var pcmData: Data = .init()
}

// MARK: - 公開函式 (本地端)
public extension WWStreamPlayer {
    
    /// 使用的FFMpeg編譯版本
    /// - Returns: String
    func ffmpegVersion() -> String {
        return ffmpegWrapper.version()
    }
    
    /// 取得編碼ID名稱 - AVCodecID(rawValue: 86018) => aac
    /// - Parameter id: AVCodecID
    /// - Returns: String
    func codecName(with id: AVCodecID) -> String {
        return ffmpegWrapper.codecName(with: id)
    }
    
    /// 取得本地端影片長度
    /// - Parameter url: URL
    /// - Returns: Result<TimeInterval, Error>
    func duration(at url: URL) -> Result<TimeInterval, Error> {
        
        var error: NSError? = nil
        let duration = ffmpegWrapper.duration(at: url, error: &error)
        
        if let error = error { return .failure(error) }
        return .success(duration)
    }
    
    /// 取得本地端影音該時段的畫面
    /// - Parameters:
    ///   - url: NSURL
    ///   - second: NSTimeInterval
    func frame(at url: URL, second: TimeInterval) -> UIImage {
        return ffmpegWrapper.frame(at: url, second: second)
    }
    
    /// 產生本地端影音縮圖 (平均時間)
    /// - Parameters:
    ///   - url: NSURL
    ///   - count: 縮圖張數
    func thumbnails(at url: URL, count: Int32) -> [UIImage] {
        return ffmpegWrapper.thumbnails(at: url, count: count)
    }
}

// MARK: - 公開函式 (遠端串流)
public extension WWStreamPlayer {
    
    /// 播放RTSP串流 (使用frame圖片)
    /// - Parameters:
    ///   - url: NSURL
    ///   - frameCallback: 返回畫面 + 時間
    ///   - failureCallback: 返回錯誤
    ///   - completionCallback: 播放完成
    func play(at url: URL, frame frameCallback: @escaping FFmpegFrameWithTimeCallback, failure failureCallback: ((Error) -> Void)? = nil, completion completionCallback: ((Bool) -> Void)? = nil) {
        
        ffmpegWrapper.playRTSP(with: url) { frame, timestamp  in
            frameCallback(frame, timestamp)
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
    ///   - elapseCallback: 時間
    ///   - failureCallback: 返回錯誤
    ///   - completionCallback: 播放完成
    func play(at url: URL, displayLayer: AVSampleBufferDisplayLayer, elapseTime elapseCallback: ((CMTime) -> Void)? = nil, failure failureCallback: ((Error) -> Void)? = nil, completion completionCallback: ((Bool) -> Void)? = nil) {
        
        ffmpegWrapper.playRTSP(with: url, displayLayer: displayLayer) { time in
            elapseCallback?(time)
        } error: { error in
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
        
        ffmpegWrapper.playRTSP(with: url, pixelBuffer: pixelBuffer) { error in
            failureCallback?(error)
        } completion: { isFinished in
            completionCallback?(isFinished)
        }
    }
    
    /// 停止播放
    /// - Parameter type: 播放類型
    func stop(for type: PlayerType) {
        switch type {
        case .image: ffmpegWrapper.stopRTSPPlay()
        case .displayLayer: ffmpegWrapper.stopRTSPPlayOnDisplayLayer()
        case .pixelBuffer: ffmpegWrapper.stopRTSPPlayWithPixelBuffer()
        }
    }
}

// MARK: - 公開函式 (遠端聲音串流)
public extension WWStreamPlayer {
    
    /// 播放聲音串流
    /// - Parameters:
    ///   - url: URL
    ///   - bufferSize: 緩衝區大小
    func playAudio(at url: URL, bufferSize: Int = 44100 * 2) {
        
        decodeAudioStream(at: url) { para in
            print(para)
            
        } pcm: { [weak self] data, sampleRate, channels in
            
            guard let this = self else { return }
            
            this.pcmData.append(data)
                        
            if (this.pcmData.count < bufferSize) { return }
            
            this.ffmpegWrapper.playPCM(this.pcmData, sampleRate: sampleRate, channels: channels)
            this.pcmData.removeAll()
            
        } error: { _ in
            
        } completion: { _ in
            
        }
    }
    
    /// 停止播放聲音串流
    func stopAudio() {
        ffmpegWrapper.stopPCM()
    }
}

// MARK: - 小工具
private extension WWStreamPlayer {
    
    /// 播放PCM (轉成WAV)
    /// - Parameters:
    ///   - pcm: Data
    ///   - sampleRate: Int
    ///   - channels: Int
    func playPCM(_ pcm: Data, sampleRate: Int, channels: Int) {
        ffmpegWrapper.playPCM(pcm, sampleRate: Int32(sampleRate), channels: Int32(channels))
    }
    
    /// 解析聲音串流
    /// - Parameters:
    ///   - url: URL
    ///   - codecCallback: AVCodecParameters
    ///   - pcmCallback: FFmpegPCMCallback
    ///   - errorCallback: Error
    ///   - completionCallback: Int
    func decodeAudioStream(at url: URL, codec codecCallback: @escaping ((AVCodecParameters) -> Void), pcm pcmCallback: @escaping FFmpegPCMCallback, error errorCallback: @escaping((Error) -> Void), completion completionCallback: @escaping ((Int) -> Void)) {
        
        ffmpegWrapper.decodeAudioStream(url) { paramaters in
            codecCallback(paramaters.pointee)
        } pcm: { data, sampleRate, channels in
            pcmCallback(data, sampleRate, channels)
        } error: { error in
            errorCallback(error)
        } completion: { count in
            completionCallback(Int(count))
        }
    }
    
    /// 串流聲音緩衝區大小
    /// - Parameters:
    ///   - duration: 時間 (秒)
    ///   - sampleRate: Int
    ///   - channels: Int
    /// - Returns: Int
    func audioBufferSize(with duration: TimeInterval, sampleRate: Int, channels: Int) -> Int {
        
        let bytesPerSecond = sampleRate * 2 * channels
        let bufferSize = Int(duration * Double(bytesPerSecond))
        
        return bufferSize
    }

}
