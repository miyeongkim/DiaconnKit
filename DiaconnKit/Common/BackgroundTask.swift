import AVFoundation

/// Keep the app alive in background using silent audio playback
class DiaconnBackgroundTask {
    private var player = AVAudioPlayer()

    func start() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(interruptedAudio),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        playAudio()
    }

    func stop() {
        NotificationCenter.default.removeObserver(
            self,
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        player.stop()
    }

    @objc private func interruptedAudio(_ notification: Notification) {
        if let info = notification.userInfo,
           let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
           typeValue == AVAudioSession.InterruptionType.ended.rawValue
        {
            playAudio()
        }
    }

    private func playAudio() {
        do {
            guard let path = Bundle(for: DiaconnSettingsViewModel.self)
                .path(forResource: "blank", ofType: "wav")
            else { return }
            let url = URL(fileURLWithPath: path)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 0.01
            player.prepareToPlay()
            player.play()
        } catch {
            NSLog("[DiaconnKit] BackgroundTask playAudio failed: \(error)")
        }
    }
}
