// WeightTrend.swift
// Tendance de poids lissée (spec §4.3) : moyenne mobile exponentielle α = 0,25.
// Les fluctuations quotidiennes deviennent secondaires, la tendance est mise en avant.

import Foundation

public enum WeightTrend {
    /// Lissage exponentiel : trend[0] = values[0],
    /// trend[i] = trend[i-1] + 0.25 × (values[i] − trend[i-1]).
    public static func smooth(_ values: [Double]) -> [Double] {
        guard var trend = values.first else { return [] }
        var result: [Double] = [trend]
        result.reserveCapacity(values.count)
        for value in values.dropFirst() {
            trend += 0.25 * (value - trend)
            result.append(trend)
        }
        return result
    }
}
