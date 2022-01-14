---
title: "Endless: An infinite scroll view library"
layout: post
authors: ["Dan Reynolds"]
tags: ["Flutter", "Library"]
category: Tech
description: How and why we built our own infinite scroll view library.
image: "/images/tech/endless-scroll-views/image.jpg"
---

How and why we built our own infinite scroll view library.

<!--halt-->

> This x-post is originally available at the [Pollyn Engineering blog](https://blog.pollyn.app/posts/2021-11-09-endless-scroll-views/){:target="_blank"}.

The Pollyn desktop and mobile applications have a variety of scroll views that users can interact with including lists of referral codes, a friends list, and notifications. While Flutter comes with out of the box widgets for building scrollable views with [ListView](https://api.flutter.dev/flutter/widgets/ListView-class.html){:target="_blank"} and [GridView](https://api.flutter.dev/flutter/widgets/GridView-class.html){:target="_blank"}, we had some additional features we wanted from our scrollable widgets that motivated us to make our own:

1. **Data loading**: Many scrollable lists, such as a friends list, should be populated with an initial set of items and then load more data as a user scrolls down the list. We wanted to make a library that abstracted that logic into an easy to use API for building infinite lists that dynamically load more data.
2. **Common scrollable elements**: Many scroll view widgets have a common set of UI elements that we wanted to bake into a library including builders for *headers*, *footers*, *loading indicators*, and *empty states*.
3. **Multiple data sources**: Some of our lists are powered by paginated data APIs, while others use streams from sources like Google's [Cloud Firestore](https://firebase.google.com/docs/firestore){:target="_blank"} library. We wanted to support multiple types of data sources out of the box to minimize the amount of data massaging clients had to do when working with scroll views.
4. **Lists + Grids**: For Flutter mobile apps, the majority of the time scrollable views use lists, while on desktop, the added screen real estate is ideal for displaying items in grids. A scroll view library with all the other features we wanted should be able to seamlessly offer APIs for both list and grid widgets.

If you do a quick search for [infinite list libraries](https://pub.dev/packages?q=infinite+list){:target="_blank"} on `pub.dev`, you will find a number of high-quality Flutter libraries already out there for working with infinite list views. What we found was that none of them quite met the set of features we wanted and decided it would be useful and interesting to go ahead and build our own. If your applications need a similar set of features or you are just curious, then let's get right to it and take a look at [Endless](https://pub.dev/packages/endless){:target="_blank"}, our new infinite scroll view library.

## Endless scroll views

The most common data source for infinite lists is generally some sort of paginated API. The library comes with two pagination widgets `EndlessPaginationListView` and `EndlessPaginationGridView` for working with this type of data. Let's take a look at a basic example: 

```dart
import 'package:flutter/material.dart';
import 'package:endless/endless.dart';

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('Endless pagination list view')),
        body: EndlessPaginationListView<String>(
          loadMore: (pageIndex) async => {...},
          paginationDelegate: EndlessPaginationDelegate(
            pageSize: 5,
            maxPages: 10,
          ),
          itemBuilder: (
            context, {
            required item,
            required index,
            required totalItems,
          }) {
            return Text(item);
          },
        ),
      ),
    );
  }
}
```

In this example, we create an `EndlessPaginationListView` with 3 configuration options:

* **loadMore**: A function that is passed the current page index and returns a list of items to add to the list.
* **paginationDelegate**: A configuration object for specifying the maximum number of pages to fetch and the size of each page. The scroll view knows that it has finished loading items when it either reaches
the max number of pages or `loadMore` returns fewer than `pageSize` items.
* **itemBuilder**: A builder for each item in the list.

When the user scrolls passed the threshold for loading more items as specified by the `paginationDelegate.extentAfterFactor`, the list view will call `loadMore` and request more data. Working with grids has the same API as lists, with an additional `gridDelegate` specification:

```dart
import 'package:flutter/material.dart';
import 'package:endless/endless.dart';

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('Endless pagination grid view')),
        body: EndlessPaginationGridView<String>(
          loadMore: (pageIndex) async => {...},
          paginationDelegate: EndlessPaginationDelegate(
            pageSize: 5,
            maxPages: 10,
          ),
          // The only difference between the basic list and grid view is that a grid specifies its delegate such as how many items
          // to put in the cross axis.
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
          ),
          itemBuilder: (
            context, {
            required item,
            required index,
            required totalItems,
          }) {
            return Text(item);
          },
        ),
      ),
    );
  }
}
```

## Common UI elements

The library uses a [CustomScrollView](https://api.flutter.dev/flutter/widgets/CustomScrollView-class.html){:target="_blank"} widget under the hood to build the elements of the list. This makes it easy to support common list elements like headers and footers. The library supports a set of builder functions for these elements of scrollable widgets as shown below:

```plaintext
Header -> headerBuilder
Items -> itemBuilder
Empty state -> emptyBuilder
Loading spinner -> loadingBuilder
Load more widget (such as a TextButton) -> loadMoreBuilder
Footer -> footerBuilder
```

The following example uses header, footer and load more builders:

```dart
class _MyHomePageState extends State<MyHomePage> {
  final pager = ExampleItemPager();
  final controller = EndlessPaginationController<ExampleItem>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.only(top: 16, left: 16, right: 16),
        child: EndlessPaginationListView<ExampleItem>(
          loadMore: (pageIndex) async => pager.nextBatch(),
          paginationDelegate: EndlessPaginationDelegate(
            pageSize: 5,
          ),
          controller: controller,
          headerBuilder: (context) {
            return const Text("I'm a header!");
          },
          footerBuilder: (context) {
            return const Text("I'm a footer!");
          },
          itemBuilder: (
            context, {
            required item,
            required index,
            required totalItems,
          }) {
            return Text(item.title);
          },
          loadMoreBuilder: (context) => TextButton(
            child: const Text('load more'),
            onPressed: () => controller.loadMore(),
          ),
        ),
      ),
    );
  }
}
```

![Builders demo](/images/tech/endless-scroll-views/demo.gif)

As we can see in the demo, while the height of the items is less than the available space, the button specified in the `loadMoreBuilder` can be used to request more data. Once the height of the items exceeds
the available space, the view becomes scrollable and infinitely loads more data when the scroll threshold is reached at the bottom.

## State properties

In the previous example, our list view had a fixed header. What if we only wanted to show our header after we've loaded items? Endless scroll views use the [StateProperty](https://pub.dev/packages/state_property){:target="_blank"} pattern found in Flutter Material's core widgets such as [TextButton](https://api.flutter.dev/flutter/material/MaterialStateProperty-class.html){:target="_blank"}.

The Material UI libray uses this pattern to let consumers of core widgets like `TextButton` style it differently when it is in one more states like hover or pressed. The basic example from the docs looks like this:

```dart
TextButton(
  style: ButtonStyle(
    // Use the color green as the background color for all button states.
    backgroundColor: MaterialStateProperty.all<Color>(Colors.green),
  ),
);

TextButton(
  style: ButtonStyle(
    backgroundColor: MaterialStateProperty.resolveWith<Color>(
      // The state property passes all the current states the button is in
      // so that the button style can be customized.
      (Set<MaterialState> states) {
        // Lighten the button color when it is in the pressed state. 
        if (states.contains(MaterialState.pressed))
          return Theme.of(context).colorScheme.primary.withOpacity(0.5);
        return null;
      },
    ),
  ),
);
```

We use this same pattern to support customizing scroll views based on their current states. The possible states are defined as the following:

```dart
enum EndlessState {
  /// Whether the endless scroll view currently has no items.
  empty,

  /// Whether the endless scroll view is currently loading items.
  loading,

  /// Whether the endless scroll view has finished loading all items. Determined when loading
  /// items returns fewer items than the expected size.
  done
}
```

We can then check the current states of the scroll view to customize our header:

```dart
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('Endless pagination list view')),
        body: EndlessPaginationListView<String>(
          loadMore: (pageIndex) async => {...},
          paginationDelegate: EndlessPaginationDelegate(
            pageSize: 5,
            maxPages: 10,
          ),
          // Each builder has a corresponding state property builder for state-dependent UI.
          headerBuilderState: EndlessStateProperty.resolveWith((states) {
            if (states.contains(EndlessState.empty)) {
              return null;
            }

            return Container(
              color: Colors.blue,
              child: const Text('Header'),
            );
          }),
          itemBuilder: (
            context, {
            required item,
            required index,
            required totalItems,
          }) {
            return Text(item);
          },
        ),
      ),
    );
  }
}
```

The full list of endless state property helpers are given below:

* `EndlessStateProperty.all`
* `EndlessStateProperty.loading`
* `EndlessStateProperty.empty`
* `EndlessStateProperty.done`
* `EndlessStateProperty.never`
* `EndlessStateProperty.resolveWith`

Some builder functions have default state property behaviors. The emptyBuilder parameter for example is automatically wrapped in an emptyStateBuilder defined to only be built if the scroll view is empty and not loading as shown below:

```dart
EndlessStateProperty<Widget?> resolveEmptyBuilderToStateProperty(
  Builder<Widget>? builder,
) {
  return _resolveBuilderToStateProperty<Widget>(
    builder,
    (Builder<Widget> builder) =>
        EndlessStateProperty.resolveWith<Widget>((context, states) {
      if (states.contains(EndlessState.empty) &&
          !states.contains(EndlessState.loading)) {
        return builder(context);
      }
      return null;
    }),
  );
}
```

The goal of these defaults like for the empty state is to provide typical behavior for an infinite scroll view. If that's not the default you would like for your empty state, no problem! You can always provide your own `emptyBuilderState` to override it.

## Data sources

So far we've seen how to use `Endless` scroll views with paginated APIs, but we also highlighted that the library should be extensible to other data sources like streamed data. To use the library with streams, create an `EndlessStreamListView` as shown below:

```dart
import 'package:flutter/material.dart';
import 'package:endless/endless.dart';

final streamController = StreamController<List<String>>();

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('Endless stream list view')),
        body: EndlessStreamListView<String>(
          // A function called when you scroll past the configurable `extentAfterFactor` to tell the stream to add more items.
          loadMore: () => {...},
          // Items emitted on the stream are added to the scroll view. The scroll view knows to not try and fetch any more items
          // once the stream has completed.
          stream: streamController.stream,
          itemBuilder: (
            context, {
            required item,
            required index,
            required totalItems,
          }) {
            return Text(item);
          },
        ),
      ),
    );
  }
}
```

The streamed version of the list view shares most of its functionality with the paginated widget we've been using previously, except it now additionally takes a `stream` option that the list view subscribes to in order to add new items. When the stream is closed, the list view knows that the end of the list has been reached.

### Firestore streams

Since our own applications heavily rely on Firestore streams, there is an additional Firestore stream widget available as a [separate package](https://pub.dev/packages/endless_firestore){:target="_blank"} that you can checkout if you are working with data from Cloud Firestore.

```dart
import 'package:flutter/material.dart';
import 'package:endless_firestore/endless_firestore.dart';

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('Endless Firestore stream list view')),
        body: EndlessFirestoreStreamListView<String>(
          // A Firestore stream takes a query to use for fetching items.
          query: FirebaseFirestore.instance.collection('users').where('name', isEqualTo: 'Tester'),
          // The batch delegate determines how many new items to fetch per batch and optionally the maximum number of batches to fetch.
          batchDelegate: EndlessFirestoreStreamBatchDelegate(
            batchSize: 5,
            maxBatches: 10,
          ),
          itemBuilder: (
            context, {
            required item,
            required index,
            required totalItems,
          }) {
            return Text(item);
          },
        ),
      ),
    );
  }
}
```

In the example above, the `EndlessFirestoreStreamListView` displays documents loaded from the specified query into a scrollable list. The scroll view subscribes to the documents returned from the query with the `Query.snapshots` API using the `Query.limit` approach described [in this video](https://youtu.be/poqTHxtDXwU?t=470){:target="_blank"} from the Firebase team.

> Note that this approach incurs a re-read of all current documents when loading successive batches so be aware of the read pricing concerns there. This trade-off was made because of the advantages that come from limit-based batching as best described in the link above.

## Extending data sources

Firestore streams are just one example of how the library can be extended to support additional custom data sources. If you have your own data sources that you would be interested in seeing support for in the library, feel free to leave a feature request on the [project GitHub](https://github.com/danReynolds/endless){:target="_blank"}.

That's all for now on building infinite scroll views with [Endless](https://pub.dev/packages/endless){:target="_blank"}. Happy coding!

