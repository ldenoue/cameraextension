//
//  cameraextensionProvider.swift
//  cameraextension
//
//  Created by laurent denoue on 7/1/22.
//

import Foundation
import CoreMediaIO
import IOKit.audio
import os.log
import Cocoa

let textColor = NSColor.white
let fontSize = 24.0
let textFont = NSFont.systemFont(ofSize: fontSize)
let CMIOExtensionPropertyCustomPropertyData_just: CMIOExtensionProperty = CMIOExtensionProperty(rawValue: "4cc_just_glob_0000")
let kWhiteStripeHeight: Int = 10

// MARK: -

class cameraDeviceSource: NSObject, CMIOExtensionDeviceSource {
    
    private(set) var device: CMIOExtensionDevice!
    
    public var _streamSource: cameraStreamSource!
    public var _streamSink: cameraStreamSink!
    private var _streamingCounter: UInt32 = 0
    private var _streamingSinkCounter: UInt32 = 0
    
    private var _timer: DispatchSourceTimer?
    
    private let _timerQueue = DispatchQueue(label: "timerQueue", qos: .userInteractive, attributes: [], autoreleaseFrequency: .workItem, target: .global(qos: .userInteractive))

    private var _videoDescription: CMFormatDescription!
    
    private var _bufferPool: CVPixelBufferPool!
    
    private var _bufferAuxAttributes: NSDictionary!
    
    private var _whiteStripeStartRow: UInt32 = 0
    
    private var _whiteStripeIsAscending: Bool = false
    
    var lastMessage = "Sample Camera for macOS"
    
    func myStreamingCounter() -> String {
        return "sc=\(_streamingCounter)"
    }

    init(localizedName: String) {
        
        paragraphStyle.alignment = NSTextAlignment.center
        textFontAttributes = [
            NSAttributedString.Key.font: textFont,
            NSAttributedString.Key.foregroundColor: textColor,
            NSAttributedString.Key.paragraphStyle: paragraphStyle
        ]
        super.init()
        let deviceID = UUID()
        self.device = CMIOExtensionDevice(localizedName: localizedName, deviceID: deviceID, legacyDeviceID: deviceID.uuidString, source: self)
        
        //let dims = CMVideoDimensions(width: 1920, height: 1080)
        let dims = CMVideoDimensions(width: fixedCamWidth, height: fixedCamHeight)
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCVPixelFormatType_32BGRA,
            //codecType: kCVPixelFormatType_32ARGB/*kCVPixelFormatType_32BGRA*/,
            width: dims.width, height: dims.height, extensions: nil, formatDescriptionOut: &_videoDescription)
        
        let pixelBufferAttributes: NSDictionary = [
            kCVPixelBufferWidthKey: dims.width,
            kCVPixelBufferHeightKey: dims.height,
            kCVPixelBufferPixelFormatTypeKey: _videoDescription.mediaSubType,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, pixelBufferAttributes, &_bufferPool)
        
        let videoStreamFormat = CMIOExtensionStreamFormat.init(formatDescription: _videoDescription, maxFrameDuration: CMTime(value: 1, timescale: Int32(kFrameRate)), minFrameDuration: CMTime(value: 1, timescale: Int32(kFrameRate)), validFrameDurations: nil)
        _bufferAuxAttributes = [kCVPixelBufferPoolAllocationThresholdKey: 5]
        
