//
//  ViewController.swift
//  SightSeeing
//
//  Created by Soheil on 03/01/2018.
//  Copyright © 2018 Soheil Novinfard. All rights reserved.
//

import UIKit
import SpriteKit
import ARKit
import CoreLocation
import GameplayKit

class ViewController: UIViewController, ARSKViewDelegate, CLLocationManagerDelegate {
    
    @IBOutlet var sceneView: ARSKView!
	let locationManager = CLLocationManager()
	var userLocation = CLLocation()
	
	var sightsJSON: JSON!
	
	var userHeading = 0.0
	var headingCount = 0
	
	var pages = [UUID: String]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view's delegate
        sceneView.delegate = self
        
        // Show statistics such as fps and node count
        sceneView.showsFPS = true
        sceneView.showsNodeCount = true
        
        // Load the SKScene from 'Scene.sks'
        if let scene = SKScene(fileNamed: "Scene") {
            sceneView.presentScene(scene)
        }
		
		locationManager.delegate = self
		locationManager.desiredAccuracy = kCLLocationAccuracyBest
		locationManager.requestWhenInUseAuthorization()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = AROrientationTrackingConfiguration()

        // Run the view's session
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }
    
    // MARK: - ARSKViewDelegate
    
	func view(_ view: ARSKView, nodeFor anchor: ARAnchor) ->
		SKNode? {
			// Create a label node showing the title for this anchor
			let labelNode = SKLabelNode(text: pages[anchor.identifier])
			labelNode.horizontalAlignmentMode = .center
			labelNode.verticalAlignmentMode = .center
			
			// scale up the label's size so we have some margin
			let size =
				labelNode.frame.size.applying(CGAffineTransform(scaleX: 1.1, y:
					1.4))
			
			// create a background node using the new size, rounding its corners gently
			let backgroundNode = SKShapeNode(rectOf: size, cornerRadius:
				10)
			
			// fill it with a random color
			backgroundNode.fillColor = UIColor(hue:
				CGFloat(GKRandomSource.sharedRandom().nextUniform()),
											   saturation: 0.5, brightness: 0.4, alpha: 0.9)
			
			// draw a border around it using a more opaque version of its fill color
			backgroundNode.strokeColor =
				backgroundNode.fillColor.withAlphaComponent(1)
			backgroundNode.lineWidth = 2
			
			// add the label to the background then send back the background
			backgroundNode.addChild(labelNode)
			return backgroundNode
	}
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
        
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
        
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        
    }
	
	// MARK: CLLocationManagerDelegate
	func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
		if status == .authorizedWhenInUse {
			locationManager.requestLocation()
		}
	}
	
	func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
		print(error.localizedDescription)
	}
	
	func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
		guard let location = locations.last else { return }
		userLocation = location
		
		DispatchQueue.global().async {
			self.fetchSights()
		}
	}
	
	// MARK: Others
	func fetchSights() {
		let urlString = "https://en.wikipedia.org/w/api.php?ggscoord=\(userLocation.coordinate.latitude)%7C\(userLocation.coordinate.longitude)&action=query&prop=coordinates%7Cpageimages%7Cpageterms&colimit=50&piprop=thumbnail&pithumbsize=500&pilimit=50&wbptterms=description&generator=geosearch&ggsradius=10000&ggslimit=50&format=json"
		guard let url = URL(string: urlString) else { return }
		
		if let data = try? Data(contentsOf: url) {
			sightsJSON = JSON(data)
			locationManager.startUpdatingHeading()
		}
		
	}
	
	func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
		DispatchQueue.main.async {
			self.headingCount += 1
			if self.headingCount != 2 {return}
			
			self.userHeading = newHeading.magneticHeading
			self.locationManager.startUpdatingHeading()
			self.createSights()
		}
	}
	
	func createSights() {
		// 1: Loop over all the pages from Wikipedia
		for page in sightsJSON["query"]["pages"].dictionaryValue.values {
			// 2: Pull out this pages coordinates and make a location from them
			let locationLat = page["coordinates"][0]["lat"].doubleValue
			let locationLon = page["coordinates"][0]["lon"].doubleValue
			let location = CLLocation(latitude: locationLat,
									  longitude: locationLon)
			
			// 3: Calculate the distance from the user to this point, then calculate its azimuth
			let distance = Float(userLocation.distance(from:
				location))
			let azimuthFromUser = direction(from: userLocation, to:
				location)
			
			// 4: Calculate the angle from the user to that direction
			let angle = azimuthFromUser - userHeading
			let angleRadians = deg2rad(angle)
			
			// 5: Create a horizontal rotation matrix
			let rotationHorizontal =
				simd_float4x4(SCNMatrix4MakeRotation(Float(angleRadians), 1, 0,
													 0))
			
			// 6: Create a vertical rotation matrix
			let rotationVertical =
				simd_float4x4(SCNMatrix4MakeRotation(-0.2 + Float(distance /
					6000), 0, 1, 0))
			
			// 7: Combine the horizontal and vertical matrices, then combine that with the camera transform.
			let rotation = simd_mul(rotationHorizontal,
									rotationVertical)
			guard let sceneView = self.view as? ARSKView else { return }
			guard let frame = sceneView.session.currentFrame else { return }
			let rotation2 = simd_mul(frame.camera.transform,
									 rotation)
			
			// 8: Create a matrix that lets us position the anchor into the screen, then combine that with our combined matrix so far
			var translation = matrix_identity_float4x4
			translation.columns.3.z = -(distance / 200)
			let transform = simd_mul(rotation2, translation)
			
			// create a new anchor using the final matrix, then add it to our `pages` dictionary.
			let anchor = ARAnchor(transform: transform)
			sceneView.session.add(anchor: anchor)
			pages[anchor.identifier] = page["title"].string ??
			"Unknown"
		}
	}
	
	func deg2rad(_ degrees: Double) -> Double {
		return degrees * .pi / 180
	}
	func rad2deg(_ radians: Double) -> Double {
		return radians * 180 / .pi
	}
	
	func direction(from p1: CLLocation, to p2: CLLocation) ->
		Double {
			let lat1 = deg2rad(p1.coordinate.latitude)
			let lon1 = deg2rad(p1.coordinate.longitude)
			let lat2 = deg2rad(p2.coordinate.latitude)
			let lon2 = deg2rad(p2.coordinate.longitude)
			
			let lon_delta = lon2 - lon1;
			let y = sin(lon_delta) * cos(lon2)
			let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) *
				cos(lon_delta)
			let radians = atan2(y, x)
			return rad2deg(radians)
	}
}
