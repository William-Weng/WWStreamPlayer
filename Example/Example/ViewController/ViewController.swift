//
//  ViewController.swift
//  Example
//
//  Created by William.Weng on 2026/3/27.
//

import UIKit
import AVFoundation
import WWStreamPlayer

final class ViewController: UIViewController {
    
    @IBOutlet weak var ffmpegVersionLabel: UILabel!
    @IBOutlet weak var videoTimeLabel: UILabel!
    @IBOutlet weak var videoImageView: UIImageView!
    
    private let rtsp = "rtsp://192.168.4.141:8554/mystream"    
    private let streamPlayer: WWStreamPlayer = .init()

    private var pcmData: Data = .init()
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        ffmepgVersion()
    }
    
    @IBAction func playVideo(_ sender: UIBarButtonItem) {
        playRtspSteam(at: rtsp)
    }
}

// MARK: - 小工具
private extension ViewController {
        
    /// 取得FFMpeg版本
    func ffmepgVersion() {
        let version = streamPlayer.ffmpegVersion()
        ffmpegVersionLabel.text = "FFMpeg: \(version)"
    }
    
    /// 播放串流 (圖片 + 聲音)
    /// - Parameter urlString: String
    func playRtspSteam(at urlString: String) {
        
        guard let url = URL(string: urlString) else { return }
        
        streamPlayer.stopVideo(for: .image)
        
        streamPlayer.playVideo(at: url, frame: { [unowned self] image, elapseTime in
            videoTimeLabel.text = "\(CMTimeGetSeconds(elapseTime))"
            videoImageView.image = image
        })
        
        streamPlayer.playAudio(at: url)
    }
}
