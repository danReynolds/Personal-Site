---
title: "PlatformBuilder: A Library for Building Cross-platform Widgets"
layout: post
authors: ["Dan Reynolds"]
tags: ["Flutter", "Library"]
category: Tech
description: A dive into how the PlatformBuilder widget has helped us design cross-platform widgets.
image: "/images/tech/platform-builders/image.jpg"
---

A dive into how the PlatformBuilder widget has helped us design cross-platform widgets.

<!--halt-->

> This x-post is originally available at the [Pollyn Engineering blog](https://blog.pollyn.app/tech/2021-11-15-platform-builders/){:target="_blank"}.

When working with cross-platform apps, it is often valuable to share widgets like inputs, cards, lists and other core components across platforms like web and native. To make building these cross platform widgets easier, we built [Platform Builder](https://pub.dev/packages/platform_builder){:target="_blank"}, a Flutter library for performing platform checks and customizing widgets by platform and form factor. 

Sharing widgets across platforms have a number of great benefits:

* They reduce development time by only having to write the core functionality and tests for a widget once.
* It's easy to achieve design consistency since you don't need to rebuild UI with different tools across different platforms
* Making changes to core pieces of your UI is centralized, you won't miss updating an input to match new designs because you forgot to do it on one platform versus another. 

Let's look at an example of a shared widget from our own app:

![Button](/images/tech/platform-builders/button.png)

This is one of our buttons from our desktop Flutter app. You can see it in action on our [homepage](https://pollyn.app){:target="_blank"}. Some of our core widgets require no changes across platform, but a minority of them like `Button` needed some small padding and font size customizations. To achieve this, we first bifurcated our implementation by platform within the widget itself:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class Button extends StatelessWidget {
  final Widget child;
  final void Function() onPressed;
  
  Button({
    required this.child,
    required this.onPressed,
    Key key,
  }) : super(key: key);

  @override
  build(context) {
    return TextButton(
      key: key,
      onPressed: onPressed,
      child: child,
      style: ButtonStyle(
        padding: MaterialStateProperty.all(
          kIsWeb ? EdgeInsets.all(16) : EdgeInsets.all(14),
        ),
        shape: MaterialStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30.0),
          ),
        ),
        backgroundColor: MaterialStateProperty.resolveWith<Color>(
          (Set<MaterialState> states) {
            if (states.contains(MaterialState.disabled))
              return Colors.grey[400];

            return Colors.greenAccent;
          },
        ),
      )
    );
  }
}
```

This approach is the simplest, but it quickly becomes messy as the number of customizations we need and platforms that have to be supported grows. At Pollyn, we share our app across 5 platforms and combining all of those design specifications into one file quickly became impractical.

The next solution we came up with was to separate our cross platform specifications into separate files that reused the core widget implementation:

![Button folder](/images/tech/platform-builders/button-folder.png)

Our core button code implementation shown above now lives in the `BaseButton` file and our separate mobile, desktop and extension button widgets reuse the core implementation with minor customizations. Here's an example of our `MobileButton`:

```dart
import 'package:flutter/material.dart';
import 'package:pollyn/src/widgets/shared/Button/BaseButton.dart';
import 'package:pollyn/src/widgets/shared/Button/ButtonData.dart';

class MobileButton extends StatelessWidget {
  final ButtonData buttonData;

  MobileButton({required this.buttonData, Key key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BaseButton(
      buttonData: buttonData.defaultWith(
        padding: EdgeInsets.all(16),
      ),
    );
  }
}
```

The `MobileButton` is essentially a `BaseButton` with some slight tweaking to the base padding. You will notice that we use A `ButtonData` class for specifying the `BaseButton` configuration. Similarly to Flutter Material's [ButtonStyle](https://api.flutter.dev/flutter/material/ButtonStyle-class.html){:target="_blank"} class, we use data classes to pass around configuration options so that we don't need to repeat ourselves as much when working with cross platform widgets that all take the same set of parameters.

The `ButtonData` class is defined as shown below:

```dart
import 'package:flutter/material.dart';

class ButtonData {
  Function onPressed;
  Widget child;
  EdgeInsets padding;

  ButtonData({
    this.onPressed,
    this.padding,
    this.child,
    Key key,
  }) : super(key: key);

