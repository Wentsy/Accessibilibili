//
//  VolumeListener.swift
//  flutter_volume_controller
//
//  Created by yosemiteyss on 18/9/2022.
//

import AVFoundation
import Flutter
import Foundation

class VolumeListener: NSObject, FlutterStreamHandler {
    private let audioSession: AVAudioSession
    
    private var outputVolumeObservation: NSKeyValueObservation?
    
    var isListening: Bool {
        return outputVolumeObservation != nil
    }
    
    init(audioSession: AVAudioSession) {
        self.audioSession = audioSession
    }
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        // Accessibilibili owns the shared playback + mixWithOthers session.
        // The upstream Dart listener defaults to ambient, which silences audio
        // on lock/background. Observing volume must not change that category
        // (nor replace it with non-mixable playback and interrupt VoiceOver).
        let args = arguments as? [String: Any]
        let emitOnStart = args?[MethodArg.emitOnStart] as? Bool ?? true

        outputVolumeObservation = audioSession.observe(\.outputVolume) { session, _ in
            events(String(session.outputVolume))
        }

        if emitOnStart {
            events(String(audioSession.outputVolume))
        }
        
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        outputVolumeObservation = nil
        // Cancelling a UI observer must not deactivate mpv's shared session.
        return nil
    }
}
