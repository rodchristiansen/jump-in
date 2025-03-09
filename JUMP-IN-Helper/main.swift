import Foundation

class HelperToolDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Configure the connection
        newConnection.exportedInterface = NSXPCInterface(with: HelperToolProtocol.self)
        
        // Create and set the exported object
        let exportedObject = HelperTool()
        newConnection.exportedObject = exportedObject
        
        // Resume the connection
        newConnection.resume()
        
        return true
    }
}

// Create the listener for the helper tool
let delegate = HelperToolDelegate()

// IMPORTANT: Use the machServiceName instead of NSXPCListener.service()
let listener = NSXPCListener(machServiceName: "com.IRL.jump-in.helper")
listener.delegate = delegate

// Log that helper is starting
print("Helper tool starting...")

// Start the listener and run the helper tool
listener.resume()
RunLoop.main.run()
