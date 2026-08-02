// scripts/gen-sounds.swift
// Source UNIQUE des chimes du timer (spec v1.9 §3.1). Exécution : swift scripts/gen-sounds.swift
// Émet : App/Resources/Sounds/timer_step.caf (une note, ~0,36 s)
//        App/Resources/Sounds/timer_done.caf (do mi sol montant, ~0,90 s)
// Mono, 44,1 kHz, PCM 16 bits. Attaque de 12 ms, extinction quasi complète (environ
// -30 dB) avant troncature : aucun clic audible.
// Idempotent : réécrit les deux fichiers à l'identique à chaque exécution.

import Foundation
import AVFoundation

let sampleRate = 44_100.0

// MARK: - Tunables (à ajuster dans un an sans replonger dans la maths)

let ATTACK_DURATION = 0.012   // s : monter ce chiffre adoucit l'attaque, descendre la durcit (risque de clic si trop bas)
let DECAY_RATE = 3.5          // coefficient d'extinction : plus haut = chime plus sec et court, plus bas = plus de sustain
let OVERTONE_RATIO = 0.28     // poids de l'octave par rapport à la fondamentale : plus haut = timbre plus « cloche »/brillant
let OUTPUT_GAIN = 0.34        // volume de sortie par note, avant garde-fou anti-saturation : monter ce chiffre = plus fort
let CLIP_CEILING = 0.92       // pic maximal toléré après somme des notes : le garde-fou renormalise si franchi

struct Note {
    let frequency: Double   // Hz
    let start: Double       // s, depuis le début du fichier
    let duration: Double    // s
}

/// Timbre de petite cloche : fondamentale + octave discrète, enveloppe percussive.
/// L'attaque de 12 ms évite le clic de début, l'extinction exponentielle amène le
/// signal quasi à zéro (environ -30 dB, soit exp(-DECAY_RATE)) avant la troncature
/// en fin de note : la coupure qui suit est donc inaudible en pratique.
func render(_ notes: [Note], totalDuration: Double) -> [Float] {
    var samples = [Float](repeating: 0, count: Int(totalDuration * sampleRate))
    for note in notes {
        let startIndex = Int(note.start * sampleRate)
        let count = Int(note.duration * sampleRate)
        for i in 0..<count {
            let index = startIndex + i
            guard index < samples.count else { break }
            let t = Double(i) / sampleRate
            let attack = min(1, t / ATTACK_DURATION)
            let decay = exp(-DECAY_RATE * t / note.duration)
            let wave = sin(2 * .pi * note.frequency * t)
                     + OVERTONE_RATIO * sin(4 * .pi * note.frequency * t)
            samples[index] += Float(attack * decay * wave * OUTPUT_GAIN)
        }
    }
    // Les notes du chime « done » se recouvrent : garde-fou anti-saturation.
    let peak = samples.map { abs($0) }.max() ?? 0
    if peak > Float(CLIP_CEILING) {
        let gain = Float(CLIP_CEILING) / peak
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
    guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                     channels: 1, interleaved: false) else {
        fatalError("format PCM float32 mono invalide")
    }
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                        frameCapacity: AVAudioFrameCount(samples.count)) else {
        fatalError("allocation du buffer PCM échouée (\(samples.count) frames)")
    }
    buffer.frameLength = AVAudioFrameCount(samples.count)
    guard let channelData = buffer.floatChannelData else {
        fatalError("buffer sans plan flottant (format non conforme)")
    }
    samples.withUnsafeBufferPointer { source in
        guard let base = source.baseAddress else { fatalError("samples vides") }
        channelData[0].update(from: base, count: samples.count)
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

// Pics indicatifs : donnent la marge restante avant CLIP_CEILING à qui monte OUTPUT_GAIN.
let stepPeakPct = Int((step.map { abs($0) }.max() ?? 0) * 100)
let donePeakPct = Int((done.map { abs($0) }.max() ?? 0) * 100)
print("OK : timer_step.caf (0,36 s) et timer_done.caf (0,90 s) écrits dans App/Resources/Sounds "
    + "(pic \(stepPeakPct) % / \(donePeakPct) %)")
