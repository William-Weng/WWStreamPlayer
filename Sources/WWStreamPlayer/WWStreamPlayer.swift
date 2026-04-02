//
//  WWStreamPlayer.swift
//  WWStreamPlayer
//
//  Created by William.Weng on 2026/3/27.
//

import ObjectiveC
import FFmpegWrapper

// MARK: - 簡易RSTP播放器
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
    func playVideo(at url: URL, frame frameCallback: @escaping FFmpegFrameWithTimeCallback, failure failureCallback: ((Error) -> Void)? = nil, completion completionCallback: ((Bool) -> Void)? = nil) {
        
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
    func playVideo(at url: URL, displayLayer: AVSampleBufferDisplayLayer, elapseTime elapseCallback: ((CMTime) -> Void)? = nil, failure failureCallback: ((Error) -> Void)? = nil, completion completionCallback: ((Bool) -> Void)? = nil) {
        
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
    func playVideo(at url: URL, pixelBuffer: @escaping FFmpegPixelBufferCallback, failure failureCallback: ((Error) -> Void)? = nil, completion completionCallback: ((Bool) -> Void)? = nil) {
        
        ffmpegWrapper.playRTSP(with: url, pixelBuffer: pixelBuffer) { error in
            failureCallback?(error)
        } completion: { isFinished in
            completionCallback?(isFinished)
        }
    }
    
    /// 停止播放
    /// - Parameter type: 播放類型
    func stopVideo(for type: PlayerType) {
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
    ///   - url: 串流網址
    ///   - bufferSize: 緩衝區大小 (44100 Hz)
    ///   - result: Result<Bool, Error>
    func playAudio(at url: URL, bufferSize: Int = 44100 * 2, result: ((Result<Bool, Error>) -> Void)? = nil) {
        
        decodeAudioStream(at: url) { [weak self] data, sampleRate, channels in
            
            guard let this = self else { return }
            
            this.pcmData.append(data)
            if (this.pcmData.count < bufferSize) { return }
            
            switch this.playPCM(this.pcmData, sampleRate: Int(sampleRate), channels: Int(channels)) {
            case .success(let isSuccess): result?(.success(isSuccess))
            case .failure(let error): result?(.failure(error))
            }
            
            this.pcmData.removeAll()
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
    ///   - pcm: PCM資料
    ///   - sampleRate: 聲音取樣頻率 (22000Hz / 44100Hz)
    ///   - channels: 聲音通道數 (單 / 雙通道)
    /// - Returns: Result<Bool, Error>
    func playPCM(_ pcm: Data, sampleRate: Int, channels: Int) -> Result<Bool, Error> {
        
        var error: NSError? = nil
        
        ffmpegWrapper.playPCM(pcm, sampleRate: Int32(sampleRate), channels: Int32(channels), error: &error)
        
        if let error { return .failure(error) }
        return .success(true)
    }
    
    /// 解析聲音串流
    /// - Parameters:
    ///   - url: URL
    ///   - codecCallback: AVCodecParameters
    ///   - pcmCallback: FFmpegPCMCallback
    ///   - errorCallback: Error
    ///   - completionCallback: Int
    func decodeAudioStream(at url: URL, codec codecCallback: ((AVCodecParameters) -> Void)? = nil, pcm pcmCallback: @escaping FFmpegPCMCallback, error errorCallback: ((Error) -> Void)? = nil, completion completionCallback: ((Int) -> Void)? = nil) {
        
        ffmpegWrapper.decodeAudioStream(url) { paramaters in
            codecCallback?(paramaters.pointee)
        } pcm: { data, sampleRate, channels in
            pcmCallback(data, sampleRate, channels)
        } error: { error in
            errorCallback?(error)
        } completion: { count in
            completionCallback?(Int(count))
        }
    }
    
    /// 串流聲音緩衝區大小
    /// - Parameters:
    ///   - duration: 時間 (秒)
    ///   - sampleRate: 聲音取樣頻率 (22000Hz / 44100Hz)
    ///   - channels: 聲音通道數 (單 / 雙通道)
    /// - Returns: Int
    func audioBufferSize(with duration: TimeInterval, sampleRate: Int, channels: Int) -> Int {
        
        let bytesPerSecond = sampleRate * 2 * channels
        let bufferSize = Int(duration * Double(bytesPerSecond))
        
        return bufferSize
    }
}
