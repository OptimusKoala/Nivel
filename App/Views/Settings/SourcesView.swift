// App/Views/Settings/SourcesView.swift
// Sources scientifiques des chiffres que l'app avance (App Review, guideline
// 1.4.1) : chaque estimation santé — objectif kcal, pas, dépense des activités,
// calories des aliments — cite sa référence, en lien tapable. Présenté en sheet
// depuis Réglages > À propos et depuis la page Objectif de l'onboarding.

import SwiftUI

struct SourcesView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Sources")
                        .font(.system(size: 26, weight: .bold, design: .rounded))

                    Text("Les chiffres que Nivel te propose s'appuient sur ces références.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtext)

                    section("Objectif calorique", sources: [
                        Source(
                            title: "Métabolisme de base : équation de Mifflin-St Jeor",
                            detail: "Mifflin MD, St Jeor ST et al. « A new predictive equation for resting energy expenditure in healthy individuals », American Journal of Clinical Nutrition, 1990.",
                            url: "https://pubmed.ncbi.nlm.nih.gov/2305711/"
                        ),
                        Source(
                            title: "Facteurs de niveau d'activité",
                            detail: "FAO/OMS/UNU, « Human energy requirements », rapport de la consultation d'experts, 2004.",
                            url: "https://www.fao.org/3/y5686e/y5686e00.htm"
                        ),
                        Source(
                            title: "Déficit modéré et rythme de perte",
                            detail: "NHS, « Lose weight » : une perte graduelle de 0,5 à 1 kg par semaine.",
                            url: "https://www.nhs.uk/better-health/lose-weight/"
                        ),
                        Source(
                            title: "Apport quotidien minimal",
                            detail: "NIH / NHLBI, « Clinical Guidelines on the Identification, Evaluation, and Treatment of Overweight and Obesity in Adults », 1998.",
                            url: "https://www.nhlbi.nih.gov/files/docs/guidelines/ob_gdlns.pdf"
                        ),
                    ])

                    section("Pas quotidiens", sources: [
                        Source(
                            title: "Nombre de pas et santé",
                            detail: "Paluch AE et al. « Daily steps and all-cause mortality: a meta-analysis of 15 international cohorts », The Lancet Public Health, 2022.",
                            url: "https://pubmed.ncbi.nlm.nih.gov/35247352/"
                        ),
                        Source(
                            title: "Recommandations d'activité physique",
                            detail: "OMS, « Lignes directrices sur l'activité physique et la sédentarité », 2020.",
                            url: "https://www.who.int/publications/i/item/9789240015128"
                        ),
                    ])

                    section("Dépense des activités et des pas", sources: [
                        Source(
                            title: "Compendium des activités physiques",
                            detail: "Ainsworth BE et al. « 2011 Compendium of Physical Activities », Medicine & Science in Sports & Exercise, 2011. Les estimations kcal des activités et des pas en sont dérivées, ajustées au poids.",
                            url: "https://pubmed.ncbi.nlm.nih.gov/21681120/"
                        ),
                    ])

                    section("Calories des aliments", sources: [
                        Source(
                            title: "Table de composition nutritionnelle Ciqual",
                            detail: "ANSES (Agence nationale de sécurité sanitaire de l'alimentation). Les calories du catalogue d'aliments en sont issues, arrondies pour des portions courantes.",
                            url: "https://ciqual.anses.fr"
                        ),
                    ])

                    Text("Ces estimations sont indicatives : Nivel n'est pas un dispositif médical et ne remplace pas l'avis d'un professionnel de santé.")
                        .font(.footnote)
                        .foregroundStyle(Theme.subtext)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .foregroundStyle(Theme.text)
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Briques

    private struct Source {
        let title: String
        let detail: String
        let url: String
    }

    private func section(_ title: String, sources: [Source]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Overline(title)
            ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                if index > 0 {
                    Rectangle().fill(Theme.track).frame(height: 1)
                }
                sourceRow(source)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func sourceRow(_ source: Source) -> some View {
        // Link (et non Button+openURL) : VoiceOver annonce « lien », et le trait
        // système « ouvre dans le navigateur » reste vrai.
        Link(destination: URL(string: source.url)!) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text(source.detail)
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.orange)
                    .padding(.top, 3)
            }
            .contentShape(Rectangle())
        }
        .multilineTextAlignment(.leading)
    }
}

#Preview {
    SourcesView()
        .fontDesign(.rounded)
}
