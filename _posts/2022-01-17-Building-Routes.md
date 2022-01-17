---
title: "Building and matching routes"
layout: post
authors: ["Dan Reynolds"]
tags: ["Flutter", "Guide"]
category: Tech
description: How to build and match routes on Flutter web with RouteBuilder.
image: "/images/tech/building-routes/image.jpg"
---

How to build and match routes on Flutter web with RouteBuilder.

<!--halt-->

> This x-post is originally available at the [Pollyn Engineering blog](https://blog.pollyn.app/posts/2022-01-17-building-routes/){:target="_blank"}.

When working with navigation in Flutter, there are great reasons why you should try to make sure you have named routes:

1. It makes it easy to get out of the box screen-navigation analytics using tools like [Firebase analytics](https://firebase.flutter.dev/docs/analytics/usage){:target="_blank"}.
2. It can decrease code duplication. Check out the [Flutter cookbook](https://docs.flutter.dev/cookbook/navigation/named-routes){:target="_blank"} on named routes to learn more.
3. It generates unique URIs on web so that users can copy/paste and deep link to different parts of your application.

Since our app [Pollyn](https://pollyn.app){:target="_blank"} is available as a Flutter web app, this last point was especially important. In this post, we'll go through how applications can generate unique routes for all of their screens and modals as seen below:

![Demo](/images/tech/building-routes/demo.gif)

## Building route names

Flutter supports specifying route names when performing navigation events:

```dart
Navigator.of(context).pushNamed('/location');
```

This navigation action will update the URI path on Flutter web to `/location`. We can similarly update the path for anonymous routes by specifying a route settings object:

```dart
Navigator.of(context).push(
  MaterialPageRoute(
    settings: RouteSettings('/location'),
    builder: (BuildContext context) {
      return child;
    },
  )
);
```

Updating the URI in this way becomes more challenging when we need to introduce dynamic arguments to route names such as in the following example where we're viewing a message from an employee:

```dart
final employeeId = uuid();
final messageId = uuid();

Navigator.of(context).push(
  MaterialPageRoute(
    settings: RouteSettings('/employee/$employeeId/messages/$messageId'),
    builder: (BuildContext context) {
      return ViewEmployeeMessage();
    },
  )
);
```

We want to make sure that we're always formatting our route names correctly across all the places in our app where we navigate to an employee message. To make this process easier and more consistent to work with, we created the [Route Builder](https://pub.dev/packages/route_builder){:target="_blank"} for building and matching routes by path, query parameters and arguments.

Here is an example where we define some routes for managing employee messages using Route Builder:

```dart
import 'package:route_builder/route_builder.dart';

class EmployeeMessageArguments extends Arguments {
  final String employeeId;
  final String messageId;

  EmployeeMessageArguments({
    required this.employeeId,
    required this.messageId,
  });

  @override
  toJson() {
    return {
      "employeeId": employeeId,
      "messageId": messageId,
    };
  }
}

class EmployeeMessageArgsFactory extends ArgumentsFactory<EmployeeMessageArguments> {
  @override
  fromJson(json) {
    return EmployeeMessageArguments(
      employeeId: employeeId,
      messageId: messageId
    );
  }
}

class Routes {
  static final viewEmployeeMessage = RouteFactory<EmployeeMessageArguments>(
    '/employee/{employeeId}/messages/{employeeMessage}',
    argsFactory: EmployeeMessageArgsFactory(),
  );

  static final updateEmployeeMessage = RouteFactory<EmployeeMessageArguments>(
    '/employee/{employeeId}/messages/{employeeMessage}/update',
    argsFactory: EmployeeMessageArgsFactory(),
  );

  static final deleteEmployeeMessage = RouteFactory<EmployeeMessageArguments>(
    '/employee/{employeeId}/messages/{employeeMessage}/delete',
    argsFactory: EmployeeMessageArgsFactory(),
  );
}
```

The next time we need to navigate view an employee message, we can then call the route factory with our type-safe arguments:

```dart
final employeeId = uuid();
final messageId = uuid();

Navigator.of(context).push(
  MaterialPageRoute(
    settings: Routes.viewEmployeeMessage(
      EmployeeMessageArguments(
        employeeId: employeeId,
        messageId: messageId,
      ),
    ).settings,
    builder: (BuildContext context) {
      return ViewEmployeeMessage(
        employeeId: employeeId,
        messageId: messageId,
      );
    },
  )
);
```

To create a new employee message, we can define another route that uses an `EmployeeArguments` class:

```dart
import 'package:route_builder/route_builder.dart';

class EmployeeArguments extends Arguments {
  final String employeeId;

  EmployeeMessageArguments({
    required this.employeeId,
  });

  @override
  toJson() {
    return {
      "employeeId": employeeId,
    };
  }
}

class EmployeeArgsFactory extends ArgumentsFactory<EmployeeArguments> {
  @override
  fromJson(json) {
    return EmployeeArguments(
      employeeId: employeeId,
      messageId: messageId
    );
  }
}

class Routes {
  ...

  static final createEmployeeMessage = RouteFactory<EmployeeArguments>(
    '/employee/{employeeId}/messages/create',
    argsFactory: EmployeeArgsFactory(),
  );

  // Routes that have no arguments can simply be specified with the Route class:
  static final viewEmployees = Route('/employees'); 
}
```

The main benefits of using this approach for *building* routes are the reusability and type safety. While it introduces some boilerplate, where this approach shines is when we go on to try and match routes.

## Matching route names

When a user deep links to a particular route on Flutter web, the [onGenerateRoute](https://api.flutter.dev/flutter/material/MaterialApp/onGenerateRoute.html) API can be used to match the URI with a particular widget.

```dart
MaterialApp(
  title: 'MyApp',
  onGenerateRoute: (RouteSettings settings) {
    final name = settings.name;

    if (Routes.viewEmployeeMessage.match(name)) {
      final route = Routes.viewEmployeeMessage.parse(name)!;
      final args = route.arguments;

      return MaterialPageRoute(
        settings: route.settings,
        builder: (BuildContext context) {
          return ViewEmployeeMessage(
            employeeId: args.employeeId,
            messageId: args.messageId,
          );
        },
      );
    }
  },
);
```

The `match` API matches routes by path and query parameters. The `parse` API can then be used to construct a route object with its arguments and pass them to the widget.

## Matching intermediary versus final routes

Flutter can call `onGenerateRoute` multiple times for each path component delimited by the slashes in the path. For example, `/employee/1/messages/2` would first be called 4 times with the `RouteSettings` name equal to:

1. /employee
2. /employee/1
3. /employee/1/message
4. /employee/1/message/1

The reasoning here is that you may want to build up a stack of screens for eacn path component, in this example first navigating the user to the employees page, and then a message page on top of that. This behavior might not be what you always want, however, so if you're looking to only match the final route, you can use a code snippet like we do below using route builder:


```dart
import 'package:universal_html/html.dart';
import 'package:route_builder/route_builder.dart' as RouteBuilder;

Route<dynamic>? onGenerateRoute(RouteSettings settings) {
  final routeUri = Uri.parse(window.location.href);
  final name = settings.name;

  // This guard will only match when the RouteSettings name reaches the last iteration and
  // matches the full URI path.
  if (name != null && RouteBuilder.Route(name).match(routeUri.toString())) {
    return DeepLinks.instance.handleDeepLink(routeUri);
  }

  return null;
}
```

## Matching query parameters

Routes can be constructed with query parameters both with and without a path:

```dart
class Routes {
  static final absoluteViewUserModal = Route('/user?modal=viewUser');
  static final relativeViewUserModal = Route('?modal=viewUser');
}
```

The first route with an absolute path will build and match a URI at the `/user` path, while the second route will build and match routes relative to the current path.

```dart
absoluteViewUserModal.match('/user?modal=viewUser'); // true
absoluteViewUserModal.match('?modal=viewUser'); // false

relativeViewUserModal.match('/user?modal=viewUser'); // true
relativeViewUserModal.match('?modal=viewUser'); // true

// By default excess parameters will still match.
relativeViewUserModal.match('?modal=viewUser&otherParam=true'); // true

// Specify `strictQueryParams` if exact query parameter matching is required
Route('?modal=viewUser', strictQueryParams: true).match('?modal=viewUser&otherParam=true'); // false
```

## Matching arguments

An arguments object can require the presence of certain fields in order to successfully match:

```dart
class EmployeeMessageArguments extends Arguments {
  final String employeeId;
  final String messageId;

  EmployeeMessageArguments({
    required this.employeeId,
    required this.messageId,
  }): super(requiredArgs: ['employeeId', 'messageId']);

  @override
  toJson() {
    return {
      "employeeId": employeeId,
      "messageId": messageId,
    };
  }
}

class EmployeeMessageArgsFactory extends ArgumentsFactory<EmployeeMessageArguments> {
  @override
  fromJson(json) {
    return EmployeeMessageArguments(
      employeeId: employeeId,
      messageId: messageId
    );
  }
}

class Routes {
  ...

  static final viewEmployeeMessage = RouteFactory<EmployeeMessageArguments>(
    '/employee/{employeeId}/messages/{employeeMessage}',
    argsFactory: EmployeeMessageArgsFactory(),
  );

  static final viewEmployeeMessageModal = RouteFactory<EmployeeMessageArguments>(
    '?modal=viewEmployeeMessage',
    argsFactory: EmployeeMessageArgsFactory(),
  );
}
```

These fields can be matched by either the argument path components or the query parameters:

```dart
viewEmployeeMessage.match('/employee/1/messages/1'); // true
viewEmployeeMessage.match('/?modal=viewEmployeeMessage&employeeId=1&messageId=1'); // true
viewEmployeeMessage.match('/?modal=viewEmployeeMessage&employeeId=1'); // false
```

## Takeaways

We get the most value out of building and matching routes to support comprehensive deep linking for all of our routes on Flutter web. Whether your application has similar requirements or you're just looking for consistent route analytics or code reuse, we hope this guide has been helpful.

Let us know if there's anything else you'd like to see discussed on [Twitter](https://twitter.com/PollynApp){:target="_blank"} and feel free to leave suggestions for ways to make `RouteBuilder` more helpful on [GitHub](https://github.com/danReynolds/route_builder){:target="_blank"}.