        let videoID = UUID()
        _streamSource = cameraStreamSource(localizedName: "SampleCamera.Video", streamID: videoID, streamFormat: videoStreamFormat, device: device)
        let videoSinkID = UUID()
        _streamSink = cameraStreamSink(localizedName: "SampleCamera.Video.Sink", streamID: videoSinkID, streamFormat: videoStreamFormat, device: device)
        do {
            try device.addStream(_streamSource.stream)
            try device.addStream(_streamSink.stream)
        } catch let error {
            fatalError("Failed to add stream: \(error.localizedDescription)")
        }
    }
    
    var availableProperties: Set<CMIOExtensionProperty> {
        
        return [.deviceTransportType, .deviceModel]
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        
        let deviceProperties = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) {
            deviceProperties.transportType = kIOAudioDeviceTransportTypeVirtual
        }
        if properties.contains(.deviceModel) {
            //deviceProperties.setPropertyState(CMIOExtensionPropertyState(value: "toto" as NSString), forProperty: .deviceModel)
            deviceProperties.model = "Sample Camera Model"
        }
        
        return deviceProperties
    }
    
    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {
        
        
        // Handle settable properties here.
    }

    let paragraphStyle = NSMutableParagraphStyle()
    let textFontAttributes: [NSAttributedString.Key : Any]

    func startStreaming() {
        
        guard let _ = _bufferPool else {
            return
        }
        
        _streamingCounter += 1
        _timer = DispatchSource.makeTimerSource(flags: .strict, queue: _timerQueue)
        _timer!.schedule(deadline: .now(), repeating: 1.0/Double(kFrameRate), leeway: .seconds(0))
        
        _timer!.setEventHandler {

            if self.sinkStarted {
                return
            }
            //var text: String? = nil
             var err: OSStatus = 0
            
            var pixelBuffer: CVPixelBuffer?

            let timestamp = CMClockGetTime(CMClockGetHostTimeClock())
            let text = self.lastMessage + " \(Int(timestamp.seconds))"
            err = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, self._bufferPool, self._bufferAuxAttributes, &pixelBuffer)
            if err != 0 {
                os_log(.error, "out of pixel buffers \(err)")
            }
            if let pixelBuffer = pixelBuffer {
                
                CVPixelBufferLockBaseAddress(pixelBuffer, [])
                let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer)
                let width = CVPixelBufferGetWidth(pixelBuffer)
                let height = CVPixelBufferGetHeight(pixelBuffer)
                let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
                if let context = CGContext(data: pixelData,
                                              width: width,
                                              height: height,
                                              bitsPerComponent: 8,
                                              bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                              space: rgbColorSpace,
                                           //bitmapInfo: UInt32(CGImageAlphaInfo.noneSkipFirst.rawValue) | UInt32(CGImageByteOrderInfo.order32Little.rawValue))
                                           bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
                {

                    let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = graphicsContext
                    let cgContext = graphicsContext.cgContext
                    let dstRect = CGRect(x: 0, y: 0, width: width, height: height)
                    cgContext.clear(dstRect)
                    cgContext.setFillColor(NSColor.black.cgColor)
                    cgContext.fill(dstRect)
                    let textOrigin = CGPoint(x: 0, y: -height/2 + Int(fontSize/2.0))
                    let rect = CGRect(origin: textOrigin, size: NSSize(width: width, height: height))
                    text.draw(in: rect, withAttributes: self.textFontAttributes)
                    NSGraphicsContext.restoreGraphicsState()
                }
                CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            }

            if let pixelBuffer = pixelBuffer {
                var sbuf: CMSampleBuffer!
                var timingInfo = CMSampleTimingInfo()
                timingInfo.presentationTimeStamp = CMClockGetTime(CMClockGetHostTimeClock())
                err = CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: self._videoDescription, sampleTiming: &timingInfo, sampleBufferOut: &sbuf)
                if err == 0 {
                    self._streamSource.stream.send(sbuf, discontinuity: [], hostTimeInNanoseconds: UInt64(timingInfo.presentationTimeStamp.seconds * Double(NSEC_PER_SEC)))
                } else {
                    self.lastMessage = "err send"
                }
            }
        }
        
        _timer!.setCancelHandler {
        }
        
        _timer!.resume()
    }
    
    func stopStreaming() {
        if _streamingCounter > 1 {
            _streamingCounter -= 1
        }
        else {
            _streamingCounter = 0
            if let timer = _timer {
                timer.cancel()
                _timer = nil
            }
        }
    }
    
    var sinkStarted = false
    var lastTimingInfo = CMSampleTimingInfo()
    func consumeBuffer(_ client: CMIOExtensionClient) {
        if sinkStarted == false {
            return
        }
        self._streamSink.stream.consumeSampleBuffer(from: client) { sbuf, seq, discontinuity, hasMoreSampleBuffers, err in
            if sbuf != nil {
                self.lastTimingInfo.presentationTimeStamp = CMClockGetTime(CMClockGetHostTimeClock())
                let output: CMIOExtensionScheduledOutput = CMIOExtensionScheduledOutput(sequenceNumber: seq, hostTimeInNanoseconds: UInt64(self.lastTimingInfo.presentationTimeStamp.seconds * Double(NSEC_PER_SEC)))
                if self._streamingCounter > 0 {
                self._streamSource.stream.send(sbuf!, discontinuity: [], hostTimeInNanoseconds: UInt64(sbuf!.presentationTimeStamp.seconds * Double(NSEC_PER_SEC)))
                }
                self._streamSink.stream.notifyScheduledOutputChanged(output)
            }
            self.consumeBuffer(client)
        }
    }

    func startStreamingSink(client: CMIOExtensionClient) {
        
        _streamingSinkCounter += 1
        self.sinkStarted = true
        consumeBuffer(client)
    }
    
    func stopStreamingSink() {
        self.sinkStarted = false
        if _streamingSinkCounter > 1 {
            _streamingSinkCounter -= 1
        }
        else {
            _streamingSinkCounter = 0
        }
    }}

