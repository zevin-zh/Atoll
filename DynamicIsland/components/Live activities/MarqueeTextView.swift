/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI

struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct MeasureSizeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(GeometryReader { geometry in
            Color.clear.preference(key: SizePreferenceKey.self, value: geometry.size)
        })
    }
}

struct MarqueeText: View {
    @Binding var text: String
    let font: Font
    let nsFont: NSFont.TextStyle
    let textColor: Color
    let backgroundColor: Color
    let minDuration: Double
    let frameWidth: CGFloat
    
    /// Gap between the two copies of the text that make up the scrolling loop.
    static let loopSpacing: CGFloat = 20

    /// Recovers the width of a single copy of the text from the measured loop.
    ///
    /// The loop is two copies of the text separated by ``loopSpacing``, so the gap
    /// has to come off before halving. Halving the raw measurement instead leaves
    /// every string half a gap wider than it really is, which makes short text look
    /// like it needs to scroll.
    static func textWidth(fromLoopWidth loopWidth: CGFloat) -> CGFloat {
        max(0, (loopWidth - loopSpacing) / 2)
    }

    @State private var textSize: CGSize = .zero
    @State private var offset: CGFloat = 0
    @State private var isAnimating: Bool = false
    
    init(_ text: Binding<String>, font: Font = .body, nsFont: NSFont.TextStyle = .body, textColor: Color = .primary, backgroundColor: Color = .clear, minDuration: Double = 3.0, frameWidth: CGFloat = 200) {
        _text = text
        self.font = font
        self.nsFont = nsFont
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.minDuration = minDuration
        self.frameWidth = frameWidth
    }
    
    private var needsScrolling: Bool {
        textSize.width > frameWidth
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: Self.loopSpacing) {
                Text(text)
                Text(text)
                    .opacity(needsScrolling ? 1 : 0)
            }
            .id(text)
            .font(font)
            .foregroundColor(textColor)
            .fixedSize(horizontal: true, vertical: false)
            .offset(x: offset)
            .background(backgroundColor)
            .modifier(MeasureSizeModifier())
            .onPreferenceChange(SizePreferenceKey.self) { size in
                let measuredWidth = Self.textWidth(fromLoopWidth: size.width)
                self.textSize = CGSize(width: measuredWidth, height: NSFont.preferredFont(forTextStyle: nsFont).pointSize)
                resetAndStart()
            }
            .onChange(of: text) { _, _ in
                resetAndStart()
            }
            .onAppear {
                resetAndStart()
            }
            .onDisappear {
                isAnimating = false
            }
        }
        .frame(width: frameWidth, alignment: .leading)
        .clipped()
        .frame(height: textSize.height * 1.3)
    }
    
    private func resetAndStart() {
        isAnimating = false
        withAnimation(.none) {
            offset = 0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if needsScrolling {
                isAnimating = true
                startAnimationLoop()
            }
        }
    }
    
    private func startAnimationLoop() {
        guard isAnimating && needsScrolling else { return }
        
        // Duration based on speed (approx 30 pts per second)
        let duration = Double(textSize.width / 30)
        
        // 1. Initial/Restart Pause
        DispatchQueue.main.asyncAfter(deadline: .now() + minDuration) {
            guard isAnimating else { return }
            
            // 2. Linear Move
            withAnimation(Motion.respected(.linear(duration: duration))) {
                offset = -(textSize.width + Self.loopSpacing) // Text width + spacing
            }
            
            // 3. Wait for move to finish
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                guard isAnimating else { return }
                
                // 4. Snap back instantly
                withAnimation(.none) {
                    offset = 0
                }
                
                // 5. Repeat
                startAnimationLoop()
            }
        }
    }
}
