# [WWStreamPlayer](https://swiftpackageindex.com/William-Weng)

[![Swift-5.7](https://img.shields.io/badge/Swift-5.7-orange.svg?style=flat)](https://developer.apple.com/swift/) [![iOS-16.0](https://img.shields.io/badge/iOS-16.0-pink.svg?style=flat)](https://developer.apple.com/swift/) ![TAG](https://img.shields.io/github/v/tag/William-Weng/WWStreamPlayer) [![Swift Package Manager-SUCCESS](https://img.shields.io/badge/Swift_Package_Manager-SUCCESS-blue.svg?style=flat)](https://developer.apple.com/swift/) [![LICENSE](https://img.shields.io/badge/LICENSE-MIT-yellow.svg?style=flat)](https://developer.apple.com/swift/)

### [Introduction - 簡介](https://swiftpackageindex.com/William-Weng)
- [Use FFMpeg to play RSTP streaming videos.](https://www.youtube.com/watch?v=aJrI_g2qDOQ)
- [使用FFMpeg來播放RSTP串流影片。](https://william-weng.github.io/2026/03/ffmpeg跟ios終於在一起了/)

https://github.com/user-attachments/assets/70ef120a-bd2b-4c10-9fad-c507abd9891d

### [Installation with Swift Package Manager](https://medium.com/彼得潘的-swift-ios-app-開發問題解答集/使用-spm-安裝第三方套件-xcode-11-新功能-2c4ffcf85b4b)
```bash
dependencies: [
    .package(url: "https://github.com/William-Weng/WWStreamPlayer.git", .upToNextMajor(from: "0.6.2"))
]
```

### 可用函式 (Function)
|函式|功能|
|-|-|
|ffmpegVersion()|使用的FFMpeg編譯版本|
|duration(at:)|取得本地端影片長度|
|frame(at:second:)|取得本地端影音該時段的畫面|
|thumbnails(at:count:)|產生本地端影音縮圖 (平均時間)|
|playVideo(at:frame:failure:completion:)|播放RTSP串流 (使用frame圖片)|
|playVideo(at:displayLayer:elapseTime:failure:completion:)|播放RTSP串流 (使用AVSampleBufferDisplayLayer)|
|playVideo(at:pixelBuffer:failure:completion:)|播放RTSP串流 (使用CVPixelBuffer for MetalKit)|
|stopVideo(for:)|停止播放|
|playAudio(at:bufferSize:result:)|播放聲音串流|
|stopAudio()|停止播放聲音串流|

### Example
```swift
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

private extension ViewController {
        
    func ffmepgVersion() {
        let version = streamPlayer.ffmpegVersion()
        ffmpegVersionLabel.text = "FFMpeg: \(version)"
    }
    
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
```

### [RTSP串流Server](https://zh.wikipedia.org/zh-tw/即時串流協定 )
- 可以使用[homebrew](https://brew.sh/)安裝[FFMpeg](https://www.ffmpeg.org/download.html) + [mediamtx](https://github.com/bluenviron/mediamtx)建立一個本地端的測試環境。

```bash
mediamtx
ffmpeg -re -stream_loop -1 -i BigBuckBunny.mp4 -c:v libx264 -preset veryfast -tune zerolatency -pix_fmt yuv420p -c:a aac -ac 2 -ar 44100 -b:a 128k -flags:a +global_header -f rtsp rtsp://localhost:8554/mystream
```

- [mediamtx.yml設定檔](https://www.cnblogs.com/bluesky-yuan/p/19582861)
```yml
# mediamtx.yml
paths:
  all:
    # 任何 client 都可以當 publisher（ffmpeg、OBS 等）
    source: publisher
```
