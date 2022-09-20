# TodoApp iOS: An iOS Sample App

This xcode project wraps the [Desktop Sample App](https://github.com/elixir-desktop/desktop-example-app) to run on an iPhone.

## How to build & run

1. Install xcode from the app store.
1. Install brew, git, carthage, npm

    `brew install carthage git openssl@1.1 npm`

1. Install Erlang-OTP (with openssl) in the same version 25.0.4 as the bundled runtime edition:

    ```
    asdf install erlang 25.0.4
    asdf install elixir 1.13.4-otp-25
    ```

    If above fails for you on an older mac or can't seem to find openssl you can try this custom build command as well:

    ```
    export DED_LDFLAGS_CONFTEST="-bundle"
    export KERL_CONFIGURE_OPTIONS="--without-javac --with-ssl=$(brew --prefix openssl@1.1)"
    asdf install erlang 25.0.4
    asdf install elixir 1.13.4-otp-25
    ```

1. fork / git clone this project to your local disk:

    `git clone https://github.com/elixir-desktop/ios-example-app.git`

1. Build the dependencies:

    `cd ios-example-app && carthage update --use-xcframeworks`

1. Open the ios-example-app project with xcode
1. Start the App

## Known todos

### Menus and other integration not yet available

This sample only launch the elixir app and shows it in a WKWebView. There is no integration yet with the iOS Clipboard, sharing or other OS capabilities. They can though easily be added to the `Bridge.swift` file when needed.

##  Other notes

- The Erlang runtime is for ease of use embedded in this example git repository. The native runtimes for M1 and iPhoneOS and the exqlite nif are are generated using the [Desktop Runtime](https://github.com/elixir-desktop/runtimes) repository. 

- iOS specific settings, icons and metadata are all contained in this xcode wrapper project. 

- `Bridge.swift` and the native library are doing most of the wrapping of the Elixir runtime. 

## Screenshots

![App](/app.png?raw=true "Running App")

## Architecture

![App](/ios_elixir.png?raw=true "Architecture")

The iOS App is initializing the Erlang VM and starting it up with a new environment variable `BRIDGE_PORT`. This environment variable is used by the `Bridge` Elixir project to connect to a local TCP server _inside the iOS app_. Through this new TCP communication channel all calls that usually would go to `wxWidgets` are now redirected. The iOS side of things implements handling in `Bridge.swift`.  
