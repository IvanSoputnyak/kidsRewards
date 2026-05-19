import SwiftUI

struct KidCoinLaunchMark: View {
    var size: CGFloat = 112

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [KidCoinTheme.sunshine, KidCoinTheme.primary.opacity(0.88)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: KidCoinTheme.primary.opacity(0.28), radius: 18, x: 0, y: 10)

            Circle()
                .stroke(KidCoinTheme.card.opacity(0.65), lineWidth: 3)
                .frame(width: size - 10, height: size - 10)

            Image(systemName: "star.fill")
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(KidCoinTheme.card)
                .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
        }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "lock.fill")
                .font(.system(size: size * 0.18, weight: .bold))
                .foregroundStyle(KidCoinTheme.mintText)
                .padding(10)
                .background(KidCoinTheme.mint.opacity(0.9))
                .clipShape(Circle())
                .overlay {
                    Circle().stroke(KidCoinTheme.card, lineWidth: 2)
                }
                .offset(x: size * 0.08, y: size * 0.08)
        }
        .accessibilityHidden(true)
    }
}

struct LoadingScreenView: View {
    @State private var logoScale: CGFloat = 0.88
    @State private var contentOpacity: Double = 0
    @State private var pulse = false

    var body: some View {
        ZStack {
            KidCoinTheme.background.ignoresSafeArea()

            loadingGlow

            VStack(spacing: 28) {
                KidCoinLaunchMark(size: 118)
                    .scaleEffect(logoScale)

                VStack(spacing: 8) {
                    Text("KidsRewards")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(KidCoinTheme.foreground)

                    Text("Earn · Save · Grow")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KidCoinTheme.mutedText)
                        .tracking(0.6)
                }
                .opacity(contentOpacity)

                ProgressView()
                    .tint(KidCoinTheme.primary)
                    .scaleEffect(1.05)
                    .opacity(contentOpacity)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 32)
        }
        .foregroundStyle(KidCoinTheme.foreground)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                logoScale = 1
            }
            withAnimation(.easeOut(duration: 0.45).delay(0.08)) {
                contentOpacity = 1
            }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var loadingGlow: some View {
        ZStack {
            Circle()
                .fill(KidCoinTheme.primary.opacity(pulse ? 0.14 : 0.08))
                .frame(width: pulse ? 320 : 280, height: pulse ? 320 : 280)
                .blur(radius: 18)

            Circle()
                .fill(KidCoinTheme.mint.opacity(pulse ? 0.16 : 0.1))
                .frame(width: pulse ? 220 : 190, height: pulse ? 220 : 190)
                .offset(x: 90, y: -120)
                .blur(radius: 22)

            Circle()
                .fill(KidCoinTheme.sunshine.opacity(pulse ? 0.14 : 0.08))
                .frame(width: pulse ? 180 : 150, height: pulse ? 180 : 150)
                .offset(x: -100, y: 140)
                .blur(radius: 20)
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    LoadingScreenView()
}