  defaultWith({
    void Function() onPressed,
    Widget child,
    EdgeInsets padding,
  }) {
    return ButtonData(
      onPressed: this.onPressed ?? onPressed,
      text: this.text ?? text,
      color: this.color ?? color,
      textColor: this.textColor ?? textColor,
      child: this.child ?? child,
      padding: this.padding ?? padding,
      key: this.key ?? key,
      disabled: this.disabled ?? disabled,
      intrinsicWidth: this.intrinsicWidth ?? intrinsicWidth,
      textSize: this.textSize ?? textSize,
    );
  }
}
```

Platform specific screens can then important the version of the `Button` widget that they need and we can have all of our buttons powered by the same core button implementation.

One issue with this approach, however, is that we may not always be using the widget from a platform specific screen. If we want to use a button on a cross-platform screen, we would need to use another platform check on that screen to determine which implementation to use.

We need a way of detecting our platform and automatically choosing the right implementation of our widgets. To solve this problem, we created a [Platform builder](https://pub.dev/packages/platform_builder){:target="_blank"} widget.

## Platform Builder

The [Platform builder](https://pub.dev/packages/platform_builder){:target="_blank"} provides builders for the following platforms:

* android
* iOS
* macOS
* linux
* fuschia
* windows
* web
* chrome extension

A basic example of using `PlatformBuilder` looks like this:

```dart
import 'package:platform_builder/platform_builder.dart';

class MyWidget extends StatelessWidget {
  @override
  build(context) {
    return PlatformBuilder(
      androidBuilder: (context) => Icon(Icons.android),
      iOSBuilder: (context) => Icon(Icons.apple),
    ),
  }
}
```

It also supports providing separate builders across different form factors, currently desktop and mobile. You may have noticed that the folder structure for our `Button` widget included a `Button.dart` file alongside the base and platform specific implementations. This is our cross-platform widget that uses `PlatformBuilder` to pick which widget to use:

```dart
import 'package:flutter/material.dart';
import 'package:platform_builder/platform_builder.dart';
import 'package:pollyn/src/widgets/shared/Button/ExtensionButton.dart';
import 'package:pollyn/src/widgets/shared/Button/MobileButton.dart';
import 'package:pollyn/src/widgets/shared/Button/DesktopButton.dart';
import 'package:pollyn/src/widgets/shared/Button/ButtonData.dart';

class Button extends StatelessWidget {
  final Function onPressed;
  final Widget child;
  final EdgeInsets padding;

  Button({
    this.onPressed,
    this.child,
    this.padding,
    Key key,
  }) : super(key: key);

