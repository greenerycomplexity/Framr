//
//  ZoomableContainer.swift
//  Framr
//
//  Created by Son Cao on 11/12/25.
//

import SwiftUI
import UIKit

/// A container that enables simultaneous pinch-to-zoom and 2-finger pan gestures using UIKit gesture recognizers
struct ZoomableContainer<Content: View>: UIViewRepresentable {
    let content: Content
    @Binding var isZooming: Bool
    
    init(isZooming: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self._isZooming = isZooming
        self.content = content()
    }
    
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .clear
        
        // Create a hosting controller for the SwiftUI content
        let hostingController = UIHostingController(rootView: content)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear
        
        containerView.addSubview(hostingController.view)
        
        // Pin hosting view to container
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        context.coordinator.hostingView = hostingController.view
        context.coordinator.containerView = containerView
        
        // Add pinch gesture
        let pinchGesture = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        pinchGesture.delegate = context.coordinator
        containerView.addGestureRecognizer(pinchGesture)
        
        // Add pan gesture (2 fingers)
        let panGesture = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        panGesture.minimumNumberOfTouches = 2
        panGesture.maximumNumberOfTouches = 2
        panGesture.delegate = context.coordinator
        containerView.addGestureRecognizer(panGesture)
        
        context.coordinator.pinchGesture = pinchGesture
        context.coordinator.panGesture = panGesture
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update content if needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(isZooming: $isZooming)
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        @Binding var isZooming: Bool
        
        weak var hostingView: UIView?
        weak var containerView: UIView?
        weak var pinchGesture: UIPinchGestureRecognizer?
        weak var panGesture: UIPanGestureRecognizer?
        
        private var currentScale: CGFloat = 1.0
        private var currentTranslation: CGPoint = .zero
        private var anchorPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
        
        init(isZooming: Binding<Bool>) {
            self._isZooming = isZooming
        }
        
        // Allow both gestures to be recognized simultaneously
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            return true
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let view = hostingView, let container = containerView else { return }
            
            switch gesture.state {
            case .began:
                // Calculate anchor point based on pinch location
                let location = gesture.location(in: container)
                anchorPoint = CGPoint(
                    x: location.x / container.bounds.width,
                    y: location.y / container.bounds.height
                )
                
                // Update layer anchor point
                let oldOrigin = view.frame.origin
                view.layer.anchorPoint = anchorPoint
                let newOrigin = view.frame.origin
                let transition = CGPoint(x: newOrigin.x - oldOrigin.x, y: newOrigin.y - oldOrigin.y)
                view.center = CGPoint(x: view.center.x - transition.x, y: view.center.y - transition.y)
                
            case .changed:
                currentScale = gesture.scale
                
                // Set zooming flag
                if currentScale > 1.01 {
                    isZooming = true
                }
                
                applyTransform()
                
            case .ended, .cancelled:
                // Always reset to original state with animation
                UIView.animate(
                    withDuration: 0.3,
                    delay: 0,
                    usingSpringWithDamping: 0.8,
                    initialSpringVelocity: 0,
                    options: [.curveEaseOut]
                ) {
                    self.currentScale = 1.0
                    self.currentTranslation = .zero
                    
                    // Reset anchor point to center
                    self.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                    let oldOrigin = view.frame.origin
                    view.layer.anchorPoint = self.anchorPoint
                    let newOrigin = view.frame.origin
                    let transition = CGPoint(x: newOrigin.x - oldOrigin.x, y: newOrigin.y - oldOrigin.y)
                    view.center = CGPoint(x: view.center.x - transition.x, y: view.center.y - transition.y)
                    
                    self.applyTransform()
                } completion: { _ in
                    self.isZooming = false
                }
                
            default:
                break
            }
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let container = containerView else { return }
            
            switch gesture.state {
            case .changed:
                // Only allow panning when zoomed
                if currentScale > 1.01 {
                    let translation = gesture.translation(in: container)
                    currentTranslation = translation
                    applyTransform()
                }
                
            case .ended, .cancelled:
                // Pan gesture end is handled by pinch gesture end
                break
                
            default:
                break
            }
        }
        
        private func applyTransform() {
            guard let view = hostingView else { return }
            
            var transform = CGAffineTransform.identity
            transform = transform.scaledBy(x: currentScale, y: currentScale)
            transform = transform.translatedBy(x: currentTranslation.x, y: currentTranslation.y)
            
            view.transform = transform
        }
    }
}