// MARK: -

class cameraStreamSource: NSObject, CMIOExtensionStreamSource {
    
    private(set) var stream: CMIOExtensionStream!
    
    let device: CMIOExtensionDevice
    //public var nConnectedClients = 0
    private let _streamFormat: CMIOExtensionStreamFormat
    
    init(localizedName: String, streamID: UUID, streamFormat: CMIOExtensionStreamFormat, device: CMIOExtensionDevice) {
        
        self.device = device
        self._streamFormat = streamFormat
        super.init()
        self.stream = CMIOExtensionStream(localizedName: localizedName, streamID: streamID, direction: .source, clockType: .hostTime, source: self)
    }
    
    var formats: [CMIOExtensionStreamFormat] {
        
        return [_streamFormat]
    }
    
    var activeFormatIndex: Int = 0 {
        
        didSet {
            if activeFormatIndex >= 1 {
                os_log(.error, "Invalid index")
            }
        }
    }
    
    var availableProperties: Set<CMIOExtensionProperty> {
        
        return [.streamActiveFormatIndex, .streamFrameDuration, CMIOExtensionPropertyCustomPropertyData_just]
    }

    public var just: String = "toto"
    public var rust: String = "0"
    var count = 0

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let streamProperties = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            streamProperties.activeFormatIndex = 0
        }
        if properties.contains(.streamFrameDuration) {
            let frameDuration = CMTime(value: 1, timescale: Int32(kFrameRate))
            streamProperties.frameDuration = frameDuration
        }
        if properties.contains(CMIOExtensionPropertyCustomPropertyData_just) {
            streamProperties.setPropertyState(CMIOExtensionPropertyState(value: self.just as NSString), forProperty: CMIOExtensionPropertyCustomPropertyData_just)

        }
        return streamProperties
    }
    
    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        
        if let activeFormatIndex = streamProperties.activeFormatIndex {
            self.activeFormatIndex = activeFormatIndex
        }
        
        if let state = streamProperties.propertiesDictionary[CMIOExtensionPropertyCustomPropertyData_just] {
            if let newValue = state.value as? String {
                self.just = newValue
                if let deviceSource = device.source as? cameraDeviceSource {
                    self.just = deviceSource.myStreamingCounter()
                }
            }
        }
    }
    
    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        
        // An opportunity to inspect the client info and decide if it should be allowed to start the stream.
        return true
    }
    
    func startStream() throws {
        
        guard let deviceSource = device.source as? cameraDeviceSource else {
            fatalError("Unexpected source type \(String(describing: device.source))")
        }
        self.rust = "1"
        deviceSource.startStreaming()
    }
    
    func stopStream() throws {
        
        guard let deviceSource = device.source as? cameraDeviceSource else {
            fatalError("Unexpected source type \(String(describing: device.source))")
        }
        self.rust = "0"
        deviceSource.stopStreaming()
    }
}