  @override
  Widget build(context) {
    final buttonData = ButtonData(
      onPressed: onPressed,
      child: child,
      padding: padding,
      key: key,
    );

    return PlatformBuilder(
      desktop: FormFactorDelegate(
        builder: (context) => DesktopButton(buttonData: buttonData),
      ),
      mobile: FormFactorDelegate(
        builder: (context) => MobileButton(buttonData: buttonData),
        chromeExtensionBuilder: (context) =>
            ExtensionButton(buttonData: buttonData),
      ),
    );
  }
}
```

Here we are saying that on desktop, all platforms should use the same `DesktopButton` implementation. Meanwhile on mobile, if the current platform is the Chrome extension, it should use its own custom button implementation, while all other mobile buttons should use the `MobileButton` widget.

Most of the time, our core widget implementations just need to be split by desktop and mobile form factors, in which case we can use the `FormFactorBuilder` helper:

```dart
import 'package:platform_builder/platform_builder.dart';

class MyWidget extends StatelessWidget {
  @override
  build(context) {
    return FormFactorBuilder(
      mobile: (context) {...},
      desktop: (context) {...}
    ),
  }
}
```

This widget is a thin wrapper around `PlatformBuilder` to simplify specifying distinct `mobile` and `desktop` implementations.

Now, you make be looking at `PlatformBuilder` and asking, *why not just use conditional statements?* Good question!

We found there to be two main reasons we preferred this abstraction over directly using if/else platform checks:

1. Readability and consistent code style/organization
2. Platform coverage checks

The first point is pretty self-explanatory, but what do we mean in that second point about platform coverage checks? As we scaled our app to 5 platforms and consider bring it to more, we need to make sure that we don't accidentally miss providing an implementation for a supported platform. This is an easy mistake to make with basic conditional statements. `PlatformBuilder`, on the other hand, will throw a runtime error if any of our supported platform are missing a matching implementation.

We do this by specifying a list of supported platforms:

```dart
import 'package:platform_builder/platform_builder.dart';

class MyWidget extends StatelessWidget {
  @override
  build(context) {
    return PlatformBuilder(
      supportedPlatforms: [Platforms.iOS, Platforms.android],
      androidBuilder: (context) => Icon(Icons.android),
      iOSBuilder: (context) => Icon(Icons.apple),
    ),
  }
}
```

In this example, if no matching builder for android or iOS is provided, our widget will throw an assertion error and let us know that we missed covering one of our supported platforms. Under the hood, `PlatformBuilder` looks for a matching implementation in order of more specific builders to less specific ones. Here's the order it uses for the Android and iOS:

```dart
Widget Function(BuildContext context)? get _androidBuilder {
  return _formFactorDelegate?.androidBuilder ??
      androidBuilder ??
      _nativeBuilder;
}

Widget Function(BuildContext context)? get _iOSBuilder {
  return _formFactorDelegate?.iOSBuilder ?? iOSBuilder ?? _nativeBuilder;
}

Widget Function(BuildContext context)? get _nativeBuilder {
  return _formFactorDelegate?.nativeBuilder ?? nativeBuilder ?? _builder;
}

Widget Function(BuildContext context)? get _builder {
  return _formFactorDelegate?.builder ?? builder;
}
```

For the Android platform, first we try to find a form factor specific android builder, followed by any android builder and then lastly any native builder, which is a helper for either iOS or Android. We can follow the chain of logic all the way to the base `builder` function that is shared by all platforms.

The `PlatformBuilder` widget will then make an assertion as shown below:

```dart
assert(
  !_supportedPlatforms.contains(Platforms.android) ||
      _androidBuilder != null,
  'Missing android platform builder',
);
```

We will then get immediate feedback if we specified android as a supported platform and failed to provide a matching implementation. This isn't foolproof though, since we could always forget to specify the android platform in the widget's `supportedPlatforms` list. To make this simpler and eliminate the need for having to pass your supported platforms all the time, `PlatformBuilder` uses a `PlatformService` singleton under the hood that we can instantiate with our platforms once at app startup:

```dart
import 'package:platform_builder/platform_builder.dart';

Platform.init(
  supportedPlatforms: [
    Platforms.iOS,
    Platforms.android,
    Platforms.web,
  ]
);
```

Now all of our platform builder widgets will know what platforms we support and check that we have our bases covered across all usages. If we are actively working on a particular widget and don't have all of our platform implementations ready yet, we can always override this default by explicitly passing the list of supported platforms as an override to the specific `PlatformBuilder` we're working on. You can throw this initialization code in your `main.dart` file when starting up your application.

The platform initializer is also the place where we specify our breakpoint for mobile vs desktop form factors:

```dart
import 'package:platform_builder/platform_builder.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Platform.init(
  /// The breakpoint at which the width of the application should be considered
  /// the desktop form factor.
  desktopBreakpoint: 760,
  /// A global navigator key used to access the current screen size.
  navigatorKey: navigatorKey,
);

class MyApp extends StatelessWidget {
  @override
  build(context) {
    return MaterialApp(
      home: Home(),
      /// Pass the same `navigatorKey` to the root of your app.
      navigatorKey: navigatorKey,
    );
  }
}
```

In order to keep track of the current screen size, we need to pass in a shared global navigator key to both the platform `init()` as well as our root `MaterialApp` so that `PlatformBuilder` will have access to the current build context.

## Platform checks

The platform singleton used by `PlatformBuilder` for selecting widget implementations is a useful tool on its own for performing platform checks outside of our widget code. While Dart has its own `Platform` class available through `dart:io`, it has a few shortcomings:

1. Calling native platforms checks like `Platform.isIOS` on web throws an exception.
2. There is no included check for web, instead you need to check `package:flutter/foundation.dart` separately for the `kIsWeb` flag.

The platform singleton additionally expands the functionality of the base platform library to include the following helpers:

* `Platform.instance.current`: The current Flutter application platform.
* `Platform.instance.currentHost`: The application's host operating system (Ex. host macOS for application web).
* `Platform.instance.isCanvasKit`: Whether the application is using the CanvasKit renderer.
* `Platform.instance.isHtml`: Whether the application is using the HTML renderer.

To use the platform singleton, import it from the platform builder library:

```dart
import 'package:platform_builder/platform_builder.dart';

if (Platform.instance.isAndroid) {
  print('android');
} else if (Platform.instance.isWeb) {
  print('web');
}
```

## All for now

That's all we have for now on building cross platform widgets with Flutter. Let us know if there are any additional features or use cases you'd like to see addressed in the platform builder lib on [our GitHub](https://github.com/danReynolds/platform_builder){:target="_blank"}. Happy coding!