// scripts/gen-sounds.swift
// Source UNIQUE des chimes du timer (spec v1.9 §3.1). Exécution : swift scripts/gen-sounds.swift
// Émet : App/Resources/Sounds/timer_step.caf (une note, ~0,36 s)
//        App/Resources/Sounds/timer_done.caf (do mi sol montant, ~0,90 s)
// Mono, 44,1 kHz, PCM 16 bits. Attaque de 12 ms et extinction complète : aucun clic.
// Idempotent : réécrit les deux fichiers à l'identique à chaque exécution.

import Foundation
import AVFoundation

let sampleRate = 44_100.0

struct Note {
    let frequency: Double   // Hz
    let start: Double       // s, depuis le début du fichier
    let duration: Double    // s
}

/// Timbre de petite cloche : fondamentale + octave discrète, enveloppe percussive.
/// L'attaque de 12 ms évite le clic de début, l'extinction exponentielle évite
/// celui de fin (le signal atteint zéro avant la fin du buffer).
func render(_ notes: [Note], totalDuration: Double) -> [Float] {
    var samples = [Float](repeating: 0, count: Int(totalDuration * sampleRate))
    for note in notes {
        let startIndex = Int(note.start * sampleRate)
        let count = Int(note.duration * sampleRate)
        for i in 0..<count {
            let index = startIndex + i
            guard index < samples.count else { break }
            let t = Double(i) / sampleRate
            let attack = min(1, t / 0.012)
            let decay = exp(-3.5 * t / note.duration)
            let wave = sin(2 * .pi * note.frequency * t)
                     + 0.28 * sin(4 * .pi * note.frequency * t)
            samples[index] += Float(attack * decay * wave * 0.34)
        }
    }
    // Les notes du chime « done » se recouvrent : garde-fou anti-saturation.
    let peak = samples.map { abs($0) }.max() ?? 0
    if peak > 0.92 {
        let gain = Float(0.92) / peak
        samples = samples.map { $0 * gain }
    }
    return samples
}

func write(_ samples: [Float], to url: URL) throws {
    try? FileManager.default.removeItem(at: url)   // AVAudioFile n'écrase pas proprement
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings,
                               commonFormat: .pcmFormatFloat32, interleaved: false)
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                               channels: 1, interleaved: false)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                  frameCapacity: AVAudioFrameCount(samples.count))!
    buffer.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer { source in
        buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
    }
    try file.write(from: buffer)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
// Garde d'ancrage : à lancer depuis la RACINE du repo (sinon les sorties atterrissent n'importe où).
guard FileManager.default.fileExists(atPath: root.appendingPathComponent("project.yml").path) else {
    fatalError("Lancer depuis la racine du repo (project.yml introuvable dans \(root.path))")
}
let outputDir = root.appendingPathComponent("App/Resources/Sounds")
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

// « Étape suivante » : une note claire et brève (la 5).
let step = render([Note(frequency: 880, start: 0, duration: 0.35)], totalDuration: 0.36)
try write(step, to: outputDir.appendingPathComponent("timer_step.caf"))

// « Terminé » : do mi sol montant, notes qui se recouvrent en accord.
let done = render([
    Note(frequency: 523.25, start: 0.00, duration: 0.55),
    Note(frequency: 659.25, start: 0.16, duration: 0.55),
    Note(frequency: 783.99, start: 0.32, duration: 0.55),
], totalDuration: 0.90)
try write(done, to: outputDir.appendingPathComponent("timer_done.caf"))

print("OK : timer_step.caf (0,36 s) et timer_done.caf (0,90 s) écrits dans App/Resources/Sounds")
