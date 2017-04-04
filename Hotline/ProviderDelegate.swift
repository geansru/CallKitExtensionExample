//
//  ProviderDelegate.swift
//  Hotline
//
//  Created by Dmitriy Roytman on 03.04.17.
//  Copyright © 2017 Razeware LLC. All rights reserved.
//

import AVFoundation
import CallKit

class ProviderDelegate: NSObject {
    fileprivate let callManager: CallManager
    fileprivate let provider: CXProvider
    
    init(callManager: CallManager) {
        self.callManager = callManager
        provider = CXProvider(configuration: type(of: self).providerConfiguration)
        super.init()
        provider.setDelegate(self, queue: nil)
    }
    
    static var providerConfiguration: CXProviderConfiguration {
        let providerConfiguration = CXProviderConfiguration(localizedName: "Hotline")
        providerConfiguration.supportsVideo = true
        providerConfiguration.maximumCallsPerCallGroup = 1
        providerConfiguration.supportedHandleTypes = [.phoneNumber]
        return providerConfiguration
    }
    
    func reportIncomingCall(uuid: UUID, handle: String, hasVideo: Bool = false, completion: ((NSError?)->())?) {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .phoneNumber, value: handle)
        
        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            if error == nil {
                let call = Call(uuid: uuid, handle: handle)
                self?.callManager.add(call: call)
            }
            
            completion?(error as? NSError)
        }
        
    }
}

extension ProviderDelegate: CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
        stopAudio()
        callManager.calls.forEach { $0.end() }
        callManager.removeAllCalls()
    }
    
    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        let call = Call(uuid: action.callUUID, outgoing: true, handle: action.handle.value)
        configureAudioSession()
        call.connectedStateChanged = { [weak self, weak call] in
            guard let sself = self, let call = call else { return }
            switch call.connectedState {
            case .pending: sself.provider.reportOutgoingCall(with: call.uuid, startedConnectingAt: nil)
            case .complete: sself.provider.reportOutgoingCall(with: call.uuid, connectedAt: nil)
            }
        }
        call.start { [weak self, weak call] success in
            guard let sself = self, let call = call else { return }
            guard success else { action.fail(); return }
            action.fulfill()
            sself.callManager.add(call: call)
        }
    }
    
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        guard let call = callManager.callWithUUID(uuid: action.callUUID) else { action.fail(); return }
        configureAudioSession()
        call.answer()
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        guard let call = callManager.callWithUUID(uuid: action.callUUID) else { action.fail(); return }
        
        stopAudio()
        call.end()
        action.fulfill()
        callManager.remove(call: call)
    }
    
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        startAudio()
    }
    
    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        guard let call = callManager.callWithUUID(uuid: action.callUUID) else { action.fail(); return }
        call.state = action.isOnHold ? .held : .active
        if call.state == .held { stopAudio() } else { startAudio() }
        action.fulfill()
    }
}
