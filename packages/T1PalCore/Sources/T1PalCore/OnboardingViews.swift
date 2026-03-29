// SPDX-License-Identifier: AGPL-3.0-or-later
// OnboardingViews.swift
// T1PalCore
//
// SwiftUI views for onboarding flow.
// Trace: APP-ONBOARD-001, APP-REVIEW-ONBOARDING-STRATEGY

#if canImport(SwiftUI)
import SwiftUI

// MARK: - Onboarding Container View

/// Container view that manages the onboarding flow UI
@available(iOS 17.0, macOS 14.0, *)
public struct OnboardingContainerView<Step: OnboardingStep, StepContent: View>: View {
    @Bindable var coordinator: OnboardingCoordinator<Step>
    let stepContent: (Step) -> StepContent
    
    public init(
        coordinator: OnboardingCoordinator<Step>,
        @ViewBuilder stepContent: @escaping (Step) -> StepContent
    ) {
        self.coordinator = coordinator
        self.stepContent = stepContent
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            OnboardingProgressView(
                currentStep: coordinator.currentStepIndex + 1,
                totalSteps: coordinator.steps.count,
                progress: coordinator.progress
            )
            
            // Step content
            if let step = coordinator.currentStep {
                stepContent(step)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // Validation error
            if let result = coordinator.validationResult, !result.isValid {
                OnboardingErrorBanner(message: result.errorMessage ?? "Validation failed")
            }
            
            // Navigation buttons
            OnboardingNavigationBar(
                canGoBack: coordinator.canGoBack,
                canProceed: coordinator.canProceed,
                isLastStep: coordinator.isLastStep,
                isValidating: coordinator.isValidating,
                isSkippable: coordinator.currentStep?.isSkippable ?? false,
                onBack: { coordinator.back() },
                onNext: { Task { await coordinator.next() } },
                onSkip: { Task { await coordinator.skipCurrent() } }
            )
        }
        .onAppear {
            if coordinator.state == .notStarted {
                coordinator.start()
            }
        }
    }
}

// MARK: - Progress View

@available(iOS 15.0, macOS 12.0, *)
public struct OnboardingProgressView: View {
    let currentStep: Int
    let totalSteps: Int
    let progress: Double
    
    public init(currentStep: Int, totalSteps: Int, progress: Double) {
        self.currentStep = currentStep
        self.totalSteps = totalSteps
        self.progress = progress
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            // Step indicator
            HStack {
                Text("Step \(currentStep) of \(totalSteps)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * progress, height: 8)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 8)
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

// MARK: - Navigation Bar

@available(iOS 15.0, macOS 12.0, *)
public struct OnboardingNavigationBar: View {
    let canGoBack: Bool
    let canProceed: Bool
    let isLastStep: Bool
    let isValidating: Bool
    let isSkippable: Bool
    let onBack: () -> Void
    let onNext: () -> Void
    let onSkip: () -> Void
    
    public init(
        canGoBack: Bool,
        canProceed: Bool,
        isLastStep: Bool,
        isValidating: Bool,
        isSkippable: Bool,
        onBack: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.canGoBack = canGoBack
        self.canProceed = canProceed
        self.isLastStep = isLastStep
        self.isValidating = isValidating
        self.isSkippable = isSkippable
        self.onBack = onBack
        self.onNext = onNext
        self.onSkip = onSkip
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Back button
                if canGoBack {
                    Button(action: onBack) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
                
                // Next/Complete button
                Button(action: onNext) {
                    HStack {
                        if isValidating {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                        } else {
                            Text(isLastStep ? "Complete" : "Continue")
                            if !isLastStep {
                                Image(systemName: "chevron.right")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(isValidating)
            }
            
            // Skip button
            if isSkippable && !isValidating {
                Button("Skip this step", action: onSkip)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

// MARK: - Error Banner

@available(iOS 15.0, macOS 12.0, *)
public struct OnboardingErrorBanner: View {
    let message: String
    
    public init(message: String) {
        self.message = message
    }
    
    public var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.1))
    }
}

// MARK: - Step Header View

@available(iOS 15.0, macOS 12.0, *)
public struct OnboardingStepHeader: View {
    let title: String
    let subtitle: String?
    let iconName: String
    
    public init(title: String, subtitle: String? = nil, iconName: String) {
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 60))
                .foregroundStyle(Color.accentColor)
            
            Text(title)
                .font(.title)
                .fontWeight(.bold)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
}

// MARK: - Step Dots Indicator

@available(iOS 15.0, macOS 12.0, *)
public struct OnboardingDotsIndicator: View {
    let totalSteps: Int
    let currentStep: Int
    
    public init(totalSteps: Int, currentStep: Int) {
        self.totalSteps = totalSteps
        self.currentStep = currentStep
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(index == currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(width: index == currentStep ? 10 : 8, height: index == currentStep ? 10 : 8)
                    .animation(.easeInOut(duration: 0.2), value: currentStep)
            }
        }
    }
}

#endif
