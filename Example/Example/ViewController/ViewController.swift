//
//  ViewController.swift
//  Example
//
//  Created by William.Weng on 2026/3/27.
//

import UIKit
import Foundation
import AVFoundation
import AudioToolbox
import WWStreamPlayer

final class ViewController: UIViewController {

    @IBOutlet weak var ffmpegVersionLabel: UILabel!
    @IBOutlet weak var videoTimeLabel: UILabel!
    @IBOutlet weak var videoImageView: UIImageView!
    @IBOutlet weak var layerTimeLabel: UILabel!
    @IBOutlet weak var layerImageView: UIImageView!

    private let rtsp = "rtsp://192.168.4.141:8554/mystream"
    private let displayLayer = AVSampleBufferDisplayLayer()
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        initSetting()
    }
    
    @IBAction func playVideo(_ sender: UIBarButtonItem) {
        if (sender.tag < 200) { playRtspSteam(at: rtsp); return }
        playRtspSteam2(at: rtsp);
    }
}

// MARK: - 小工具
private extension ViewController {
    
    /// 初始化設定
    func initSetting() {
        
        displayLayer.frame = layerImageView.bounds
        displayLayer.videoGravity = .resizeAspect
        displayLayer.isOpaque = true;
        
        layerImageView.layer.addSublayer(displayLayer)
        ffmepgVersion()
    }
    
    /// 取得FFMpeg版本
    func ffmepgVersion() {
        let version = WWStreamPlayer.shared.ffmpegVersion()
        ffmpegVersionLabel.text = "FFMpeg: \(version)"
    }
    
    /// 播放串流 (圖片)
    /// - Parameter urlString: String
    func playRtspSteam(at urlString: String) {
        
        guard let url = URL(string: urlString) else { return }
        
        WWStreamPlayer.shared.stop(for: .image)

        WWStreamPlayer.shared.play(at: url) { image, elapseTime in
            self.videoTimeLabel.text = "\(Int(CMTimeGetSeconds(elapseTime)))"
            self.videoImageView.image = image
        }
    }
    
    /// 播放串流 (AVSampleBufferDisplayLayer)
    /// - Parameter urlString: String
    func playRtspSteam2(at urlString: String) {
        
        guard let url = URL(string: urlString) else { return }
        
        WWStreamPlayer.shared.decodeAudioStream(at: url) { codec in
            let codecName = WWStreamPlayer.shared.codecName(with: codec.codec_id)
            print("[Codec] \(codecName) => \(codec.codec_id)")
        } pcmCallback: { pcmData, sampleRate, channels in
            self.playPCM(pcmData, sampleRate: Int(sampleRate), channels: Int(channels))
        }
    }
    
    // MARK: - 獨立播放函數
    func playPCM(_ pcmData: Data, sampleRate: Int, channels: Int) {
        let player = PCMPlayer.shared  // 單例管理 AudioQueue
        
        player.playPCM(pcmData, sampleRate: sampleRate, channels: channels)
    }
}

// MARK: - PCMPlayer (播放專用)
class PCMPlayer {
    
    static let shared = PCMPlayer()
    
    private var audioQueue: AudioQueueRef?
    private var asbd = AudioStreamBasicDescription()
    private var isInitialized = false
    private var sampleRate: Float64 = 0
    private var channels: UInt32 = 0
    
    private init() {}
    
    func playPCM(_ pcmData: Data, sampleRate: Int, channels: Int) {
        let sr = Float64(sampleRate)
        let ch = UInt32(channels)
        
        // 動態初始化
        if !isInitialized || self.sampleRate != sr || self.channels != ch {
            setupAudioQueue(sampleRate: sr, channels: ch)
        }
        
        guard let audioQueue = audioQueue else { return }
        
        // 填 buffer
        var buffer: AudioQueueBufferRef?
        AudioQueueAllocateBuffer(audioQueue, UInt32(pcmData.count), &buffer)
        
        pcmData.withUnsafeBytes { ptr in
            let unsafePtr = ptr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            memcpy(buffer!.pointee.mAudioData, unsafePtr, pcmData.count)
        }
        buffer!.pointee.mAudioDataByteSize = UInt32(pcmData.count)
        
        AudioQueueEnqueueBuffer(audioQueue, buffer!, 0, nil)
    }
    
    private func setupAudioQueue(sampleRate: Float64, channels: UInt32) {
        
        var asbd = AudioStreamBasicDescription()
        asbd.mSampleRate = sampleRate
        asbd.mChannelsPerFrame = channels
        asbd.mBitsPerChannel = 16
        asbd.mBytesPerFrame = 2 * channels
        asbd.mFramesPerPacket = 1
        asbd.mBytesPerPacket = asbd.mBytesPerFrame
        asbd.mFormatID = kAudioFormatLinearPCM
        asbd.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
        
        self.asbd = asbd
        self.sampleRate = sampleRate
        self.channels = channels
        
        var audioQueue: AudioQueueRef?
        
        // 正確參數順序：userData, runLoop, runLoopMode 都在 callback 之後
        AudioQueueNewOutput(&asbd,
                            audioQueueOutputCallback,
                           Unmanaged.passUnretained(self).toOpaque(),
                            nil,           // CFRunLoopRef
                            nil,
                            0,
                           &audioQueue)
        
        guard let queue = audioQueue else { return }
        self.audioQueue = queue
        
        AudioQueueSetParameter(queue, kAudioQueueParam_Volume, 1.0)
        AudioQueuePrime(queue, 0, nil)
        AudioQueueStart(queue, nil)
        isInitialized = true
    }
    
    private let audioQueueOutputCallback: AudioQueueOutputCallback = { userData, inAQ, inBuffer in
        let player = Unmanaged<WWStreamPlayer>.fromOpaque(userData!).takeUnretainedValue()
        print("AudioQueue 需要更多 PCM...")
        // 檢查緩衝，可觸發更多解碼
    }
    
    func stop() {
        if let audioQueue = audioQueue {
            AudioQueueStop(audioQueue, true)
            AudioQueueDispose(audioQueue, true)
            self.audioQueue = nil
            isInitialized = false
        }
    }
}
