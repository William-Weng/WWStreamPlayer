//
//  AudioPlayer.swift
//  WWStreamPlayer
//
//  Created by William.Weng on 2026/4/8.
//

import AVFoundation
import WWWavWriter

// MARK: - 聲音串流播放器
final actor AudioPlayer: NSObject {
    
    private let session = AVAudioSession.sharedInstance()
    private var player: AVAudioPlayer?
}

// MARK: - AVAudioPlayerDelegate
extension AudioPlayer: AVAudioPlayerDelegate {
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) async {
        
        if (self.player === player) {
            self.player = nil
            try? self.session.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

// MARK: - 工具函式
extension AudioPlayer {
    
    /// 播放聲音串流
    /// - Parameters:
    ///   - pcmData: 音訊原始資料
    ///   - sampleRate: 音訊取樣率
    ///   - channels: 聲道數量
    /// - Returns: Bool
    func playPCM(_ pcmData: Data, sampleRate: Int, channels: Int) async throws -> Bool {
        
        let wavData = try WWWavWriter.makeData(wavType: .PCM16(pcmData), sampleRate: UInt32(sampleRate), channels: UInt16(channels))
        let newPlayer = try AVAudioPlayer(data: wavData)
        
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
        
        player?.stop()
        player = nil
        
        newPlayer.delegate = self
        newPlayer.volume = 1.0
        newPlayer.enableRate = true
        newPlayer.prepareToPlay()
        
        guard newPlayer.play() else { return false }
        player = newPlayer
        
        return true
    }
    
    /// 停止播放聲音串流
    func stopPCM() async throws {
        player?.stop()
        player = nil
        try session.setActive(false, options: .notifyOthersOnDeactivation)
    }
}