class cameraStreamSink: NSObject, CMIOExtensionStreamSource {
    
    private(set) var stream: CMIOExtensionStream!
    
    let device: CMIOExtensionDevice
    private let _streamFormat: CMIOExtensionStreamFormat
    
    init(localizedName: String, streamID: UUID, streamFormat: CMIOExtensionStreamFormat, device: CMIOExtensionDevice) {
        
        self.device = device
        self._streamFormat = streamFormat
        super.init()
        self.stream = CMIOExtensionStream(localizedName: localizedName, streamID: streamID, direction: .sink, clockType: .hostTime, source: self)
    }
    
    var formats: [CMIOExtensionStreamFormat] {
        
        return [_streamFormat]
    }
    
    var activeFormatIndex: Int = 0 {
        
        didSet {
            if activeFormatIndex >= 1 {
                os_log(.error, "Invalid index")
            }
        }
    }
    
    var availableProperties: Set<CMIOExtensionProperty> {
        
        return [.streamActiveFormatIndex, .streamFrameDuration, .streamSinkBufferQueueSize, .streamSinkBuffersRequiredForStartup, .streamSinkBufferUnderrunCount, .streamSinkEndOfData]
    }

    var client: CMIOExtensionClient?
    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let streamProperties = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            streamProperties.activeFormatIndex = 0
        }
        if properties.contains(.streamFrameDuration) {
            let frameDuration = CMTime(value: 1, timescale: Int32(kFrameRate))
            streamProperties.frameDuration = frameDuration
        }
        if properties.contains(.streamSinkBufferQueueSize) {
            streamProperties.sinkBufferQueueSize = 1
        }
        if properties.contains(.streamSinkBuffersRequiredForStartup) {
            streamProperties.sinkBuffersRequiredForStartup = 1
        }
        return streamProperties
    }
    
    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        
        if let activeFormatIndex = streamProperties.activeFormatIndex {
            self.activeFormatIndex = activeFormatIndex
        }
        
    }
    
    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        
        // An opportunity to inspect the client info and decide if it should be allowed to start the stream.
        self.client = client
        return true
    }
    
    func startStream() throws {
        
        guard let deviceSource = device.source as? cameraDeviceSource else {
            fatalError("Unexpected source type \(String(describing: device.source))")
        }
        if let client = client {
            deviceSource.startStreamingSink(client: client)
        }
    }
    
    func stopStream() throws {
        
        guard let deviceSource = device.source as? cameraDeviceSource else {
            fatalError("Unexpected source type \(String(describing: device.source))")
        }
        deviceSource.stopStreamingSink()
    }
}

// MARK: -

class cameraProviderSource: NSObject, CMIOExtensionProviderSource {
    
    private(set) var provider: CMIOExtensionProvider!
    
    private var deviceSource: cameraDeviceSource!

    init(clientQueue: DispatchQueue?) {
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
        deviceSource = cameraDeviceSource(localizedName: cameraName)
        
        do {
            try provider.addDevice(deviceSource.device)
        } catch let error {
            fatalError("Failed to add device: \(error.localizedDescription)")
        }
    }

    func connect(to client: CMIOExtensionClient) throws {
        
    }

    func disconnect(from client: CMIOExtensionClient) {
        
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        
        // See full list of CMIOExtensionProperty choices in CMIOExtensionProperties.h
        return [.providerManufacturer]
    }
    
    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        
        let providerProperties = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) {
            providerProperties.manufacturer = "Sample Camera Manufacturer"
        }
        return providerProperties
    }
    
    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {
        // Handle settable properties here.
    }
}
