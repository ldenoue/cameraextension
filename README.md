# cameraextension
sample camera extension using coremedia io based on code I'm using in my own app Screegle https://www.appblit.com/screegle available on the App Store. This is why this new Camera Extension framework is so good: it lets us ship virtual cameras inside an app bundle that can be distributed on the App Store. And these cameras work in any app on macOS (including Apple's own apps such as FaceTime, QuickTime, Safari, etc.).

this example creates a virtual camera that has 2 streams: a source and a sink stream

- the source stream is used by apps that want to receive frames from our camera (e.g. QuickTime, Zoom, Safari, etc.)
- the sink stream is used by our own app to send frames to the virtual camera, which immediately forwards them to its source stream

when the sink stream is not started, the camera simply shows a black frame with a text (+ number of seconds)

when the app runs, it asks the camera (using CoreMediaIO C API in Swift) if its source stream has started (meaning that at least one client such as QuickTime wants to see frames). If so, it starts sending frames to the sink (on our case a static image of Chamonix).

after you compiled the code, find where it is using Xcode menu `Product` and `Show Build Folder in Finder` then open the `Build > Products > Debug` and drag `samplecamera` into `Applications`

From `/Applications` open `samplecamera`

Only then will the `activate` button work

To see the camera working, open for example QuickTime and pick the `sample camera`. You should see a beautiful picture of Chamonix.

# links that can be useful


- Apple documentation https://developer.apple.com/documentation/coremediaio/creating_a_camera_extension_with_core_media_i_o
- WWDC22 video explaining camera extensions https://developer.apple.com/videos/play/wwdc2022/10022/
- Forum about custom properties https://developer.apple.com/forums/thread/708548
- Forum about the idea of using a source and sink streams instead of XPC https://developer.apple.com/forums/thread/706184
