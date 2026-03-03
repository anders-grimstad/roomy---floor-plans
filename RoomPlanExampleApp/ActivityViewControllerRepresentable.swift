/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
UIViewControllerRepresentable wrapper for UIActivityViewController.
*/

import SwiftUI

struct ActivityViewControllerRepresentable: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
