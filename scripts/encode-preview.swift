// scripts/encode-preview.swift
// Encode l'aperçu App Store à partir de l'enregistrement brut du simulateur.
//
//   swift scripts/encode-preview.swift <entrée.mov> <sortie.mp4> <début en s> <durée en s>
//
// Pourquoi AVFoundation et pas ffmpeg : l'installation Homebrew de ffmpeg de cette
// machine est cassée (libbluray absent du Cellar), et on ne va pas faire dépendre la
// publication d'une app d'un paquet tiers réparable ou non. Tout ce qui suit n'utilise
// que des briques du système.
//
// Contraintes Apple pour un aperçu : 15 à 30 s, H.264, 30 im/s au plus, ET une piste
// audio — une vidéo sans piste audio du tout est refusée au téléversement. On ajoute
// donc un silence, jamais de musique (question de droits).

import AVFoundation
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 5,
      let start = Double(arguments[3]), let duration = Double(arguments[4]) else {
    FileHandle.standardError.write(
        "usage: swift encode-preview.swift <entrée.mov> <sortie.mp4> <début> <durée>\n"
            .data(using: .utf8)!)
    exit(2)
}
let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("✗ \(message)\n".data(using: .utf8)!)
    exit(1)
}

/// Piste audio silencieuse : un WAV de zéros converti en AAC par `afconvert`.
/// Un `AVMutableComposition` ne peut pas porter une piste audio « vide » : il lui faut
/// une vraie source.
func makeSilentAudio(seconds: Double) throws -> URL {
    let temporary = FileManager.default.temporaryDirectory
    let wavURL = temporary.appendingPathComponent("nivel-silence.wav")
    let m4aURL = temporary.appendingPathComponent("nivel-silence.m4a")

    let sampleRate = 44_100
    let channels = 2
    let bitsPerSample = 16
    let frames = Int(seconds.rounded(.up)) * sampleRate
    let dataBytes = frames * channels * bitsPerSample / 8

    var header = Data()
    func append(_ string: String) { header.append(string.data(using: .ascii)!) }
    func append32(_ value: Int) { withUnsafeBytes(of: UInt32(value).littleEndian) { header.append(contentsOf: $0) } }
    func append16(_ value: Int) { withUnsafeBytes(of: UInt16(value).littleEndian) { header.append(contentsOf: $0) } }

    append("RIFF"); append32(36 + dataBytes); append("WAVE")
    append("fmt "); append32(16); append16(1); append16(channels)
    append32(sampleRate); append32(sampleRate * channels * bitsPerSample / 8)
    append16(channels * bitsPerSample / 8); append16(bitsPerSample)
    append("data"); append32(dataBytes)

    try (header + Data(count: dataBytes)).write(to: wavURL)

    try? FileManager.default.removeItem(at: m4aURL)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
    process.arguments = ["-f", "m4af", "-d", "aac", "-b", "128000", wavURL.path, m4aURL.path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fail("afconvert a échoué") }
    return m4aURL
}

let semaphore = DispatchSemaphore(value: 0)

Task {
    let asset = AVURLAsset(url: inputURL)
    guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
        fail("aucune piste vidéo dans \(inputURL.lastPathComponent)")
    }
    let assetDuration = CMTimeGetSeconds(try await asset.load(.duration))
    guard start + duration <= assetDuration + 0.1 else {
        fail(String(format: "fenêtre %.1f–%.1f s hors de l'enregistrement (%.1f s)",
                    start, start + duration, assetDuration))
    }

    let size = try await videoTrack.load(.naturalSize)
    let composition = AVMutableComposition()
    let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                            duration: CMTime(seconds: duration, preferredTimescale: 600))

    guard let videoOut = composition.addMutableTrack(withMediaType: .video,
                                                    preferredTrackID: kCMPersistentTrackID_Invalid)
    else { fail("piste vidéo de sortie impossible") }
    try videoOut.insertTimeRange(range, of: videoTrack, at: .zero)

    let silenceURL = try makeSilentAudio(seconds: duration)
    let silence = AVURLAsset(url: silenceURL)
    guard let silenceTrack = try await silence.loadTracks(withMediaType: .audio).first,
          let audioOut = composition.addMutableTrack(withMediaType: .audio,
                                                    preferredTrackID: kCMPersistentTrackID_Invalid)
    else { fail("piste audio silencieuse impossible") }
    try audioOut.insertTimeRange(
        CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 600)),
        of: silenceTrack, at: .zero)

    // 30 im/s : le simulateur enregistre à ~48, au-delà du plafond d'Apple.
    let videoComposition = AVMutableVideoComposition()
    videoComposition.renderSize = size
    videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero,
                                        duration: CMTime(seconds: duration, preferredTimescale: 600))
    let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoOut)
    instruction.layerInstructions = [layer]
    videoComposition.instructions = [instruction]

    try? FileManager.default.removeItem(at: outputURL)
    guard let export = AVAssetExportSession(asset: composition,
                                            presetName: AVAssetExportPresetHighestQuality)
    else { fail("session d'export impossible") }
    export.outputURL = outputURL
    export.outputFileType = .mp4
    export.videoComposition = videoComposition

    do {
        try await export.export(to: outputURL, as: .mp4)
    } catch {
        fail("export : \(error.localizedDescription)")
    }

    // Relecture du résultat : c'est ce fichier-là qu'Apple recevra, pas nos intentions.
    let result = AVURLAsset(url: outputURL)
    let resultDuration = CMTimeGetSeconds(try await result.load(.duration))
    let resultVideo = try await result.loadTracks(withMediaType: .video).first
    let resultAudio = try await result.loadTracks(withMediaType: .audio)
    let resultSize = try await resultVideo?.load(.naturalSize) ?? .zero
    let fps = try await resultVideo?.load(.nominalFrameRate) ?? 0
    var codec = "?"
    if let descriptions = try await resultVideo?.load(.formatDescriptions),
       let first = descriptions.first {
        let type = CMFormatDescriptionGetMediaSubType(first)
        codec = String(bytes: [UInt8(type >> 24 & 0xFF), UInt8(type >> 16 & 0xFF),
                               UInt8(type >> 8 & 0xFF), UInt8(type & 0xFF)], encoding: .ascii) ?? "?"
    }

    print(String(format: "%dx%d · %.1f s · %.1f im/s · codec %s · pistes audio %d",
                 Int(resultSize.width), Int(resultSize.height), resultDuration, fps,
                 (codec as NSString).utf8String!, resultAudio.count))

    var problems: [String] = []
    if resultDuration < 15 || resultDuration > 30 { problems.append("durée hors des 15–30 s exigées") }
    if resultAudio.isEmpty { problems.append("aucune piste audio : refus au téléversement") }
    if fps > 30.5 { problems.append("plus de 30 im/s") }
    if codec != "avc1" { problems.append("codec \(codec) au lieu de H.264 (avc1)") }
    if !problems.isEmpty { fail(problems.joined(separator: " ; ")) }

    print("✓ \(outputURL.path)")
    semaphore.signal()
}

semaphore.wait()
