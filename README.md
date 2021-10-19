# TodoApp iOS: An iOS Sample App

This xcode project wraps the [Desktop Sample App](https://github.com/elixir-desktop/desktop-example-app) to run on an iPhone.

## How to build & run

1. Install xcode from the app store.
1. Install brew, elixir, git, carthage, npm

    `brew install elixir carthage git npm`

1. fork / git clone this project to your local disk:

    `git clone https://github.com/elixir-desktop/ios-example-app.git`
1. Build the dependencies:

    `cd ios-example-app && carthage update --use-xcframeworks`

1. Open the ios-example-app project with xcode
1. Start the App

## Known todos

### Can only emulate on Apple M1 and on real iPhones

The bundled binaries are only for the real iPhone as well as the Apple M1 mac machines. If you've got an intel based x86 mac the emulator won't run at the moment.

### Menus and other integration not yet available

This sample only launch the elixir app and shows it in a WKWebView. There is no integration yet with the iOS Clipboard, sharing or other OS capabilities. They can though easily be added to the `Bridge.swift` file when needed.

##  Other notes

- The Erlang runtime is for ease of use embedded in this example git repository. The native runtimes for M1 and iPhoneOS and the exqlite nif are are generated using the [Desktop Runtime](https://github.com/elixir-desktop/runtimes) repository. 

- iOS specific settings, icons and metadata are all contained in this xcode wrapper project. 

- `Bridge.swift` and the native library are doing most of the wrapping of the Elixir runtime. 

## Screenshots

![App](/app.png?raw=true "Running App")

## Architecture

![App](/iox_elixir.png?raw=true "Architecture")

The iOS App is initializing the Erlang VM and starting it up with a new environment variable `BRIDGE_PORT`. This environment variable is used by the `Bridge` Elixir project to connect to a local TCP server _inside the iOS app_. Through this new TCP communication channel all calls that usually would go to `wxWidgets` are now redirected. The iOS side of things implements handling in `Bridge.swift`.  