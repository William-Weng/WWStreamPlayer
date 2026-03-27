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
    @IBOutlet weak var videoImageView: UIImageView!
    @IBOutlet weak var layerImageView: UIImageView!

    private let rtsp = "rtsp://localhost:8554/mystream"
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
        WWStreamPlayer.shared.play(at: url) { image in self.videoImageView.image = image }
    }
    
    /// 播放串流 (AVSampleBufferDisplayLayer)
    /// - Parameter urlString: String
    func playRtspSteam2(at urlString: String) {
        guard let url = URL(string: urlString) else { return }
        WWStreamPlayer.shared.play(at: url, displayLayer: displayLayer)
    }
}
