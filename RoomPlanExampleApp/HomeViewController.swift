/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Home screen for starting scans and viewing saved scans.
*/

import UIKit

class HomeViewController: UIViewController {
    @IBAction func startScan(_ sender: UIButton) {
        if let viewController = storyboard?.instantiateViewController(
            withIdentifier: "RoomCaptureViewNavigationController") {
            viewController.modalPresentationStyle = .fullScreen
            present(viewController, animated: true)
        }
    }

    @IBAction func showSavedScans(_ sender: UIButton) {
        let viewController = SavedScansViewController()
        let navigationController = UINavigationController(rootViewController: viewController)
        navigationController.modalPresentationStyle = .fullScreen
        present(navigationController, animated: true)
    }
}
